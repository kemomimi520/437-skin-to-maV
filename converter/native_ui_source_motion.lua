-- Source UI animation state machine. Only public ordinary module properties
-- are written. No note, input, judgement, score, camera or clock is changed.
-- Queue/gap/retirement math follows the retained runtime.lua aniActive /
-- aniPercent implementation and original AnimationManager 0x6c3030.
local NativeUiMotion={items={},_prelude={}}
function NativeUiMotion.Clear()
    NativeUiMotion.items={}
    NativeUiMotion._prelude={}
    NativeUiMotion._all_done=false
    NativeUiMotion._actions_done=false
end
local function preludeEffectiveTime(time,sys_time,playing,loaded)
    if sys_time==nil then return math.modf(time),nil end
    local p=NativeUiMotion._prelude
    if p.started then return math.modf(time),nil end
    local minStart=nil
    for _,item in ipairs(NativeUiMotion.items) do
        for i,a in ipairs(item.motions) do
            if not item.retired[i] and not a.clock and a.repeats==0 and a.start<0 and a.finish<=0 and a.finish>-2000 then
                minStart=minStart and math.min(minStart,a.start) or a.start
            end
        end
    end
    if not minStart then
        if playing==true or (playing==nil and time>1e-4) then p.started=true end
        return math.modf(time),nil
    end
    local entryTime=math.max(-2000,minStart)
    local isLoaded=(loaded~=false) or (playing==true)
    if not isLoaded then
        p.prev_sys=nil
        p.mapped=nil
        p.last_t=entryTime
        return math.modf(entryTime),nil
    end
    if playing==true then p.was_playing=true end
    if playing==false and p.was_playing then
        p.prev_sys=sys_time
        return math.modf(p.mapped or entryTime),nil
    end
    if not p.mapped or not p.prev_sys then
        p.mapped=entryTime
        p.prev_sys=sys_time
        p.last_t=entryTime
        return math.modf(entryTime),nil
    end
    local raw_dt=math.max(0,sys_time-p.prev_sys)
    p.prev_sys=sys_time
    local prev_t=p.mapped
    local mapped=math.min(0,prev_t+raw_dt)
    p.mapped=mapped
    p.last_t=mapped
    if mapped>=0 then
        if playing==false then
            p.preplay_done=true
            return 0,nil
        end
        p.started=true
        return math.modf(time),(prev_t<0) and 0 or nil
    end
    return math.modf(mapped),nil
end
local function float(v)local n=string.unpack('f',string.pack('f',v));return n end
local function active(a,t,state)
    if t<a.start then return false,state end
    if t<=a.finish then return true,1 end
    local live=false;local duration=a.finish-a.start
    if a.repeats~=0 then
        if a.delay<1 then live=a.repeats==-1 or (t-a.finish)/a.repeats<duration
        else
            local cycle=duration+a.delay;local turn=math.floor((t-a.finish)/cycle)
            live=(a.repeats<1 or turn<a.repeats) and a.delay<=t-cycle*turn-a.finish
        end
    end
    if not live and (state==-1 or state==1) then return true,0 end
    return live,live and 1 or 0
end
local function bezier(a,p)
    if not a.custom then return p end
    p=float(p)
    local b=a.custom;local cx,cy=3*b.p1,3*b.p2
    local bx,by=3*(b.p3-b.p1)-cx,3*(b.p4-b.p2)-cy
    local ax,ay=1-cx-bx,1-cy-by
    local function x(t)return ((ax*t+bx)*t+cx)*t end
    local function y(t)return ((ay*t+by)*t+cy)*t end
    local epsilon=float(1/(a.finish-a.start));local guess=p
    for _=1,8 do
        local d=x(guess)-p;if math.abs(d)<epsilon then return float(y(guess)) end
        local slope=(3*ax*guess+2*bx)*guess+cx
        if math.abs(slope)<1e-6 then break end
        guess=guess-d/slope
    end
    local low,high=0,1;guess=p
    if guess<low then return float(y(low)) elseif guess>high then return float(y(high)) end
    for _=1,100 do
        local v=x(guess);if math.abs(v-p)<epsilon then break end
        if p>v then low=guess else high=guess end
        local nextGuess=(high-low)*.5+low;if nextGuess==guess then break end;guess=nextGuess
    end
    return float(y(guess))
end
local function percent(a,t)
    if a.instant then return 1 end
    local duration=a.finish-a.start
    if duration<=0 then return t>=a.start and 1 or 0 end
    if t<a.start then return 0 end
    if t<=a.finish then return bezier(a,(t-a.start)/duration) end
    if a.repeats~=0 then
        local cycle=duration+a.delay;local turn=math.floor((t-a.finish)/cycle)
        local rest=t-cycle*turn-a.finish
        if (a.repeats<1 or turn<a.repeats) and rest>=a.delay then
            local p=(rest-a.delay)/duration
            if a.repeatType==2 and turn%2==0 then p=1-p end
            return bezier(a,p)
        end
    end
    return 1
end
local function live_aspect()
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
local function resolve_endpoint(vals,pcts,pxs,i)
    if pcts and pcts[i] and pcts[i]~=0 then
        local aspect=live_aspect()
        if aspect then return pxs[i]+pcts[i]*aspect end
    end
    return vals[i]
end
local function skewMatrix(rotate,skewX,skewY,sx_scale,sy_scale)
    local radians=float(math.pi/180)
    sx_scale=sx_scale or 1;sy_scale=sy_scale or 1
    local ratio=sx_scale/sy_scale
    local kx=float(math.tan(float(skewX*radians)))*ratio
    local ky=float(math.tan(float(skewY*radians)))/ratio
    local angle=-rotate*math.pi/180;local c,s=math.cos(angle),math.sin(angle)
    return 1-c*s*(kx+ky),c*c*kx-s*s*ky,c*c*ky-s*s*kx,1+c*s*(kx+ky)
end
local function skewFactors(a,b,c,d)
    local aa,bb,ab=a*a+c*c,b*b+d*d,a*b+c*d
    local phi=.5*math.atan(2*ab,aa-bb)
    local largest=.5*(aa+bb+math.sqrt((aa-bb)^2+4*ab*ab))
    local sx=math.sqrt(largest)
    assert(sx>0 and sx<math.huge,'Non-finite source UI skew')
    local vx,vy=math.cos(phi),math.sin(phi)
    local theta=math.atan((c*vx+d*vy)/sx,(a*vx+b*vy)/sx)
    return theta*180/math.pi,sx,(a*d-b*c)/sx,-phi*180/math.pi
end
local function skewAnchor(rotate,anchor,width,height,skewX,skewY)
    if skewX==0 and skewY==0 then return 0,0 end
    local ax=(anchor%3)*.5*width
    local ay=(1-math.floor(anchor/3)*.5)*height
    local angle=-rotate*math.pi/180;local co,si=math.cos(angle),math.sin(angle)
    return ax-co*ax+si*ay,ay-si*ax-co*ay
end
NativeUiMotion.SkewMatrix=skewMatrix
NativeUiMotion.SkewFactors=skewFactors
NativeUiMotion.SkewAnchor=skewAnchor
local function syncSkew(item)
    local skewX,skewY=item.skewX or 0,item.skewY or 0
    local state=item.skew_wrap
    if not state and skewX==0 and skewY==0 then return end
    local U=CS and CS.UnityEngine
    local rect=item.rect
    if not (U and U.GameObject and U.RectTransform and rect and rect.parent) then return end
    if not state then
        local parent=rect.parent
        local saved={anchorMin=rect.anchorMin,anchorMax=rect.anchorMax,pivot=rect.pivot,
            position=rect.anchoredPosition3D,size=rect.sizeDelta,rotation=rect.localRotation,scale=rect.localScale}
        local sibling=rect:GetSiblingIndex()
        local function makeRect(name,p,anchorMin,anchorMax,pivot,sizeDelta)
            local go=U.GameObject(name,typeof(U.RectTransform))
            go.layer=rect.gameObject.layer
            local tr=go.transform
            tr:SetParent(p,false)
            tr.anchorMin=anchorMin;tr.anchorMax=anchorMax;tr.pivot=pivot;tr.sizeDelta=sizeDelta
            return tr
        end
        local zero2=U.Vector2(0,0)
        local outer=makeRect('source_skew_origin',parent,zero2,zero2,zero2,zero2)
        outer:SetSiblingIndex(sibling)
        local scale=makeRect('source_skew_scale',outer,zero2,zero2,zero2,zero2)
        local turn=makeRect('source_skew_basis',scale,zero2,zero2,zero2,zero2)
        local content=makeRect('source_skew_content',turn,zero2,zero2,parent.pivot,parent.rect.size)
        rect:SetParent(content,false)
        rect.anchorMin=saved.anchorMin;rect.anchorMax=saved.anchorMax;rect.pivot=saved.pivot
        rect.sizeDelta=saved.size;rect.anchoredPosition3D=saved.position
        rect.localRotation=saved.rotation;rect.localScale=saved.scale
        state={outer=outer,scale=scale,turn=turn,content=content}
        item.skew_wrap=state
    end
    local lp=rect.localPosition
    local rr=rect.rect
    local rs=rect.localScale
    local lx,ly=lp.x,lp.y
    local width=rr.width*rs.x
    local height=rr.height*rs.y
    local rotate=item.module.Rotate or 0
    if state.lx==lx and state.ly==ly and state.rotate==rotate and state.skewX==skewX and state.skewY==skewY
        and state.width==width and state.height==height then return end
    if skewX==0 and skewY==0 then
        local Q,V=U.Quaternion,U.Vector3
        state.outer.localPosition=V(0,0,0);state.outer.localRotation=Q.Euler(0,0,0)
        state.scale.localScale=V(1,1,1);state.turn.localRotation=Q.Euler(0,0,0)
        state.content.localPosition=V(0,0,0)
    else
        local sx_scale,sy_scale=1,1
        if item.tex_size and item.tex_size[1]>0 and item.tex_size[2]>0 and width~=0 and height~=0 then
            sx_scale=math.abs(width)/item.tex_size[1]
            sy_scale=math.abs(height)/item.tex_size[2]
        end
        local a,b,c,d=skewMatrix(rotate,skewX,skewY,sx_scale,sy_scale)
        local theta,sx,sy,phi=skewFactors(a,b,c,d)
        local dx,dy=skewAnchor(rotate,item.anchor,width,height,skewX,skewY)
        local Q,V=U.Quaternion,U.Vector3
        state.outer.localPosition=V(lx+dx,ly+dy,0);state.outer.localRotation=Q.Euler(0,0,theta)
        state.scale.localScale=V(sx,sy,1);state.turn.localRotation=Q.Euler(0,0,phi)
        state.content.localPosition=V(-lx,-ly,0)
    end
    state.lx,state.ly,state.rotate,state.skewX,state.skewY=lx,ly,rotate,skewX,skewY
    state.width,state.height=width,height
end
local function apply(item,a,p)
    local m=item.module
    local function mix(i)
        local from=resolve_endpoint(a.from,a.from_pct,a.from_px,i)
        local to=resolve_endpoint(a.to,a.to_pct,a.to_px,i)
        return from+(to-from)*p
    end
    local method=a.method
    if method=='DoMove' then m.X=mix(1);m.Y=mix(2)
    elseif method=='DoMoveX' then m.X=mix(1)
    elseif method=='DoMoveY' then m.Y=mix(1)
    elseif method=='DoResize' then m.Width=mix(1);m.Height=mix(2)
    elseif method=='DoWidth' then m.Width=mix(1)
    elseif method=='DoHeight' then m.Height=mix(1)
    elseif method=='DoRotate' then m.Rotate=mix(1)
    elseif method=='DoAlpha' then
        -- Cocos stores a byte, including truncation at intermediate values.
        local from=math.min(255,math.max(0,math.floor(float(a.from[1]*float(2.55)))))
        local to=math.min(255,math.max(0,math.floor(float(a.to[1]*float(2.55)))))
        local byte=math.floor(float(from+(to-from)*p))
        -- xLua's integer setter returns zero for a non-integral Lua number.
        -- Preserve the old byte exactly on the ordinary UI Graphics instead
        -- of quantizing the source opacity to maV's integer percentages.
        m.Alpha=math.floor(byte*100/255)
        local pma=item.pma_rgb
        local r=pma and math.floor(pma[1]*byte/255)/255
        local g=pma and math.floor(pma[2]*byte/255)/255
        local b=pma and math.floor(pma[3]*byte/255)/255
        for _,graphic in ipairs(item.graphics) do
            local color=graphic.color
            if pma then color.r=r;color.g=g;color.b=b end
            color.a=byte/255;graphic.color=color
        end
    elseif method=='DoScale' then
        m.Width=item.base.Width*mix(1)*(item.frames and NativeUiFrames.Ratio(item.frames,'width') or 1)
        m.Height=item.base.Height*mix(2)*(item.frames and NativeUiFrames.Ratio(item.frames,'height') or 1)
    elseif method=='DoScaleX' then m.Width=item.base.Width*mix(1)*(item.frames and NativeUiFrames.Ratio(item.frames,'width') or 1)
    elseif method=='DoScaleY' then m.Height=item.base.Height*mix(1)*(item.frames and NativeUiFrames.Ratio(item.frames,'height') or 1)
    elseif method=='DoSkew' then item.skewX=mix(1);item.skewY=mix(2)
    elseif method=='DoSkewX' then item.skewX=mix(1)
    elseif method=='DoSkewY' then item.skewY=mix(1)
    else error('Unmapped source UI method '..tostring(method)) end
end
function NativeUiMotion.Bind(module,entry)
    NativeUiMotion._all_done=false
    NativeUiMotion._actions_done=false
    if #NativeUiMotion.items==0 then NativeUiMotion._prelude={} end
    local base={}
    for _,name in ipairs({'X','Y','Width','Height','Rotate','Alpha'}) do base[name]=module[name] end
    if entry.frame_state then
        base.Width=base.Width/NativeUiFrames.Ratio(entry.frame_state,'width')
        base.Height=base.Height/NativeUiFrames.Ratio(entry.frame_state,'height')
    end
    local hasSkew=false;local hasSys=false
    for _,a in ipairs(entry.motions) do
        if a.method=='DoSkew' or a.method=='DoSkewX' or a.method=='DoSkewY' then hasSkew=true end
        if a.clock=='system' then hasSys=true end
    end
    local item={module=module,rect=module.transform,motions=entry.motions,base=base,states={},retired={},
        graphics={},base_alphas={},base_colors={},pma_rgb=entry.pma_rgb,frames=entry.frame_state,
        has_skew=hasSkew,has_sys=hasSys,skewX=0,skewY=0,anchor=entry.source_anchor or 4,tex_size=entry.source_tex_size}
    for _,a in ipairs(item.motions) do
        if a.method=='DoAlpha' then
            xlua.load_assembly('UnityEngine.UI')
            local kinds={CS.UnityEngine.UI.Image,CS.UnityEngine.UI.RawImage}
            if entry.source_text then
                if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'Unity.TextMeshPro') end
                if CS.TMPro and CS.TMPro.TMP_Text and typeof(CS.TMPro.TMP_Text)~=nil then
                    kinds[#kinds+1]=CS.TMPro.TMP_Text
                end
            end
            local function visit(transform)
                for _,kind in ipairs(kinds) do
                    local graphic=transform.gameObject:GetComponent(typeof(kind))
                    if graphic then
                        item.graphics[#item.graphics+1]=graphic
                        local c=graphic.color
                        item.base_alphas[#item.base_alphas+1]=c.a
                        item.base_colors[#item.base_colors+1]={c.r,c.g,c.b}
                    end
                end
                for child=0,transform.childCount-1 do visit(transform:GetChild(child)) end
            end
            visit(module.transform)
            assert(#item.graphics>0,'Source UI alpha has no ordinary Graphic')
            break
        end
    end
    NativeUiMotion.items[#NativeUiMotion.items+1]=item
    for i,a in ipairs(item.motions) do
        if a.instant then apply(item,a,1);item.retired[i]=true end
    end
    if item.has_skew and (item.skewX~=0 or item.skewY~=0) then syncSkew(item) end
end
function NativeUiMotion.Stop(module)
    for _,item in ipairs(NativeUiMotion.items) do
        if item.module==module then
            for i=1,#item.motions do item.retired[i]=true end
        end
    end
end
function NativeUiMotion.Reset()
    NativeUiMotion._all_done=false
    NativeUiMotion._actions_done=false
    NativeUiMotion._prelude={}
    for _,item in ipairs(NativeUiMotion.items) do
        item.all_done=false
        item.motions_done=false
        for name,value in pairs(item.base) do item.module[name]=value end
        for idx,graphic in ipairs(item.graphics) do
            local color=graphic.color;local bc=item.base_colors[idx]
            if bc then color.r=bc[1];color.g=bc[2];color.b=bc[3] end
            color.a=item.base_alphas[idx];graphic.color=color
        end
        if item.frames then
            item.module.Width=item.base.Width*NativeUiFrames.Ratio(item.frames,'width')
            item.module.Height=item.base.Height*NativeUiFrames.Ratio(item.frames,'height')
        end
        item.states={};item.retired={};item.last=nil;item.last_live=nil;item.sys0=nil;item.sys_last=nil;item.skewX=0;item.skewY=0
        for i,a in ipairs(item.motions) do
            if a.instant then apply(item,a,1);item.retired[i]=true end
        end
        if item.has_skew then syncSkew(item) end
    end
end
local function isPurePreludeAction(a)
    return not a.clock and a.repeats==0 and a.start<0 and a.finish<=0 and a.finish>-2000
end
local function stepMotionFrame(tPrelude,tLive,sys)
    local allDone=NativeUiMotion._prelude.started==true
    local actionsDone=allDone
    for _,item in ipairs(NativeUiMotion.items) do
        if not item.all_done then
            if not item.motions_done then
                local tSys
                if item.has_sys then
                    if sys~=nil then
                        item.sys0=item.sys0 or sys
                        tSys=math.modf(sys-item.sys0)
                    else
                        tSys=tLive
                    end
                end
                local preludeChanged=item.last~=tPrelude
                local liveChanged=item.last_live~=tLive
                local sysChanged=item.has_sys and item.sys_last~=tSys
                if preludeChanged or liveChanged or sysChanged then
                    local pending=false
                    for i,a in ipairs(item.motions) do
                        if not item.retired[i] then
                            local isSys=a.clock=='system'
                            local usePrelude=not isSys and isPurePreludeAction(a)
                            if usePrelude and liveChanged then
                                for j=i+1,#item.motions do
                                    local b=item.motions[j]
                                    if not item.retired[j] and not b.clock and not isPurePreludeAction(b) and tLive>=b.start then
                                        usePrelude=false;break
                                    end
                                end
                            end
                            local mt=isSys and tSys or (usePrelude and tPrelude or tLive)
                            local changed=(isSys and sysChanged) or (usePrelude and preludeChanged) or (not isSys and not usePrelude and liveChanged)
                            if changed then
                                local live,state=active(a,mt,item.states[i] or -1);item.states[i]=state
                                if mt>=a.finish and (a.repeats==0 or a.repeats~=-1 and
                                    float(float(mt-a.finish)/a.repeats)>=float(a.finish-a.start+a.delay)) then
                                    item.retired[i]=true
                                end
                                if live then apply(item,a,percent(a,mt)) end
                            end
                            if not item.retired[i] then pending=true end
                        end
                    end
                    item.last=tPrelude
                    item.last_live=tLive
                    if item.has_sys then item.sys_last=tSys end
                    if not pending then
                        item.motions_done=true
                        if not (item.has_skew and (item.skew_wrap or item.skewX~=0 or item.skewY~=0)) then
                            item.all_done=true
                        end
                    end
                end
            end
            if item.has_skew and (item.skew_wrap or item.skewX~=0 or item.skewY~=0) then syncSkew(item) end
            if not item.motions_done then actionsDone=false end
            if not item.all_done then allDone=false end
        end
    end
    if actionsDone then NativeUiMotion._actions_done=true end
    if allDone then NativeUiMotion._all_done=true end
end
function NativeUiMotion.SyncSkews()
    local U=CS and CS.UnityEngine
    local time=U and U.Time
    local fc=time and time.frameCount
    if fc~=nil and (NativeUiNumber and (NativeUiNumber._dirty or 0)<=0) and (fc%15)~=0 then return end
    for _,item in ipairs(NativeUiMotion.items) do
        if item.has_skew and (item.skew_wrap or item.skewX~=0 or item.skewY~=0) then syncSkew(item) end
    end
end
function NativeUiMotion.Update(time,sys_time,playing,loaded)
    if NativeUiMotion._all_done then return end
    if NativeUiMotion._actions_done then
        NativeUiMotion.SyncSkews()
        return
    end
    local tPrelude,flush0=preludeEffectiveTime(time,sys_time,playing,loaded)
    local p=NativeUiMotion._prelude
    local rawLive=math.modf(time)
    local tLive=((playing==false and p.was_playing and p.last_live) and p.last_live) or ((playing==false and not p.was_playing) and math.min(0,rawLive)) or rawLive
    p.last_live=tLive
    local sys=(sys_time~=nil and (loaded~=false or playing==true)) and math.modf(sys_time) or nil
    if flush0~=nil then stepMotionFrame(flush0,math.min(0,tLive),sys) end
    stepMotionFrame(tPrelude,tLive,sys)
end
