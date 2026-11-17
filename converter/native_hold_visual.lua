-- Research adapter for the original Key renderer's head policy. It uses
-- ordinary OnHit/OnInput, never a Free note callback. Only the two visual
-- enums and the visual head distance may be written. The engine's already
-- evaluated visual distance is read; chart, input, judge, score, replay and settings are
-- never changed. The adapter remains blocked from public MSZ export until its
-- old/new state transitions and platform behaviour have been verified.
local holdModes,holdEventCarrier,holdObjectMethod,holdStateField,holdModeField,holdHeadField
local holdPublicFlags,holdAllFlags,holdDeclaredFlags,holdDefaultFlags,holdEmptyArguments
local holdDeltaField,holdRuntimeCarrierField,holdRecords
local holdNames={[0]='None',[1]='StopOnHit'}
local function noteObjectGetter(kind)
    -- GetMethod(string, number) is ambiguous in xLua between its Type[]
    -- and BindingFlags overloads. Enumerate the public zero-argument getter
    -- once; do not rely on Lua-number enum overload selection.
    local methods=kind:GetMethods(holdPublicFlags)
    for i=0,methods.Length-1 do
        local method=methods[i]
        if method.Name=='get_NoteObject' and method:GetParameters().Length==0 then return method end
    end
end
local function invokeHoldGetter(method,target)
    return method:Invoke(target,holdDefaultFlags,nil,holdEmptyArguments,nil)
end
local function captureHoldOffset(head,current,offset)
    -- 437 0x4f15b0..0x4f15e1: abs(binary32 distance) < double .0001
    -- means capture again. The stored value is NOT an initialized boolean.
    if offset==nil or math.abs(offset)<.0001 then
        return string.unpack('f',string.pack('f',head-current))
    end
    return offset
end
local function findNativeHoldModule(name)
    local module=Module:Find(name)
    if not module then return nil end
    local tp=module.GetType and module:GetType()
    if tp and tp.FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeDummy' then return nil end
    return module
end
local function initHoldVisual(data)
    holdRecords={}
    holdModes=data.hold_policy
    for _,policy in ipairs(data.hold_policies or {}) do
        if findNativeHoldModule(policy.marker) then holdModes=policy.lanes end
    end
    if holdModes then
        local flags=typeof(CS.System.Reflection.BindingFlags)
        holdPublicFlags=CS.System.Enum.Parse(flags,'Instance, Public')
        holdAllFlags=CS.System.Enum.Parse(flags,'Instance, Public, NonPublic')
        holdDeclaredFlags=CS.System.Enum.Parse(flags,'Instance, Public, NonPublic, DeclaredOnly')
        holdDefaultFlags=CS.System.Reflection.BindingFlags.Default
        holdEmptyArguments=CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
    end
end
local function eventCarrier(event)
    if not holdEventCarrier then
        local fields=event:GetType():GetFields(holdAllFlags)
        local observed={event:GetType().FullName..' fields='..tostring(fields.Length)}
        for i=0,fields.Length-1 do
            observed[#observed+1]=fields[i].Name..':'..fields[i].FieldType.FullName
            local method=noteObjectGetter(fields[i].FieldType)
            if method then
                assert(not holdEventCarrier,'Ambiguous native visual carrier')
                holdEventCarrier,holdObjectMethod=fields[i],method
            end
        end
        assert(holdEventCarrier,'Native visual carrier unavailable: '..table.concat(observed,'; '))
    end
    return holdEventCarrier:GetValue(event)
end
local function visualFields(note)
    if holdStateField then return end
    local kind=note:GetType()
    while kind do
        local fields=kind:GetFields(holdDeclaredFlags)
        for i=0,fields.Length-1 do
            local f=fields[i]
            if f.FieldType.FullName=='Malody.Scene.Play.Note.PlayNoteHoldRuntime' then
                assert(not holdStateField,'Ambiguous native visual hold state')
                holdStateField=f
                local members=f.FieldType:GetFields(holdPublicFlags)
                for j=0,members.Length-1 do
                    if members[j].Name=='headType' then holdModeField=members[j] end
                    if members[j].Name=='headDeltaY' then holdDeltaField=members[j] end
                end
                members=f.FieldType:GetFields(holdAllFlags)
                for j=0,members.Length-1 do
                    if members[j].FieldType:Equals(holdEventCarrier.FieldType) then
                        assert(not holdRuntimeCarrierField,'Ambiguous native hold owner')
                        holdRuntimeCarrierField=members[j]
                    end
                end
            elseif f.Name=='holdHeadType' then holdHeadField=f end
        end
        kind=kind.BaseType
    end
    assert(holdStateField and holdModeField and holdHeadField and holdDeltaField and holdRuntimeCarrierField,
        'Native hold appearance fields unavailable')
end
local function liveHoldRecord(record)
    local note=invokeHoldGetter(holdObjectMethod,record.carrier)
    if not note or not note:Equals(record.note) or not note.gameObject.activeInHierarchy then return nil end
    local state=holdStateField:GetValue(note)
    local owner=holdRuntimeCarrierField:GetValue(state)
    -- A Unity object may already have been checked out for another carrier.
    -- Matching its instance alone would write the old hold into a new note.
    if owner and owner:Equals(record.carrier) then return state end
end
local function pruneHoldRecords(lane)
    local retained={}
    for _,record in ipairs(holdRecords[lane] or {}) do
        if liveHoldRecord(record) then retained[#retained+1]=record end
    end
    holdRecords[lane]=retained
    return retained
end
local function holdVisualInput(lane,kind)
    if not holdModes or kind~=1 then return end
    for _,record in ipairs(pruneHoldRecords(lane)) do
        local state=liveHoldRecord(record)
        -- UpdateDelta stores headY in relative coordinates; Update stores it
        -- absolute. Both keep headDeltaY relative. Only that shared contract
        -- is usable across the native Vivid/SV and ordinary render branches.
        record.offset=captureHoldOffset(state.headDeltaY,0,record.offset)
        -- Native StopOnHit recalculates headDeltaY while released. Restore
        -- 437's separately retained distance only on a new input-down; the
        -- original native UpdateDelta still moves/clips the sprite and body.
        holdDeltaField:SetValue(state,record.offset,holdDefaultFlags,nil,nil)
        holdStateField:SetValue(record.note,state,holdDefaultFlags,nil,nil)
    end
end
local function holdVisualHit()
    if not holdModes then return end
    local event=Game:HitEvent()
    if event:NoteType()~=2 or event:JudgeResult()<1 or event:JudgeResult()>3 then return end
    local policy=holdModes[event:HitX()]
    if policy==nil then return end
    local carrier=eventCarrier(event)
    if not carrier then return end
    -- Use the full MethodBase signature. In the skin VM, Invoke(object,nil)
    -- may select a BindingFlags overload and try to cast nil to that enum.
    local note=invokeHoldGetter(holdObjectMethod,carrier)
    if not note then return end
    assert(note:GetType().FullName=='Malody.Scene.Play.Note.PlayNoteKeySkin','Unexpected note renderer')
    visualFields(note)
    local state=holdStateField:GetValue(note)
    local desired=CS.System.Enum.Parse(holdModeField.FieldType,assert(holdNames[policy]))
    local record
    if policy==1 then
        local records=pruneHoldRecords(event:HitX())
        for _,saved in ipairs(records) do if saved.carrier:Equals(carrier) then record=saved end end
        if not record then
            record={carrier=carrier,note=note,offset=captureHoldOffset(state.headDeltaY,0)}
            records[#records+1]=record
            holdDeltaField:SetValue(state,record.offset,holdDefaultFlags,nil,nil)
        end
    end
    if not holdModeField:GetValue(state):Equals(desired) then
        -- Preserve holding/headRatio and the original carrier. Its C++ state
        -- machine continues to own subsequent movement and body shrinking.
        holdModeField:SetValue(state,desired,holdDefaultFlags,nil,nil)
        holdHeadField:SetValue(note,desired,holdDefaultFlags,nil,nil)
    end
    holdStateField:SetValue(note,state,holdDefaultFlags,nil,nil)
end
-- Keep this helper's standalone harness entry; the ordinary UI entry below
-- composes it with other factory-specific appearance callbacks.
function OnHit() holdVisualHit() end
