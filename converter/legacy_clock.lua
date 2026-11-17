-- Pure reconstruction of the old TimePointOffset/TimePoint arithmetic.
-- Native chart offsets are not interchangeable with this computation.
local LegacyClock={}
function LegacyClock.Beat(value)
    assert(value and #value==3 and value[3]>0,'Ma Skin Bridge: invalid source beat fraction')
    return value[1]+UnityBridge.Float(value[2]/value[3])
end
function LegacyClock.Build(source)
    local points={}
    for idx,point in ipairs(source) do
        assert(point.beat_length>0 and point.beat_length<math.huge,'Ma Skin Bridge: invalid legacy tempo')
        points[#points+1]={beat=LegacyClock.Beat(point.beat),length=point.beat_length,idx=idx}
    end
    table.sort(points,function(a,b) return a.beat==b.beat and a.idx<b.idx or a.beat<b.beat end)
    assert(#points>0,'Ma Skin Bridge: legacy clock requires at least one tempo point')
    points[1].offset=0
    for i=2,#points do
        local previous=points[i-1]
        points[i].offset=previous.offset+(points[i].beat-previous.beat)*previous.length
    end
    return points
end
function LegacyClock.Time(points,value)
    local beat=LegacyClock.Beat(value);local lo,hi=1,#points
    while lo<hi do
        local mid=(lo+hi+1)//2
        if points[mid].beat<=beat then lo=mid else hi=mid-1 end
    end
    local point=points[lo]
    local offset=point.offset+(beat-point.beat)*point.length
    return offset<0 and math.ceil(offset) or math.floor(offset)
end
