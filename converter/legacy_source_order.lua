local function parseMcJson(text)
    local pos=1
    local len=#text
    if len>=3 and text:sub(1,3)=='\239\187\191' then pos=4 end
    local find,byte,sub=string.find,string.byte,string.sub
    local function skipWs()
        local _,nextEnd=find(text,'^[ \t\r\n]+',pos)
        if nextEnd then pos=nextEnd+1 end
    end
    local parseValue
    local function parseString()
        pos=pos+1
        local chunks={}
        while pos<=len do
            local s,e,ch=find(text,'([\\"])',pos)
            if not s then error('Ma Skin Bridge: unterminated MC JSON string') end
            if s>pos then chunks[#chunks+1]=sub(text,pos,s-1) end
            if ch=='"' then
                pos=e+1
                return #chunks==0 and '' or (#chunks==1 and chunks[1] or table.concat(chunks))
            end
            pos=e+1
            local esc=sub(text,pos,pos)
            pos=pos+1
            if esc=='"' or esc=='\\' or esc=='/' then chunks[#chunks+1]=esc
            elseif esc=='b' then chunks[#chunks+1]='\b'
            elseif esc=='f' then chunks[#chunks+1]='\f'
            elseif esc=='n' then chunks[#chunks+1]='\n'
            elseif esc=='r' then chunks[#chunks+1]='\r'
            elseif esc=='t' then chunks[#chunks+1]='\t'
            elseif esc=='u' then
                local hex=sub(text,pos,pos+3)
                local cp=assert(tonumber(hex,16),'Ma Skin Bridge: invalid MC JSON unicode escape')
                pos=pos+4
                if cp>=0xD800 and cp<=0xDBFF and sub(text,pos,pos+1)=='\\u' then
                    local low=tonumber(sub(text,pos+2,pos+5),16)
                    if low and low>=0xDC00 and low<=0xDFFF then
                        cp=0x10000+((cp-0xD800)*0x400)+(low-0xDC00)
                        pos=pos+6
                    end
                end
                chunks[#chunks+1]=(utf8 and utf8.char) and utf8.char(cp) or '?'
            else
                error('Ma Skin Bridge: invalid MC JSON escape '..esc)
            end
        end
        error('Ma Skin Bridge: unterminated MC JSON string')
    end
    local function parseArray()
        pos=pos+1
        skipWs()
        local arr={}
        if sub(text,pos,pos)==']' then pos=pos+1;return arr end
        while true do
            arr[#arr+1]=parseValue()
            skipWs()
            local ch=sub(text,pos,pos)
            if ch==']' then pos=pos+1;return arr end
            if ch~=',' then error('Ma Skin Bridge: expected , or ] in MC JSON array') end
            pos=pos+1
        end
    end
    local function parseObject()
        pos=pos+1
        skipWs()
        local obj={}
        if sub(text,pos,pos)=='}' then pos=pos+1;return obj end
        while true do
            skipWs()
            if sub(text,pos,pos)~='"' then error('Ma Skin Bridge: expected string key in MC JSON object') end
            local k=parseString()
            skipWs()
            if sub(text,pos,pos)~=':' then error('Ma Skin Bridge: expected : in MC JSON object') end
            pos=pos+1
            local v=parseValue()
            if v~=nil then obj[k]=v end
            skipWs()
            local ch=sub(text,pos,pos)
            if ch=='}' then pos=pos+1;return obj end
            if ch~=',' then error('Ma Skin Bridge: expected , or } in MC JSON object') end
            pos=pos+1
        end
    end
    parseValue=function()
        skipWs()
        local b=byte(text,pos)
        if not b then error('Ma Skin Bridge: unexpected end of MC JSON') end
        if b==34 then return parseString() end
        if b==123 then return parseObject() end
        if b==91 then return parseArray() end
        if b==116 and sub(text,pos,pos+3)=='true' then pos=pos+4;return true end
        if b==102 and sub(text,pos,pos+4)=='false' then pos=pos+5;return false end
        if b==110 and sub(text,pos,pos+3)=='null' then pos=pos+4;return nil end
        local _,numEnd,numStr=find(text,'^(-?%d+%.?%d*[eE]?[+-]?%d*)',pos)
        if numStr then
            local num=tonumber(numStr)
            if num~=nil then pos=numEnd+1;return num end
        end
        error('Ma Skin Bridge: invalid token in MC JSON at '..pos)
    end
    local parsed=parseValue()
    skipWs()
    assert(pos>len,'Ma Skin Bridge: trailing data in MC JSON')
    return parsed
end

-- maV reorders equal-beat MC notes. Recover the old pointer-vector ordering
-- from original MC inputs, including its unstable large-vector partitions.
-- Read only the selected native MC, using its public path and JSON API.
function UnityBridge.LegacySourceOrder(chart,notes,nativeMods)
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'Newtonsoft.Json') end
    assert(#notes<=100000,'Ma Skin Bridge: chart exceeds 100000-note sort range')
    local path=publicGetter(chart,'get_FilePath')
    if not CS.System.IO.Path.IsPathRooted(path) then
        path=chart:GetAbsFilePath(publicGetter(chart,'get_FileName'))
    end
    assert(CS.System.IO.File.Exists(path),'Ma Skin Bridge: original MC source is required for equal-beat ordering')
    local text=CS.System.IO.File.ReadAllText(path)
    assert(#text<=16*1024*1024,'Ma Skin Bridge: MC exceeds the 16 MiB source read bound')
    local function key(lane,start,finish)
        -- Taps/Holds deliberately replace native ends. Original starts and
        -- source lanes still identify the same multiset of chart heads.
        if ((nativeMods or 0)&49152)~=0 then finish=start end
        return LegacyNoteIdentity.BeatKey(lane,start,finish)
    end
    local native=LegacyNoteIdentity.Index(notes,function(note) return key(note.source_lane or note.lane,note.beat,note.endbeat) end)
    local matched=0;local sourceNotes={}
    local function recordRow(index0,laneNum,start,finish)
        if laneNum~=nil then
            local lane=assert(laneNum,'Ma Skin Bridge: nonnumeric MC column')+1
            local id=key(lane,start,finish or start)
            local note=LegacyNoteIdentity.Take(native,id)
            note.source_order=index0;matched=matched+1
            sourceNotes[#sourceNotes+1]={beat=start,note=note}
        end
    end
    local ok,root=pcall(function() return CS.Newtonsoft.Json.Linq.JObject.Parse(text) end)
    if ok and root~=nil then
        -- This player strips GetValue and xLua does not expose JObject's string
        -- indexer. The shipped public TryGetValue/out and linked JToken siblings
        -- survive; do not enable private access or synthesize replacement JSON.
        local lookup
        local methods=root:GetType():GetMethods(20)
        for i=0,methods.Length-1 do
            if methods[i].Name=='TryGetValue' and methods[i]:GetParameters().Length==2 then lookup=methods[i] end
        end
        assert(lookup,'Ma Skin Bridge: public MC JSON lookup unavailable')
        local function member(object,name)
            local values=CS.System.Array.CreateInstance(typeof(CS.System.Object),2);values[0]=name
            local found=lookup:Invoke(object,CS.System.Reflection.BindingFlags.Default,nil,values,nil)
            return CS.System.Convert.ToBoolean(found) and values[1] or nil
        end
        local array=assert(member(root,'note'),'Ma Skin Bridge: original MC note array missing')
        local count=tonumber(publicGetter(array,'get_Count'))
        assert(count and count<=100000,'Ma Skin Bridge: invalid MC source array size')
        local function beat(token)
            assert(publicGetter(token,'get_Count')==3,'Ma Skin Bridge: invalid MC beat array')
            local result={};local current=publicGetter(token,'get_First')
            for i=1,3 do
                assert(current,'Ma Skin Bridge: incomplete MC beat array')
                result[i]=assert(tonumber(current:ToString()),'Ma Skin Bridge: nonnumeric MC beat')
                current=publicGetter(current,'get_Next')
            end
            return result
        end
        local row=publicGetter(array,'get_First')
        for i=0,count-1 do
            assert(row,'Ma Skin Bridge: incomplete MC source note array')
            local column=member(row,'column')
            local rowType=member(row,'type')
            local isSample=rowType~=nil and assert(tonumber(rowType:ToString()),'Ma Skin Bridge: nonnumeric MC note type')==1
            if column~=nil and not isSample then
                local start=beat(assert(member(row,'beat')))
                local tail=member(row,'endbeat')
                recordRow(i,tonumber(column:ToString()),start,tail and beat(tail) or nil)
            end
            row=publicGetter(row,'get_Next')
        end
    else
        local parsed=assert(parseMcJson(text),'Ma Skin Bridge: invalid MC JSON')
        local array=assert(type(parsed)=='table' and type(parsed.note)=='table' and parsed.note,'Ma Skin Bridge: original MC note array missing')
        local count=#array
        assert(count<=100000,'Ma Skin Bridge: invalid MC source array size')
        local function beat(tbl)
            assert(type(tbl)=='table' and #tbl==3,'Ma Skin Bridge: invalid MC beat array')
            local a=assert(tonumber(tbl[1]),'Ma Skin Bridge: nonnumeric MC beat')
            local b=assert(tonumber(tbl[2]),'Ma Skin Bridge: nonnumeric MC beat')
            local c=assert(tonumber(tbl[3]),'Ma Skin Bridge: nonnumeric MC beat')
            return {a,b,c}
        end
        for i=1,count do
            local row=assert(type(array[i])=='table' and array[i],'Ma Skin Bridge: incomplete MC source note array')
            local isSample=row.type~=nil and assert(tonumber(row.type),'Ma Skin Bridge: nonnumeric MC note type')==1
            if row.column~=nil and not isSample then
                local col=assert(tonumber(row.column),'Ma Skin Bridge: nonnumeric MC column')
                local start=beat(row.beat)
                local finish=row.endbeat~=nil and beat(row.endbeat) or nil
                recordRow(i-1,col,start,finish)
            end
        end
    end
    assert(matched==#notes,'Ma Skin Bridge: MC source order did not cover native notes')
    local canonical=true
    for _,row in ipairs(sourceNotes) do
        local b=row.beat
        if not (b and #b==3 and math.type(b[1])=='integer' and math.type(b[2])=='integer' and math.type(b[3])=='integer'
                and b[1]>=0 and b[1]<=2147483647 and b[2]>=0 and b[2]<b[3] and b[3]<=65535) then
            canonical=false;break
        end
    end
    if canonical then LegacyNoteSort.Source(sourceNotes) else LegacyNoteSort.SourceGeneral(sourceNotes) end
    for _,row in ipairs(sourceNotes) do row.note.legacy_order=row.legacy_order end
end
