-- Source FIFO owns only scene-created ORIGINAL PlayNoteKeySkin visuals.
-- The original NoteLayer, carriers, NoteObject links, inputs and judge stay
-- owned by the game. No Free object, replacement judge or vertex draw loop.
local sourcePool
local function nativeSourceVisualContext() return sourcePool end
local function nativeSourcePart3Factory(factory)
    return factory=='part3' or factory=='scale3part3' or factory=='tile3'
end
local function nativeSourceRetainedFactory(factory)
    -- All non-default 4.3.7 hold factories retain the head distance after
    -- input.  Their geometry differs, but their move/lifetime callback owns
    -- the same source timing and hit-state contract.
    return factory=='part3' or factory=='scale3part3' or factory=='tile3'
end
local function sourceCarrierId(carrier)
    -- Native carriers expose UnityEngine.Object.GetInstanceID.  The pure Lua
    -- regression shim intentionally uses plain tables; keep the lookup
    -- identity-only and avoid making the production path depend on a helper
    -- absent from that shim.
    local ok,id=pcall(function() return carrier:GetInstanceID() end)
    return ok and id or tostring(carrier)
end
local function initNativeSourcePool(data)
    local U=CS.UnityEngine
    if sourcePool then
        for _,row in pairs(sourcePool.slots) do
            if row.part3Mesh then NativeSourcePart3Mesh.Dispose(row) end
        end
        for _,row in pairs(sourcePool.masked) do
            if not row.renderer:Equals(nil) then row.renderer.enabled=row.enabled end
        end
        if sourcePool.root and not sourcePool.root:Equals(nil) then U.Object.Destroy(sourcePool.root) end
    end
    sourcePool=nil;NATIVE_SOURCE_POOL=nil;NATIVE_SOURCE_MEMBERS=nil
    local config=data.source_visual_pool
    if not config then return end
    if config.motion and config.motion.speed_source then
        -- Keep the byte-attested DATA immutable. Flow changes affect the
        -- live source window, not another branch or the next retry's JSON.
        local original=config;config={}
        for name,value in pairs(original) do config[name]=value end
        config.motion={}
        for name,value in pairs(original.motion) do config.motion[name]=value end
    end
    assert(data.native_frame_driver and (config.scope=='controlled-source-fifo' or config.scope=='legacy-source-fifo-v1'),
        'Source visual pool requires the original post-layer callback and explicit source FIFO scope')
    assert(config.distance>0 and config.distance<math.huge and config.judge_ahead>=0,
        'Invalid source lifetime window')
    if config.motion then NativeSourceMotion.Check(config.motion,config.distance) end
    assert(math.type(config.base)=='integer' and math.type(config.capacity)=='integer' and
        config.capacity>0 and config.base>=-32768 and config.base+config.capacity*5-1<=32767,
        'Invalid source visual sorting capacity')
    for _,recipe in ipairs(assert(data.scale3_recipes)) do
        assert((recipe.factory=='scale3' and recipe.toggle>=0 and recipe.toggle<=3) or
            (nativeSourceRetainedFactory(recipe.factory) and recipe.toggle>=0 and recipe.toggle<=3),
            'Source-owned native factory/input policy is not mapped')
        assert(not nativeSourceRetainedFactory(recipe.factory) or config.motion and
            (config.motion.scope=='legacy-linear-part3-v1' or config.motion.scope=='legacy-mixed-v1'),
            'Retained 437 hold factories require their unbounded head and clipped tail motion')
    end
    sourcePool={config=config,masked={},slots={},pending={},events={},states={},heldByLane={},generation=0,byCarrier={}}
    NATIVE_SOURCE_POOL={frames=0,created=0,admitted=0,retired=0,reused=0,updates=0,
        visible=0,active=0,source_y=0,judge_time=0,display_time=0,links_preserved=0,
        original_native_links_changed=0,cpp_updates=0,group_moves=0,fast_motion=0,motion_speed=0,motion_distance=config.distance,
        release_candidates=0,full_motion_verified=false,full_acceptance=false}
    NATIVE_SOURCE_POOL.holds=sourcePool.states
    NATIVE_SOURCE_MEMBERS='[]'
end
local function sourceHoldMembership(pool,n,state,held)
    local lane=n.lane
    local bucket=pool.heldByLane[lane]
    if held then
        if not bucket then bucket={};pool.heldByLane[lane]=bucket end
        bucket[n.nid]=state
    elseif bucket then
        bucket[n.nid]=nil
        if next(bucket)==nil then pool.heldByLane[lane]=nil end
    end
end
local function maskOriginalRenderer(r)
    if not r.enabled then return end
    local id=r:GetInstanceID()
    if not sourcePool.masked[id] then
        sourcePool.masked[id]={renderer=r,enabled=true}
    end
    r.enabled=false
end
local function nativeSourceMaskOriginal(note)
    if not sourcePool or not sourcePool.input then return end
    maskOriginalRenderer(note.body)
    maskOriginalRenderer(note.tail)
    maskOriginalRenderer(note.head)
    maskOriginalRenderer(note.overlap)
    maskOriginalRenderer(note.rearOverlap)
end
local function nativeSourcePoolReady()
    return sourcePool and sourcePool.input~=nil
end
local function sourcePoolObjects(pool,layer)
    local U=CS.UnityEngine
    local template
    for i=0,layer.prefabObject.Length-1 do
        local candidate=layer.prefabObject[i]
        local note=candidate:GetComponent(typeof(CS.Malody.Scene.Play.Note.PlayNoteKeySkin))
        if note then assert(not template,'Ambiguous original KeySkin visual template');template=candidate end
    end
    assert(template,'Original KeySkin visual template missing')
    local root=U.GameObject('legacy-source-native-pool',typeof(U.RectTransform))
    root.layer=layer.gameObject.layer
    local rect=root.transform;rect:SetParent(layer.transform,false)
    rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(1,1)
    rect.sizeDelta=U.Vector2(0,0)
    local fieldOffset=pool.config.field_offset_x or 0
    assert(type(fieldOffset)=='number' and fieldOffset==fieldOffset and math.abs(fieldOffset)<1e7,
        'Invalid source field offset')
    rect.anchoredPosition=U.Vector2(fieldOffset,0)
    rect.localScale=U.Vector3(1,1,1)
    pool.root=root;pool.template=template;pool.layer=layer
    if pool.config.motion and pool.config.motion.legacy_play_plane then
        local cameras=U.Object.FindObjectsOfType(typeof(U.Camera),false)
        local mask=1<<layer.gameObject.layer
        for i=0,cameras.Length-1 do
            local candidate=cameras[i]
            if candidate.enabled and candidate.gameObject.activeInHierarchy and candidate.cullingMask&mask~=0 then
                assert(not pool.noteCamera,'Ambiguous original note camera for projected legacy geometry')
                pool.noteCamera=candidate
            end
        end
        assert(pool.noteCamera,'Original note camera missing for projected legacy geometry')
    end
    pool.headMode=CS.System.Enum.Parse(typeof(CS.Malody.Scene.Play.Note.PlayNoteHoldRuntime.HeadType),'None')
end
local function sourcePoolPolicy(pool,note,carrier)
    if not pool.stateField then
        local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic, DeclaredOnly')
        local kind=note:GetType()
        while kind do
            local fields=kind:GetFields(flags)
            for i=0,fields.Length-1 do
                local f=fields[i]
                if f.FieldType.FullName=='Malody.Scene.Play.Note.PlayNoteHoldRuntime' then
                    assert(not pool.stateField,'Ambiguous owned native hold state');pool.stateField=f
                    local members=f.FieldType:GetFields(flags)
                    pool.ownerFields=pool.ownerFields or {}
                    for j=0,members.Length-1 do
                        local member=members[j]
                        if member.Name=='headType' then pool.modeField=member end
                        -- The hold runtime has had more than one carrier-like
                        -- field across maV builds.  Selecting the first field
                        -- by type can bind a stale/reference field and makes
                        -- a valid cloned LN fail with "carrier differs".
                        -- Keep every candidate and select the field whose
                        -- current value owns this exact native carrier.
                        if member.FieldType:Equals(carrier:GetType()) then
                            pool.ownerFields[#pool.ownerFields+1]=member
                        end
                    end
                end
            end
            kind=kind.BaseType
        end
        assert(pool.stateField and pool.modeField and pool.ownerFields and #pool.ownerFields>0,
            'Owned native hold policy fields missing')
    end
    -- InitObject can select the player's current policy. Set BOTH the owned
    -- state value and its public template policy AFTER native initialization,
    -- as the existing ordinary-admission adapter does. Never edit originals.
    local state=assert(pool.stateField:GetValue(note),'Owned native hold state missing')
    local ownerField,owner;local ownerSeen=false
    local function ownerMatches(value)
        if not value then return false end
        if value:Equals(carrier) then return true end
        -- PlayNoteKey.InitObject may copy the public carrier into a private
        -- ChartPlayer.blk wrapper.  The wrapper still points at the same
        -- native NoteObject; use that stable identity when direct wrapper
        -- identity differs across the C# boundary.
        local okOwner,ownerNote=pcall(function() return NativeSourceInput.Get(value,'get_NoteObject') end)
        local okCarrier,carrierNote=pcall(function() return NativeSourceInput.Get(carrier,'get_NoteObject') end)
        return okOwner and okCarrier and ownerNote and carrierNote and ownerNote:Equals(carrierNote)
    end
    for _,candidate in ipairs(pool.ownerFields) do
        local value=candidate:GetValue(state)
        if value then ownerSeen=true end
        if ownerMatches(value) then ownerField,owner=candidate,value;break end
    end
    local resetSucceeded=false
    if not ownerField then
        -- Our source FIFO reuses the native KeySkin object directly, outside
        -- ObjectLayer's normal return-to-pool path.  maV leaves the previous
        -- PlayNoteHoldRuntime owner in that case.  Invoke the runtime's own
        -- public Reset(noteCarrier) before touching headType, then re-read the
        -- state; this is the same lifecycle reset used by native pooling.
        local resetError
        local resetOk,firstError=pcall(function() state:Reset(carrier) end)
        resetError=firstError
        if not resetOk then resetOk,resetError=pcall(function()
            local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic')
            local methods=state:GetType():GetMethods(flags);local reset
            for i=0,methods.Length-1 do
                local method=methods[i]
                if method.Name=='Reset' and method:GetParameters().Length==1 then
                    assert(not reset,'Ambiguous native hold Reset');reset=method
                end
            end
            assert(reset,'Native hold Reset method missing')
            local args=CS.System.Array.CreateInstance(typeof(CS.System.Object),1);args[0]=carrier
            reset:Invoke(state,CS.System.Reflection.BindingFlags.Default,nil,args,nil)
        end) end
        if resetOk then
            resetSucceeded=true
            -- Reset mutates this boxed struct. Persist the complete result,
            -- including its transient hold fields, before reading it again.
            -- Re-reading first discards Reset and only rebinding the carrier
            -- below would leave the previous LN's runtime state behind.
            pool.stateField:SetValue(note,state,CS.System.Reflection.BindingFlags.Default,nil,nil)
            state=assert(pool.stateField:GetValue(note),'Owned native hold state missing after reset')
            ownerSeen=false;ownerField=nil;owner=nil
            for _,candidate in ipairs(pool.ownerFields) do
                local value=candidate:GetValue(state)
                if value then ownerSeen=true end
                if ownerMatches(value) then ownerField,owner=candidate,value;break end
            end
        end
    end
    if not ownerField then
        -- PlayNoteHoldRuntime is a value-type field in this build.  Reset on
        -- the boxed reflection value can return successfully without changing
        -- the value stored by PlayNoteKeySkin.  Rebind the candidate field on
        -- that value and write the complete state back below, matching the
        -- native pool's reinitialization semantics.
        if resetSucceeded then
            local candidate=pool.ownerFields[1]
            local rebound=pcall(function()
                candidate:SetValue(state,carrier,CS.System.Reflection.BindingFlags.Default,nil,nil)
            end)
            if rebound then
                ownerField,owner=candidate,carrier;ownerSeen=true
            end
        end
    end
    assert(ownerSeen,'Owned native hold state owner missing')
    if not ownerField then
        -- Include the live field identities in the failure.  A maV build may
        -- keep the hold runtime's owner as an internal carrier wrapper rather
        -- than the public ChartPlayer carrier; the wrapper must be identified
        -- before we can apply the 437 head policy safely.
        local rows={}
        local function describe(value)
            if not value then return 'nil' end
            local okStart,start=pcall(function() return NativeSourceInput.Get(value,'get_StartOffset') end)
            local okEnd,ending=pcall(function() return NativeSourceInput.Get(value,'get_EndOffset') end)
            local okNote,noteObject=pcall(function() return NativeSourceInput.Get(value,'get_NoteObject') end)
            local noteId='nil'
            if okNote and noteObject then
                local ok,id=pcall(function() return noteObject:GetInstanceID() end)
                noteId=ok and tostring(id) or tostring(noteObject)
            end
            return (okStart and tostring(start) or '?')..','..(okEnd and tostring(ending) or '?')..',note='..noteId
        end
        for _,candidate in ipairs(pool.ownerFields) do
            local value=candidate:GetValue(state)
            local valueType='nil'
            if value then
                local ok,kind=pcall(function() return value:GetType() end)
                valueType=ok and kind.FullName or 'unknown'
            end
            local valueId='nil'
            if value then
                local ok,id=pcall(function() return value:GetInstanceID() end)
                valueId=ok and tostring(id) or tostring(value)
            end
            rows[#rows+1]=candidate.Name..':'..valueType..':'..valueId..':'..describe(value)..':carrier='..describe(carrier)
        end
        error('Owned native hold state carrier differs; reset='..tostring(resetError)..'; fields='..table.concat(rows,'|'))
    end
    assert(ownerField and owner,'Owned native hold state carrier differs')
    local flags=CS.System.Reflection.BindingFlags.Default
    pool.modeField:SetValue(state,pool.headMode,flags,nil,nil)
    pool.stateField:SetValue(note,state,flags,nil,nil)
    note.holdHeadType=pool.headMode
end
local function nativePart3MeshAvailable(row)
    return NativeSourcePart3Mesh and row.note.body and row.note.body.sharedMaterial and row.note.body.sprite
end
local function applySourceNoteVisual(row,recipe)
    -- 437 applies note tint/opacity to the Sprite submissions themselves.
    -- The native carrier is retained for judgement, while source-owned meshes
    -- consume this colour through their vertex colours.  Set every cloned
    -- renderer so both the mesh path and the retained Scale3 path receive the
    -- same value on pool reuse.
    local hex=recipe.note_color or '#FFFFFF'
    assert(type(hex)=='string' and #hex==7 and hex:match('^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$'),
        'Native source note colour is not a six-digit RGB value')
    local r=tonumber(hex:sub(2,3),16)/255
    local g=tonumber(hex:sub(4,5),16)/255
    local b=tonumber(hex:sub(6,7),16)/255
    local a=math.max(0,math.min(100,recipe.note_opacity or 100))/100
    local color
    if CS.UnityEngine.Color then color=CS.UnityEngine.Color(r,g,b,a)
    else color={r=r,g=g,b=b,a=a} -- pure-Lua regression shim
    end
    for _,renderer in ipairs({row.note.body,row.note.tail,row.note.head,row.note.overlap,row.note.rearOverlap}) do
        renderer.color=color
    end
end

-- Part3 attaches three independent 437 submissions as body, head, tail.
-- Whole Scale3 is a different factory: keep its existing native sliced-field
-- order rather than treating that single old node as three Part3 children.
-- UpdateObject and mesh movement can both overwrite renderer order, so run
-- this AFTER movement, including chord head rebinding and slot reuse.
local SORT_MESH_PARTS={'body','head','tail'}
local function applySourceSorting(row,force)
    local base=assert(row.sortingBase,'Source visual slot has no legacy sorting rank')
    if not force and row.sortedBase==base and (not row.part3Mesh or row.meshSortedBase==base) then
        return
    end
    local body,head,tail,overlap,rear=row.note.body,row.note.head,row.note.tail,
        row.note.overlap,row.note.rearOverlap
    if not force and row.sortedBase==base and body.sortingOrder==base and body.sortingLayerName=='Notes' then
        if not row.part3Mesh then return end
        local meshBody=row.part3Mesh.body
        if meshBody and meshBody.renderer and meshBody.renderer.sortingOrder==base and
                meshBody.renderer.sortingLayerID==body.sortingLayerID then
            row.meshSortedBase=base
            return
        end
    end
    body.sortingLayerName='Notes';head.sortingLayerName='Notes';tail.sortingLayerName='Notes'
    overlap.sortingLayerName='Notes';rear.sortingLayerName='Notes'
    body.sortingOrder=base
    if row.part3Mesh then
        overlap.sortingOrder=base+1
        rear.sortingOrder=base+2
        head.sortingOrder=base+3
        tail.sortingOrder=base+4
        -- Meshes can be created before the cloned source fields have their
        -- final sorting domain. Restore the actual layer ID as well as order.
        local layerId=body.sortingLayerID
        for index=1,3 do
            local part=row.part3Mesh[SORT_MESH_PARTS[index]]
            if part and part.renderer then
                part.renderer.sortingLayerID=layerId
                part.renderer.sortingOrder=base+index-1
            end
        end
        if row.part3Mesh.renderer then
            row.part3Mesh.renderer.sortingLayerID=layerId
            row.part3Mesh.renderer.sortingOrder=base
        end
        row.meshSortedBase=base
    else
        tail.sortingOrder=base+1
        head.sortingOrder=base+2
        overlap.sortingOrder=base+3
        rear.sortingOrder=base+4
    end
    row.sortedBase=base
end
local function sourcePart3Visibility(row,visible)
    if row.object then row.object:SetActive(visible) end
    local state=row.part3Mesh
    if state then
        for _,part in ipairs({state.body,state.head,state.tail}) do
            if part and part.object then
                local act=visible and part.draw_visible~=false
                part.object:SetActive(act)
                part.last_active=act
            end
        end
    end
    row.visible=visible
end
local function sourceGroupedMoveCanSkip(pool,row,n,recipe,current)
    -- Legacy projection is perspective: a translated cached mesh is no
    -- longer the projection of the source point at the new chart time.
    -- Recompute it every admitted frame, even while its carrier range is
    -- otherwise rigid and shareable through a motion group.
    if recipe.legacy_projected then return false end
    local groups=pool.groups
    if not groups or row.groupOwner~=n or row.groupEpoch~=groups.epoch then return false end
    local previous=row.groupLastCurrent
    -- A reverse scroll, speed rebase or first bind must revisit the boundary
    -- test. Stable forward frames already move through the shared parent.
    if previous==nil or current<previous then return false end
    if nativeSourceRetainedFactory(recipe.factory) then
        local state=pool.states[n.nid]
        if row.groupRigid and not (state and state.held) and n.end_y<=current+pool.config.distance then
            row.groupLastCurrent=current
            return true
        end
    elseif not row.groupFar and n.display_y<=current+pool.config.distance then
        row.groupLastCurrent=current
        return true
    end
    return false
end
local function legacyPart3Size(recipe,ratio,fallback)
    -- Only an active original size2 pair enables SetSize in Move. Without
    -- it, retain each Sprite's independently resolved size; never inject an
    -- intrinsic-texture endpoint. Keep the original float32 arithmetic.
    local start=recipe.legacy_size_start;local finish=recipe.legacy_size_end
    if not (start and finish and start[1] and start[2] and finish[1] and finish[2]) then
        return fallback
    end
    local f=scale3float;local t=f(ratio)
    return {f(f(finish[1]-start[1])*t+start[1]),
        f(f(finish[2]-start[2])*t+start[2])}
end
-- Travel belongs to the source lane; the display window alone is global.
local function sourceLaneTravel(pool,recipe,lane)
    local list=pool.config.motion.lane_travel_720
    if list and list[lane] then return list[lane] end
    if recipe.layout and recipe.layout.travel_720 then return recipe.layout.travel_720 end
    if recipe.start_y and recipe.end_y then return recipe.start_y-recipe.end_y end
    return pool.config.motion.travel_720
end
local function sourcePoolMove(pool,row,n,current)
    if not pool.config.motion then return end
    local recipe=scale3Recipes[n.lane]
    if sourceGroupedMoveCanSkip(pool,row,n,recipe,current) then return end
    if pool.groups and not nativeSourceRetainedFactory(recipe.factory) then
        NativeSourceGroups.Bind(pool.groups,row,n,current,scale3Recipes)
        return
    end
    local rect,unit
    if pool.groups and row.groupOwner==n then
        -- The owned binding already captured these values. Its epoch
        -- handles flow changes; stable frames need no boxed Rect read.
        rect,unit=row.groupRect,row.groupUnit
    else
        rect=row.rectNoteRange
        if not rect then rect=row.note.rectNoteRange;row.rectNoteRange=rect end
    end
    local function resolveUnit()
        if unit then return unit end
        local S=CS.UnityEngine and CS.UnityEngine.Screen
        local sw,sh=S and S.width,S and S.height
        local units=pool.laneUnits
        if sw and sh and units and pool.unitSw==sw and pool.unitSh==sh and units[n.lane] then
            unit=units[n.lane]
        else
            unit=rect.rect.width/recipe.lane_width_720
            if sw and sh then
                if not units or pool.unitSw~=sw or pool.unitSh~=sh then
                    units={};pool.laneUnits=units;pool.unitSw=sw;pool.unitSh=sh
                end
                units[n.lane]=unit
            end
        end
        return unit
    end
    local head,tail,part3State,part3Geometry,canSaveRigid,isHold,hidden
    if nativeSourceRetainedFactory(recipe.factory) then
        isHold=n.endtime>n.time
        local state
        if isHold then
            state=pool.states[n.nid]
            if not state then state={};pool.states[n.nid]=state end
            part3State=state
        end
        local headRatio
        if state then
            headRatio,tail,hidden=NativeSourcePart3.Step(state,n,current,pool.config.distance,state.held,recipe.toggle)
        else
            headRatio=scale3float((n.display_y-current)/pool.config.distance)
            tail=headRatio
        end
        local plane=pool.config.motion.legacy_play_plane
        local rigidReady=not hidden and plane and plane.default_2d and
            not recipe.legacy_size_start and recipe.start_x and recipe.end_x and
            nativeSourcePart3Factory(recipe.factory) and row.part3Mesh and row.part3Mesh.projectionRoot and
            not (state and (state.held or state.hidden)) and
            ((not isHold and n.display_y<=current+pool.config.distance) or
             (isHold and n.end_y<=current+pool.config.distance))
        local p3=row.p3Rigid
        if rigidReady and p3 and p3.carrier==row.carrier and p3.recipe==recipe and
                p3.distance==pool.config.distance and p3.chord==row.chord and
                p3.has_tail==isHold and current>=p3.baseCurrent and
                NativeSourcePart3Mesh and NativeSourcePart3Mesh.UpdateRigid then
            local t=-(current-p3.baseCurrent)/pool.config.distance
            if NativeSourcePart3Mesh.UpdateRigid(row,recipe,isHold,p3.dxSpan*t,p3.dySpan*t,p3.dzSpan*t) then
                return
            end
        end
        if plane and not plane.default_2d and recipe.legacy_projected and
                (recipe.factory or 'part3')=='part3' and recipe.start_x and recipe.end_x and
                row.part3Mesh and NativeSourcePart3Mesh and NativeSourcePart3Mesh.UpdateProjectedFast then
            if hidden then
                LegacyLifetime.Visibility(pool.lifetime,row.module,false)
                sourcePart3Visibility(row,false)
            end
            NativeSourcePart3Mesh.UpdateProjectedFast(row,recipe,isHold,headRatio,tail,
                plane,pool.noteCamera,pool.root.transform)
            row.p3Rigid=nil
            return
        end
        canSaveRigid=rigidReady
        head=headRatio
        if recipe.start_x and recipe.end_x then
            local hx=NativeSourceGeometry.Position(recipe.start_x,recipe.end_x,headRatio)
            local tx=NativeSourceGeometry.Position(recipe.start_x,recipe.end_x,tail)
            local hy=NativeSourceGeometry.Position(recipe.start_y,recipe.end_y,headRatio)
            local ty=NativeSourceGeometry.Position(recipe.start_y,recipe.end_y,tail)
            local fixedHead=isHold and recipe.head_size or recipe.tap_head_size or recipe.head_size
            local fixedTail=isHold and recipe.tail_size or recipe.tap_head_size or recipe.head_size
            local headSize=legacyPart3Size(recipe,head,fixedHead)
            local tailSize=legacyPart3Size(recipe,tail,fixedTail)
            local bodyPoints,meta=NativeSourceGeometry.BodyPoints({hx,hy},{tx,ty},headSize,tailSize,
                recipe.anchor,recipe.rotate,recipe.body_axis)
            local headCx,headCy=NativeSourceGeometry.Center(hx,hy,headSize[1],headSize[2],
                recipe.anchor,recipe.rotate)
            local tailCx,tailCy=NativeSourceGeometry.Center(tx,ty,tailSize[1],tailSize[2],
                recipe.anchor,recipe.rotate)
            part3Geometry={head_x=hx,tail_x=tx,head_y=hy,tail_y=ty,points=meta,vertices=bodyPoints,
                has_tail=isHold,
                head_vertices=NativeSourceGeometry.HeadPoints(headCx,headCy,headSize,recipe.rotate),
                tail_vertices=isHold and NativeSourceGeometry.HeadPoints(tailCx,tailCy,tailSize,recipe.rotate) or nil}
            if recipe.factory=='scale3part3' then
                part3Geometry.vertices,part3Geometry.sliced_body=NativeSourceFactory.Scale3Part3(
                    recipe,part3Geometry.head_vertices,part3Geometry.tail_vertices or part3Geometry.head_vertices)
            elseif recipe.factory=='tile3' then
                part3Geometry.vertices,part3Geometry.body_crops=NativeSourceFactory.Tile3(
                    recipe,part3Geometry.head_vertices,part3Geometry.tail_vertices or part3Geometry.head_vertices)
            end
        end
        -- The old MUI stores trajectory endpoints per lane.  A radial or
        -- otherwise nonuniform Key skin can have a zero-length lane, so the
        -- shared validation travel is not the lane's actual local motion.
        local laneTravel=(recipe.start_y or pool.config.motion.travel_720)-(recipe.end_y or 0)
        head=NativeSourcePart3.Position(laneTravel,0,head)*resolveUnit()
        tail=NativeSourcePart3.Position(laneTravel,0,tail)*resolveUnit()
        if hidden then
            LegacyLifetime.Visibility(pool.lifetime,row.module,false)
            sourcePart3Visibility(row,false)
        end
    else head,tail=NativeSourceMotion.Range(pool.config.motion,n,current,pool.config.distance,resolveUnit(),sourceLaneTravel(pool,recipe,n.lane)) end
    local changed=true
    local ownsProjectedMesh=nativeSourcePart3Factory(recipe.factory) and part3Geometry and row.part3Mesh
    local skipNativeRange=ownsProjectedMesh and recipe.legacy_projected==true and pool.config.motion.legacy_play_plane~=nil
    if pool.groups then
        changed=NativeSourceGroups.BindPart3(pool.groups,row,n,current,recipe,
            part3State and part3State.head or n.display_y,part3State and part3State.held,head,tail)
    elseif not skipNativeRange then
        local low,high=rect.offsetMin,rect.offsetMax
        local V=CS.UnityEngine.Vector2
        rect.offsetMin=V(low.x,head);rect.offsetMax=V(high.x,tail)
    end
    -- OnWillRenderObject is too late/visibility-dependent after a source
    -- contraction changes this native range. Flush its EXISTING C++ size
    -- cache now, or a correct rect can still draw yesterday's long body.
    if row.part3Layout and changed and not ownsProjectedMesh then
        row.part3Layout:UpdateSpriteSize()
    end
    if ownsProjectedMesh then
        NativeSourcePart3Mesh.Update(row,recipe,part3Geometry,resolveUnit(),
            pool.config.motion.legacy_play_plane,pool.noteCamera,pool.root.transform)
        if canSaveRigid and NativeSourcePart3Mesh.Displacement then
            local dxSpan,dySpan,dzSpan=NativeSourcePart3Mesh.Displacement(pool.noteCamera,pool.root.transform,rect,
                pool.config.motion.legacy_play_plane,recipe.start_x-recipe.end_x,recipe.start_y-recipe.end_y)
            row.p3Rigid={carrier=row.carrier,recipe=recipe,distance=pool.config.distance,chord=row.chord,
                has_tail=isHold,baseCurrent=current,dxSpan=dxSpan,dySpan=dySpan,dzSpan=dzSpan}
        else
            row.p3Rigid=nil
        end
    end
end
local function sourcePoolSlot(pool,module,carrier,lane,n,current)
    local row=pool.slots[module]
    if not row then
        assert(module<=pool.config.capacity,'Source visual pool exceeds its native sorting range')
        local object=CS.UnityEngine.Object.Instantiate(pool.template,pool.root.transform,false)
        object.name='legacy-source-native-note-'..module
        local note=assert(object:GetComponent(typeof(CS.Malody.Scene.Play.Note.PlayNoteKeySkin)))
        row={object=object,note=note,module=module};pool.slots[module]=row
        if nativeSourceRetainedFactory(scale3Recipes[lane].factory) then
            local ok,layout=pcall(function()
                return note.body:GetComponent(typeof(CS.Malody.UI.UISpriteRect))
            end)
            if ok then row.part3Layout=layout end
        end
        NATIVE_SOURCE_POOL.created=NATIVE_SOURCE_POOL.created+1
    elseif row.carrier then
        NATIVE_SOURCE_POOL.reused=NATIVE_SOURCE_POOL.reused+1
    end
    -- Preparation also discovers the native size/style metadata on a FIRST
    -- allocation. It is not merely a restore step for reused visual slots.
    row.cached_depth=nil
    row.fast_ready_ver=nil
    row.slot_ver=(row.slot_ver or 0)+1
    local recipe=scale3Recipes[lane]
    row.chord=n.chord==true
    if row.part3Mesh and not nativeSourcePart3Factory(recipe.factory) then
        NativeSourcePart3Mesh.Dispose(row)
    end
    if recipe.factory=='scale3' then prepareScale3Admission(row.note,carrier,lane) end
    local before=NativeSourceInput.Get(carrier,'get_NoteObject')
    row.object:SetActive(true);row.visible=true;row.note.holdHeadType=pool.headMode
    row.note:InitObject(carrier,pool.layer)
    local after=NativeSourceInput.Get(carrier,'get_NoteObject')
    local same=(before==nil and after==nil) or before and after and before:Equals(after)
    if not same then
        NATIVE_SOURCE_POOL.original_native_links_changed=NATIVE_SOURCE_POOL.original_native_links_changed+1
        error('Source visual initialization must never rebind original carrier.NoteObject')
    end
    NATIVE_SOURCE_POOL.links_preserved=NATIVE_SOURCE_POOL.links_preserved+1
    applySourceNoteVisual(row,recipe)
    local angle=recipe.rotate or 0
    if angle~=0 then
        local rotation=CS.UnityEngine.Quaternion.Euler(0,0,-angle)
        for _,renderer in ipairs({row.note.body,row.note.tail,row.note.head,row.note.overlap,row.note.rearOverlap}) do
            renderer.transform.localRotation=rotation
        end
    end
    -- The original tap has no hold-runtime owner. Only an LN needs its owned
    -- visual policy adjusted; a missing/mismatched LN owner remains an error.
    if n.endtime>n.time then sourcePoolPolicy(pool,row.note,carrier) end
    row.note:UpdateObject()
    NATIVE_SOURCE_POOL.cpp_updates=NATIVE_SOURCE_POOL.cpp_updates+1
    if nativeSourcePart3Factory(recipe.factory) and nativePart3MeshAvailable(row) then
        NativeSourcePart3Mesh.Ensure(row,recipe,n.endtime>n.time,pool.root.transform)
    end
    sourcePoolMove(pool,row,n,current)
    local sourceHeight
    if pool.config.motion and recipe.factory=='scale3' then
        sourceHeight=NativeSourceMotion.AdmittedHeight(pool.config.motion,n,scale3Recipes[lane].layout)
    end
    if recipe.factory=='scale3' then finishScale3Admission(row.note,carrier,lane,pool.layer,sourceHeight) end
    row.carrier=carrier;row.lane=lane
    row.sortingBase=pool.config.base+(module-1)*5
    applySourceSorting(row,true)
    return row
end
local function sourceSetVisible(row,visible)
    if row.visible~=visible then sourcePart3Visibility(row,visible) end
end
local function sourceHideHit(pool,carrier)
    local found=false
    for module,row in pairs(pool.slots) do
        if row.carrier and row.carrier:Equals(carrier) then
            found=true
            local recipe=scale3Recipes[row.lane]
            -- Plain Part3 toggle 1 hides a completed retained head, NOT a
            -- successfully hit LN. Without bit 2 that head never advances
            -- to the tail; source FIFO retirement owns its eventual exit.
            local hold=row.owner and row.owner.endtime>row.owner.time
            if recipe.toggle&1~=0 and not (nativeSourceRetainedFactory(recipe.factory) and hold) then
                LegacyLifetime.Visibility(pool.lifetime,module,false)
                sourceSetVisible(row,false)
            end
        end
    end
    return found
end
local function nativeSourcePoolHit()
    if not sourcePool then return end
    local event=Game:HitEvent()
    local grade=event:JudgeResult()
    if grade<1 or grade>4 then return end
    local carrier=scale3HitCarrier(event)
    if not carrier then return end
    local sourceNote=sourcePool.byCarrier and sourcePool.byCarrier[sourceCarrierId(carrier)]
    local sourceRecipe=sourceNote and scale3Recipes[sourceNote.lane]
    if (not sourceRecipe or nativeSourceRetainedFactory(sourceRecipe.factory)) and sourcePool.config.motion and
        (sourcePool.config.motion.scope=='legacy-linear-part3-v1' or sourcePool.config.motion.scope=='legacy-mixed-v1') then
        sourcePool.events[#sourcePool.events+1]={carrier=carrier,grade=grade,time=event:Time(),
            start=NativeSourceInput.Get(carrier,'get_StartOffset')}
        return
    end
    if grade==4 then return end
    if sourcePool.lifetime and sourceHideHit(sourcePool,carrier) then return end
    for _,old in ipairs(sourcePool.pending) do if old:Equals(carrier) then return end end
    sourcePool.pending[#sourcePool.pending+1]=carrier
end
local function nativeSourcePoolInput(lane,kind,time)
    if not sourcePool or not sourcePool.config.motion then return end
    if kind==3 and scale3Recipes[lane] and nativeSourceRetainedFactory(scale3Recipes[lane].factory) and
        (sourcePool.config.motion.scope=='legacy-linear-part3-v1' or sourcePool.config.motion.scope=='legacy-mixed-v1') then
        sourcePool.events[#sourcePool.events+1]={lane=lane,release=true,time=time}
    end
end
local function sourcePoolEvents(pool,judgeTime)
    local count=#pool.events;local pending=0
    for _,event in ipairs(pool.events) do
        -- Native Auto can dispatch its nominal timestamp before the current
        -- fractional display frame reaches that time. 437's Auto KeyUIS has
        -- not hit yet on that frame. Keep the visual event until its clock;
        -- gameplay judgement and the event itself stay owned by maV.
        if event.time and event.time>judgeTime then
            pending=pending+1;pool.events[pending]=event
        else
        if event.release then
            local bucket=pool.heldByLane[event.lane]
            if bucket then
                for nid,state in pairs(bucket) do
                    local n=pool.scroll.notes[nid]
                    NATIVE_SOURCE_POOL.release_candidates=NATIVE_SOURCE_POOL.release_candidates+1
                    if state.held and event.time and event.time>=n.endtime then
                        state.tailCommitted=true
                    else
                        state.held=false
                    end
                end
                -- A completed tail remains visually held while its retained
                -- head finishes, but it no longer needs a later lane scan.
                pool.heldByLane[event.lane]=nil
            end
        else
            local found
            for _,n in ipairs(pool.byStart[event.start] or {}) do
                if pool.input.carriers[n.nid]:Equals(event.carrier) then found=n;break end
            end
            assert(found,'Original Part3 hit has no source owner')
            local n=found;local recipe=scale3Recipes[n.lane]
            if not nativeSourceRetainedFactory(recipe.factory) then
                if event.grade~=4 then sourceHideHit(pool,event.carrier) end
            elseif n.endtime>n.time then
                local state=pool.states[n.nid]
                if not state then state={};pool.states[n.nid]=state end
                if event.grade~=4 and event.time>=n.endtime and state.held then
                    state.tailCommitted=true
                    sourceHoldMembership(pool,n,state,false)
                else
                    state.held=event.grade~=4 and event.time<n.endtime
                    sourceHoldMembership(pool,n,state,state.held)
                end
                -- Capture in the first held Move. An invented fixed frame
                -- interval changes retained distance and is not an old rule.
            elseif event.grade~=4 and not sourceHideHit(pool,event.carrier) then
                pool.pending[#pool.pending+1]=event.carrier
            end
        end
        end
    end
    -- Keep the event buffer across idle frames. Replacing it allocated one
    -- empty table per rendered frame even after the entire chart retired.
    for i=count,pending+1,-1 do pool.events[i]=nil end
end
local function sourcePoolMembers(pool,frame)
    local rows={}
    for _,entry in ipairs(frame.drawables) do
        local n=entry.note;local row=pool.slots[entry.module]
        rows[#rows+1]=string.format('{"module":%d,"nid":%d,"lane":%d,"id":%d,"time":%.17g,"endtime":%.17g,"head_y":%.17g,"tail_y":%.17g,"chord":%s}',
            entry.module,n.nid,n.lane,row.note:GetInstanceID(),n.time,n.endtime,n.display_y,n.end_y,row.chord and 'true' or 'false')
    end
    NATIVE_SOURCE_MEMBERS='['..table.concat(rows,',')..']'
end
local function updateNativeSourcePool()
    local pool=sourcePool
    if not pool then return end
    if not pool.input then
        local U=CS.UnityEngine
        local layers=U.Object.FindObjectsOfType(typeof(CS.Malody.Play.NoteLayer),false)
        assert(layers.Length==1,'Source visuals require one original NoteLayer')
        pool.input=NativeSourceInput.Read(layers[0])
        if not pool.input then return end
        pool.scroll=LegacyScroll.Build(pool.input)
        pool.byStart={};pool.byCarrier={}
        for _,n in pairs(pool.scroll.notes) do
            -- 437's source clock truncates to integer ms; a real MC native
            -- carrier can retain fractional offsets. Index its identity by
            -- the ORIGINAL carrier offset, never by a source visual time.
            local carrier=pool.input.carriers[n.nid]
            local start=NativeSourceInput.Get(carrier,'get_StartOffset')
            local bucket=pool.byStart[start] or {};pool.byStart[start]=bucket;bucket[#bucket+1]=n
            pool.byCarrier[sourceCarrierId(carrier)]=n
        end
        pool.lifetime=LegacyLifetime.New(pool.scroll,pool.config.distance,pool.config.judge_ahead)
        sourcePoolObjects(pool,layers[0])
        -- Other Mods retain the original per-object visual update path;
        -- their alpha/appearance semantics are not assumed affine.
        if pool.config.motion and pool.config.motion.affine_groups and pool.input.native_mods==0 then
            pool.groups=NativeSourceGroups.New(pool.root,pool.config.motion,pool.config.distance)
            NATIVE_SOURCE_POOL.fast_motion=1
        end
    end
    if pool.config.motion and pool.config.motion.speed_source=='native-layer' then
        local speed=NativeSourceInput.VisualSpeed(pool.input)
        if speed~=pool.config.motion.speed then
            pool.config.motion.speed=speed
            pool.config.distance=632.5/scale3float(speed*scale3float(pool.config.motion.scale))
            pool.lifetime.distance=pool.config.distance
            if pool.groups then NativeSourceGroups.Reconfigure(pool.groups,pool.config.distance) end
        end
    end
    local judgeTime,displayTime=NativeSourceInput.Times(pool.input)
    sourcePoolEvents(pool,judgeTime)
    local frame=LegacyLifetime.Step(pool.lifetime,judgeTime,displayTime,pool.frame)
    pool.frame=frame
    if pool.groups then NativeSourceGroups.Update(pool.groups,frame.display_y) end
    for _,event in ipairs(frame.events) do
        if event.operation=='admit' then
            local n=event.note
            local row=sourcePoolSlot(pool,event.module,assert(pool.input.carriers[n.nid]),n.lane,n,frame.display_y)
            row.owner=n
            NATIVE_SOURCE_POOL.admitted=NATIVE_SOURCE_POOL.admitted+1
        else
            if event.hide then sourceSetVisible(assert(pool.slots[event.module]),false) end
            NATIVE_SOURCE_POOL.retired=NATIVE_SOURCE_POOL.retired+1
        end
    end
    for i=#pool.pending,1,-1 do
        if sourceHideHit(pool,pool.pending[i]) then table.remove(pool.pending,i) end
    end
    local visible=0
    for _,entry in ipairs(frame.drawables) do
        local row=assert(pool.slots[entry.module]);local draw=entry.slot.busy
        assert(row.owner==entry.note,'Source drawable lost its first-free slot owner')
        sourceSetVisible(row,draw)
        if draw then
            local recipe=scale3Recipes[entry.note.lane]
            local skipNative=(row.part3Mesh~=nil and recipe~=nil and recipe.legacy_projected==true)
            if not pool.groups and not skipNative then
                row.note:UpdateObject();NATIVE_SOURCE_POOL.cpp_updates=NATIVE_SOURCE_POOL.cpp_updates+1
            end
            -- UpdateObject and native pool checkout can restore prefab order;
            -- repair it after the native update and before the frame is drawn.
            sourcePoolMove(pool,row,entry.note,frame.display_y)
            applySourceSorting(row,not pool.groups and not skipNative)
            if row.visible then visible=visible+1 end
            NATIVE_SOURCE_POOL.updates=NATIVE_SOURCE_POOL.updates+1
        end
    end
    if #frame.events>0 or not pool.members then sourcePoolMembers(pool,frame);pool.members=true end
    local stats=NATIVE_SOURCE_POOL
    stats.frames=stats.frames+1;stats.visible=visible;stats.active=#frame.active
    stats.judge_time=judgeTime;stats.display_time=displayTime;stats.source_y=frame.display_y
    stats.motion_speed=pool.config.motion and pool.config.motion.speed or 0;stats.motion_distance=pool.config.distance
    if pool.groups then stats.group_moves=pool.groups.moves end
end
