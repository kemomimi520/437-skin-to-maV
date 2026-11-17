-- One original Sprite/StateAnimator == one ordinary native Image, with
-- exclusive frames. Original Key supplies input, carriers and judgement.
local NativeUiEvents={items={},pressed={}}
local function eventFloat(value)return string.unpack('f',string.pack('f',value))end
function NativeUiEvents.SystemTime()return CS.UnityEngine.Time.time*1000 end
function NativeUiEvents.StaticPlan(start,time)
    local elapsed=math.modf(time)-start
    local p=eventFloat(math.min(1,math.max(0,elapsed/160)))
    local first=eventFloat(1.15)
    local scale=eventFloat(first+(1-first)*p)
    local alpha=255
    if elapsed>=160 then
        p=eventFloat(math.min(1,math.max(0,(elapsed-160)/160)))
        alpha=math.floor(eventFloat(255-255*p))
    end
    return scale,alpha,elapsed
end
function NativeUiEvents.DrawStatic(item,time)
    local scale,alpha,elapsed=NativeUiEvents.StaticPlan(item.static_start,time)
    local frame=item.config.banks[item.bank+1].frames[1]
    item.module.Width=item.width*frame.width/item.reference.width*scale
    item.module.Height=item.height*frame.height/item.reference.height*scale
    local color=item.image.color;color.a=alpha/255;item.image.color=color
    item.elapsed=elapsed;item.active=elapsed<320
end
local function drawEvent(item,frame)
    local before=item.drawn
    item.module.Width=item.module.Width*frame.width/before.width
    item.module.Height=item.module.Height*frame.height/before.height
    item.image.sprite=NativeUiSampling.Sprite(frame.file)
    item.drawn=frame
end
local function selectEvent(item)
    if not item.active then return end
    local bank=item.config.banks[item.bank+1]
    local index=item.absolute
    if index>=#bank.frames then
        if bank.repeat_count~=-1 and (bank.repeat_count<=1 or index>=#bank.frames*bank.repeat_count) then
            item.active=false;item.displayed=nil
            item.visible=bank.keep_last==true
            item.image.enabled=item.visible
            return
        end
        index=index%#bank.frames
    end
    if index<0 then return end
    drawEvent(item,bank.frames[index+1]);item.displayed=index
end
function NativeUiEvents.Start(item,bank)
    if not item.config.banks[bank+1] then return end
    item.bank=bank;item.elapsed=0;item.absolute=0;item.active=true;item.visible=true
    item.image.enabled=true;selectEvent(item)
    if item.config.static_effect then
        if NativeUiMotion and NativeUiMotion.Stop then NativeUiMotion.Stop(item.module) end
        item.static_start=math.modf(NativeUiEvents.SystemTime())
        NativeUiEvents.DrawStatic(item,NativeUiEvents.SystemTime())
    end
end
function NativeUiEvents.Bind(module,entry)
    local config=entry.source_events
    assert(config.interval>0 and #config.banks>0,'Invalid original EventFactory bank')
    local reference=config.banks[1].frames[1]
    local item={module=module,config=config,image=NativeUiSampling.Image(module),
        reference=reference,drawn=reference,width=module.Width,height=module.Height,
        elapsed=0,absolute=0,bank=0,active=false,visible=false}
    if config.static_effect then item.initial_alpha=item.image.color.a end
    item.image.sprite=NativeUiSampling.Sprite(reference.file);item.image.enabled=false
    entry.frame_state=item;NativeUiEvents.items[#NativeUiEvents.items+1]=item
    if config.kind=='press' and #config.banks>1 then NativeUiEvents.Start(item,1) end
    if config.kind=='key' then NativeUiEvents.Start(item,0) end
end
function NativeUiEvents.Input(lane,kind,clock)
    if kind~=1 and kind~=3 then return end
    local pressed=kind==1
    if pressed==(NativeUiEvents.pressed[lane]==true) then return end
    NativeUiEvents.pressed[lane]=pressed
    -- KeyUIS always switches its press vector before its hit vector,
    -- independently of the MUI definition / native module creation order.
    for _,eventKind in ipairs({'key','press','hit'}) do
    for _,item in ipairs(NativeUiEvents.items) do
        if item.config.lane==lane and item.config.kind==eventKind then
            if item.config.kind=='key' then NativeUiEvents.Start(item,pressed and 1 or 0)
            elseif item.config.kind=='press' then
                if pressed then NativeUiEvents.Start(item,0)
                elseif item.bank==0 and #item.config.banks>1 then NativeUiEvents.Start(item,1)
                else item.visible=false;item.image.enabled=false end
            elseif item.config.kind=='hit' then
                if not pressed and item.bank==1 then NativeUiEvents.Start(item,2)
                elseif pressed and item.hold_end and clock and clock<item.hold_end then
                    -- Original 005ad7f0: re-press a previously hit, unfinished
                    -- hold before asking its judge; restore the held bank.
                    NativeUiEvents.Start(item,1)
                end
            end
        end
    end
    end
end
function NativeUiEvents.Hit(event)
    -- Auto's physical key transitions are internal to the original native
    -- processor and do not invoke SkinScriptRuntime.OnInput. Reflect its
    -- actual hit/tail results only when the source readout confirms Auto.
    local kind,grade=event:NoteType(),event:JudgeResult()
    if kind~=1 and kind~=2 then return end
    local lane=event:HitX()
    if grade==8 then
        for _,item in ipairs(NativeUiEvents.items) do
            if item.config.kind=='hit' and item.config.lane==lane then
                if item.bank==1 then NativeUiEvents.Start(item,2) end
                item.hold_end=nil
            end
        end
        return
    end
    if grade<1 or grade>4 then return end
    local clock=event:Time()
    -- uqk/sih stores Offset = target note tick - actual event Time.
    -- A late short-LN HEAD may occur after EndOffset; an early TAIL can
    -- occur before it. Classify the judged endpoint, never wall timing.
    local targetTime=clock+event:Offset()
    local ending
    if kind==2 then
        local carrier=scale3HitCarrier(event)
        assert(carrier,'Original hit animation requires its native hold carrier')
        ending=scale3Getter(carrier,'get_EndOffset')
    end
    -- Native beat Int truncates fractional ticks, while EndOffset is double.
    local endingTick=ending and math.modf(ending)
    local tail=endingTick and targetTime>=endingTick
    local auto=(sourcePool and sourcePool.input and sourcePool.input.native_mods&1~=0)
        or (Game and Game.PlayMeta and ((Game:PlayMeta('mod') or 0)&1~=0))
    if auto and grade<=3 then NativeUiEvents.Input(lane,tail and 3 or 1,clock) end
    for _,item in ipairs(NativeUiEvents.items) do
        -- KeyUIS routes ScoreAnimation at the note HEAD. Native Key also
        -- emits hold-tail results; those must not restart the old judge bank.
        -- 437 ScoreBase maps best/cool/good/miss to banks 0/1/2/3.
        if item.config.kind=='judge' and (item.config.all_lanes or item.config.lane==lane) and
                not tail then
            NativeUiEvents.Start(item,grade-1)
        end
        if item.config.kind=='hit' and item.config.lane==lane then
            if tail then
                if item.bank==1 then NativeUiEvents.Start(item,2) end
                item.hold_end=nil
            elseif grade<=3 then
                item.hold_end=ending
                NativeUiEvents.Start(item,ending and 1 or 0)
            end
        end
        if item.config.kind=='timing' and not tail and (grade==2 or grade==3) and
                ((event:Offset()>0)==(item.config.fast==true)) then
            NativeUiEvents.Start(item,0)
        end
    end
    if auto and kind==1 and grade<=3 then NativeUiEvents.Input(lane,3,clock) end
end
function NativeUiEvents.Reset()
    NativeUiEvents.last_frame=nil;NativeUiEvents.pressed={}
    for _,item in ipairs(NativeUiEvents.items) do
        item.module.Width=item.width;item.module.Height=item.height
        item.drawn=item.reference;item.image.sprite=NativeUiSampling.Sprite(item.reference.file)
        item.bank=0;item.elapsed=0;item.absolute=0;item.active=false;item.visible=false;item.hold_end=nil
        item.image.enabled=false
        item.static_start=nil
        if item.initial_alpha then
            local color=item.image.color;color.a=item.initial_alpha;item.image.color=color
        end
        if item.config.kind=='press' and #item.config.banks>1 then NativeUiEvents.Start(item,1) end
        if item.config.kind=='key' then NativeUiEvents.Start(item,0) end
    end
end
function NativeUiEvents.Advance(dt)
    local delta=eventFloat(eventFloat(dt)*1000)
    for _,item in ipairs(NativeUiEvents.items) do
        if item.visible and item.config.kind~='key' and not item.config.static_effect then
            item.elapsed=item.elapsed+delta;item.absolute=math.floor(item.elapsed/item.config.interval)
            if item.active then selectEvent(item) end
        end
    end
end
function NativeUiEvents.Update()
    local time=CS.UnityEngine.Time
    if NativeUiEvents.last_frame==time.frameCount then return end
    NativeUiEvents.last_frame=time.frameCount
    local hasHold,hasAnim,hasStatic=false,false,false
    for _,item in ipairs(NativeUiEvents.items) do
        if item.config.kind=='hit' and item.hold_end then hasHold=true end
        if item.visible and item.config.kind~='key' and not item.config.static_effect then hasAnim=true end
        if item.static_start then hasStatic=true end
    end
    if not (hasHold or hasAnim or hasStatic) then return end
    if hasHold then
        local clock=Game:Time()
        for _,item in ipairs(NativeUiEvents.items) do
            if item.config.kind=='hit' and item.hold_end and clock>=item.hold_end then
                if item.bank==1 then NativeUiEvents.Start(item,2) end
                item.hold_end=nil
            end
        end
    end
    if hasAnim then NativeUiEvents.Advance(time.deltaTime) end
    if hasStatic then
        local sysTime=NativeUiEvents.SystemTime()
        for _,item in ipairs(NativeUiEvents.items) do
            if item.static_start then
                NativeUiEvents.DrawStatic(item,sysTime)
                if not item.active then item.static_start=nil end
            end
        end
    end
end
