-- Original Key display-carrier reconstruction. Native visibility, pooling
-- and the relationship between the games' speed settings remain gated.
local LegacyScroll={}
function LegacyScroll.Build(input)
    local clock
    if input.absolute then
        clock={}
        for _,point in ipairs(input.timepoints) do
            clock[#clock+1]={beat=LegacyClock.Beat(point.beat),offset=point.offset,length=point.beat_length}
        end
    else clock=LegacyClock.Build(input.timepoints) end
    local function offset(value)
        local beat=LegacyClock.Beat(value);local selected=clock[1]
        for i=2,#clock do if clock[i].beat>beat then break end;selected=clock[i] end
        return selected.offset+(beat-selected.beat)*selected.length
    end
    local ordered={}
    for _,n in ipairs(input.notes) do
        ordered[#ordered+1]={nid=n.nid,lane=n.lane,beat=LegacyClock.Beat(n.beat),
            source_order=n.source_order,legacy_order=n.legacy_order,
            chord=n.chord,
            time=input.absolute and n.time or LegacyClock.Time(clock,n.beat),
            endtime=input.absolute and n.endtime or LegacyClock.Time(clock,n.endbeat)}
    end
    table.sort(ordered,function(a,b)
        if a.legacy_order and b.legacy_order then return a.legacy_order<b.legacy_order end
        return a.beat==b.beat and (a.source_order or a.nid)<(b.source_order or b.nid) or a.beat<b.beat
    end)
    assert(#ordered>0,'Ma Skin Bridge: empty legacy scroll chart is not certified')
    local first,last=ordered[1].time,ordered[#ordered].endtime
    local function clamp(v) return math.max(first,math.min(last,v)) end
    local weights={}
    for i,p in ipairs(clock) do
        weights[#weights+1]={length=p.length,duration=(clock[i+1] and clamp(clock[i+1].offset) or last)-clamp(p.offset)}
    end
    table.sort(weights,function(a,b) return a.length==b.length and a.duration<b.duration or a.length<b.length end)
    local remaining=(last-first)*0.33299999999999996;local base=weights[#weights].length
    for _,w in ipairs(weights) do remaining=remaining-w.duration;if remaining<0 then base=w.length;break end end
    local events={}
    for i,p in ipairs(clock) do events[#events+1]={offset=p.offset,kind=0,index=i,value=p.length} end
    for i,e in ipairs(input.effects) do
        if input.absolute or (e.type==1 and (e.variant_type==2 or e.variant_type==3 or e.variant_type==4)
                and type(e.value)=='number' and e.value==e.value and math.abs(e.value)<math.huge) then
            events[#events+1]={offset=input.absolute and e.offset or offset(e.beat),kind=1,index=i,value=e.value}
        end
    end
    table.sort(events,function(a,b)
        if a.offset~=b.offset then return a.offset<b.offset end
        if a.kind~=b.kind then return a.kind<b.kind end
        return a.index<b.index
    end)
    local times={};local length,scroll=clock[1].length,1
    for _,event in ipairs(events) do
        if event.kind==0 then length=event.value
        elseif event.value~=nil then scroll=UnityBridge.Float(event.value) end
        local previous=times[#times];local speed=UnityBridge.Float(scroll*base/length)
        local y=previous and previous.display_y+(event.offset-previous.offset)*previous.speed or speed*event.offset
        times[#times+1]={offset=event.offset,display_y=y,speed=speed}
    end
    local function findCarrier(time,first)
        local lo,hi=first or 1,#times
        while lo<hi do
            local mid=(lo+hi+1)//2
            if times[mid].offset<=time then lo=mid else hi=mid-1 end
        end
        return lo
    end
    local function display(time,first)
        local index=findCarrier(time+1,first)
        local selected=times[index]
        return selected.display_y+(time-selected.offset)*selected.speed,index
    end
    local notes={};local tailSegment=1
    for _,note in ipairs(ordered) do
        note.display_y=display(note.time)
        note.end_y=note.display_y
        if note.endtime>note.time then
            -- The original builder resolves pending HOLD tails through one
            -- FIFO. A long earlier hold advances the tail segment used by a
            -- later shorter hold, even across lanes. Never rewind this cursor.
            note.end_y,tailSegment=display(note.endtime,tailSegment)
        end
        notes[note.nid]=note
    end
    return {base_beat_length=base,time_carriers=times,notes=notes,source_clock=clock}
end
function LegacyScroll.CarrierY(state,time)
    -- The original builder selects a time-carrier up to offset+1 ms, unlike
    -- the current display-clock cursor which uses the exact current offset.
    local times=state.time_carriers
    local lo,hi=1,#times
    while lo<hi do
        local mid=(lo+hi+1)//2
        if times[mid].offset<=time+1 then lo=mid else hi=mid-1 end
    end
    local selected=times[lo]
    return selected.display_y+(time-selected.offset)*selected.speed
end
function LegacyScroll.CurrentY(state,time)
    local times=state.time_carriers
    local lo,hi=1,#times
    while lo<hi do
        local mid=(lo+hi+1)//2
        if times[mid].offset<=time then lo=mid else hi=mid-1 end
    end
    local selected=times[lo]
    return selected.display_y+(time-selected.offset)*selected.speed
end
function LegacyScroll.Progress(state,nid,time,distance)
    assert(distance>0 and distance<math.huge,'Ma Skin Bridge: invalid native scroll window')
    local current=LegacyScroll.CurrentY(state,time)
    local note=assert(state.notes[nid],'Ma Skin Bridge: original note carrier missing')
    -- Part3 computes the remaining-distance ratio as float32. Complementing
    -- a maV float32 progress would lose that rounding order at boundaries.
    return 1-UnityBridge.Float((note.display_y-current)/distance),
        1-UnityBridge.Float((note.end_y-current)/distance)
end
function LegacyScroll.Hide(note,toggle)
    return (toggle & 1)~=0 and note.end_y<=note.display_y
end
