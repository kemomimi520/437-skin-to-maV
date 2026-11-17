-- Original Key chart/processor readout for SOURCE VISUALS only. No Free API,
-- replacement parser for gameplay, carrier writes, clock or score changes.
-- NativeBindings and the retained 437 clock/scroll/sort readers precede this.
local NativeSourceInput={}
local nativeSourceMethods,nativeSourceFields={},{}
local nativeSourceEmpty,nativeSourceWaitingPlayer
local function resolvePublic(object,name,static)
    local kind=static and object or object:GetType()
    local key=kind.FullName..':'..name..(static and ':static' or '')
    local method=nativeSourceMethods[key]
    if not method then
        local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),static and 'Public, Static' or 'Public, Instance')
        local methods=kind:GetMethods(flags)
        for i=0,methods.Length-1 do
            local m=methods[i]
            if m.Name==name and m:GetParameters().Length==0 then
                assert(not method,'Ambiguous native source getter '..name);method=m
            end
        end
        nativeSourceMethods[key]=assert(method,'Original source getter missing '..name)
    end
    nativeSourceEmpty=nativeSourceEmpty or CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
    return method
end
local function sourcePublic(object,name,static)
    local method=resolvePublic(object,name,static)
    local target=object
    if static then target=nil end
    return method:Invoke(target,CS.System.Reflection.BindingFlags.Default,nil,nativeSourceEmpty,nil)
end
local function sourceField(object,name)
    name=NativeBindings.Name(name)
    local kind=object:GetType();local key=kind.FullName..':'..name
    local field=nativeSourceFields[key]
    if not field then
        local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Public, Instance')
        field=kind:GetField(name,flags)
        nativeSourceFields[key]=assert(field and field.IsPublic and field,'Original source field missing '..name)
    end
    return field:GetValue(object)
end
local function sourceFraction(timing)
    assert(sourcePublic(timing,'get_IsBeatValid'),'Absolute MC timings need a source timing mapping')
    local beat=sourcePublic(timing,'get_Beat')
    return {sourcePublic(beat,'get_Int'),sourcePublic(beat,'get_Numer'),sourcePublic(beat,'get_Denom')}
end
local function sourcePath(chart)
    local path=sourcePublic(chart,'get_FilePath')
    if not CS.System.IO.Path.IsPathRooted(path) then path=chart:GetAbsFilePath(sourcePublic(chart,'get_FileName')) end
    assert(CS.System.IO.File.Exists(path),'Original chart source is required for 437 visual ordering')
    return path
end
function NativeSourceInput.Read(layer)
    xlua.load_assembly('Assembly-CSharp');xlua.load_assembly('UnityEngine.CoreModule')
    local player=nativeSourceWaitingPlayer
    if not player or player:Equals(nil) then
        local players=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.Malody.Play.ChartPlayer),false)
        assert(players.Length==1,'Source visuals require one original ChartPlayer')
        player=players[0];nativeSourceWaitingPlayer=player
    end
    -- Setup can notify variables at clock zero BEFORE Play establishes the
    -- real prelude. Do not consume any source FIFO entries at that time.
    if not sourcePublic(player,'get_IsPlaying') then return nil end
    local processor=sourcePublic(player,'get_Processor')
    assert(processor:GetType().FullName=='Malody.Play.ProcessorKey','Source Key visual pool is not mapped for this processor')
    local chart=sourcePublic(processor,'get_ChartToProcess');NativeBindings.Select(chart)
    local list=sourcePublic(processor,'get_ResultNoteList')
    assert(list and list.Count>0 and list.Count<=100000,'Source visual note count exceeds source sort range')
    local mods=CS.System.Convert.ToInt32(sourcePublic(processor,'get_UseMod'))
    local format=CS.System.Convert.ToInt32(sourcePublic(chart,'get_Format'))
    local input,carriers={timepoints={},notes={},effects={}},{}
    if format==5 then
        input=LegacyOsu.Parse(CS.System.IO.File.ReadAllText(sourcePath(chart)))
        assert(#input.notes==list.Count,'Source OSU/native note count differs')
        local function identity(lane,start,finish)
            if mods&49152~=0 then finish=start end
            return string.format('%d:%.17g:%.17g',lane,start,finish)
        end
        local index=LegacyNoteIdentity.Index(input.notes,function(n)return identity(n.lane,n.time,n.endtime)end)
        for i=0,list.Count-1 do
            local carrier=list[i];local raw=sourceField(carrier,'bcbb')
            local start=sourcePublic(carrier,'get_StartOffset');local ending=sourcePublic(carrier,'get_EndOffset')
            local sourceLane=sourcePublic(raw,'get_X')+1
            local note=LegacyNoteIdentity.Take(index,identity(sourceLane,start,ending))
            note.nid=i;note.source_lane=sourceLane;note.lane=sourceField(carrier,'bcbd')+1
            -- Native Mods own the effective length. The source sort rank was
            -- obtained before matching; do not reorder by the processed lane.
            if mods&49152~=0 then
                note.endtime=ending
                if ending<=start then note.endbeat=note.beat end
            end
            carriers[i]=carrier
        end
    else
        assert(format==1,'Source visual timing requires MC or mania OSU')
        local points=sourceField(chart,'bifq')
        for i=0,points.Count-1 do
            input.timepoints[#input.timepoints+1]={beat=sourceFraction(sourceField(points[i],'start')),
                beat_length=sourceField(points[i],'beatLength')}
        end
        for i=0,list.Count-1 do
            local carrier=list[i];local raw=sourceField(carrier,'bcbb')
            input.notes[#input.notes+1]={nid=i,lane=sourceField(carrier,'bcbd')+1,
                source_lane=sourcePublic(raw,'get_X')+1,beat=sourceFraction(sourceField(raw,'start')),
                endbeat=sourceFraction(sourcePublic(raw,'get_EndOrStart'))}
            carriers[i]=carrier
        end
        -- Only read source order; gameplay continues to use the game's own
        -- already parsed notes, processor, input, judge and Replay.
        sourceLegacyOrder(chart,input.notes,mods,sourcePublic)
        local effects=sourceField(chart,'bifs')
        for i=0,effects.Count-1 do
            local effect=effects[i]
            local timing=sourceField(effect,'start')
            if sourcePublic(timing,'get_IsBeatValid') then
                local value=sourceField(effect,'value')
                local kind=CS.System.Convert.ToInt32(sourceField(effect,'type'))
                local vt=CS.System.Convert.ToInt32(sourcePublic(value,'get_Type'))
                local num=(vt==2 or vt==3 or vt==4) and sourcePublic(value,'get_Double') or nil
                input.effects[#input.effects+1]={beat=sourceFraction(timing),type=kind,
                    variant_type=vt,value=num}
            end
        end
    end
    -- 4.3.7's Note_SetAlternateTexture is selected by the original note
    -- factory for simultaneous starts.  Keep that source condition beside
    -- the matched note identity so the visual queue can switch tex4 without
    -- touching maV's carrier, judge or score state.  Start offsets come from
    -- the native carrier, which preserves MC fractional timing and the
    -- original OSU source ordering.
    local starts={}
    for _,note in ipairs(input.notes) do
        local carrier=assert(carriers[note.nid],'Source chord carrier missing')
        local start=sourcePublic(carrier,'get_StartOffset')
        local bucket=starts[start]
        if not bucket then bucket={};starts[start]=bucket end
        bucket[#bucket+1]=note
    end
    for _,bucket in pairs(starts) do
        if #bucket>1 then for _,note in ipairs(bucket) do note.chord=true end end
    end
    input.layer=layer;input.native_mods=mods;input.carriers=carriers;input.clock=NativeBindings.ClockType()
    input.processor=processor;input.chart=chart;input.format=format
    return input
end
function NativeSourceInput.Bars(input,scroll)
    if input.format==1 then
        local begin=sourcePublic(sourceField(input.chart,'biff'),'get_BarBegin')
        assert(begin>=0 and begin<=4294967295 and begin==math.floor(begin),'Invalid source MC BarBegin')
        if begin>=2147483648 then return {},begin end
    end
    local list=sourcePublic(input.processor,'get_ResultBarList')
    assert(list and list.Count<=100000,'Original Key bar source is unavailable or exceeds the visual bound')
    local bars={}
    for i=0,list.Count-1 do
        local carrier=list[i]
        local time=sourcePublic(carrier,'get_StartOffset')
        if input.format==1 then
            local beat=sourcePublic(carrier,'get_StartBeat')
            time=LegacyClock.Time(scroll.source_clock,{sourcePublic(beat,'get_Int'),
                sourcePublic(beat,'get_Numer'),sourcePublic(beat,'get_Denom')})
        end
        bars[#bars+1]={offset=time,displayY=LegacyScroll.CarrierY(scroll,time)}
    end
    return bars
end
local function resolveCallable(object,name,static,cache,key)
    local cached=cache[key]
    if cached~=nil then return cached,cache[key..'_fn'] end
    local method=resolvePublic(object,name,static)
    local fn
    local ok,del=pcall(function()
        local ftype=CS.System.Func(method.ReturnType)
        return static and CS.System.Delegate.CreateDelegate(typeof(ftype),method)
            or CS.System.Delegate.CreateDelegate(typeof(ftype),object,method)
    end)
    if ok and del then fn=del end
    cache[key]=method
    cache[key..'_fn']=fn or false
    return method,fn or false
end
function NativeSourceInput.Times(input)
    local mc,fc=input._m_chart,input._f_chart
    if not mc then mc,fc=resolveCallable(input.clock,'get_ChartTime',true,input,'_c_chart');input._m_chart=mc;input._f_chart=fc end
    local md,fd=input._m_display,input._f_display
    if not md then md,fd=resolveCallable(input.clock,'get_DisplayTime',true,input,'_c_display');input._m_display=md;input._f_display=fd end
    if fc and fd then return fc(),fd() end
    local df=CS.System.Reflection.BindingFlags.Default
    return (fc and fc() or mc:Invoke(nil,df,nil,nativeSourceEmpty,nil)),
        (fd and fd() or md:Invoke(nil,df,nil,nativeSourceEmpty,nil))
end
function NativeSourceInput.VisualSpeed(input)
    local ms,fs=input._m_speed,input._f_speed
    if not ms then ms,fs=resolveCallable(input.layer,'get_SpeedScale',false,input,'_c_speed');input._m_speed=ms;input._f_speed=fs end
    local raw=fs and fs() or ms:Invoke(input.layer,CS.System.Reflection.BindingFlags.Default,nil,nativeSourceEmpty,nil)
    if raw==input._raw_speed and input._f_speed_val then return input._f_speed_val end
    local speed=scale3float(raw)
    assert(speed>0 and speed<math.huge,'Original native visual speed is invalid')
    input._raw_speed=raw;input._f_speed_val=speed
    return speed
end
NativeSourceInput.Get=sourcePublic
