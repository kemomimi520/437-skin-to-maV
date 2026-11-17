-- Research-only ordinary Key appearance initialization. No Free callback,
-- chart clock, judge, setting or score writes. Original C++ still renders.
-- Observe the native active list; refresh a newly observed native object
-- once with its source head policy. With native_frame_driver, this runs from
-- the original layer's onAfterUpdate through an ORIGINAL C# method target.
-- The older ordinary Update path can miss a later admission in that frame.
-- Neither path yet reproduces the 437 admission/FIFO timeline.
-- The active List version avoids scanning unchanged objects every frame.
local admissionUpdate
local function initNoteAdmission(data)
    admissionUpdate=nil
    if not data.admission_policy then return end
    xlua.load_assembly('Assembly-CSharp')
    xlua.load_assembly('UnityEngine.CoreModule')
    if initNativePainter then initNativePainter(data) end
    local modes=data.admission_policy
    local flags=typeof(CS.System.Reflection.BindingFlags)
    local public=CS.System.Enum.Parse(flags,'Instance, Public')
    local all=CS.System.Enum.Parse(flags,'Instance, Public, NonPublic, DeclaredOnly')
    local defaults=CS.System.Reflection.BindingFlags.Default
    local empty=CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
    local layers=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.Malody.Play.NoteLayer),false)
    assert(layers.Length==1,'Expected one active native Key layer at skin initialization')
    local layer=layers[0]
    local listField,carrierField,noteGetter,versionField,stateField,modeField,ownerField,headField
    local startOffsetGetter,endOffsetGetter
    local kind=layer:GetType()
    while kind do
        local fields=kind:GetFields(all)
        for i=0,fields.Length-1 do
            local f=fields[i]
            if f.FieldType.IsGenericType and f.FieldType:GetGenericTypeDefinition().FullName=='System.Collections.Generic.List`1' then
                local rowType=f.FieldType:GetGenericArguments()[0]
                local members=rowType:GetFields(public)
                local rowCarrier,rowGetter,hasObject
                for j=0,members.Length-1 do
                    if members[j].FieldType.FullName=='UnityEngine.GameObject' then hasObject=true end
                    local methods=members[j].FieldType:GetMethods(public)
                    for k=0,methods.Length-1 do
                        if methods[k].Name=='get_NoteObject' and methods[k]:GetParameters().Length==0 then
                            rowCarrier,rowGetter=members[j],methods[k]
                        end
                    end
                end
                if hasObject and rowCarrier then
                    assert(not listField,'Ambiguous original native active list')
                    listField,carrierField,noteGetter=f,rowCarrier,rowGetter
                end
            end
        end
        kind=kind.BaseType
    end
    assert(listField,'Original native active list missing')
    local seen,lastList,lastVersion={},nil,nil
    NATIVE_NOTE_ADMISSION={frames=0,scans=0,configured=0}
    local function configureFields(note,carrierType)
        if stateField then return end
        local noteType=note:GetType()
        while noteType do
            local fields=noteType:GetFields(all)
            for i=0,fields.Length-1 do
                local f=fields[i]
                if f.FieldType.FullName=='Malody.Scene.Play.Note.PlayNoteHoldRuntime' then
                    assert(not stateField,'Ambiguous native hold state')
                    stateField=f
                    local members=f.FieldType:GetFields(all)
                    for j=0,members.Length-1 do
                        if members[j].Name=='headType' then modeField=members[j] end
                        if members[j].FieldType:Equals(carrierType) then ownerField=members[j] end
                    end
                elseif f.Name=='holdHeadType' then headField=f end
            end
            noteType=noteType.BaseType
        end
        assert(stateField and modeField and ownerField and headField,'Native appearance fields missing')
        if data.native_painter then
            local methods=carrierType:GetMethods(public)
            for i=0,methods.Length-1 do
                local m=methods[i]
                if m:GetParameters().Length==0 then
                    if m.Name=='get_StartOffset' then startOffsetGetter=m end
                    if m.Name=='get_EndOffset' then endOffsetGetter=m end
                end
            end
            assert(startOffsetGetter and endOffsetGetter,'Native painter timing identity missing')
        end
    end
    local desired={}
    local function afterUpdate()
        NATIVE_NOTE_ADMISSION.frames=NATIVE_NOTE_ADMISSION.frames+1
        if data.source_visual_pool and not nativeSourcePoolReady() then return end
        local list=listField:GetValue(layer)
        if not list then return end
        if not versionField then
            versionField=list:GetType():GetField('_version',CS.System.Enum.Parse(flags,'Instance, NonPublic'))
            assert(versionField,'Original active-list version missing')
        end
        local version=versionField:GetValue(list)
        if lastList and (list==lastList or list:Equals(lastList)) and version==lastVersion then return end
        lastList,lastVersion=list,version
        NATIVE_NOTE_ADMISSION.scans=NATIVE_NOTE_ADMISSION.scans+1
        local current={}
        if beginNativePainter then beginNativePainter() end
        for i=0,list.Count-1 do
            local carrier=carrierField:GetValue(list[i])
            local note=carrier and noteGetter:Invoke(carrier,defaults,nil,empty,nil)
            if note and note.gameObject.activeInHierarchy then
                local id=note:GetInstanceID()
                local sameSeen=seen[id] and carrier:Equals(seen[id])
                if not sameSeen then
                    assert(note:GetType().FullName=='Malody.Scene.Play.Note.PlayNoteKeySkin','Unexpected native note object')
                end
                current[id]=carrier
                if data.source_visual_pool then
                    nativeSourceMaskOriginal(note)
                else
                configureFields(note,carrier:GetType())
                local state=stateField:GetValue(note)
                assert(ownerField:GetValue(state):Equals(carrier),'Native visual owner mismatch')
                local lane=math.floor(note.rectNoteRange.anchorMin.x*#modes+.5)+1
                if nativePainterInspect then
                    nativePainterInspect(note,carrier,lane,
                        endOffsetGetter:Invoke(carrier,defaults,nil,empty,nil)>startOffsetGetter:Invoke(carrier,defaults,nil,empty,nil))
                end
                if not seen[id] or not carrier:Equals(seen[id]) then
                    local policy=assert(modes[lane],'Native visual lane outside source policy')
                    assert(policy==0 or policy==1,'Unimplemented source head policy')
                    if prepareScale3Admission then prepareScale3Admission(note,carrier,lane) end
                    if not desired[policy] then desired[policy]=CS.System.Enum.Parse(modeField.FieldType,policy==0 and 'None' or 'StopOnHit') end
                    modeField:SetValue(state,desired[policy],defaults,nil,nil)
                    stateField:SetValue(note,state,defaults,nil,nil)
                    headField:SetValue(note,desired[policy],defaults,nil,nil)
                    note:UpdateObject()
                    if finishScale3Admission then finishScale3Admission(note,carrier,lane,layer) end
                    NATIVE_NOTE_ADMISSION.configured=NATIVE_NOTE_ADMISSION.configured+1
                end
                end
            end
        end
        if finishNativePainter then finishNativePainter() end
        seen=current
    end
    admissionUpdate=afterUpdate
end
local function updateNoteAdmission()
    if admissionUpdate then admissionUpdate() end
end
