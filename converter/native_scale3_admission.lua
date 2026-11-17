-- Research-only source Scale3 admission into ORIGINAL Key renderers. No
-- chart/clock/judge/score replacement, external Lua delegates or frame colour loop.
-- Current scope: controlled Scale3 geometry and default-factory hit visibility. Full source
-- motion calibration, first-frame admission and uploads remain unverified.
local scale3Bindings,scale3Recipes,scale3Fields,scale3StyleMethod,scale3SpriteCache
local scale3SkinSprites,scale3SkinSpriteGetter,scale3SkinSpriteArgs,scale3SourceFileCache
local scale3Flags,scale3DefaultFlags,scale3Empty
local scale3TrackField,scale3CarrierDataField
local scale3HitCarrierField,scale3HitNoteGetter,scale3PendingHits
local function scale3Invoke(method,target)
    return method:Invoke(target,scale3DefaultFlags,nil,scale3Empty,nil)
end
local function scale3Getter(target,name)
    local methods=target:GetType():GetMethods(CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public'))
    local found
    for i=0,methods.Length-1 do
        if methods[i].Name==name and methods[i]:GetParameters().Length==0 then
            assert(not found,'Ambiguous native Scale3 getter '..name);found=methods[i]
        end
    end
    return scale3Invoke(assert(found,'Missing native Scale3 getter '..name),target)
end
local function scale3NativeStyle(note)
    if not scale3Fields then
        assert(note:GetType().FullName=='Malody.Scene.Play.Note.PlayNoteKeySkin','Unexpected native Scale3 renderer type')
        scale3Fields={}
        local fields=note:GetType():GetFields(scale3Flags)
        for i=0,fields.Length-1 do
            if fields[i].FieldType.FullName=='UnityEngine.Vector2' then scale3Fields[#scale3Fields+1]=fields[i] end
        end
        -- Verified Awake stores head/tail/body sizes in these three fields,
        -- in declaration order. Metadata tokens remove GetFields ordering as
        -- an assumption. Refuse a different layout instead of guessing.
        assert(#scale3Fields==3,'Native Scale3 size-cache layout changed')
        table.sort(scale3Fields,function(a,b)return a.MetadataToken<b.MetadataToken end)
        local methods=note:GetType():GetMethods(scale3Flags)
        for i=0,methods.Length-1 do
            local m=methods[i]
            if m.IsVirtual and m.Name~='Awake' and m.ReturnType.FullName=='System.Void' and m:GetParameters().Length==0 then
                assert(not scale3StyleMethod,'Ambiguous native Scale3 appearance method');scale3StyleMethod=m
            end
        end
        assert(scale3StyleMethod,'Native Scale3 appearance method missing')
        local kind=note:GetType()
        while kind do
            local members=kind:GetFields(scale3Flags)
            for i=0,members.Length-1 do
                if members[i].FieldType.FullName=='Malody.Scene.Play.Widget.WidgetKeyTrack3D' then
                    assert(not scale3TrackField,'Ambiguous native track owner');scale3TrackField=members[i]
                end
            end
            kind=kind.BaseType
        end
        assert(scale3TrackField,'Native track owner missing')
    end
end
local function scale3MotionSource(carrier)
    if not scale3CarrierDataField then
        local kind=carrier:GetType()
        while kind do
            local fields=kind:GetFields(scale3Flags)
            for i=0,fields.Length-1 do
                if fields[i].FieldType.FullName=='System.Object' then
                    assert(not scale3CarrierDataField,'Ambiguous native carrier visual data')
                    scale3CarrierDataField=fields[i]
                end
            end
            kind=kind.BaseType
        end
        assert(scale3CarrierDataField,'Native carrier visual data missing')
    end
    local data=scale3CarrierDataField:GetValue(carrier)
    if not data then return end
    local methods=data:GetType():GetMethods(CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public'))
    for i=0,methods.Length-1 do
        if methods[i].Name=='get_DynamicScrollVisual' and methods[i]:GetParameters().Length==0 then
            return scale3Invoke(methods[i],data)
        end
    end
end
local function unclippedScale3RangeHeight(track,carrier,layer)
    -- The original C++ mapper saturates at distanceMax AFTER projection.
    -- Recover a verified linear 2D slope near zero, then apply the raw
    -- carrier delta (including HS) and original layer speed compensation.
    -- Never change distanceMax, the track, the carrier or a score field.
    assert(scale3Getter(track,'get_TrackAngle')==0,'Unclipped Scale3 projection is only verified for linear 2D')
    local step=1/1024
    local zero=track:GetNoteDistanceFromDeltaY(0,true)
    local plus=track:GetNoteDistanceFromDeltaY(step,true)
    local minus=track:GetNoteDistanceFromDeltaY(-step,true)
    local twice=track:GetNoteDistanceFromDeltaY(step*2,true)
    local tolerance=math.max(1e-10,math.abs(plus)*.00002)
    assert(math.abs(zero)<1e-10 and math.abs(plus+minus)<=tolerance and math.abs(twice-plus*2)<=tolerance,
        'Native note-distance mapping is not verified affine 2D')
    local slope=plus/step
    assert(slope>=0 and slope<math.huge,'Invalid native note-distance slope')
    local speed=scale3Getter(layer,'get_SpeedScale')
    local startY=scale3Getter(carrier,'get_StartY')
    local visual=scale3MotionSource(carrier)
    local delta
    if visual then
        -- Match UpdateObject's dynamic-scroll branch. Raw EndY-StartY is
        -- NOT its GetDelta result, even for an ordinary OSU containing SV.
        local hs=carrier:DeltaYStart(startY-1)
        assert(startY-(startY-1)==1,'Native HS readback lost double precision')
        delta=visual:GetDelta(scale3Getter(carrier,'get_EndOffset'),scale3Getter(carrier,'get_StartOffset'),hs,speed)
    else
        delta=carrier:DeltaYEnd(startY)
    end
    -- Current UpdateObject calls SetOffsetY, NOT SetAnchorY. This mapper
    -- returns parent-coordinate distances, not a fraction of parent height.
    local height=slope*delta*speed
    assert(height==height and math.abs(height)<math.huge,'Non-finite unclipped native range')
    return height
end
local function scale3Restore(record)
    record.state:Dispose()
    for i,field in ipairs(scale3Fields) do field:SetValue(record.note,record.originalSizes[i],scale3DefaultFlags,nil,nil) end
    -- Reapply the ORIGINAL style method, never InitObject: InitObject would
    -- reset the native hold runtime if input had already reached this note.
    scale3Invoke(scale3StyleMethod,record.note)
end
local function nativeScale3SpriteCache(sprites)
    local getter,args
    return setmetatable({}, {
        __index=function(cache,key)
            local name='__msb_scale3:'..key
            if not sprites:ContainsKey(name) then return end
            -- xLua's managed string member lookup is not this dictionary's
            -- Item property. Use the actual public indexed getter, not
            -- sprites[name], which returned nil for an existing Sprite.
            if not getter then
                local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public')
                local methods=sprites:GetType():GetMethods(flags)
                for i=0,methods.Length-1 do
                    local m=methods[i];local parameters=m:GetParameters()
                    if m.Name=='get_Item' and parameters.Length==1 and
                       parameters[0].ParameterType.FullName=='System.String' and m.ReturnType.FullName=='UnityEngine.Sprite' then
                        assert(not getter,'Ambiguous original Sprite cache getter');getter=m
                    end
                end
                assert(getter,'Original Sprite cache getter missing')
                args=CS.System.Array.CreateInstance(typeof(CS.System.Object),1)
            end
            args[0]=name
            local value=getter:Invoke(sprites,CS.System.Reflection.BindingFlags.Default,nil,args,nil)
            assert(value,'Original Sprite cache contains an empty entry')
            rawset(cache,key,value);return value
        end,
        __newindex=function(cache,key,value)
            sprites:Add('__msb_scale3:'..key,value);rawset(cache,key,value)
        end})
end

-- Source Part3 meshes use the exact Sprite objects imported by the native
-- SkinRuntime. The ordinary KeySkin overlap slots may be empty when the
-- converted package has no maV head module.
function NativeSourceSprite(file)
    if not scale3SkinSprites or not file then return nil end
    local cached=scale3SourceFileCache and scale3SourceFileCache[file]
    if cached then return cached end
    if not scale3SkinSprites:ContainsKey(file) then return nil end
    if not scale3SkinSpriteGetter then
        local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public')
        local methods=scale3SkinSprites:GetType():GetMethods(flags)
        for i=0,methods.Length-1 do
            local method=methods[i];local parameters=method:GetParameters()
            if method.Name=='get_Item' and parameters.Length==1 and
               parameters[0].ParameterType.FullName=='System.String' and
               method.ReturnType.FullName=='UnityEngine.Sprite' then
                assert(not scale3SkinSpriteGetter,'Ambiguous native source Sprite getter')
                scale3SkinSpriteGetter=method
            end
        end
        assert(scale3SkinSpriteGetter,'Native source Sprite getter missing')
        scale3SkinSpriteArgs=CS.System.Array.CreateInstance(typeof(CS.System.Object),1)
    end
    scale3SkinSpriteArgs[0]=file
    local sprite=scale3SkinSpriteGetter:Invoke(scale3SkinSprites,CS.System.Reflection.BindingFlags.Default,nil,scale3SkinSpriteArgs,nil)
    if sprite then scale3SourceFileCache[file]=sprite end
    return sprite
end

local function initScale3Admission(data)
    -- Ordinary skin environments have not preloaded the observer's Unity
    -- namespaces. Match the existing admission helper's explicit imports.
    xlua.load_assembly('Assembly-CSharp')
    xlua.load_assembly('UnityEngine.CoreModule')
    -- UISpriteRect is in Framework.dll (TypeDefIndex 9432), unlike
    -- UIOffsetScale and PlayKeyTrackScaledObject in Assembly-CSharp.dll.
    xlua.load_assembly('Framework')
    assert(typeof(CS.Malody.UI.UISpriteRect),'Native Scale3 Framework.UISpriteRect import missing')
    if scale3Bindings then
        for _,record in pairs(scale3Bindings) do
            if not record.note:Equals(nil) then scale3Restore(record) end
        end
    end
    scale3Bindings={};scale3Recipes=data.scale3_recipes;scale3PendingHits={};scale3SourceFileCache={}
    if not scale3Recipes then return end
    scale3Flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic, DeclaredOnly')
    scale3DefaultFlags=CS.System.Reflection.BindingFlags.Default
    scale3Empty=CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
    assert(data.admission_policy,'Native Scale3 requires the owned native-admission policy')
    local runtime=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.Malody.Scene.Play.Skin.SkinRuntime),false)
    assert(runtime.Length==1,'Expected one active native SkinRuntime')
    local skin=scale3Getter(runtime[0],'get_ValidSkin')
    local sprites=scale3Getter(skin,'get_Sprites');scale3SkinSprites=sprites
    -- Same owner as original runtime-created Sprites. No texture copies and
    -- no teardown callback/delegate keeping the Lua environment alive. The
    -- original Skin.UnloadSkin clears this dictionary along with its images.
    scale3SpriteCache=nativeScale3SpriteCache(sprites)
    NATIVE_SCALE3_ADMISSION={configured=0,restored=0,reused=0,unclipped=0,max_range_correction=0,
        hidden=0,early_hits=0,geometry_scope_only=true}
end
local function scale3HideRecord(record,carrier)
    assert(record.carrier:Equals(carrier),'Scale3 hit owner changed before visibility write')
    if not record.hidden then
        record.state.object:SetActive(false);record.hidden=true
        if nativePainterSourceHidden then nativePainterSourceHidden(record.note,carrier) end
        NATIVE_SCALE3_ADMISSION.hidden=NATIVE_SCALE3_ADMISSION.hidden+1
    end
end
local function scale3HitCarrier(event)
    if not scale3HitCarrierField then
        local kind=event:GetType()
        while kind do
            local fields=kind:GetFields(scale3Flags)
            for i=0,fields.Length-1 do
                local methods=fields[i].FieldType:GetMethods(CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public'))
                for j=0,methods.Length-1 do
                    local method=methods[j]
                    if method.Name=='get_NoteObject' and method:GetParameters().Length==0 then
                        assert(not scale3HitCarrierField,'Ambiguous original hit carrier')
                        scale3HitCarrierField,scale3HitNoteGetter=fields[i],method
                    end
                end
            end
            kind=kind.BaseType
        end
        assert(scale3HitCarrierField,'Original Scale3 hit carrier unavailable')
    end
    local carrier=scale3HitCarrierField:GetValue(event)
    return carrier,carrier and scale3Invoke(scale3HitNoteGetter,carrier)
end
local function scale3VisualHit()
    if not scale3Recipes then return end
    local event=Game:HitEvent()
    if event:NoteType()~=2 or event:JudgeResult()<1 or event:JudgeResult()>3 then return end
    local recipe=scale3Recipes[event:HitX()]
    if not recipe or recipe.toggle&1==0 then return end
    local carrier,note=scale3HitCarrier(event)
    if not carrier then return end
    local record=note and scale3Bindings[note:GetInstanceID()]
    if record and record.carrier:Equals(carrier) then scale3HideRecord(record,carrier);return end
    -- Original input can precede the ordinary script's admission scan.
    -- Keep its real carrier rather than applying the hit to an older occupant
    -- of the same physical note. Consume only on a matching later binding.
    for _,pending in ipairs(scale3PendingHits) do if pending:Equals(carrier) then return end end
    assert(#scale3PendingHits<16384,'Unconsumed Scale3 hit evidence exceeds verified bound')
    scale3PendingHits[#scale3PendingHits+1]=carrier
    NATIVE_SCALE3_ADMISSION.early_hits=NATIVE_SCALE3_ADMISSION.early_hits+1
end
local function prepareScale3Admission(note,carrier,lane)
    if not scale3Recipes then return end
    scale3NativeStyle(note)
    local id=note:GetInstanceID();local old=scale3Bindings[id]
    if old then
        assert(old.note:Equals(note),'Native Scale3 pooled object identity changed')
        scale3Restore(old);scale3Bindings[id]=nil
        NATIVE_SCALE3_ADMISSION.restored=NATIVE_SCALE3_ADMISSION.restored+1
        NATIVE_SCALE3_ADMISSION.reused=NATIVE_SCALE3_ADMISSION.reused+1
    end
end
local function finishScale3Admission(note,carrier,lane,layer,sourceHeight)
    if not scale3Recipes then return end
    if scale3Getter(carrier,'get_EndOffset')<=scale3Getter(carrier,'get_StartOffset') then return end
    local recipe=assert(scale3Recipes[lane],'Missing source Scale3 lane recipe')
    assert((recipe.factory=='scale3' or recipe.factory=='scale3part3') and math.type(recipe.toggle)=='integer',
        'Unverified source Scale3 factory/lifetime recipe')
    assert(recipe.scope=='controlled-native-binding' or recipe.scope=='legacy-source-native-v1','Unverified source/native motion calibration')
    assert(tostring(note.holdHeadType):match('^None'),'Controlled Scale3 factories require native None head policy')
    assert(recipe.factory=='scale3' or recipe.toggle==0,'Dynamic Scale3Part3 hit policy is not yet verified')
    local U=CS.UnityEngine
    local originalSizes={}
    for i,field in ipairs(scale3Fields) do originalSizes[i]=field:GetValue(note) end
    local source=assert(note.body.sprite,'Source Scale3 body missing from original style')
    local layout=recipe.layout
    local unit=note.rectNoteRange.rect.width/recipe.lane_width_720
    local spec={fixed_at_admission=layout.fixed_at_admission,pivot=layout.pivot,size_delta=layout.size_delta,
        anchor_y={layout.anchor_y[1]/unit,layout.anchor_y[2]/unit},
        scale={layout.scale[1]*unit,layout.scale[2]*unit},
        offset={layout.offset[1]*unit,layout.offset[2]*unit}}
    if recipe.motion_range_source=='source-whole-scale3' then
        assert(DATA.source_visual_pool and DATA.source_visual_pool.motion and recipe.factory=='scale3' and
            sourceHeight and sourceHeight==sourceHeight and math.abs(sourceHeight)<math.huge,
            'Source whole-image admission needs its original display interval')
        local track=scale3TrackField:GetValue(note)
        assert(scale3Getter(track,'get_TrackAngle')==0,'Source motion currently requires linear native 2D')
        spec.source_admitted_height=sourceHeight
    elseif recipe.motion_range_source=='native-linear-unclipped' then
        local track=scale3TrackField:GetValue(note)
        assert(note.rectNoteRange.anchorMin.y==note.rectNoteRange.anchorMax.y,
            'Unverified native range with a nonzero anchor span')
        spec.unclipped_range_height=unclippedScale3RangeHeight(track,carrier,layer)
        NATIVE_SCALE3_ADMISSION.unclipped=NATIVE_SCALE3_ADMISSION.unclipped+1
        NATIVE_SCALE3_ADMISSION.max_range_correction=math.max(NATIVE_SCALE3_ADMISSION.max_range_correction,
            math.abs(spec.unclipped_range_height-note.rectNoteRange.rect.height))
        if recipe.factory=='scale3part3' then
            -- This body follows the LIVE native range, not a fixed whole
            -- image. Without the source tail window, anchors cannot recover
            -- a saturated native range. Never change the distance ceiling.
            if recipe.tail_window_720 then
                -- min(min(nativeTail, nativeCeiling), sourceCeiling) equals
                -- min(nativeTail, sourceCeiling) when sourceCeiling is smaller.
                -- A very long tail therefore needs no expanded native range.
                local ceiling=track:GetNoteDistanceFromDeltaY(1e9,true)
                assert(ceiling>recipe.tail_window_720*unit and ceiling<math.huge,
                    'Original native distance ceiling is inside the source tail window')
            else
                assert(math.abs(spec.unclipped_range_height-note.rectNoteRange.rect.height)<.01,
                    'Dynamic Scale3Part3 range is clipped at admission')
            end
        end
    else
        assert(not layout.requires_unclipped_motion_range,'Original Scale3 cannot admit from a clipped native range')
    end
    local state=newNativeScale3Rect(source,note.body,note.rectNoteRange,recipe.part,scale3SpriteCache,{note.tail,note.head,note.body})
    state:BindRange(spec)
    -- OnWillRenderObject runs only after visibility culling. An offscreen
    -- recycled renderer can retain its OLD small size and get culled before
    -- the new long image ever updates its bounds. Initialize once through
    -- the ORIGINAL C++ layout method, then let native dirty updates run.
    for _,piece in pairs(state.parts) do piece.layout:UpdateSpriteSize() end
    for i,r in ipairs({note.head,note.tail,note.body}) do
        scale3Fields[i]:SetValue(note,r.transform.rect.size,scale3DefaultFlags,nil,nil)
    end
    if recipe.tail_window_720 then
        assert(DATA.native_frame_driver and recipe.factory=='scale3part3' and recipe.toggle==0,
            'Source tail clipping requires the verified post-native driver and dynamic factory toggle 0')
        assert(recipe.tail_window_720>0 and recipe.tail_window_720<math.huge,'Invalid source display window')
    end
    local record={note=note,carrier=carrier,state=state,originalSizes=originalSizes,recipe=recipe,unit=unit}
    scale3Bindings[note:GetInstanceID()]=record
    for i=#scale3PendingHits,1,-1 do
        if scale3PendingHits[i]:Equals(carrier) then
            if recipe.toggle&1~=0 then scale3HideRecord(record,carrier) end
            table.remove(scale3PendingHits,i)
        end
    end
    NATIVE_SCALE3_ADMISSION.configured=NATIVE_SCALE3_ADMISSION.configured+1
end
local function updateScale3SourceWindow()
    if not scale3Bindings then return end
    local U=CS.UnityEngine
    for _,record in pairs(scale3Bindings) do
        local limit=record.recipe.tail_window_720
        if limit and record.note.gameObject.activeInHierarchy then
            local rect=record.note.rectNoteRange
            local top=rect.offsetMax
            limit=scale3float(limit*record.unit)
            record.windowFrame=U.Time.frameCount
            record.nativeTailDistance=top.y
            record.sourceTailDistance=math.min(top.y,limit)
            -- 437 Part3/Scale3Part3/Tile3 clamp ONLY the tail to source pos.
            -- offsetMax leaves offsetMin/head unchanged. C++ anchors and
            -- UISpriteRect then resize the borrowed source segments normally.
            if top.y>limit then rect.offsetMax=U.Vector2(top.x,limit) end
            record.state:RefreshBodyBounds()
        end
    end
end
