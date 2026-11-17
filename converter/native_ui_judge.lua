-- 437 JudgeFactory type=2: one grade image plus a per-grade DynamicNumber.
-- The game still owns judgement, score, replay and submission.  This adapter
-- only mirrors the native HitEvent and drives the two ordinary maV modules.
local NativeUiJudge={items={}}
local function setManagedText(handle,text)
    if NativeUiNumber and NativeUiNumber.SetManagedText then NativeUiNumber.SetManagedText(handle,text) end
end

-- ScoreSpriteIIDX passes round mode 5 to DynamicNumber_SetTarget. In the
-- original NumberSprite_UpdateLayout this rounds a nonnegative integral
-- counter up to the next even integer (including an already-even value).
-- Keep the actual per-grade counter separate from this displayed value.
function NativeUiJudge.DisplayedCount(count)
    return count+count%2
end

local function judgeNumber(transform)
    local found
    local function visit(t)
        local candidate=t.gameObject:GetComponent(typeof(CS.Malody.UI.UIDynamicNumber))
        if candidate then assert(not found,'Ambiguous type=2 judge number provider');found=candidate end
        for i=0,t.childCount-1 do visit(t:GetChild(i)) end
    end
    visit(transform)
    assert(found,'Type=2 judge DynamicNumber provider missing')
    return found
end

local function systemTime()
    return math.floor(CS.UnityEngine.Time.time*1000)
end

local function findNativeJudgeModule(name)
    local module=Module:Find(name)
    if not module then return nil end
    local tp=module.GetType and module:GetType()
    if tp and tp.FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeDummy' then return nil end
    return module
end
function NativeUiJudge.Bind(module,entry)
    local cfg=assert(entry.source_judge_counter,'Missing type=2 judge configuration')
    local numberModule=assert(findNativeJudgeModule(cfg.number_handle),'Type=2 judge number module missing')
    local number=judgeNumber(numberModule.transform)
    if cfg.projection then
        -- Apply the SAME original compound anchor to both ordinary module
        -- rectangles. The parent projector runs outside their rotations.
        NativeUiProjection.Bind(module,cfg.projection,cfg.source_position,{cfg.anchor_x,cfg.anchor_y},cfg)
        NativeUiProjection.Bind(numberModule,cfg.projection,cfg.source_position,{cfg.anchor_x,cfg.anchor_y},cfg)
    end
    -- SkinRuntimeNumber exposes the exact CanvasGroup used by set_Alpha; use
    -- that field so this does not depend on an optional xLua type binding.
    local alphaGroup=numberModule.canvasGroup
    assert(alphaGroup,'Type=2 judge number CanvasGroup missing')
    local item={module=module,numberModule=numberModule,number=number,numberAlpha=alphaGroup,config=cfg,
        image=NativeUiSampling.Image(module),numberConfig=cfg.number,
        counts={0,0,0,0},bank=0,started=nil,active=false,
        baseWidth=module.Width,baseHeight=module.Height,baseX=module.X,baseY=module.Y,
        imageWidth=module.Width}
    -- Both native modules retain the source rotation. Their translations
    -- must follow that same local x axis, rather than always screen x.
    -- This build strips Transform.localEulerAngles from the skin binding.
    -- The supported SkinModuleBase.get_Rotate returns NEGATED local Euler Z
    -- (1804584c0). Read that actual module orientation, including Setup's
    -- transform, instead of assuming Setup uses the public setter convention.
    local angle=-module.Rotate*math.pi/180
    item.axisX=math.cos(angle);item.axisY=math.sin(angle)
    item.numberModule.Text='0'
    setManagedText(cfg.number_handle,'0')
    item.image.enabled=false
    module.Alpha=0;numberModule.Alpha=0
    item.image.sprite=NativeUiSampling.Sprite(cfg.banks[1].frames[1].file)
    NativeUiJudge.items[#NativeUiJudge.items+1]=item
end

local function planWidth(item)
    local count=item.counts[item.bank+1]
    if item.cached_num_count~=count then
        local plan=NativeUiNumber.Plan(item.numberConfig,tostring(NativeUiJudge.DisplayedCount(count)))
        item.cached_num_count=count
        item.cached_num_width=plan.width*item.numberConfig.units_per_pixel
    end
    return item.cached_num_width
end

local function draw(item,time)
    if not item.started then return end
    local elapsed=time-item.started
    local progress=math.min(1,math.max(0,(elapsed-160)/160))
    local alpha=math.floor(255-255*progress)
    local scale=elapsed<160 and 1.15-(.15*math.max(0,elapsed/160)) or 1
    local numberWidth=planWidth(item)
    item.module.Width=item.baseWidth*scale;item.module.Height=item.baseHeight*scale
    -- JudgeFactory animates one parent containing the grade image and the
    -- DynamicNumber.  Both children therefore scale around the parent
    -- anchor. Position the two native modules from their actual scaled
    -- widths so the number starts exactly at the image's right edge for any
    -- digit count and for every point of the 160 ms pop animation.
    local anchor=item.config.anchor_x or .5
    local axisX,axisY=item.axisX or 1,item.axisY or 0
    local gradeOffset=-numberWidth*scale*anchor
    local numberOffset=item.module.Width*(1-anchor)
    item.module.X=item.baseX+gradeOffset*axisX
    item.module.Y=item.baseY+gradeOffset*axisY
    item.numberModule.X=item.baseX+numberOffset*axisX
    item.numberModule.Y=item.baseY+numberOffset*axisY
    item.numberModule.ScaleX=scale;item.numberModule.ScaleY=scale
    -- maV Module.Alpha is an integer percentage, whereas 437's fade is an
    -- 8-bit opacity. Passing 255 through that API produces alpha=2.55 and
    -- delays the visible fade. Keep the modules open and set the original
    -- Image / UIDynamicNumber colours in their native float domain.
    item.module.Alpha=100;item.numberModule.Alpha=100
    local tint=item.image.color;tint.a=alpha/255;item.image.color=tint
    -- UIDynamicNumber.set_Color stores RGBA but only copies RGB to its
    -- existing glyphs (1808d63d0). The original number module's CanvasGroup
    -- owns its opacity. Use its float alpha without percentage quantization.
    item.number.Color=CS.UnityEngine.Color(tint.r,tint.g,tint.b,1)
    item.numberAlpha.alpha=alpha/255
    item.active=elapsed<320
    if elapsed>=320 then item.started=nil end
end

function NativeUiJudge.Start(item,bank)
    local source=item.config.banks[bank+1]
    if not source then return end
    item.bank=bank
    item.counts[bank+1]=item.counts[bank+1]+1
    local text=tostring(NativeUiJudge.DisplayedCount(item.counts[bank+1]))
    item.numberModule.Text=text
    setManagedText(item.config.number_handle,text)
    item.image.sprite=NativeUiSampling.Sprite(source.frames[1].file)
    item.image.enabled=true
    item.started=systemTime();item.active=true
    draw(item,item.started)
end

function NativeUiJudge.Hit(event)
    if not event then return end
    local kind,grade=event:NoteType(),event:JudgeResult()
    if (kind~=1 and kind~=2) or grade<1 or grade>4 then return end
    local lane=event:HitX();local clock=event:Time()
    local ending
    if kind==2 then
        local carrier=scale3HitCarrier(event)
        if carrier then ending=scale3Getter(carrier,'get_EndOffset') end
    end
    -- The event clock includes early/late judgement. Recover the target
    -- endpoint from the original event Offset; late short-LN heads must
    -- still increment their grade counter, early tails must not.
    local targetTime=clock+event:Offset()
    local endingTick=ending and math.modf(ending)
    if endingTick and targetTime>=endingTick then return end
    for _,item in ipairs(NativeUiJudge.items) do
        if item.config.all_lanes or item.config.lane==lane then NativeUiJudge.Start(item,grade-1) end
    end
end

function NativeUiJudge.Update()
    local now
    for _,item in ipairs(NativeUiJudge.items) do
        if item.started then
            now=now or systemTime()
            draw(item,now)
        end
    end
end

function NativeUiJudge.Reset()
    for _,item in ipairs(NativeUiJudge.items) do
        item.counts={0,0,0,0};item.bank=0;item.started=nil;item.active=false
        item.cached_num_count=nil;item.cached_num_width=nil
        item.numberModule.Text='0';item.module.Alpha=0;item.numberModule.Alpha=0
        setManagedText(item.config.number_handle,'0')
        item.numberAlpha.alpha=0
        item.module.X=item.baseX;item.module.Y=item.baseY
        item.numberModule.X=item.baseX;item.numberModule.Y=item.baseY
        item.image.enabled=false
    end
end
