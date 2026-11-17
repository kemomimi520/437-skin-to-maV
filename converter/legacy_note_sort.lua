-- 4.3.7 x86 0x496e90. Equal keys are stable only in insertion-sized
-- partitions. Preserve median/partition/heap tie choices, not just key order.
local LegacyNoteSort={}
function LegacyNoteSort.Sort(values,less,ideal)
    local function swap(a,b) values[a],values[b]=values[b],values[a] end
    local function median(a,b,c)
        if less(values[b],values[a]) then swap(a,b) end
        if less(values[c],values[b]) then
            swap(b,c)
            if less(values[b],values[a]) then swap(a,b) end
        end
    end
    local function partition(first,last)
        local mid=first+(last-first)//2;local final=last-1
        if final-first>40 then
            local step=(final-first+1)//8
            median(first,first+step,first+2*step)
            median(mid-step,mid,mid+step)
            median(final-2*step,final-step,final)
            median(first+step,mid,final-step)
        else median(first,mid,final) end
        local low,high=mid,mid+1
        while first<low and not less(values[low-1],values[low]) and not less(values[low],values[low-1]) do low=low-1 end
        while high<last and not less(values[high],values[low]) and not less(values[low],values[high]) do high=high+1 end
        local left,right=low,high
        while true do
            while right<last do
                if less(values[low],values[right]) then right=right+1
                elseif less(values[right],values[low]) then break
                else swap(high,right);high=high+1;right=right+1 end
            end
            while first<left do
                local trial=left-1
                if less(values[trial],values[low]) then left=left-1
                elseif less(values[low],values[trial]) then break
                else low=low-1;swap(low,trial);left=left-1 end
            end
            if left==first and right==last then return low,high end
            if left==first then
                if high~=right then swap(low,high) end
                high=high+1;swap(low,right);low=low+1;right=right+1
            elseif right==last then
                left=left-1;low=low-1
                if left~=low then swap(left,low) end
                high=high-1;swap(low,high)
            else left=left-1;swap(left,right);right=right+1 end
        end
    end
    local function heap(first,last)
        local size=last-first
        local function adjust(hole,length,value)
            local top=hole;local child=2*hole+2
            while child<length do
                if less(values[first+child],values[first+child-1]) then child=child-1 end
                values[first+hole]=values[first+child];hole=child;child=2*hole+2
            end
            if child==length then values[first+hole]=values[first+child-1];hole=child-1 end
            while hole>top do
                local parent=(hole-1)//2
                if not less(values[first+parent],value) then break end
                values[first+hole]=values[first+parent];hole=parent
            end
            values[first+hole]=value
        end
        for hole=size//2-1,0,-1 do adjust(hole,size,values[first+hole]) end
        for length=size-1,1,-1 do
            local value=values[first+length];values[first+length]=values[first]
            adjust(0,length,value)
        end
    end
    local function sort(first,last,budget)
        while last-first>32 do
            if budget<=0 then heap(first,last);return end
            local low,high=partition(first,last);budget=budget//2+(budget//2)//2
            if low-first<last-high then sort(first,low,budget);first=high
            else sort(high,last,budget);last=low end
        end
        for at=first+1,last-1 do
            local value=values[at];local hole=at
            while hole>first and less(value,values[hole-1]) do values[hole]=values[hole-1];hole=hole-1 end
            values[hole]=value
        end
    end
    sort(1,#values+1,ideal or #values)
    return values
end
function LegacyNoteSort.Less(a,b)
    local x,y=a.sort_key,b.sort_key
    if x[1]~=y[1] then return x[1]<y[1] end
    if x[2]~=y[2] then return x[2]<y[2] end
    return ((x[3]*y[4]) & 0xffffffff)<((x[4]*y[3]) & 0xffffffff)
end
function LegacyNoteSort.Source(notes)
    for _,note in ipairs(notes) do
        local beat=note.beat
        assert(beat and #beat==3 and math.type(beat[1])=='integer' and
            math.type(beat[2])=='integer' and math.type(beat[3])=='integer' and
            beat[1]>=0 and beat[1]<=2147483647 and beat[2]>=0 and beat[2]<beat[3] and beat[3]<=65535,
            'Ma Skin Bridge: legacy sort requires normalized bounded source beat fractions')
        note.sort_key={0,beat[1],beat[2],beat[3]}
    end
    LegacyNoteSort.Sort(notes,LegacyNoteSort.Less)
    for rank,note in ipairs(notes) do note.legacy_order=rank end
end
function LegacyNoteSort.LessGeneral(a,b)
    local x,y=a.sort_key,b.sort_key
    if x[1]~=y[1] then return x[1]<y[1] end
    if x[2]~=y[2] then return x[2]<y[2] end
    if x[3]<=2147483647 and y[4]<=2147483647 and x[4]<=2147483647 and y[3]<=2147483647 then
        return (x[3]*y[4])<(x[4]*y[3])
    end
    return (x[3]/x[4])<(y[3]/y[4])
end
function LegacyNoteSort.SourceGeneral(notes)
    local uint32Bound=true
    for _,note in ipairs(notes) do
        local beat=note.beat
        assert(beat and #beat==3 and beat[3]>0,'Ma Skin Bridge: invalid source beat fraction')
        local w=math.floor(beat[1]);local n=math.floor(beat[2]);local d=math.floor(beat[3])
        local q=n//d
        w=w+q;n=n-q*d
        if n==0 then d=1 else
            local a,b=n,d
            while b~=0 do a,b=b,a%b end
            n=n//a;d=d//a
        end
        if w<0 or w>2147483647 or d>65535 then uint32Bound=false end
        note.sort_key={0,w,n,d}
    end
    LegacyNoteSort.Sort(notes,uint32Bound and LegacyNoteSort.Less or LegacyNoteSort.LessGeneral)
    for rank,note in ipairs(notes) do note.legacy_order=rank end
end
