-- Equal lane/time identities are a multiset, not a unique-note dictionary.
-- Keep every occurrence, then assign the original unstable source sort rank.
local LegacyNoteIdentity={}
function LegacyNoteIdentity.BeatKey(lane,start,finish)
    local function beat(value)
        local q=value[2]//value[3]
        local w=value[1]+q
        local n=value[2]-q*value[3]
        local a,b=n,value[3]
        while b~=0 do a,b=b,a%b end
        return string.format('%d:%d/%d',w,n//a,value[3]//a)
    end
    -- Identity must not use float32 beat values: different rational beats
    -- can round to the same float. Reduce equivalent fractions exactly.
    return tostring(lane)..':'..beat(start)..':'..beat(finish)
end
function LegacyNoteIdentity.Index(notes,key)
    local groups={}
    for _,note in ipairs(notes) do
        local identity=key(note);local group=groups[identity]
        if not group then group={next=1,values={}};groups[identity]=group end
        group.values[#group.values+1]=note
    end
    return groups
end
function LegacyNoteIdentity.Take(groups,identity)
    local group=groups[identity]
    assert(group and group.next<=#group.values,'Ma Skin Bridge: source/native note multiset mismatch')
    local note=group.values[group.next];group.next=group.next+1
    return note
end
