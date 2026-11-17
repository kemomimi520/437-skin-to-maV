-- Original ChartOSU timing rules, reconstructed from 0x4b7010/0x4b7a60.
-- The source chart is read in place. No skin-name or chart-name branches.
local LegacyOsu={}
local function integer(text)
    return assert(tonumber(tostring(text):match('^%s*([+-]?%d+)')),'Ma Skin Bridge: invalid OSU integer')
end
local function columns(line)
    local result={}
    for value in (line..','):gmatch('(.-),') do result[#result+1]=value end
    return result
end
local function finite(value)
    assert(value and value==value and math.abs(value)<math.huge,'Ma Skin Bridge: invalid OSU number')
    return value
end
local function rounded(value)
    -- The old CRT round is halfway away from zero.
    return value<0 and math.ceil(value-.5) or math.floor(value+.5)
end
function LegacyOsu.Fraction(value,length)
    local snap=rounded(value*24)
    if math.abs(value*24-snap)*length<48 then
        local whole=math.floor(snap/24);local numer=snap-whole*24
        local a,b=numer,24
        while b~=0 do a,b=b,a%b end
        return {whole,numer//a,24//a}
    end
    -- 0x600590 continued fraction, absolute time tolerance 2 ms. Preserve
    -- its stopping test; nearest fraction with a denominator cap is different.
    local whole=rounded(value);local remainder=value-whole
    local numerator,oldNumerator,denominator,oldDenominator=0,1,1,0
    local error=-remainder;local tolerance=2/length
    for _=1,128 do
        if math.abs(error)<math.abs(denominator)*tolerance then break end
        local inverse=1/remainder;local quotient=rounded(inverse)
        remainder=inverse-quotient
        local nextDenominator=quotient*denominator+oldDenominator
        local nextNumerator=quotient*numerator+oldNumerator
        if math.abs(nextDenominator)>16777215 then break end
        oldNumerator,numerator=numerator,nextNumerator
        oldDenominator,denominator=denominator,nextDenominator
        error=-error*remainder
    end
    if denominator<0 then numerator=-numerator end
    denominator=math.abs(denominator)
    if numerator<0 then whole=whole-1;numerator=numerator+denominator end
    return {whole,math.tointeger(numerator),math.tointeger(denominator)}
end
function LegacyOsu.Parse(text)
    assert(#text<=16*1024*1024,'Ma Skin Bridge: OSU exceeds the 16 MiB source read bound')
    text=text:gsub('^\239\187\191','')
    local section;local timing,rawNotes,settings={},{},{}
    for raw in (text..'\n'):gmatch('(.-)\n') do
        local line=raw:match('^%s*(.-)%s*$')
        if line:sub(1,2)~='//' and #line>0 then
            if line:match('^%[.-%]$') then section=line:sub(2,-2)
            elseif section=='General' or section=='Difficulty' then
                local name,value=line:match('^([^:]+):%s*(.-)%s*$')
                if name then settings[name:match('^%s*(.-)%s*$')]=value end
            elseif section=='TimingPoints' then timing[#timing+1]=columns(line)
            elseif section=='HitObjects' then rawNotes[#rawNotes+1]=columns(line) end
        end
    end
    local keys=integer(settings.CircleSize or '')
    assert(settings.Mode and integer(settings.Mode)==3 and keys>=1 and keys<=10,
        'Ma Skin Bridge: original OSU adapter requires mania with 1..10 keys')
    assert(#timing>0 and #timing<=100000,'Ma Skin Bridge: OSU timing input bounds')
    assert(#rawNotes>0 and #rawNotes<=16384,'Ma Skin Bridge: OSU note count exceeds verified sort range')
    local rows,points,effects={},{},{};local tempo
    local function beatAt(time)
        local row=assert(rows[1],'Ma Skin Bridge: OSU requires an initial uninherited timing point')
        for i=2,#rows do if rows[i].offset>time then break end;row=rows[i] end
        local value=LegacyClock.Beat(row.beat)+(time-row.offset)/row.length
        return LegacyOsu.Fraction(value,row.length)
    end
    for _,fields in ipairs(timing) do
        local time=integer(fields[1]);local length=finite(tonumber(fields[2]))
        assert(not rows[#rows] or time>=rows[#rows].offset,'Ma Skin Bridge: unsorted OSU timing points are not certified')
        local inherited=fields[7] and integer(fields[7])==0
        local beat
        if inherited then
            assert(tempo and length<0,'Ma Skin Bridge: inherited OSU timing requires a prior tempo and negative length')
            beat=beatAt(time)
            effects[#effects+1]={offset=time,value=-100/length}
        else
            assert(length>0,'Ma Skin Bridge: OSU tempo must be positive')
            local whole=tempo and math.ceil((time-tempo.offset-2)/tempo.length)+tempo.beat[1] or 0
            beat={whole,0,1}
            tempo={beat=beat,offset=time,length=length}
            points[#points+1]={beat=beat,offset=time,beat_length=length}
            -- The original export emits an empty effect followed by SV=1.
            -- Both occupy display-carrier positions, including equal offsets.
            effects[#effects+1]={offset=time}
            effects[#effects+1]={offset=time,value=1}
        end
        rows[#rows+1]={offset=time,beat=beat,length=tempo.length}
    end
    local notes={};local width=512//keys
    for index,fields in ipairs(rawNotes) do
        local kind=integer(fields[4]);local time=integer(fields[3]);local finish=time
        assert((kind & (1|128))~=0 and (kind & (2|8))==0,'Ma Skin Bridge: unsupported OSU hit object')
        if (kind & 128)~=0 then finish=integer(assert(fields[6])) end
        assert(finish>=time,'Ma Skin Bridge: invalid OSU hold duration')
        local x=integer(fields[1]);local lane=math.max(0,math.min(keys-1,x//width))+1
        notes[#notes+1]={nid=index-1,lane=lane,time=time,endtime=finish,
            beat=beatAt(time),endbeat=beatAt(finish),source_order=index-1}
    end
    local sorted={}
    for _,note in ipairs(notes) do sorted[#sorted+1]={beat=note.beat,note=note} end
    LegacyNoteSort.Source(sorted)
    for _,row in ipairs(sorted) do row.note.legacy_order=row.legacy_order end
    return {absolute=true,keys=keys,timepoints=points,effects=effects,notes=notes}
end
function UnityBridge.LegacyOsuInput(chart,processor,layer,includeScroll)
    local path=publicGetter(chart,'get_FilePath')
    if not CS.System.IO.Path.IsPathRooted(path) then
        path=chart:GetAbsFilePath(publicGetter(chart,'get_FileName'))
    end
    assert(CS.System.IO.File.Exists(path),'Ma Skin Bridge: original OSU source is required')
    local result=LegacyOsu.Parse(CS.System.IO.File.ReadAllText(path))
    local list=publicGetter(processor,'get_ResultNoteList')
    assert(list.Count==#result.notes and list.Count==Chart:NoteCount(),'Ma Skin Bridge: OSU source/native note count mismatch')
    local function key(lane,time,finish) return string.format('%d:%.17g:%.17g',lane,time,finish) end
    local byIdentity=LegacyNoteIdentity.Index(result.notes,function(note) return key(note.lane,note.time,note.endtime) end)
    for i=0,list.Count-1 do
        local carrier=list[i];local nativeNote=Chart:NoteAt(i)
        -- The processor keeps the original chart NoteKey on this PUBLIC
        -- field; Flip/Luck change ScriptNote.x independently. Using x here
        -- can reject a valid chart, or silently swap equal-time chord notes.
        -- Match with the source identity, then retain the processed draw lane.
        local sourceField=carrier:GetType():GetField(NativeBindings.Name('bcbb'),20)
        assert(sourceField and sourceField.IsPublic,'Ma Skin Bridge: public OSU source note field missing')
        local source=assert(sourceField:GetValue(carrier),'Ma Skin Bridge: original OSU note missing')
        local sourceLane=publicGetter(source,'get_X')+1
        if includeScroll then
            local field=assert(carrier:GetType():GetField(NativeBindings.Name('bcay'),20))
            assert(field:GetValue(carrier)==1,'Ma Skin Bridge: per-note OSU speed is not certified')
        end
        local identity=key(sourceLane,publicGetter(carrier,'get_StartOffset'),publicGetter(carrier,'get_EndOffset'))
        local note=LegacyNoteIdentity.Take(byIdentity,identity)
        note.nid=nativeNote.nid
        note.source_lane=sourceLane;note.lane=nativeNote.x
    end
    if includeScroll then assert(layer,'Ma Skin Bridge: native OSU scroll layer is absent') end
    result.layer=layer
    return result
end
