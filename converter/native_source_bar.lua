-- 437 BarFactory -> NoteSprite (0x4f29f0 kind=0, 0x4f1120 move).
-- Read original Key bar carriers; adapt appearance only. No queue, input,
-- judge, Replay, score eligibility or clock writes and no Free APIs.
local NativeSourceBars={}
function NativeSourceBars.Assign(state,active,create,hide)
    local present={};local rows={}
    -- BarFactoryCreate (0x4f3390) selects the LAST unused object in its
    -- creation vector. New admissions precede this frame's FIFO retirement.
    for _,bar in ipairs(active) do
        present[bar]=true
        local part=state.owners[bar]
        if not part then
            for _,candidate in ipairs(state.parts) do if not candidate.owner then part=candidate end end
            if not part then part=create(#state.parts+1);state.parts[#state.parts+1]=part end
            part.owner=bar;state.owners[bar]=part
        end
        rows[#rows+1]={bar=bar,part=part}
    end
    for bar,part in pairs(state.owners) do
        if not present[bar] then hide(part);part.owner=nil;state.owners[bar]=nil end
    end
    return rows
end
function NativeSourceBars.Geometry(recipe,barY,current,distance)
    local f=scale3float
    local ratio=barY>current+distance and 1 or f((barY-current)/distance)
    local x=NativeSourceGeometry.Position(recipe.start[1],recipe.finish[1],ratio)
    local y=NativeSourceGeometry.Position(recipe.start[2],recipe.finish[2],ratio)
    local size=recipe.size
    if recipe.end_size and barY<=current+distance then
        size={NativeSourceGeometry.Position(size[1],recipe.end_size[1],ratio),
            NativeSourceGeometry.Position(size[2],recipe.end_size[2],ratio)}
    end
    local cx,cy=NativeSourceGeometry.Center(x,y,size[1],size[2],recipe.anchor,recipe.rotate)
    return NativeSourceGeometry.HeadPoints(cx,cy,size,recipe.rotate)
end
function NativeSourceBars.Reset()
    local state=NativeSourceBars.state
    if state then
        for _,part in ipairs(state.parts) do NativeSourcePart3Mesh.DisposeSprite(part) end
        for _,row in pairs(state.masked) do
            if not row.renderer:Equals(nil) then row.renderer.enabled=row.enabled end
        end
    end
    NativeSourceBars.state=nil
end
local function maskNativeBars(state,U)
    local layer=state.bar_layer
    if (not layer or layer:Equals(nil)) and CS.Malody and CS.Malody.Play and CS.Malody.Play.BarLayer then
        layer=U.Object.FindObjectOfType(typeof(CS.Malody.Play.BarLayer))
        state.bar_layer=layer
        state.bar_transform=layer and layer.transform or nil
        state.bar_child_count=nil
    end
    local renderers=state.native_renderers
    local usedFallback=true
    if layer and state.bar_transform and not layer:Equals(nil) then
        usedFallback=false
        local transform=state.bar_transform
        local count=transform.childCount
        if state.bar_child_count~=count or not renderers then
            renderers={}
            for i=0,count-1 do
                local child=transform:GetChild(i)
                local renderer=child and child.gameObject:GetComponent(typeof(U.SpriteRenderer))
                if renderer then
                    renderers[#renderers+1]=renderer
                    local id=renderer:GetInstanceID()
                    if not state.masked[id] then state.masked[id]={renderer=renderer,enabled=renderer.enabled} end
                end
            end
            state.native_renderers=renderers
            state.bar_child_count=count
        end
    else
        local tick=(state.fallback_tick or 0)+1
        state.fallback_tick=tick
        if not renderers or (#renderers==0 and tick%30==1) then
            renderers={}
            local native=U.Object.FindObjectsOfType(typeof(CS.Malody.Scene.Play.Note.PlayBarKey),false)
            for i=0,native.Length-1 do
                local renderer=native[i].gameObject:GetComponent(typeof(U.SpriteRenderer))
                if renderer then
                    renderers[#renderers+1]=renderer
                    local id=renderer:GetInstanceID()
                    if not state.masked[id] then state.masked[id]={renderer=renderer,enabled=renderer.enabled} end
                end
            end
            state.native_renderers=renderers
        end
    end
    for i=1,#renderers do
        local renderer=renderers[i]
        if renderer and (not usedFallback or not renderer:Equals(nil)) and renderer.enabled then
            local id=renderer:GetInstanceID()
            if not state.masked[id] then state.masked[id]={renderer=renderer,enabled=true} end
            renderer.enabled=false
        end
    end
end
function NativeSourceBars.Update(pool,recipe,suppress)
    if not recipe and not suppress then return end
    local U=CS.UnityEngine
    local state=NativeSourceBars.state
    if not recipe then
        if not state then
            state={parts={},owners={},masked={}}
            NativeSourceBars.state=state
        end
        maskNativeBars(state,U)
        return
    end
    if not pool or not pool.frame then return end
    if not state then
        local bars,begin=NativeSourceInput.Bars(pool.input,pool.scroll)
        state={lifetime=LegacyLifetime.NewBars(bars),parts={},owners={},masked={},begin=begin}
        NativeSourceBars.state=state
    end
    -- Native bar checkout restores its renderer. Mask the real provider each
    -- post-layer frame using cached BarLayer children instead of scanning the scene.
    maskNativeBars(state,U)
    local frame=pool.frame
    local active=LegacyLifetime.StepBars(state.lifetime,frame and NATIVE_SOURCE_POOL.judge_time or 0,
        frame.display_y,pool.config.distance)
    local depth=pool.noteCamera:WorldToScreenPoint(pool.root.transform.position).z
    local rows=NativeSourceBars.Assign(state,active,function(index)
        local order=(recipe.before_notes and -32768 or pool.config.base+pool.config.capacity*5)+index-1
        assert(order<=32767 and (not recipe.before_notes or order<pool.config.base),
            'Source bar painter order exceeds the native range')
        return NativeSourcePart3Mesh.NewSprite(pool.root,'legacy-source-bar-slot-'..index,
            NativeUiSampling.Sprite(recipe.file),order)
    end,function(part)part.object:SetActive(false)end)
    for _,row in ipairs(rows) do
        local part,bar=row.part,row.bar
        part.object.name='legacy-source-bar-'..string.format('%.17g',bar.offset)
        local points=NativeSourceBars.Geometry(recipe,bar.displayY,frame.display_y,pool.config.distance)
        NativeSourcePart3Mesh.UpdateSprite(part,points,pool.config.motion.legacy_play_plane,
            pool.noteCamera,pool.root.transform,depth,recipe.color or {255,255,255})
    end
end
