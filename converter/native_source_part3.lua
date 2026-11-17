-- 437 0x4f1580: plain Part3 source state, before any target geometry.
-- Its head is UNBOUNDED; only the future tail is placed at the source start.
-- These are visual values. No carrier, input, clock or judgement is written.
local NativeSourcePart3={}
function NativeSourcePart3.Offset(head,current,offset)
    -- fabs(float retainedDistance) is compared to the DOUBLE .0001.
    if offset==nil or math.abs(offset)<.0001 then return scale3float(head-current) end
    return offset
end
function NativeSourcePart3.Step(state,n,current,distance,held,toggle,captureCurrent)
    assert(distance>0 and distance<math.huge,'Invalid Part3 source window')
    if state.head==nil then state.head=n.display_y end
    if held and toggle&2~=0 then
        -- 4.3.7 captures the retained distance on the first held movement,
        -- but the capture clock is the old input frame, not necessarily the
        -- maV render clock. The source pool may provide that frame explicitly;
        -- ordinary callers retain the historical current-frame behavior.
        local capture=state.capture_current or captureCurrent or current
        state.offset=NativeSourcePart3.Offset(state.head,capture,state.offset)
        state.head=capture+state.offset
        state.capture_current=nil
        if state.head>=n.end_y then state.head=n.end_y;state.finished=true end
    end
    if toggle&1~=0 and state.head>=n.end_y then state.hidden=true end
    local head=scale3float((state.head-current)/distance)
    local tail=n.end_y>=current+distance and 1 or scale3float((n.end_y-current)/distance)
    return head,tail,state.hidden or false
end
function NativeSourcePart3.Position(first,last,ratio)
    -- mulss/addss in the actual move function, not double interpolation.
    local f=scale3float
    return f(f(f(first-last)*ratio)+last)
end
