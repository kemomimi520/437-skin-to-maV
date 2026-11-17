-- Ordinary Key renderer-order candidate. Logical first-free slots use the
-- observed NATIVE active-list timeline. Source lifetime equality is unproven.
local nativePainter,nativePainterConfig,nativePainterRecords,nativePainterGroups
local function nativePainterRestore()
    for _,row in pairs(nativePainterRecords or {}) do
        if CS.UnityEngine.Object.op_Implicit(row.note) then
            for _,r in ipairs(row.renderers) do r.object.sortingOrder=r.order end
        end
    end
end
local function initNativePainter(data)
    nativePainterRestore()
    nativePainterConfig=data.native_painter;nativePainterRecords={};nativePainterGroups={}
    if not nativePainterConfig then nativePainter=nil;return end
    assert(nativePainterConfig.scope=='native-membership-only','Unverified native painter lifetime scope')
    local config=nativePainterConfig
    assert(math.type(config.base)=='integer' and config.base>=-32768 and
        math.type(config.capacity)=='integer' and config.capacity>0 and config.base+config.capacity*5-1<=32767,
        'Invalid native painter sorting range')
    nativePainter=NativePainterSlots.New(config.capacity)
    NATIVE_PAINTER={scope=config.scope,source_lifetime_verified=false,frames=0,allocations=0,reuses=0,slots=0,hidden_releases=0}
end
local function nativePainterInspect(note,carrier,lane,isHold)
    if not nativePainter then return end
    local id=note:GetInstanceID();local row=nativePainterRecords[id]
    if not row then
        row={note=note,renderers={}};nativePainterRecords[id]=row
        local layer,group
        for _,r in ipairs({note.body,note.tail,note.head,note.overlap,note.rearOverlap}) do
            if r then
                assert(layer==nil or layer==r.sortingLayerID,'Native painter renderers span sorting layers')
                layer=r.sortingLayerID
                local parent=r.transform;local owningGroup=0
                while parent do
                    local g=parent.gameObject:GetComponent(typeof(CS.UnityEngine.Rendering.SortingGroup))
                    if g and g.enabled then owningGroup=g:GetInstanceID();break end
                    parent=parent.parent
                end
                assert(group==nil or group==owningGroup,'Native painter renderers span sorting groups')
                group=owningGroup
                row.renderers[#row.renderers+1]={object=r,order=r.sortingOrder}
            end
        end
        assert(#row.renderers==5,'Native painter requires original five KeySkin renderer fields')
        -- All families must share the same outer ordering domain. Changing
        -- inner Renderer orders cannot overcome different SortingGroups.
        if nativePainterGroups.layer~=nil then
            assert(nativePainterGroups.layer==layer and nativePainterGroups.group==group,
                'Original note families do not share one sorting domain')
        else nativePainterGroups.layer=layer;nativePainterGroups.group=group end
    end
    -- Unity managed equality is not Lua userdata identity. Preserve a stable
    -- token while the original carrier reference remains equal.
    if not row.carrier or not carrier:Equals(row.carrier) then row.token={};row.carrier=carrier end
    local record=NativePainterSlots.Touch(nativePainter,id,row.token,tostring(lane)..(isHold and ':hold' or ':tap'))
    row.slot=record.slot
end
local function beginNativePainter()
    if nativePainter then NativePainterSlots.Begin(nativePainter) end
end
local function nativePainterSourceHidden(note,carrier)
    if not nativePainter then return end
    local row=assert(nativePainterRecords[note:GetInstanceID()],'Native painter hidden object was not observed')
    assert(row.carrier:Equals(carrier),'Native painter hidden carrier was reused')
    NativePainterSlots.Hide(nativePainter,note:GetInstanceID(),row.token)
    NATIVE_PAINTER.hidden_releases=NATIVE_PAINTER.hidden_releases+1
end
local function finishNativePainter()
    if not nativePainter then return end
    NativePainterSlots.Finish(nativePainter)
    for id,record in pairs(nativePainter.owners) do
        local row=nativePainterRecords[id];local base=nativePainterConfig.base+(record.slot.rank-1)*5
        -- Scale3's middle, upper cap, lower cap occupy consecutive orders.
        -- The two carrier-only overlap fields remain inside this family.
        if record.slot.owner==record then
            for i,r in ipairs(row.renderers) do r.object.sortingOrder=base+i-1 end
        end
    end
    NATIVE_PAINTER.frames=nativePainter.frame;NATIVE_PAINTER.allocations=nativePainter.allocations
    NATIVE_PAINTER.reuses=nativePainter.reuses;NATIVE_PAINTER.slots=nativePainter.next
end
