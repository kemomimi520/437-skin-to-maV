-- Pure 437 whole-image motion/admission arithmetic. All positions are
-- source visual values; no carrier, judge, clock or native settings writes.
local NativeSourceMotion={}
function NativeSourceMotion.Check(config,distance)
    assert(config.speed_source==nil or config.speed_source=='native-layer','Unknown source visual speed binding')
    for _,name in ipairs({'logical_height','travel_720','speed','scale'}) do
        local value=config[name]
        assert(type(value)=='number' and value>0 and value<math.huge,'Invalid source motion '..name)
    end
    assert((config.scope=='controlled-linear-whole-scale3' or config.scope=='legacy-linear-whole-scale3-v1' or
        config.scope=='legacy-linear-part3-v1' or config.scope=='legacy-mixed-v1') and
        config.logical_height>0 and config.travel_720>0,
        'Unverified source motion geometry')
    local speed,scale=scale3float(config.speed),scale3float(config.scale)
    assert(speed>0 and scale>0 and math.abs(distance-632.5/scale3float(speed*scale))<1e-8,
        'Source lifetime and motion speed differ')
end
function NativeSourceMotion.Range(config,n,current,distance,unit,laneTravel)
    -- 437 interpolates each note with ITS OWN source travel (pos.y-pos2.y).
    -- Only the display window (distance) is global. Callers pass the lane's
    -- recipe travel; omitting it keeps the historical uniform default.
    local travel=laneTravel or config.travel_720
    assert(type(travel)=='number' and travel==travel and math.abs(travel)<math.huge,
        'Invalid source lane travel')
    if config.scope=='legacy-linear-part3-v1' and n.endtime>n.time then
        -- Stateless Part3 reference. Owned toggle-2 visuals use their
        -- retained source head through NativeSourcePart3.Step instead.
        local head=scale3float((n.display_y-current)/distance)
        local tail=n.end_y>=current+distance and 1 or scale3float((n.end_y-current)/distance)
        return NativeSourcePart3.Position(travel,0,head)*unit,
            NativeSourcePart3.Position(travel,0,tail)*unit
    end
    local ratio=scale3float((n.display_y-current)/distance)
    -- Default NoteSprite.virtual_5 clamps only the far head. It does not
    -- clamp negative motion after the judge line or clamp a separate tail.
    if n.display_y>current+distance then ratio=1 end
    return scale3float(scale3float(travel)*ratio)*unit,
        (n.end_y-current)/distance*travel*unit
end
function NativeSourceMotion.AdmittedHeight(config,n,layout)
    local f=scale3float
    local sy=f(f(layout.scale[2]*config.logical_height)/720)
    local saved=f(layout.size_delta[2])
    local coefficient=f(f(f(f(config.logical_height)*f(config.scale))*f(config.speed))/720)
    local physical=f(f(sy*saved)+f((n.end_y-n.display_y)*coefficient))
    return f(physical/sy)
end
