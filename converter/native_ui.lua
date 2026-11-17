-- Ordinary Key UI only. The game owns chart parsing, note motion, input,
-- judgement, score, replay and submission. No Free API or note callback.
local active={}
local nativeChartPlayer
local nativeIsPlayingGetter
local function liveChartPlaying()
    if not nativeChartPlayer then
        nativeIsPlayingGetter=nil
        local ok,players=pcall(function()
            if xlua and xlua.load_assembly then
                pcall(xlua.load_assembly,'UnityEngine.CoreModule')
                pcall(xlua.load_assembly,'Assembly-CSharp')
            end
            local U=CS and CS.UnityEngine
            local CP=CS and CS.Malody and CS.Malody.Play and CS.Malody.Play.ChartPlayer
            if U and U.Object and CP and typeof(CP)~=nil then
                return U.Object.FindObjectsOfType(typeof(CP),false)
            end
            return nil
        end)
        if ok and players and players.Length and players.Length>0 then
            nativeChartPlayer=players[0]
        else
            return nil
        end
    end
    if not nativeIsPlayingGetter then
        -- xLua C# proxies raise errors when indexing obfuscated/absent members,
        -- so probe each getter strategy in an isolated pcall.
        local ok1,val1=pcall(function() return nativeChartPlayer.IsPlaying end)
        if ok1 and type(val1)=='boolean' then
            nativeIsPlayingGetter=function(p) return p.IsPlaying end
            return val1
        end
        local ok2,val2=pcall(function() return nativeChartPlayer:get_IsPlaying() end)
        if ok2 and type(val2)=='boolean' then
            nativeIsPlayingGetter=function(p) return p:get_IsPlaying() end
            return val2
        end
        local ok3,val3=pcall(function()
            local props=nativeChartPlayer:GetType():GetProperties(20)
            for i=0,props.Length-1 do
                local m=props[i]:GetGetMethod()
                if m and m.Name=='get_IsPlaying' then
                    local prop=props[i]
                    nativeIsPlayingGetter=function(p) return prop:GetValue(p,nil) end
                    return prop:GetValue(nativeChartPlayer,nil)
                end
            end
            return nil
        end)
        if ok3 and type(val3)=='boolean' then return val3 end
        nativeChartPlayer=nil
        nativeIsPlayingGetter=nil
        return nil
    end
    local ok,playing=pcall(nativeIsPlayingGetter,nativeChartPlayer)
    if ok and type(playing)=='boolean' then return playing end
    nativeChartPlayer=nil
    nativeIsPlayingGetter=nil
    return nil
end
local nativeScriptRuntime
local nativePhaseGetter
local function liveSceneLoaded()
    if not nativeScriptRuntime then
        nativePhaseGetter=nil
        local ok,inst=pcall(function()
            if xlua and xlua.load_assembly then
                pcall(xlua.load_assembly,'Assembly-CSharp')
                pcall(xlua.load_assembly,'UnityEngine.CoreModule')
            end
            local U=CS and CS.UnityEngine
            local SR=CS and CS.Malody and CS.Malody.Scene and CS.Malody.Scene.Play and CS.Malody.Scene.Play.Skin and CS.Malody.Scene.Play.Skin.SkinScriptRuntime
            if U and U.Object and SR and typeof(SR)~=nil then
                local runtimes=U.Object.FindObjectsOfType(typeof(SR),true)
                if runtimes and runtimes.Length and runtimes.Length>0 then
                    for i=0,runtimes.Length-1 do
                        if runtimes[i].gameObject.activeInHierarchy then return runtimes[i] end
                    end
                    return runtimes[0]
                end
            end
            return nil
        end)
        if ok and inst then
            nativeScriptRuntime=inst
        else
            return nil
        end
    end
    if not nativePhaseGetter then
        local ok1,v1=pcall(function() return nativeScriptRuntime:get_Phase() end)
        if ok1 and v1~=nil then
            nativePhaseGetter=function(r) return CS.System.Convert.ToInt32(r:get_Phase())>=2 end
            return CS.System.Convert.ToInt32(v1)>=2
        end
        local ok2,v2=pcall(function() return nativeScriptRuntime.Phase end)
        if ok2 and v2~=nil then
            nativePhaseGetter=function(r) return CS.System.Convert.ToInt32(r.Phase)>=2 end
            return CS.System.Convert.ToInt32(v2)>=2
        end
        local ok3,v3=pcall(function()
            local props=nativeScriptRuntime:GetType():GetProperties(20)
            for i=0,props.Length-1 do
                local m=props[i]:GetGetMethod()
                if m and m.Name=='get_Phase' then
                    local prop=props[i]
                    nativePhaseGetter=function(r) return CS.System.Convert.ToInt32(prop:GetValue(r,nil))>=2 end
                    return CS.System.Convert.ToInt32(prop:GetValue(nativeScriptRuntime,nil))>=2
                end
            end
            return nil
        end)
        if ok3 and type(v3)=='boolean' then return v3 end
        nativeScriptRuntime=nil
        nativePhaseGetter=nil
        return nil
    end
    local ok,loaded=pcall(nativePhaseGetter,nativeScriptRuntime)
    if ok and type(loaded)=='boolean' then return loaded end
    nativeScriptRuntime=nil
    nativePhaseGetter=nil
    return nil
end
local function liveScreenAspect()
    if Game and Game.Width and Game.Height then
        local gw,gh=Game:Width(),Game:Height()
        if type(gw)=='number' and type(gh)=='number' and gh>0 then return gw/gh end
    end
    local S=CS and CS.UnityEngine and CS.UnityEngine.Screen
    if S then
        local sw,sh=S.width,S.height
        if type(sw)=='number' and type(sh)=='number' and sh>0 then return sw/sh end
    end
    return nil
end
local function evalAffineX(aff,aspect)
    return aff[1]*aspect+aff[2]
end
local function findNativeModule(name)
    -- Malody.Scene.Play.Skin.bet.Find returns SkinRuntimeDummy instead of nil
    -- when SkinRuntime.throwError is false (normal gameplay outside probes).
    local module=Module:Find(name)
    if not module then return nil end
    local tp=module.GetType and module:GetType()
    if tp and tp.FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeDummy' then return nil end
    return module
end
local function nativePrepareRuntimeData(data)
    for _,config in ipairs(data.configs or {}) do
        if config.branch_config and findNativeModule(config.marker) then
            for k,v in pairs(config.branch_config) do data[k]=v end
            break
        end
    end
    local aspect=liveScreenAspect()
    if not aspect then return end
    if data.source_visual_pool then
        local pool=data.source_visual_pool
        if pool.motion and pool.motion.legacy_play_plane and pool.motion.legacy_play_plane.source_projection then
            local p=pool.motion.legacy_play_plane.source_projection
            p[1]=p[6]/aspect
        end
        if pool.x_affine then
            local xa=pool.x_affine
            local centers={}
            for i,c in ipairs(xa.lane_centers_x) do centers[i]=evalAffineX(c,aspect) end
            local keys=xa.keys
            local spacing=keys>1 and ((centers[keys]-centers[1])/(keys-1)) or math.max(evalAffineX(xa.note1_size_x,aspect),100)
            local width=spacing*keys
            local live_scale=width/(720*14/9)
            local field_offset_x=(centers[1]+centers[keys])*.5-aspect*360
            pool.field_offset_x=field_offset_x*1.5/live_scale
            xa.live_scale=live_scale
            xa.live_judge=math.floor(xa.judge_line_720*1.5/live_scale-160+0.5)
        end
    end
    for _,recipe in ipairs(data.scale3_recipes or {}) do
        local rx=recipe.x_affine
        if rx then
            if recipe.factory=='scale3' then
                local w=evalAffineX(rx.size_x,aspect)
                if data.source_visual_pool and data.source_visual_pool.x_affine and data.source_visual_pool.x_affine.lane_centers_x then
                    local xa=data.source_visual_pool.x_affine;local c={}
                    for i,p in ipairs(xa.lane_centers_x) do c[i]=evalAffineX(p,aspect) end
                    recipe.lane_width_720=xa.keys>1 and ((c[xa.keys]-c[1])/(xa.keys-1)) or math.max(w,100)
                end
                if recipe.layout and recipe.layout.size then recipe.layout.size[1]=w end
            else
                local sx=evalAffineX(rx.start_x,aspect);local ex=evalAffineX(rx.end_x,aspect)
                local w=evalAffineX(rx.size_x,aspect)
                local final_w=rx.size2_x and evalAffineX(rx.size2_x,aspect) or w
                recipe.start_x=sx;recipe.end_x=ex
                if data.source_visual_pool and data.source_visual_pool.x_affine then
                    local xa=data.source_visual_pool.x_affine;local c={}
                    for i,p in ipairs(xa.lane_centers_x) do c[i]=evalAffineX(p,aspect) end
                    recipe.lane_width_720=xa.keys>1 and ((c[xa.keys]-c[1])/(xa.keys-1)) or math.max(w,100)
                end
                recipe.tap_head_size[1]=w;if rx.size_auto_h then recipe.tap_head_size[2]=w*rx.tap_aspect end
                recipe.head_size[1]=w;if rx.size_auto_h then recipe.head_size[2]=w*rx.head_aspect end
                local width_end=(rx.size2_x and final_w>0 and math.abs(final_w-w)>=0.0001) and final_w or w
                recipe.tail_size[1]=width_end;if rx.size_auto_h then recipe.tail_size[2]=width_end*rx.tail_aspect end
                if recipe.legacy_size_end then recipe.legacy_size_end[1]=w end
                if recipe.legacy_size_start then recipe.legacy_size_start[1]=final_w end
                recipe.tile_width=rx.size2_x and final_w or w
            end
        end
    end
    if data.source_bar and data.source_bar.x_affine then
        local bx=data.source_bar.x_affine;local b=data.source_bar
        b.start[1]=evalAffineX(bx.start,aspect)
        b.finish[1]=evalAffineX(bx.finish,aspect)
        local w=evalAffineX(bx.size,aspect);b.size[1]=w
        if bx.auto_h then b.size[2]=w*bx.aspect end
        if bx.end_size and b.end_size then
            local w2=evalAffineX(bx.end_size,aspect);b.end_size[1]=w2
            if bx.auto_h then b.end_size[2]=w2*bx.aspect end
        end
    end
end
if DATA.source_visual_pool then
    -- Original SkinScriptRuntime.OnStart(true) invokes its OWN OnRetry
    -- action. Init is not repeated on retry. Do not infer a new attempt from
    -- a backwards clock adjustment, or keep carriers from the previous load.
    function OnRetry()
        if NativeSourcePlaneUI then NativeSourcePlaneUI.Reset() end
        if NativeSourceBars then NativeSourceBars.Reset() end
        if NativeUiFrames then NativeUiFrames.Reset() end
        if NativeUiEvents then NativeUiEvents.Reset() end
        if NativeUiJudge then NativeUiJudge.Reset() end
        if NativeUiMotion then NativeUiMotion.Reset() end
        if NativeUiMeter then NativeUiMeter.Reset() end
        if NativeUiNumber then NativeUiNumber._dirty=10 end
        nativePrepareRuntimeData(DATA)
        initScale3Admission(DATA)
        initNoteAdmission(DATA)
        initNativeSourcePool(DATA)
        if syncHitsoundVolume then syncHitsoundVolume(true) end
    end
end
if DATA.scale3_recipes or DATA.hold_policy or DATA.hold_policies or NativeUiEvents or NativeUiJudge or #(DATA.hitsounds or {})>0 then
    function OnHit()
        if syncHitsoundVolume then syncHitsoundVolume(false) end
        if NATIVE_FRAME_DRIVER then NATIVE_FRAME_DRIVER.hits=NATIVE_FRAME_DRIVER.hits+1 end
        if NativeUiNumber then NativeUiNumber._dirty=4 end
        local event=Game:HitEvent()
        if NativeUiEvents then NativeUiEvents.Hit(event) end
        if NativeUiJudge then NativeUiJudge.Hit(event) end
        if DATA.source_visual_pool then nativeSourcePoolHit()
        else
            if holdVisualHit then holdVisualHit() end
            if scale3VisualHit then scale3VisualHit() end
        end
    end
end
local syncIdleDefaultCover,resetIdleCoverState
do
local idleCoverState={checked=false,targets=nil,track=nil,lastActive=nil}
function resetIdleCoverState()
    idleCoverState={checked=false,hidden=false,targets=nil,track=nil,lastActive=nil}
end
local function readTrackProp(track,prop,getter)
    local ok,val=pcall(function() return track[prop] end)
    if ok and val~=nil then return true,val end
    return pcall(function() return track[getter](track) end)
end
local function collectRenderComps(go,kinds,out)
    local seen={}
    local function visit(tr)
        if not tr then return end
        local g=tr.gameObject
        if g then
            for _,k in ipairs(kinds) do
                local ok,comp=pcall(function() return g:GetComponent(typeof(k)) end)
                if ok and comp and not (comp.Equals and comp:Equals(nil)) and not seen[comp] then
                    seen[comp]=true
                    out[#out+1]={comp=comp,enabled=comp.enabled}
                end
            end
        end
        for i=0,tr.childCount-1 do visit(tr:GetChild(i)) end
    end
    visit(go.transform)
end
function syncIdleDefaultCover()
    if not (CS and CS.UnityEngine and CS.UnityEngine.Object and CS.Malody and CS.Malody.Scene and CS.Malody.Scene.Play) then return end
    local U=CS.UnityEngine
    local W=CS.Malody.Scene.Play.Widget and CS.Malody.Scene.Play.Widget.WidgetKeyTrack3D
    if not (W and typeof(W)~=nil) then return end
    local track=idleCoverState.track
    if not track or (track.Equals and track:Equals(nil)) then
        local ok,found=pcall(function() return U.Object.FindObjectOfType(typeof(W)) end)
        if not ok or not found then return end
        track=found;idleCoverState.track=track
    end
    local okHas,hasCover=readTrackProp(track,'HasCover','get_HasCover')
    local okRatio,ratio=readTrackProp(track,'CoverRatio','get_CoverRatio')
    if not okHas or not okRatio then return end
    local coverActive=hasCover and ratio<0.999
    if idleCoverState.checked and idleCoverState.lastActive==coverActive then return end
    idleCoverState.lastActive=coverActive
    if not idleCoverState.targets or #idleCoverState.targets==0 then
        if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UI') end
        local kinds={}
        if U.Renderer and typeof(U.Renderer)~=nil then kinds[#kinds+1]=U.Renderer end
        if U.UI and U.UI.Graphic and typeof(U.UI.Graphic)~=nil then kinds[#kinds+1]=U.UI.Graphic end
        local list={}
        local D=CS.Malody.Scene.Play.Skin and CS.Malody.Scene.Play.Skin.SkinRuntimeDef
        if D and typeof(D)~=nil and #kinds>0 then
            local okDefs,defs=pcall(function() return U.Object.FindObjectsOfType(typeof(D),true) end)
            if okDefs and defs then
                for i=0,defs.Length-1 do
                    local def=defs[i]
                    local okType,kind=pcall(function() return CS.System.Convert.ToInt32(def.type) end)
                    if okType and kind==15 and def.gameObject then
                        local comps={}
                        collectRenderComps(def.gameObject,kinds,comps)
                        if #comps>0 then list[#list+1]={go=def.gameObject,comps=comps} end
                    end
                end
            end
        end
        if #kinds>0 then
            pcall(function()
                local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic')
                local f=track:GetType():GetField('transformsAsCover',flags)
                local arr=f and f:GetValue(track)
                if arr then
                    for i=0,arr.Length-1 do
                        local tr=arr[i]
                        if tr and tr.gameObject then
                            local comps={}
                            collectRenderComps(tr.gameObject,kinds,comps)
                            if #comps>0 then list[#list+1]={go=tr.gameObject,comps=comps} end
                        end
                    end
                end
            end)
        end
        idleCoverState.targets=list
    end
    if #idleCoverState.targets==0 then return end
    idleCoverState.checked=true
    local show=coverActive
    for _,item in ipairs(idleCoverState.targets) do
        for _,entry in ipairs(item.comps) do
            if entry.comp and not (entry.comp.Equals and entry.comp:Equals(nil)) then
                entry.comp.enabled=show and entry.enabled or false
            end
        end
    end
end
end
local syncHitsoundVolume,resetHitsoundState
do
local hitsoundState={reflReady=false,reflFailed=false,cfgTried=false,cfgProvider=nil,cfgBool=nil,cfgInt=nil,
    ks=nil,ksType=nil,ksZjt=nil,ksZea=nil,srsType=nil,srsYvm=nil,srmEhr=nil,cdmSetVol=nil,cdmVsk=nil,
    targets=nil,lastScale=nil,checkTick=0}
function resetHitsoundState()
    hitsoundState={reflReady=false,reflFailed=false,cfgTried=false,cfgProvider=nil,cfgBool=nil,cfgInt=nil,
        ks=nil,ksType=nil,ksZjt=nil,ksZea=nil,srsType=nil,srsYvm=nil,srmEhr=nil,cdmSetVol=nil,cdmVsk=nil,
        targets=nil,lastScale=nil,checkTick=0}
end
local function isAliveUnityObj(obj)
    return obj~=nil and not (obj.Equals and obj:Equals(nil))
end
local function ensureHitsoundReflection()
    if hitsoundState.reflReady then return true end
    if hitsoundState.reflFailed then return false end
    local ok=pcall(function()
        if xlua and xlua.load_assembly then
            pcall(xlua.load_assembly,'Assembly-CSharp')
            pcall(xlua.load_assembly,'UnityEngine.CoreModule')
        end
        local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic')
        local SRS=CS.Malody.Scene.Play.Skin.Module.SkinRuntimeSound
        local SRM=CS.Malody.Scene.Play.Skin.Module.SkinRuntimeModule
        assert(SRS and typeof(SRS)~=nil and SRM and typeof(SRM)~=nil)
        hitsoundState.srsType=SRS
        hitsoundState.srsYvm=typeof(SRS):GetField('yvm',flags)
        hitsoundState.srmEhr=typeof(SRM):GetField('ehr',flags)
        local CDM=(hitsoundState.srsYvm and hitsoundState.srsYvm.FieldType) or (CS.Malody.Audio and typeof(CS.Malody.Audio.cdm))
        if CDM then
            hitsoundState.cdmSetVol=CDM:GetMethod('set_Volume')
            hitsoundState.cdmVsk=CDM:GetField('vsk',flags)
        end
        local KS=CS.Malody.Play and CS.Malody.Play.Sound and CS.Malody.Play.Sound.KeySoundBase
        if KS and typeof(KS)~=nil then
            hitsoundState.ksType=KS
            hitsoundState.ksZjt=typeof(KS):GetField('zjt',flags)
            hitsoundState.ksZea=typeof(KS):GetField('zea',flags)
        end
        local KSP=CS.Malody.Play and CS.Malody.Play.Sound and CS.Malody.Play.Sound.KeySoundPlayer
        if KSP and typeof(KSP)~=nil then
            hitsoundState.kspZvs=typeof(KSP):GetField('zvs',flags)
        end
    end)
    if ok and hitsoundState.srsYvm and (hitsoundState.cdmSetVol or hitsoundState.cdmVsk) then
        hitsoundState.reflReady=true
        return true
    end
    hitsoundState.reflFailed=true
    return false
end
local function setupHitsoundConfigReader(parentTransform)
    if hitsoundState.cfgTried then return isAliveUnityObj(hitsoundState.cfgProvider) end
    hitsoundState.cfgTried=true
    local ok,provider,mBool,mInt=pcall(function()
        local U=CS.UnityEngine
        local CVP=CS.Malody and CS.Malody.UI and CS.Malody.UI.ConfigValueProvider
        if not (U and CVP and typeof(CVP)~=nil) then return nil end
        local generic=typeof(CVP):GetMethod('GetValue')
        if not generic then return nil end
        local bArr=CS.System.Array.CreateInstance(typeof(CS.System.Type),1)
        bArr[0]=typeof(CS.System.Boolean)
        local iArr=CS.System.Array.CreateInstance(typeof(CS.System.Type),1)
        iArr[0]=typeof(CS.System.Int32)
        local mb=generic:MakeGenericMethod(bArr)
        local mi=generic:MakeGenericMethod(iArr)
        if not (mb and mi) then return nil end
        local go=U.GameObject('NativeHitsoundConfig')
        if parentTransform then go.transform:SetParent(parentTransform,false) end
        local comp=go:AddComponent(typeof(CVP))
        comp.perMode=false
        return comp,mb,mi
    end)
    if ok and provider and mBool and mInt then
        hitsoundState.cfgProvider=provider
        hitsoundState.cfgBool=mBool
        hitsoundState.cfgInt=mInt
        return true
    end
    return false
end
local function unboxBool(val)
    if type(val)=='boolean' then return val end
    if val~=nil and CS.System and CS.System.Convert and CS.System.Convert.ToBoolean then
        local ok,b=pcall(CS.System.Convert.ToBoolean,val)
        if ok and type(b)=='boolean' then return b end
    end
    return nil
end
local function unboxNum(val)
    if type(val)=='number' then return val end
    if val~=nil and CS.System and CS.System.Convert and CS.System.Convert.ToDouble then
        local ok,n=pcall(CS.System.Convert.ToDouble,val)
        if ok and type(n)=='number' then return n end
    end
    return nil
end
local function readHitsoundScale()
    if isAliveUnityObj(hitsoundState.cfgProvider) and hitsoundState.cfgBool and hitsoundState.cfgInt then
        local ok,val=pcall(function()
            local p=hitsoundState.cfgProvider
            p.perMode=false
            p.configKey='key_sound'
            local enabled=unboxBool(hitsoundState.cfgBool:Invoke(p,nil))
            if enabled==false then return 0 end
            p.configKey='skip_keysound'
            local skip=unboxBool(hitsoundState.cfgBool:Invoke(p,nil))
            if skip==true then return 0 end
            p.configKey='hit_volume'
            local hv=unboxNum(hitsoundState.cfgInt:Invoke(p,nil))
            if enabled==true and type(hv)=='number' then return math.max(0,math.min(1,hv/100)) end
            return nil
        end)
        if ok and type(val)=='number' then return val end
    end
    if hitsoundState.ksType and typeof(hitsoundState.ksType)~=nil and hitsoundState.ksZjt then
        local ks=hitsoundState.ks
        if not isAliveUnityObj(ks) then
            local okFind,found=pcall(function()
                return CS.UnityEngine.Object.FindObjectOfType(typeof(hitsoundState.ksType))
            end)
            if okFind and isAliveUnityObj(found) then
                ks=found;hitsoundState.ks=ks
            else
                ks=nil;hitsoundState.ks=nil
            end
        end
        if ks then
            local okKs,val=pcall(function()
                local active=unboxBool(hitsoundState.ksZjt:GetValue(ks))
                if active==false then return 0 end
                if active==true then
                    if hitsoundState.ksZea then
                        local zea=hitsoundState.ksZea:GetValue(ks)
                        if isAliveUnityObj(zea) then
                            local v=nil
                            if hitsoundState.cdmVsk then v=unboxNum(hitsoundState.cdmVsk:GetValue(zea)) end
                            if type(v)~='number' and zea.get_Volume then v=unboxNum(zea:get_Volume()) end
                            if type(v)=='number' then return math.max(0,math.min(1,v)) end
                        end
                    end
                    if hitsoundState.kspZvs then
                        local zvs=unboxNum(hitsoundState.kspZvs:GetValue(ks))
                        if type(zvs)=='number' then return math.max(0,math.min(1,zvs)) end
                    end
                    return 1
                end
                return nil
            end)
            if okKs and type(val)=='number' then return val end
        end
    end
    return nil
end
local function applyCdmVolume(inst,vol)
    if not isAliveUnityObj(inst) then return end
    local ok,yvm=pcall(function() return hitsoundState.srsYvm:GetValue(inst) end)
    if not (ok and yvm~=nil) then return end
    local okDirect=pcall(function()
        assert(type(yvm)=='userdata')
        if yvm.set_Volume then yvm:set_Volume(vol) else yvm.Volume=vol end
    end)
    if okDirect then return end
    pcall(function()
        local fval=CS.System.Convert and CS.System.Convert.ToSingle and CS.System.Convert.ToSingle(vol) or vol
        if hitsoundState.cdmSetVol then
            local args=CS.System.Array.CreateInstance(typeof(CS.System.Object),1)
            args[0]=fval
            hitsoundState.cdmSetVol:Invoke(yvm,args)
        end
        if hitsoundState.cdmVsk then
            hitsoundState.cdmVsk:SetValue(yvm,fval)
        end
    end)
end
function syncHitsoundVolume(force)
    local rows=DATA.hitsounds
    if not (rows and #rows>0) then return end
    if not (CS and CS.UnityEngine and CS.UnityEngine.Object and CS.Malody) then return end
    if not ensureHitsoundReflection() then return end
    if not hitsoundState.targets then
        local list={}
        for _,row in ipairs(rows) do
            local mod=findNativeModule(row.handle)
            if mod then
                list[#list+1]={mod=mod,base=(row.volume or 100)/100,cloneCount=-1}
            end
        end
        hitsoundState.targets=list
        if #list>0 and not hitsoundState.cfgTried then
            setupHitsoundConfigReader(list[1].mod.transform)
        end
    end
    if not hitsoundState.targets or #hitsoundState.targets==0 then return end
    if not force and hitsoundState.lastScale~=nil then
        hitsoundState.checkTick=(hitsoundState.checkTick or 0)-1
        if hitsoundState.checkTick>0 then
            if hitsoundState.srmEhr then
                for _,target in ipairs(hitsoundState.targets) do
                    local okPool,pool=pcall(function() return hitsoundState.srmEhr:GetValue(target.mod) end)
                    if okPool and pool and pool.Count and pool.Count~=target.cloneCount then
                        local vol=hitsoundState.lastScale*target.base
                        applyCdmVolume(target.mod,vol)
                        for i=0,pool.Count-1 do applyCdmVolume(pool[i],vol) end
                        target.cloneCount=pool.Count
                    end
                end
            end
            return
        end
    end
    hitsoundState.checkTick=10
    local scale=readHitsoundScale()
    if type(scale)~='number' then return end
    local scaleChanged=hitsoundState.lastScale==nil or math.abs(scale-hitsoundState.lastScale)>1e-4
    for _,target in ipairs(hitsoundState.targets) do
        local vol=scale*target.base
        local pool,count=nil,0
        if hitsoundState.srmEhr then
            local okPool,p=pcall(function() return hitsoundState.srmEhr:GetValue(target.mod) end)
            if okPool and p and p.Count then pool=p;count=p.Count end
        end
        if scaleChanged or count~=target.cloneCount then
            applyCdmVolume(target.mod,vol)
            if pool then
                for i=0,count-1 do applyCdmVolume(pool[i],vol) end
            end
            target.cloneCount=count
        end
    end
    hitsoundState.lastScale=scale
end
end
local function updateAppearance()
    syncIdleDefaultCover()
    syncHitsoundVolume(false)
    if DATA.admission_policy then
        if beginNativeFrame then beginNativeFrame() end
        if updateNativeSourcePool then updateNativeSourcePool() end
        if NativeSourceBars then NativeSourceBars.Update(nativeSourceVisualContext(),DATA.source_bar,DATA.suppress_native_bar) end
        updateNoteAdmission()
        if updateScale3SourceWindow then updateScale3SourceWindow() end
    elseif DATA.suppress_native_bar and NativeSourceBars then
        NativeSourceBars.Update(nil,nil,true)
    end
    if NativeUiMotion and not NativeUiMotion._all_done then
        if NativeUiMotion._actions_done then
            if NativeUiMotion.SyncSkews then NativeUiMotion.SyncSkews() end
        else
            NativeUiMotion.Update(Game:Time(),Game.SystemTime and Game:SystemTime() or nil,liveChartPlaying(),liveSceneLoaded())
        end
    end
    if NativeUiFrames then NativeUiFrames.Update() end
    if NativeUiEvents then NativeUiEvents.Update() end
    if NativeUiJudge then NativeUiJudge.Update() end
    if NativeUiNumber then NativeUiNumber.Update() end
    if NativeUiText then NativeUiText.Update() end
    if NativeUiMeter then NativeUiMeter.Update() end
    if NativeUiStrip then NativeUiStrip.Update() end
    if NativeUiProjection then NativeUiProjection.Update() end
    if NativeSourcePlaneUI then NativeSourcePlaneUI.Update(nativeSourceVisualContext()) end
end
if DATA.native_frame_driver then
    function OnVarChange() updateAppearance() end
elseif DATA.admission_policy or DATA.scale3_recipes or #(DATA.entries or {})>0 or #(DATA.hitsounds or {})>0 then
    -- Hold-policy-only adapters are event driven through OnHit/OnInput. Do
    -- not expose an otherwise empty per-frame callback for those skins; the
    -- original Key runtime remains the sole owner of note movement.
    function Update() updateAppearance() end
end
function Init()
    active={}
    resetIdleCoverState()
    resetHitsoundState()
    nativeChartPlayer=nil;nativeIsPlayingGetter=nil
    nativeScriptRuntime=nil;nativePhaseGetter=nil
    nativePrepareRuntimeData(DATA)
    if NativeSourceBars then NativeSourceBars.Reset() end
    if NativeUiMotion then if NativeUiMotion.Clear then NativeUiMotion.Clear() else NativeUiMotion.items={};NativeUiMotion._all_done=false end end
    if NativeUiFrames then NativeUiFrames.items={};NativeUiFrames.last_frame=nil end
    if NativeUiEvents then NativeUiEvents.items={};NativeUiEvents.pressed={};NativeUiEvents.last_frame=nil end
    if NativeUiNumber then NativeUiNumber.items={};NativeUiNumber.by_handle={};NativeUiNumber._dirty=10 end
    if NativeUiJudge then NativeUiJudge.items={} end
    if NativeUiText then NativeUiText.items={} end
    if NativeUiMeter then NativeUiMeter.items={} end
    if NativeUiStrip then NativeUiStrip.items={} end
    if NativeUiProjection then NativeUiProjection.items={} end
    if NativeSourcePlaneUI then NativeSourcePlaneUI.Clear() end
    syncIdleDefaultCover()
    syncHitsoundVolume(true)
    if initHoldVisual then initHoldVisual(DATA) end
    if initNoteAdmission then initNoteAdmission(DATA) end
    if initNativeSourcePool then initNativeSourcePool(DATA) end
    if initNativeFrameDriver then initNativeFrameDriver(DATA) end
    for _,config in ipairs(DATA.configs or {}) do
        if findNativeModule(config.marker) then
            Game:SetFieldMeta('Scale',config.scale)
            Game:SetFieldMeta('Judge',config.judge)
            Game:SetFieldMeta('Angle',config.angle)
        end
    end
    local aspect=liveScreenAspect()
    for _,entry in ipairs(DATA.entries) do
        local module=findNativeModule(entry.handle)
        if module then
            active[#active+1]={entry=entry,module=module}
            if entry.source_size and aspect then
                local ss=entry.source_size
                local w=ss.w_pct*aspect+ss.w_px
                module.Width=w
                if ss.auto_h then module.Height=w*ss.aspect end
            end
            if entry.source_projection then
                local p=entry.source_projection
                NativeUiProjection.Bind(module,p.projection,p.source_position,p.source_anchor,p)
            end
            if entry.source_texture then NativeUiSampling.Bind(module,entry) end
            if entry.source_frames then NativeUiFrames.Bind(module,entry) end
            if entry.source_events then NativeUiEvents.Bind(module,entry) end
            if entry.source_frame_interval then NativeUiFrameRate.Bind(module,entry) end
            if entry.source_number then NativeUiNumber.Bind(module,entry) end
            if entry.source_judge_counter_number then
                NativeUiNumber.Bind(module,{handle=entry.handle,managed_by_judge=true,
                    source_number=entry.source_judge_counter_number})
            end
            if entry.source_judge_counter then NativeUiJudge.Bind(module,entry) end
            if entry.source_text then NativeUiText.Bind(module,entry) end
            if entry.source_meter then NativeUiMeter.Bind(module,entry) end
            if entry.source_strip then NativeUiStrip.Bind(module,entry) end
            if entry.source_blend and NativeUiBlend then NativeUiBlend.Bind(module,entry) end
            if entry.color then module:SetColor(entry.color[1],entry.color[2],entry.color[3]) end
            if entry.source_motion then NativeUiMotion.Bind(module,entry) else
            local function motionPoint(vals,pcts,pxs)
                if not pcts or not aspect then return vals end
                local out={}
                for i=1,#vals do out[i]=(pcts[i] and pcts[i]~=0) and (pxs[i]+pcts[i]*aspect) or vals[i] end
                return out
            end
            for _,motion in ipairs(entry.motions or {}) do
                local mfrom=motionPoint(motion.from,motion.from_pct,motion.from_px)
                local mto=motionPoint(motion.to,motion.to_pct,motion.to_px)
                if motion.instant then
                    local value=mto
                    if motion.method=='DoMove' then module.X=value[1];module.Y=value[2]
                    elseif motion.method=='DoResize' then module.Width=value[1];module.Height=value[2]
                    elseif motion.method=='DoScale' then module.ScaleX=value[1];module.ScaleY=value[2]
                    elseif motion.method=='DoMoveX' then module.X=value[1]
                    elseif motion.method=='DoMoveY' then module.Y=value[1]
                    elseif motion.method=='DoWidth' then module.Width=value[1]
                    elseif motion.method=='DoHeight' then module.Height=value[1]
                    elseif motion.method=='DoScaleX' then module.ScaleX=value[1]
                    elseif motion.method=='DoScaleY' then module.ScaleY=value[1]
                    elseif motion.method=='DoAlpha' then module.Alpha=value[1]
                    elseif motion.method=='DoRotate' then module.Rotate=value[1] end
                else
                local first={start=motion.start,finish=motion.finish,from=mfrom[1],to=mto[1],
                    repeats=motion.repeats,repeatType=motion.repeatType,delay=motion.delay,
                    custom=motion.custom}
                local second={from=mfrom[2],to=mto[2]}
                if motion.method=='DoMove' then module:DoMove(first,second)
                elseif motion.method=='DoResize' then module:DoResize(first,second)
                elseif motion.method=='DoScale' then module:DoScale(first,second)
                elseif motion.method=='DoMoveX' then module:DoMoveX(first)
                elseif motion.method=='DoMoveY' then module:DoMoveY(first)
                elseif motion.method=='DoWidth' then module:DoWidth(first)
                elseif motion.method=='DoHeight' then module:DoHeight(first)
                elseif motion.method=='DoScaleX' then module:DoScaleX(first)
                elseif motion.method=='DoScaleY' then module:DoScaleY(first)
                elseif motion.method=='DoAlpha' then module:DoAlpha(first)
                elseif motion.method=='DoRotate' then module:DoRotate(first) end
                end
            end
            end
            if entry.source_sorting then
                if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UIModule') end
                local U=CS.UnityEngine
                local go=module.transform and module.transform.gameObject or module.gameObject
                if go then
                    local canvas=go:GetComponent(typeof(U.Canvas)) or go:AddComponent(typeof(U.Canvas))
                    canvas.overrideSorting=true
                    canvas.sortingLayerName=entry.source_sorting.layer
                    canvas.sortingOrder=entry.source_sorting.order
                end
            end
            if entry.source_plane_ui and NativeSourcePlaneUI then NativeSourcePlaneUI.Bind(module,entry) end
        end
    end
end
function OnInput()
    if NATIVE_FRAME_DRIVER then NATIVE_FRAME_DRIVER.inputs=NATIVE_FRAME_DRIVER.inputs+1 end
    local input=Game:InputEvent()
    local lane,kind=input:HitX(),input:Type()
    if NativeUiEvents then NativeUiEvents.Input(lane,kind,input:Time()) end
    if nativeSourcePoolInput then nativeSourcePoolInput(lane,kind,input:Time()) end
    if holdVisualInput then holdVisualInput(lane,kind) end
    for _,item in ipairs(active) do
        local entry=item.entry
        if entry.input_lane==lane and (kind==1 or kind==3) then
            local pressed=kind==1
            item.module.Alpha=(pressed==entry.pressed) and entry.alpha or 0
            if pressed and entry.pressed and entry.frames then item.module:Play() end
        end
    end
end
