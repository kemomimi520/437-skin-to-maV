-- Engine metadata profiles, independent of skin names or assets. Unknown
-- layouts fail explicitly; do not infer field roles from their contents.
local NativeBindings={}
local bindingProfiles={
    ['Malody.Chart.bbbg']={id='core-0b707b7d',clock='Malody.Play.bpa',vars='bec',names={}},
    ['Malody.Chart.iqy']={id='steam-build-26024338',clock='Malody.Play.bmp',vars='dxb',note_position_deadband=.0001,names={
        bifq='zmw',bifs='zmy',biff='zml',bcbb='syd',bcbd='syf',bcay='sya',bcib='tkt',
        bcgf='thz',bcgj='tig',bcgk='tih',znq='fcy',cno='bvp',cnp='bvq'}},
}
local selectedBinding
function NativeBindings.Select(chart)
    local name=chart:GetType().FullName
    local profile=assert(bindingProfiles[name],'Ma Skin Bridge: unsupported engine chart metadata '..tostring(name))
    assert(not selectedBinding or selectedBinding==profile,'Ma Skin Bridge: engine metadata changed inside one skin environment')
    selectedBinding=profile
    return profile.id
end
function NativeBindings.Name(name)
    local profile=assert(selectedBinding,'Ma Skin Bridge: engine metadata has not been selected')
    return profile.names[name] or name
end
function NativeBindings.ClockType()
    local profile=assert(selectedBinding,'Ma Skin Bridge: engine metadata has not been selected')
    local assembly=typeof(CS.Malody.Play.ChartPlayer).Assembly
    return assert(assembly:GetType(profile.clock),'Ma Skin Bridge: native clock metadata missing '..profile.clock)
end
function NativeBindings.TriggerValueType(trigger)
    local profile=assert(selectedBinding,'Ma Skin Bridge: engine metadata has not been selected')
    return CS.Malody.Composer[profile.vars].TriggerValueType(trigger)
end
function NativeBindings.NotePositionDeadband()
    -- Current ckf.set_X/Y read the double at 0x182309b78. Other metadata
    -- profiles keep their original public setters until independently proved.
    local profile=assert(selectedBinding,'Ma Skin Bridge: engine metadata has not been selected')
    return profile.note_position_deadband
end
