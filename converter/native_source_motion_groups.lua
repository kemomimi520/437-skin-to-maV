-- Affine lowering of the source whole-image motion, on owned visual roots.
-- Stable frames move ONE ordinary RectTransform per (unit scale, lane travel).
-- No native carrier/clock/judge writes and no mesh or per-note draw callback.
local NativeSourceGroups={}
function NativeSourceGroups.New(root,motion,distance)
    return {root=root,motion=motion,distance=distance,groups={},moves=0,bindings=0,current=0,epoch=0}
end
function NativeSourceGroups.Reconfigure(state,distance)
    if state.distance==distance then return end
    state.distance=distance;state.epoch=state.epoch+1
    for _,bucket in pairs(state.groups) do
        for _,group in pairs(bucket) do group.factor=group.travel/distance*group.unit end
    end
end
-- 437 moves each lane with its own signed travel (pos.y-pos2.y). The package
-- emits motion.lane_travel_720 only for nonuniform lanes; a uniform or legacy
-- package keeps the historical validated span.
local function laneTravel(state,recipe,lane)
    local list=state.motion.lane_travel_720
    if list and list[lane] then return list[lane] end
    if recipe then
        if recipe.layout and recipe.layout.travel_720 then return recipe.layout.travel_720 end
        if recipe.start_y and recipe.end_y then return recipe.start_y-recipe.end_y end
    end
    return state.motion.travel_720
end
local function sourceGroupMove(state,group)
    local y=scale3float(-state.current*group.factor)
    if y~=group.y then
        group.rect.anchoredPosition=CS.UnityEngine.Vector2(0,y)
        group.y=y;state.moves=state.moves+1
    end
end
function NativeSourceGroups.Update(state,current)
    state.current=current
    for _,bucket in pairs(state.groups) do
        for _,group in pairs(bucket) do sourceGroupMove(state,group) end
    end
end
local function sourceGroup(state,unit,travel)
    -- Lua normalizes integral float table keys, so identical travel values
    -- from different lanes share one parent; different travel never does.
    local bucket=state.groups[unit]
    if not bucket then bucket={};state.groups[unit]=bucket end
    local group=bucket[travel]
    if group then return group end
    local U=CS.UnityEngine
    local object=U.GameObject('legacy-source-motion-group-'..tostring(unit)..'|'..tostring(travel),typeof(U.RectTransform))
    object.layer=state.root.layer
    local rect=object.transform;rect:SetParent(state.root.transform,false)
    rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(1,1)
    rect.sizeDelta=U.Vector2(0,0);rect.anchoredPosition=U.Vector2(0,0)
    rect.localScale=U.Vector3(1,1,1)
    group={rect=rect,unit=unit,travel=travel,factor=travel/state.distance*unit,y=0}
    bucket[travel]=group;sourceGroupMove(state,group)
    return group
end
function NativeSourceGroups.Bind(state,row,n,current,recipes)
    local fresh=row.groupOwner~=n
    if fresh then
        row.groupRect=row.note.rectNoteRange
        row.groupUnit=row.groupRect.rect.width/recipes[n.lane].lane_width_720
        assert(row.groupUnit>0 and row.groupUnit<math.huge,'Invalid source visual parent unit')
    end
    local travel=laneTravel(state,recipes[n.lane],n.lane)
    local far=n.display_y>current+state.distance
    if not fresh and row.groupFar==far and row.groupEpoch==state.epoch then return end
    local rect,unit=row.groupRect,row.groupUnit
    local factor=travel/state.distance*unit
    local parent,head,tail
    if far then
        -- Default whole-image factory keeps the entire fixed image at its
        -- far point. Its unused native tail has no independent source art.
        parent=state.root.transform
        head=travel*unit
        tail=(n.end_y-current)*factor
    else
        parent=sourceGroup(state,unit,travel).rect
        head=n.display_y*factor;tail=n.end_y*factor
    end
    rect:SetParent(parent,false)
    local low,high=rect.offsetMin,rect.offsetMax
    rect.offsetMin=CS.UnityEngine.Vector2(low.x,head)
    rect.offsetMax=CS.UnityEngine.Vector2(high.x,tail)
    row.groupOwner=n;row.groupFar=far;row.groupEpoch=state.epoch;row.groupLastCurrent=current;state.bindings=state.bindings+1
end
function NativeSourceGroups.BindPart3(state,row,n,current,recipe,sourceHead,held,head,tail)
    local fresh=row.groupOwner~=n
    if fresh then
        row.groupRect=row.note.rectNoteRange
        row.groupUnit=row.groupRect.rect.width/recipe.lane_width_720
        assert(row.groupUnit>0 and row.groupUnit<math.huge,'Invalid Part3 parent unit')
    end
    local rect,unit=row.groupRect,row.groupUnit
    local hold=n.endtime>n.time
    local first,last=recipe.legacy_size_start,recipe.legacy_size_end
    local fixedSize=not (first and last) or first[1]==last[1] and first[2]==last[2]
    local vertical=not (recipe.start_x and recipe.end_x) or recipe.start_x==recipe.end_x
    local travel=laneTravel(state,recipe,n.lane)
    local sharedTravel=not (recipe.start_y and recipe.end_y) or
        math.abs(travel-state.motion.travel_720)<.0001
    -- Only a rigid interval may share translation. A clipped future tail,
    -- a held moving source head, and a far-clamped TAP are non-rigid.
    local rigid=fixedSize and vertical and sharedTravel and not recipe.legacy_projected and
        not held and (hold and n.end_y<=current+state.distance or
        not hold and n.display_y<=current+state.distance)
    if rigid and not fresh and row.groupRigid and row.groupEpoch==state.epoch and row.groupHead==sourceHead then return false end
    local parent
    if rigid then
        parent=sourceGroup(state,unit,travel).rect
        local factor=travel/state.distance*unit
        head=sourceHead*factor;tail=n.end_y*factor
    else parent=state.root.transform end
    if fresh or row.groupParent~=parent then rect:SetParent(parent,false) end
    local low,high=rect.offsetMin,rect.offsetMax
    rect.offsetMin=CS.UnityEngine.Vector2(low.x,head)
    rect.offsetMax=CS.UnityEngine.Vector2(high.x,tail)
    row.groupOwner=n;row.groupParent=parent;row.groupRigid=rigid
    row.groupEpoch=state.epoch;row.groupHead=sourceHead;row.groupLastCurrent=current;state.bindings=state.bindings+1
    return true
end
