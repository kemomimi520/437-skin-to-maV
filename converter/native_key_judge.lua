-- Research adapter: Free supplies custom drawing but its default judge does
-- not implement Key judgement. Bind the shipped Key judge after ChartPlayer
-- loads the chart. No scores, hit results, input times or timing windows are
-- synthesized. This version-specific binding remains an opt-in candidate.
local NativeKeyJudge={}
function NativeKeyJudge.Bind()
    local players=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.Malody.Play.ChartPlayer))
    assert(players.Length==1,'Ma Skin Bridge: expected one native ChartPlayer')
    local player=players[0]
    local member=player:GetType():GetField('judgeLogic',36)
    assert(member and member.FieldType==typeof(CS.Malody.Play.JudgeLogicBase),
        'Ma Skin Bridge: unsupported native judge binding')
    local previous=member:GetValue(player)
    assert(previous and previous:GetType()==typeof(CS.Malody.Play.JudgeLogicFree),
        'Ma Skin Bridge: unexpected original Free judge')
    local replacement=player.gameObject:AddComponent(typeof(CS.Malody.Play.JudgeLogicKey))
    replacement.maxJudgeRepeatCount=previous.maxJudgeRepeatCount
    -- ScenePlay loads ChartPlayer before invoking the skin's Init callback.
    -- A fresh judge otherwise reports an empty queue as finished immediately.
    local info=publicGetter(player,'get_SourcePlayInfo')
    local processor=publicGetter(player,'get_Processor')
    assert(info and processor,'Ma Skin Bridge: native chart not loaded before skin Init')
    replacement:OnLoadChart(info,processor)
    local recorder=publicGetter(previous,'get_Recorder')
    local members=replacement:GetType():GetProperties(20)
    for i=0,members.Length-1 do
        local setter=members[i]:GetSetMethod()
        if setter and setter.Name=='set_Recorder' then
            local values=CS.System.Array.CreateInstance(typeof(CS.System.Object),1);values[0]=recorder
            setter:Invoke(replacement,CS.System.Reflection.BindingFlags.Default,nil,values,nil)
        end
    end
    member:SetValue(player,replacement)
    previous.enabled=false
    assert(member:GetValue(player)==replacement,'Ma Skin Bridge: native Key judge not bound')
    if publicGetter(info,'get_IsAuto') then
        -- ChartPlayer can finish installing Free.Auto before an asynchronous
        -- skin Init runs (observed on Android). Replacing judgeLogic alone
        -- leaves touch-based Free control driving the indexed Key judge.
        -- Use the original controller setter: it detaches the previous
        -- controller and attaches/resets the Key judge's own Auto instance.
        -- No hit callbacks, input times, scores or per-frame inputs are made.
        NativeBindings.Select(publicGetter(player,'get_LoadedChart'))
        local auto=assert(publicGetter(replacement,'get_AutoPlayController'),
            'Ma Skin Bridge: native Key Auto controller missing')
        local methods=player:GetType():GetMethods(36)
        local getter,setter
        for i=0,methods.Length-1 do
            local method=methods[i]
            if method.Name==NativeBindings.Name('cno') then getter=method
            elseif method.Name==NativeBindings.Name('cnp') then setter=method end
        end
        assert(getter and setter and setter:GetParameters().Length==1 and
            setter:GetParameters()[0].ParameterType:IsAssignableFrom(auto:GetType()),
            'Ma Skin Bridge: unsupported native Auto controller binding')
        local flags=CS.System.Reflection.BindingFlags.Default
        local empty=CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
        if getter:Invoke(player,flags,nil,empty,nil)~=auto then
            local values=CS.System.Array.CreateInstance(typeof(CS.System.Object),1);values[0]=auto
            setter:Invoke(player,flags,nil,values,nil)
        end
        assert(getter:Invoke(player,flags,nil,empty,nil)==auto,
            'Ma Skin Bridge: native Key Auto controller was not installed')
    end
end
