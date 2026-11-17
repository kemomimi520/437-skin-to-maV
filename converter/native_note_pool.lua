-- Opt-in, version-specific READ of the native idle list. Never reorder, pop,
-- replace or write that list. Logical legacy slots are assigned in layers.lua.
local nativeNotePoolReader
function UnityBridge.NotePoolIdle(typeName)
    if not nativeNotePoolReader then
        local group=Note:GetGroup('legacy_pool_observer')
        local parent=group.transform;local layer
        while parent and not layer do
            layer=parent.gameObject:GetComponent(typeof(CS.Malody.Scene.Play.Skin.SkinNoteLayer))
            parent=parent.parent
        end
        assert(layer,'Ma Skin Bridge: native note layer missing for pool read')
        local member=typeof(CS.Malody.Scene.Play.Skin.SkinNoteLayer):GetField('xhd',36)
        assert(member,'Ma Skin Bridge: unsupported native idle-pool field')
        local dictionary=assert(member:GetValue(layer),'Ma Skin Bridge: native idle dictionary missing')
        local lookup
        local methods=dictionary:GetType():GetMethods(20)
        for i=0,methods.Length-1 do
            if methods[i].Name=='TryGetValue' and methods[i]:GetParameters().Length==2 then lookup=methods[i] end
        end
        assert(lookup,'Ma Skin Bridge: native idle dictionary lookup unavailable')
        nativeNotePoolReader={dictionary=dictionary,lookup=lookup}
    end
    local reader=nativeNotePoolReader
    local values=CS.System.Array.CreateInstance(typeof(CS.System.Object),2)
    values[0]=typeName
    local found=reader.lookup:Invoke(reader.dictionary,CS.System.Reflection.BindingFlags.Default,nil,values,nil)
    if not CS.System.Convert.ToBoolean(found) then return {} end
    local list=assert(values[1],'Ma Skin Bridge: native idle list is null')
    local count=publicGetter(list,'get_Count');local ids={};local seen={}
    for i=0,count-1 do
        local object=assert(list[i].bccu,'Ma Skin Bridge: idle object missing')
        local mod=assert(object:GetComponent(typeof(CS.Malody.Scene.Play.Note.PlayNoteFree)),
            'Ma Skin Bridge: idle object is not a free note module')
        local id=mod:GetInstanceID()
        assert(not seen[id],'Ma Skin Bridge: duplicate object in native idle list')
        seen[id]=true;ids[#ids+1]=id
    end
    assert(publicGetter(list,'get_Count')==count,'Ma Skin Bridge: idle list changed during read')
    return ids
end
