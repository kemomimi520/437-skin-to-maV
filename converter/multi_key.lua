-- The native SkinFile holds all Key entries; instantiate only this chart's script.
local active,selectedKeys,selectedPrefix,selectedPlatform,unselectedModules
local function selectEntry()
    if active then return active end
    xlua.load_assembly('Assembly-CSharp')
    local group=Note:GetGroup('legacy_key_selector')
    local parent=group.transform
    local processor
    while parent~=nil and processor==nil do
        processor=parent.gameObject:GetComponent(typeof(CS.Malody.Play.ProcessorFree))
        parent=parent.parent
    end
    assert(processor,'Ma Skin Bridge: chart processor is unavailable')
    local chart
    local properties=processor:GetType():GetProperties(20)
    for i=0,properties.Length-1 do
        local getter=properties[i]:GetGetMethod()
        if getter and getter.Name=='get_ChartToProcess' then
            chart=properties[i]:GetValue(processor,nil);break
        end
    end
    assert(chart,'Ma Skin Bridge: public chart property is unavailable')
    local kind=chart:GetType();local recordField
    if kind.FullName=='Malody.Chart.bbbg' then recordField='biff'
    elseif kind.FullName=='Malody.Chart.iqy' then recordField='zml'
    else error('Ma Skin Bridge: unsupported engine chart metadata '..tostring(kind.FullName)) end
    local member=kind:GetField(recordField,20)
    assert(member and member.IsPublic,'Ma Skin Bridge: native Key chart record missing')
    local keys=tonumber(member:GetValue(chart).Column)
    selectedKeys=keys
    local entryId=keys
    if platformEntries then
        xlua.load_assembly('UnityEngine.CoreModule')
        local engine=CS.UnityEngine
        local platform=engine.Application.platform
        local sourcePlatform
        if platform==engine.RuntimePlatform.WindowsPlayer then sourcePlatform='windows'
        elseif platform==engine.RuntimePlatform.Android then sourcePlatform='android'
        else error('Ma Skin Bridge: unverified source platform '..tostring(platform)) end
        selectedPlatform=sourcePlatform
        entryId=platformEntries[sourcePlatform] and platformEntries[sourcePlatform][keys]
        assert(entryId,'Ma Skin Bridge: this MSZ has no '..sourcePlatform..' '..tostring(keys)..'K definition')
    end
    selectedPrefix='k'..tostring(entryId)..'_'
    local builder=builders[entryId]
    assert(builder,'Ma Skin Bridge: this MSZ has no '..tostring(keys)..'K entry')
    active=builder()
    return active
end
local function disableUnselectedModules()
    if not unselectedModules then
        unselectedModules={}
        local prefix=selectedPrefix
        -- The native loader excludes other-platform definitions before their
        -- modules exist. Only resolve this platform's remaining Key entries;
        -- selected/missing modules still fail in their ordinary Init path.
        local currentHandles=platformHandles and platformHandles[selectedPlatform] or handles
        for _,name in ipairs(currentHandles) do
            if name:sub(1,#prefix)~=prefix then
                local object=assert(Module:Find(name),'Ma Skin Bridge: unselected UI module missing '..name)
                unselectedModules[#unselectedModules+1]=object.gameObject
            end
        end
    end
    for _,object in ipairs(unselectedModules) do object:SetActive(false) end
end
function CanPlay() return CS~=nil and typeof~=nil end
function OnProcessNote() if active then return active.OnProcessNote() end end
function Init()
    xlua.load_assembly('Assembly-CSharp')
    local callbacks=selectEntry()
    disableUnselectedModules()
    return callbacks.Init()
end
function Update() if active then return active.Update() end end
function OnRetry() if active then disableUnselectedModules();return active.OnRetry() end end
function OnInput() if active then return active.OnInput() end end
function OnHit() if active then return active.OnHit() end end
function OnDrawNote(...) return selectEntry().OnDrawNote(...) end
function OnNoteMove(...) return selectEntry().OnNoteMove(...) end
function ReportCustomInfo() return 'Ma Skin Bridge MSZ; native visual acceptance pending' end
