-- Opt-in visual lifetime research. The native judge/audio queues stay owned
-- by maV. Inputs are reconstructed original MC display carriers. Explicit
-- native retry resets this state; a clock correction alone does not.
local LegacyLifetime={}
function LegacyLifetime.RecordSample(state,time,idle)
    if state.trace_capacity_exceeded then return false end
    local last=state.samples[#state.samples]
    if idle and state.trace_idle_index and time>=last then
        state.samples[state.trace_idle_index]=time
        state.trace_idle_compressed=(state.trace_idle_compressed or 0)+1
    else
        if #state.samples>=200000 then state.trace_capacity_exceeded=true;return false end
        state.samples[#state.samples+1]=time
        state.trace_idle_index=idle and #state.samples or nil
    end
    return true
end
function LegacyLifetime.New(scroll,distance,judgeAhead)
    assert(distance>0 and distance<math.huge and judgeAhead>=0,
        'Ma Skin Bridge: invalid legacy lifetime window')
    local notes={}
    for _,n in pairs(scroll.notes) do notes[#notes+1]=n end
    table.sort(notes,function(a,b)
        if a.legacy_order and b.legacy_order then return a.legacy_order<b.legacy_order end
        return a.beat==b.beat and (a.source_order or a.nid)<(b.source_order or b.nid) or a.beat<b.beat
    end)
    return {scroll=scroll,notes=notes,distance=distance,judgeAhead=judgeAhead,
        next=1,first=1,active={},pools={},slots={},serial=0,time=-math.huge,segment=1}
end
function LegacyLifetime.Visibility(state,module,visible)
    assert(type(visible)=='boolean','Ma Skin Bridge: invalid visual slot visibility')
    local slot=assert(state.slots[module],'Ma Skin Bridge: unknown lifetime visual slot')
    if slot.cullHidden then return false end
    local changed=slot.busy~=visible;slot.busy=visible
    return changed
end
function LegacyLifetime.NewBars(bars)
    return {bars=bars,next=1,first=1,active={}}
end
function LegacyLifetime.StepBars(state,time,y,distance)
    local changed=state.active_snapshot==nil
    while state.next<=#state.bars and state.bars[state.next].displayY<=y+distance do
        state.active[#state.active+1]=state.bars[state.next];state.next=state.next+1
        changed=true
    end
    while state.first<=#state.active do
        local bar=state.active[state.first]
        if time<=bar.offset or y-1000<=bar.displayY then break end
        state.first=state.first+1
        changed=true
    end
    if changed then
        local active={}
        for i=state.first,#state.active do active[#active+1]=state.active[i] end
        state.active_snapshot=active
    end
    return state.active_snapshot
end
function LegacyLifetime.Step(state,judgeTime,displayTime,frame)
    state.time=judgeTime
    local times=state.scroll.time_carriers
    while state.segment<#times and times[state.segment+1].offset<=displayTime do
        state.segment=state.segment+1
    end
    while state.segment>1 and times[state.segment].offset>displayTime do
        state.segment=state.segment-1
    end
    local c=times[state.segment]
    local y=c.display_y+(displayTime-c.offset)*c.speed
    -- The renderer consumes a frame synchronously. Its owned output may be
    -- reused; callers retaining snapshots omit it and keep immutable results.
    local events=frame and frame.events or {}
    for i=#events,1,-1 do events[i]=nil end
    local changed=state.active_snapshot==nil
    -- Admission runs before retirement in the original virtual_195. A slot
    -- retiring on this frame cannot be reused by this frame's admissions.
    while state.next<=#state.notes do
        local n=state.notes[state.next]
        if judgeTime+state.judgeAhead<n.time and y+state.distance<n.display_y then break end
        local kind=tostring(n.lane)..(n.endtime>n.time and ':hold' or ':tap')
        local pool=state.pools[kind]
        if not pool then pool={};state.pools[kind]=pool end
        local slot
        for _,p in ipairs(pool) do if not p.busy then slot=p;break end end
        if not slot then
            state.serial=state.serial+1;slot={module=state.serial};pool[#pool+1]=slot;state.slots[slot.module]=slot
        end
        slot.busy=true;slot.owner=n;slot.end_y=n.end_y;slot.cullHidden=false
        local row={note=n,module=slot.module,slot=slot}
        state.active[#state.active+1]=row
        events[#events+1]={operation='admit',note=row.note,module=row.module}
        state.next=state.next+1
        changed=true
    end
    -- One FIFO across lanes and kinds. The time guard uses the HEAD offset,
    -- while the display guard uses the TAIL Y; reverse scroll exposes this.
    while state.first<=#state.active do
        local row=state.active[state.first];local n=row.note
        if judgeTime<=n.time or y-1000<=n.end_y then break end
        -- A carrier can outlive its visible sprite and refer to a reused
        -- object. Original virtual_195 checks its current tail Y before
        -- hiding it; retirement alone must not hide the newer occupant.
        local hide=math.abs(row.slot.end_y-n.end_y)<1.1920928955078125e-7
        if hide then row.slot.busy=false;row.slot.cullHidden=true end
        events[#events+1]={operation='retire',note=row.note,module=row.module,hide=hide}
        state.first=state.first+1
        changed=true
    end
    if changed then
        -- Timeline carriers can retain a reused slot long after its drawable
        -- has another owner. Keep the exact FIFO for observation/retirement,
        -- but rebuild its render view only when membership/ownership changes.
        -- Visibility only changes busy: keep hidden current owners here so
        -- reverse scrolling can still update and reveal them.
        local active,drawables={},{}
        for i=state.first,#state.active do
            local row=state.active[i];active[#active+1]=row
            if row.slot.owner==row.note and not row.slot.cullHidden then
                drawables[#drawables+1]=row
            end
        end
        state.active_snapshot,state.drawable_snapshot=active,drawables
    end
    frame=frame or {}
    frame.display_y,frame.events=y,events
    frame.active,frame.drawables=state.active_snapshot,state.drawable_snapshot
    return frame
end
