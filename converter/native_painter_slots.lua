-- Logical PAINTER slots only. Never modifies a native pool, carrier, judge,
-- score or clock. The source admission/visibility/retirement timeline is a
-- separate contract: native membership alone cannot prove 437 lifetime.
local NativePainterSlots={}
function NativePainterSlots.New(limit)
    assert(math.type(limit)=='integer' and limit>0,'Invalid native painter capacity')
    return {limit=limit,pools={},owners={},next=0,frame=0,allocations=0,reuses=0}
end
function NativePainterSlots.Begin(state)
    state.frame=state.frame+1
end
function NativePainterSlots.Touch(state,identity,owner,poolKey)
    assert(type(identity)=='number' and owner~=nil and type(poolKey)=='string','Invalid native painter identity')
    local prior=state.owners[identity]
    if prior and prior.owner==owner then
        assert(prior.poolKey==poolKey,'Original painter owner changed pool kind')
        prior.frame=state.frame;return prior,false
    end
    local pool=state.pools[poolKey]
    if not pool then pool={};state.pools[poolKey]=pool end
    local slot
    for _,candidate in ipairs(pool) do if not candidate.busy then slot=candidate;break end end
    if not slot then
        assert(state.next<state.limit,'Native painter sorting range exhausted')
        state.next=state.next+1;slot={rank=state.next};pool[#pool+1]=slot
        state.allocations=state.allocations+1
    else state.reuses=state.reuses+1 end
    slot.busy=true
    local row={identity=identity,owner=owner,poolKey=poolKey,slot=slot,frame=state.frame}
    slot.owner=row
    if prior then
        state.retired=state.retired or {};state.retired[#state.retired+1]=prior
    end
    state.owners[identity]=row
    return row,true
end
function NativePainterSlots.Finish(state)
    -- Original KeyUIS admits first, then retires. Even a physical instance
    -- reused by maV within a frame must not free its old logical slot early.
    for identity,row in pairs(state.owners) do
        if row.frame~=state.frame then
            if row.slot.owner==row then row.slot.busy=false;row.slot.owner=nil end
            state.owners[identity]=nil
        end
    end
    for _,row in ipairs(state.retired or {}) do
        if row.slot.owner==row then row.slot.busy=false;row.slot.owner=nil end
    end
    state.retired=nil
end
function NativePainterSlots.Hide(state,identity,owner)
    local row=assert(state.owners[identity],'Native painter hide has no admitted owner')
    assert(row.owner==owner,'Native painter hide owner mismatch')
    if row.slot.owner==row then row.slot.busy=false end
    row.hidden=true
end
