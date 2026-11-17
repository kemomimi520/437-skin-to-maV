-- Opt-in, version-specific source for the Free prefab's disabled bar queue.
-- Invoke only the shipped bar builder after original chart processing. Never
-- reprocess or replace the already loaded time/note/judge queues.
local generatedBarSources=setmetatable({},{__mode='k'})
function UnityBridge.LegacyBarBegin(processor)
    local chart=publicGetter(processor,'get_ChartToProcess')
    if CS.System.Convert.ToInt32(publicGetter(chart,'get_Format'))~=1 then return nil end
    NativeBindings.Select(chart)
    local member=chart:GetType():GetField(NativeBindings.Name('biff'),20) -- Public | Instance
    assert(member and member.IsPublic,'Ma Skin Bridge: public MC chart record missing')
    local record=member:GetValue(chart)
    local begin=tonumber(publicGetter(record,'get_BarBegin'))
    assert(begin and begin==math.floor(begin) and begin>=0 and begin<=4294967295,
        'Ma Skin Bridge: invalid native MC bar beginning')
    -- 4.3.7 converts its signed MC bar_begin to uint32 before calculating
    -- bars. maV converts it back to a signed Fraction, so missing/-1 starts
    -- visible bars in maV but produces none in the original Key builder.
    return begin
end
function UnityBridge.EnsureBarSource(processor)
    local currentNotes=publicGetter(processor,'get_ResultNoteList')
    local cached=generatedBarSources[processor]
    if cached and cached.notes==currentNotes then return cached.list end
    assert(processor:GetType()==typeof(CS.Malody.Play.ProcessorFree),
        'Ma Skin Bridge: unsupported native bar processor')
    local kind=typeof(CS.Malody.Play.ProcessorBasic)
    local enabled=kind:GetField('barEnabled',36)
    local queue=kind:GetField(NativeBindings.Name('bcib'),36)
    local build
    local methods=kind:GetMethods(36)
    for i=0,methods.Length-1 do if methods[i].Name==NativeBindings.Name('znq') then build=methods[i] end end
    assert(enabled and queue and build and build:GetParameters().Length==0,
        'Ma Skin Bridge: unsupported native bar source binding')
    local times=publicGetter(processor,'get_ResultTimeList')
    local notes=publicGetter(processor,'get_ResultNoteList')
    assert(times and times.Count>0 and notes,'Ma Skin Bridge: chart must be loaded before bars')
    local original=enabled:GetValue(processor)
    enabled:SetValue(processor,true)
    local ok,failure=xpcall(function()
        local empty=CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
        build:Invoke(processor,CS.System.Reflection.BindingFlags.Default,nil,empty,nil)
    end,debug.traceback)
    enabled:SetValue(processor,original)
    assert(ok,failure)
    assert(publicGetter(processor,'get_ResultTimeList')==times and
        publicGetter(processor,'get_ResultNoteList')==notes,
        'Ma Skin Bridge: bar builder altered loaded time/note queues')
    local result=queue:GetValue(processor)
    assert(result,'Ma Skin Bridge: original bar builder produced no queue')
    generatedBarSources[processor]={list=result,notes=notes}
    return result
end
