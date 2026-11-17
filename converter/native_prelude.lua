-- Research candidate: use the shipped player's public rewind transition.
-- The real native clock/audio/judge advance; no replacement clock is installed.
local LegacyPrelude={}
function LegacyPrelude.NeedsStartCorrection(first,start,playing,normal,range)
    return first~=nil and first>=0 and start>0 and not playing and normal and not range
end
function LegacyPrelude.Bind(driver)
    local state={ready=false,active=false,attempts=0,bound_clock=driver.clock()}
    function state:Reset()
        if self.active then driver.setCurve(self.originalCurve) end
        self.ready=false;self.active=false
    end
    function state:Update(time)
        if not self.ready and driver.isPlaying() and not driver.isRewinding() then
            local start=driver.clock()
            self.ready=true;self.attempts=self.attempts+1;self.start=start
            -- Native -2000 starts already cover the source interval. Practice
            -- or late starts still need separate old-engine lifecycle evidence.
            if start>-2000 and start<=0 then
                self.originalCurve=driver.getCurve();self.active=true
                driver.setCurve(driver.linear(0,-2000-start,2000+start,0))
                driver.pause();driver.resume()
                return -2000
            end
        end
        if self.active and driver.isPlaying() and not driver.isRewinding() then
            driver.setCurve(self.originalCurve);self.active=false
        end
        return self.ready and time or -2000
    end
    return state
end
function UnityBridge.PreparePrelude(sourceTimes)
    local parent=Note:GetGroup('legacy_clock').transform;local player
    while parent and not player do
        player=parent.gameObject:GetComponent(typeof(CS.Malody.Play.ChartPlayer));parent=parent.parent
    end
    assert(player,'Ma Skin Bridge: native prelude ChartPlayer missing')
    local properties=player:GetType():GetProperties(20);local getters={};local setStart
    for i=0,properties.Length-1 do
        local property=properties[i];local getter=property:GetGetMethod()
        if getter then getters[getter.Name]=property end
        local setter=property:GetSetMethod()
        if setter and setter.Name=='set_TimeStart' then setStart=setter end
    end
    local clock
    local clocks=NativeBindings.ClockType():GetProperties(24)
    for i=0,clocks.Length-1 do
        local getter=clocks[i]:GetGetMethod()
        if getter and getter.Name=='get_ChartTime' then clock=clocks[i] end
    end
    assert(clock and getters.get_IsPlaying and getters.get_IsResumeRewinding,'Ma Skin Bridge: public prelude clock properties missing')
    local first
    for _,note in pairs(sourceTimes or {}) do first=first and math.min(first,note.time) or note.time end
    local before=CS.System.Convert.ToDouble(clock:GetValue(nil,nil))
    local corrected=false
    if first and first>=0 and before>0 and not getters.get_IsPlaying:GetValue(player,nil) then
        local info=publicGetter(player,'get_SourcePlayInfo');local kind=info:GetType()
        local from=kind:GetField(NativeBindings.Name('bcgf'),20)
        local begin=kind:GetField(NativeBindings.Name('bcgj'),20);local finish=kind:GetField(NativeBindings.Name('bcgk'),20)
        assert(from and begin and finish and from.IsPublic and begin.IsPublic and finish.IsPublic,
            'Ma Skin Bridge: public prelude range context missing')
        local normal=CS.System.Convert.ToInt32(from:GetValue(info))==0
        local range=begin:GetValue(info)~=nil or finish:GetValue(info)~=nil
        if LegacyPrelude.NeedsStartCorrection(first,before,false,normal,range) then
            assert(setStart,'Ma Skin Bridge: public TimeStart setter missing')
            local values=CS.System.Array.CreateInstance(typeof(CS.System.Object),1);values[0]=0
            -- Load already finished; Play has not started. Use its public
            -- start configuration, not a seek or a replacement clock.
            setStart:Invoke(player,CS.System.Reflection.BindingFlags.Default,nil,values,nil)
            corrected=true
        end
    end
    local state=LegacyPrelude.Bind({
        clock=function() return CS.System.Convert.ToDouble(clock:GetValue(nil,nil)) end,
        isPlaying=function() return getters.get_IsPlaying:GetValue(player,nil) end,
        isRewinding=function() return getters.get_IsResumeRewinding:GetValue(player,nil) end,
        getCurve=function() return player.timeCurveResumeRewind end,
        setCurve=function(value) player.timeCurveResumeRewind=value end,
        linear=function(...) return CS.UnityEngine.AnimationCurve.Linear(...) end,
        pause=function() player:Pause() end,resume=function() player:Resume(false) end})
    state.normal_start_corrected=corrected;state.source_first_time=first
    return state
end
