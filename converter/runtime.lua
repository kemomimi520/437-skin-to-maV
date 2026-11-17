-- Generated compatibility runtime. Uses the target game's public skin API only.
-- Compilation does not constitute a passed visual acceptance test.
local objects, pressed, hits, audio = {}, {}, {}, {}
-- BuildUI falls back to a global judge only when exactly one successful
-- factory exists and it occupies slot 1. A lone later slot stays per-lane.
local globalJudge=PROFILE.global_judge==true
local chordTimes={}
local legacyTimes={}
local legacyScroll={}
local legacyScrollLayer
local legacyLifetime,lifetimeModule,lifetimeDrawing
local legacyPrelude
local ownedNoteChildren={}
local function noteChild(mod,name)
    local children=ownedNoteChildren[mod]
    if children then return children[name] end
    return mod:GetChild(name)
end
local prepareLifetime,updateLifetime,resetLifetime
local updateRigidProgress
local lifetimeHide
local lifetimeTapProgress={Length=1,[0]=0}
local lifetimeHoldProgress={Length=2,[0]=0,[1]=0}
local function noteTime(note)
    local old=legacyTimes[note.nid]
    return old and old.time or note.time,old and old.endtime or note.endtime
end
local noteStates={}
-- Keep rendering history for old Part3/reverse-scroll semantics, but input
-- release and end-sound work only needs currently held/pending notes.
local heldNotesByLane,pendingHoldEnds={},{}
local pressEvents={}
local updateBars,prepareBars,prepareMusicbar,updateMusicbar,judgeMusicbar
local function releaseHit(lane,t,nid)
    local hit=hits[lane]
    if hit and hit.state=='2' and (not nid or hit.nid==nid) then hits[lane]={time=t,state='3',nid=hit.nid} end
end
local function playEnd(state)
    if PROFILE.sound_end and not state.endSoundPlayed and state.grade then
        local grade=({'best','cool','good'})[state.grade]
        if grade and audio[grade] then Audio:Play(audio[grade],100) end
        state.endSoundPlayed=true
    end
end
local function updateHoldEnds(time)
    for nid,state in pairs(pendingHoldEnds) do
        if not state.held then pendingHoldEnds[nid]=nil
        elseif state.endtime and time>=state.endtime then
            playEnd(state);releaseHit(state.lane,time,nid);pendingHoldEnds[nid]=nil
        end
    end
end
local factor = 1.5
local frameWidth,frameTime
local motionSystemEpoch,motionSystemTime=0,0
local visualRevision=0
local uiSchedule
local noMotions={}
local musicbarWhite={255,255,255}
local function axis(v, extent) return v[1]*extent+v[2] end
local function screen() return (frameWidth or Game:Width())/factor,720 end
local function geometry(e)
    local w,h=screen()
    return axis(e.pos[1],w),axis(e.pos[2],h),axis(e.size[1],w),axis(e.size[2],h)
end
local noteFrameLayouts
local retainedNoteLayouts,retainedNoteWidth,retainedNoteFactor
local noteRotation={}
local function rotationCoefficients(anchor,rotate)
    local rotations=noteRotation[anchor]
    if not rotations then rotations={};noteRotation[anchor]=rotations end
    local cached=rotations[rotate]
    if not cached then
        local rad=-rotate*math.pi/180
        cached={rotate=rotate,ax=(anchor%3)*.5,ay=1-math.floor(anchor/3)*.5,
            cos=math.cos(rad),sin=math.sin(rad)}
        rotations[rotate]=cached
    end
    return cached
end
local function dimensions(w,h,texture,nativeIntrinsic)
    if w==0 and h==0 then
        -- An unscaled Cocos Sprite keeps pixel-valued content size in the
        -- original logical viewport. It is not a 720-unit requested size.
        local scale=nativeIntrinsic and 720/(PROFILE.ui_rounding_height or 720) or 1
        return texture.width*scale,texture.height*scale
    end
    if w==0 then w=h*texture.width/texture.height end
    if h==0 then h=w*texture.height/texture.width end
    return w,h
end
local function applySkew(e,x,y,rotate,skewX,skewY,width,height)
    if skewX~=0 or skewY~=0 or e._skewCreated then
        e._skewCreated=true
        UnityBridge.SkewEntry(e,x*factor,y*factor,rotate,skewX,skewY,width*factor,height*factor)
    end
end
local function scalar(v,extent) return axis(v,extent or 100) end
local function legacyRound(v)
    -- Native ApplyVisualParams rounds AFTER the parser scales to the old
    -- logical viewport. Rounding directly in canonical 720 units shifts UI.
    local scale=(PROFILE.ui_rounding_height or 720)/720
    local old=UnityBridge.Float(v*scale)
    return (old<0 and math.ceil(old-0.5) or math.floor(old+0.5))/scale
end
local function entryLayout(e)
    local width,height=screen()
    local p,s=e.pos,e.size
    local cached=e._baseLayout
    local program=e.native_pos_program
    local rounding=PROFILE.ui_rounding_height or 720
    if not cached or cached.viewport~=width or cached.rounding~=rounding or cached.program~=program or
       cached.p1~=p[1][1] or cached.p2~=p[1][2] or cached.p3~=p[2][1] or cached.p4~=p[2][2] or
       cached.s1~=s[1][1] or cached.s2~=s[1][2] or cached.s3~=s[2][1] or cached.s4~=s[2][2] then
        local x,y,w,h=geometry(e)
        if program then x,y=LegacyPosition.Rounded(e,width,height)
        else x,y=legacyRound(x),legacyRound(y) end
        cached={x=x,y=y,w=w,h=h,viewport=width,rounding=rounding,program=program,
            p1=p[1][1],p2=p[1][2],p3=p[2][1],p4=p[2][2],s1=s[1][1],s2=s[1][2],s3=s[2][1],s4=s[2][2]}
        e._baseLayout=cached
    end
    return cached.x,cached.y,cached.w,cached.h
end
local function aniActive(a,t,s)
    if t<a.start then return false,s end
    if t<=a.finish then return true,1 end
    local live=false
    local duration=a.finish-a.start
    if a.repeats~=0 then
        if a.delay<1 then live=a.repeats==-1 or (t-a.finish)/a.repeats<duration
        else
            local cycle=duration+a.delay
            local turn=math.floor((t-a.finish)/cycle)
            live=(a.repeats<1 or turn<a.repeats) and a.delay<=t-cycle*turn-a.finish
        end
    end
    if not live and (s==-1 or s==1) then return true,0 end
    return live,live and 1 or 0
end
local function legacyBezier(a,p)
    if not a.bezier then return p end
    local f=UnityBridge.Float
    p=f(p)
    local x1,y1,x2,y2=table.unpack(a.bezier)
    local cx,cy=3*x1,3*y1
    local bx,by=3*(x2-x1)-cx,3*(y2-y1)-cy
    local ax,ay=1-cx-bx,1-cy-by
    local function x(t) return ((ax*t+bx)*t+cx)*t end
    local function y(t) return ((ay*t+by)*t+cy)*t end
    local epsilon=f(1/(a.finish-a.start))
    local guess=p
    for _=1,8 do
        local difference=x(guess)-p
        if math.abs(difference)<epsilon then return f(y(guess)) end
        local slope=(3*ax*guess+2*bx)*guess+cx
        if math.abs(slope)<1e-6 then break end
        guess=guess-difference/slope
    end
    local low,high=0,1;guess=p
    if guess<low then return f(y(low)) elseif guess>high then return f(y(high)) end
    for _=1,100 do
        local actual=x(guess)
        if math.abs(actual-p)<epsilon then break end
        if p>actual then low=guess else high=guess end
        local nextGuess=(high-low)*.5+low
        if nextGuess==guess then break end
        guess=nextGuess
    end
    return f(y(guess))
end
local function aniPercent(a,t)
    if a.clock=='attachment_terminal' then return 1 end
    local duration=a.finish-a.start
    if duration<=0 then return t>=a.start and 1 or 0 end
    if t<a.start then return 0 end
    if t<=a.finish then return legacyBezier(a,(t-a.start)/duration) end
    if a.repeats~=0 then
        local cycle=duration+a.delay
        local turn=math.floor((t-a.finish)/cycle)
        local rest=t-cycle*turn-a.finish
            if (a.repeats<1 or turn<a.repeats) and rest>=a.delay then
                local p=(rest-a.delay)/duration
                if a.reverse_repeat and turn%2==0 then p=1-p end
                return legacyBezier(a,p)
            end
    end
    return 1
end
local function animate(e,x,y,w,h,t)
    -- 0x6c3030 passes an int clock to every AnimationBase. C++ truncates
    -- negative chart prelude times toward zero, unlike math.floor.
    t=math.modf(t)
    local frozen=e._judgeFrozen
    if frozen then
        if e._animation then e._animation.time=t end
        return frozen.x,frozen.y,frozen.w,frozen.h,255,frozen.rotate,frozen.skewX,frozen.skewY
    end
    local definitions=PROFILE.motions[e.motion] or noMotions
    local cache=e._animation
    -- No attached tracks: a changing chart clock cannot change this layout.
    -- Keep the wake/time contract used by static images, including rewinds.
    if #definitions==0 then
        if not cache or cache.motion~=e.motion or cache.definitions~=definitions or
           cache.base_x~=x or cache.base_y~=y or cache.base_w~=w or cache.base_h~=h or
           cache.opacity~=e.opacity or cache.base_rotate~=e.rotate then
            cache={x=x,y=y,w=w,h=h,base_x=x,base_y=y,base_w=w,base_h=h,
                alpha=UnityBridge.BytePercent(e.opacity),rotate=e.rotate,skewX=0,skewY=0,
                motion=e.motion,definitions=definitions,opacity=e.opacity,base_rotate=e.rotate,nextWake=math.huge}
            e._animation=cache
        end
        cache.time=t
        return x,y,w,h,cache.alpha,cache.rotate,0,0
    end
    if not cache or cache.motion~=e.motion or
       cache.base_x~=x or cache.base_y~=y or cache.base_w~=w or cache.base_h~=h then
        cache={x=x,y=y,w=w,h=h,base_x=x,base_y=y,base_w=w,base_h=h,
            alpha=UnityBridge.BytePercent(e.opacity),rotate=e.rotate,skewX=0,skewY=0,states={},retired={},time=t,motion=e.motion};e._animation=cache
    end
    local rewound=t<cache.time or cache.system_time and motionSystemTime<cache.system_time
    if cache.nextWake and t<cache.nextWake and not rewound then
        cache.time=t
        return cache.x,cache.y,cache.w,cache.h,cache.alpha,cache.rotate,cache.skewX,cache.skewY
    end
    x,y,w,h=cache.x,cache.y,cache.w,cache.h
    local alpha,rotate=cache.alpha,cache.rotate
    local skewX,skewY=cache.skewX,cache.skewY
    local nextWake=math.huge
    local sw,sh=screen()
    local function scaleBase()
        local texture=e.states and e.states['1'] and e.states['1'][1]
        if texture then return dimensions(cache.base_w,cache.base_h,texture,true) end
        return cache.base_w,cache.base_h
    end
    for i,a in ipairs(definitions) do
        if not cache.retired[i] then
        local clock=a.clock=='system' and motionSystemTime or t
        local active,nextState
        if a.clock=='attachment_terminal' then active=(cache.states[i] or -1)~=0;nextState=0
        else active,nextState=aniActive(a,clock,cache.states[i] or -1) end
        cache.states[i]=nextState
        -- AdvanceAnimations (0x6c3030) removes finished queue entries even
        -- at the exact endpoint. A clock correction cannot recreate them;
        -- OnRetry explicitly clears the attachment cache instead.
        local retired=a.clock=='attachment_terminal' or clock>=a.finish and
            (a.repeats==0 or a.repeats~=-1 and
             UnityBridge.Float(UnityBridge.Float(clock-a.finish)/a.repeats)>=
             UnityBridge.Float(a.finish-a.start+a.delay))
        if retired then cache.retired[i]=true end
        -- Retire only settled, non-repeating tracks. Repeat gaps keep the
        -- original state machine; future tracks wake at their exact start.
        if not retired then
            if a.clock=='system' then
                -- A paused chart clock cannot schedule a system-clock wake.
                -- Keep this element live until the original track retires.
                if clock<a.start or nextState~=0 or a.repeats~=0 then nextWake=t end
            elseif t<a.start then nextWake=math.min(nextWake,a.start)
            elseif nextState~=0 or a.repeats~=0 then nextWake=t end
        end
        if active then
            local p=aniPercent(a,clock)
            local function mix(i,extent)
                local f=scalar(a.from[i] or a.from[1],extent)
                local v=scalar(a.to[i] or a.to[1],extent)
                if a.kind=='f' or a.kind=='fade' then f=UnityBridge.BytePercent(f);v=UnityBridge.BytePercent(v) end
                if a.bezier then
                    local scale=(a.kind=='f' or a.kind=='fade' or a.kind=='r' or a.kind=='skewx' or a.kind=='skewy') and 1 or (PROFILE.ui_rounding_height or 720)/720
                    local oldFrom,oldTo=UnityBridge.Float(f*scale),UnityBridge.Float(v*scale)
                    return UnityBridge.Float(UnityBridge.Float(oldTo-oldFrom)*p+oldFrom)/scale
                end
                return f+(v-f)*p
            end
            if a.kind=='m' then x=mix(1,sw);y=mix(2,sh)
            elseif a.kind=='mx' then x=mix(1,sw)
            elseif a.kind=='my' then y=mix(1,sh)
            elseif a.kind=='w' then w=mix(1,sw);cache.judgeContentW=w
            elseif a.kind=='h' then h=mix(1,sh);cache.judgeContentH=h
            elseif a.kind=='size' then w=mix(1,sw);h=mix(2,sh);cache.judgeContentW=w;cache.judgeContentH=h
            elseif a.kind=='r' then rotate=mix(1,360)
            elseif a.kind=='f' or a.kind=='fade' then alpha=UnityBridge.Float(mix(1,100))
            elseif a.kind=='s' then
                -- Original attachment captures factory scale once. Reusing
                -- last frame's rendered size compounds the factor forever.
                local bw,bh=scaleBase();w=bw*mix(1,1);h=bh*mix(2,1)
            elseif a.kind=='sx' then local bw=scaleBase();w=bw*mix(1,1)
            elseif a.kind=='sy' then local _,bh=scaleBase();h=bh*mix(1,1)
            elseif a.kind=='skew' then
                local scale=(PROFILE.ui_rounding_height or 720)/720
                skewX=mix(1,sw)*scale;skewY=mix(2,sh)*scale
            elseif a.kind=='skewx' then skewX=mix(1,1)
            elseif a.kind=='skewy' then skewY=mix(1,1)
            end
        end
        end
    end
    cache.x,cache.y,cache.w,cache.h=x,y,w,h
    cache.alpha,cache.rotate,cache.time=alpha,rotate,t
    cache.skewX,cache.skewY=skewX,skewY
    cache.system_time=motionSystemTime
    cache.nextWake=nextWake
    return x,y,w,h,alpha,rotate,skewX,skewY
end
local function stopStaticJudgeMotion(e)
    if e._judgeFrozen then return end
    local x,y,w,h=entryLayout(e)
    local cache=e._animation
    -- Native StaticHit sets opacity/scale, clears THIS node's animation
    -- manager (0x6c1360), then installs the built-in hit effect. Removing
    -- tracks retains their current position/rotation/skew/content size; it
    -- neither restores declaration defaults nor affects other attachments.
    e._judgeFrozen={x=cache and cache.x or x,y=cache and cache.y or y,
        w=cache and (cache.judgeContentW or cache.base_w) or w,
        h=cache and (cache.judgeContentH or cache.base_h) or h,
        rotate=cache and cache.rotate or e.rotate,skewX=cache and cache.skewX or 0,
        skewY=cache and cache.skewY or 0}
    if cache then
        for i in ipairs(PROFILE.motions[e.motion] or noMotions) do cache.retired[i]=true;cache.states[i]=0 end
        cache.nextWake=math.huge
    end
end
local glyphIds={['%']=10,['.']=11,['-']=12,['+']=13,['x']=14,[':']=15}
local function comboEffect(e,t,target)
    local pulse=e._combo or {target=0};e._combo=pulse
    if target~=pulse.target then
        pulse.target=target;pulse.start=t
        if target>0 and target%100==0 then pulse.flash=t end
    end
    local sy=1
    if pulse.start and t<pulse.start+160 then
        local p=UnityBridge.Float(math.min(1,math.max(0,t-pulse.start)/160))
        local top=UnityBridge.Float(1.1)
        sy=UnityBridge.Float((1-top)*p+top)
    end
    local color
    if pulse.flash then
        if t>=pulse.flash+800 then
            pulse.white=pulse.white or {255,255,255};color=pulse.white
        else
            local p=UnityBridge.Float(math.min(1,math.max(0,t-pulse.flash)/800))
            color={UnityBridge.Byte(16*p+239),UnityBridge.Byte(153*p+102),UnityBridge.Byte(153*p+102)}
        end
    end
    return sy,color
end
local function numberValue(e,t,target)
    local n=e._number or {value=0,target=0,step=0,timer=42,time=t};e._number=n
    if target~=n.target then
        n.target=target
        n.step=e.number.duration>0 and (target-n.value)*42/e.number.duration or (target-n.value)*1e30
    end
    if n.value~=n.target then
        local elapsed=UnityBridge.Float(UnityBridge.Float(math.max(0,t-n.time)/1000)*1000)
        n.timer=n.timer-elapsed
        if n.timer<0 then
            n.value=n.value+n.step
            if (n.step>0 and n.value>n.target) or (n.step<0 and n.value<n.target) then n.value=n.target end
            n.timer=n.timer+42
        end
    end
    n.time=t
    return n.value
end
local function numberSource(e)
    local source=objects[e.value_handle]
    return UnityBridge.NativeTextValue and UnityBridge.NativeTextValue(source) or source.Text or ''
end
local function updateNumber(e,x,y,alpha,rotate,t,skewX,skewY,sourceText)
    local config=e.number
    sourceText=sourceText or numberSource(e)
    if e._sourceText~=sourceText then
        e._sourceText=sourceText;e._sourceNumber=tonumber(sourceText:match('[%d%.%-]+')) or 0
    end
    local value=e._sourceNumber
    local sy,color=1,nil
    if config.variable=='combo' then sy,color=comboEffect(e,t,value) end
    value=numberValue(e,t,value)
    local text=e._formattedText
    if text==nil or e._formattedValue~=value then
        text=config.variable=='acc' and string.format('%.2f%%',value) or
            string.format('%d',config.variable=='combo' and math.ceil(value) or math.floor(value))
        e._formattedValue=value;e._formattedText=text
    end
    local previous=e._numberVisual
    local r,g,b=color and color[1],color and color[2],color and color[3]
    if previous and previous.text==text and previous.x==x and previous.y==y and previous.alpha==alpha and
       previous.rotate==rotate and previous.sy==sy and previous.factor==factor and
       previous.r==r and previous.g==g and previous.b==b then
        applySkew(e,x,y,rotate,skewX,skewY,previous.width,previous.height)
        return
    end
    local sameGlyphs=previous and previous.text==text and previous.factor==factor and
        previous.alpha==alpha and previous.r==r and previous.g==g and previous.b==b
    local visual=previous or {};e._numberVisual=visual
    visual.text,visual.x,visual.y,visual.alpha=text,x,y,alpha
    visual.rotate,visual.sy,visual.factor=rotate,sy,factor
    visual.r,visual.g,visual.b=r,g,b
    local plan=e._numberPlan
    if not plan or plan.text~=text then
        local scale=config.height/config.glyphs[0].frame_height
        local spacing=axis(config.spacing,100)
        local advance=config.glyphs[0].width*scale
        local width,last=0,advance
        local glyphs={}
        for i=1,math.min(30,#text) do
            local c=text:sub(i,i);local id=tonumber(c) or glyphIds[c];local tex=config.glyphs[id]
            if tex then
                if config.proportional then advance=tex.width*scale end
                glyphs[#glyphs+1]={texture=tex,left=width}
                width=width+advance*spacing;last=advance
            end
        end
        plan={text=text,scale=scale,width=width+(1-spacing)*last,glyphs=glyphs};e._numberPlan=plan
    end
    local scale,width,glyphs=plan.scale,plan.width,plan.glyphs
    e._numberVisual.width,e._numberVisual.height=width,config.height*sy
    applySkew(e,x,y,rotate,skewX,skewY,width,config.height*sy)
    local ax=(e.anchor%3)*.5;local ay=1-math.floor(e.anchor/3)*.5
    local angle=-rotate*math.pi/180;local cos,sin=math.cos(angle),math.sin(angle)
    -- A NumberSprite's position/rotation/Combo pulse belongs to its parent.
    -- Keep glyph layout local, instead of resizing/moving every digit for
    -- every pulse frame. Color/opacity still use the proved source blending.
    local grouped=e._numberGroup and UnityBridge.NumberGroupTransform(e,x*factor,y*factor,rotate,sy)
    if grouped and sameGlyphs then
        -- A parent's pulse/translation/rotation does not dirty glyph-local
        -- geometry, UVs or tint. Let the engine transform its retained children.
        local stats=UnityBridge.NotePerformance
        if stats then stats.number_local_layout_skips=(stats.number_local_layout_skips or 0)+1 end
        return
    end
    if grouped then sy=1;rotate=0;cos=1;sin=0 end
    e._glyphFiles=e._glyphFiles or {}
    e._glyphVisuals=e._glyphVisuals or {}
    local glyphLimit=e._glyphCount and math.max(e._glyphCount,#glyphs) or #e.handles.glyphs
    e._glyphCount=#glyphs
    for i=1,glyphLimit do
        local key=e.handles.glyphs[i]
        local obj=objects[key];local glyph=glyphs[i]
        UnityBridge.AlphaByte(obj,glyph and alpha or 0)
        if glyph then
            local tex=glyph.texture
            if e._glyphFiles[i]~=tex.file then UnityBridge.SpriteFile(obj,tex.file,tex.alpha_encoding);e._glyphFiles[i]=tex.file end
            local w,h=tex.width*scale,tex.height*scale*sy
            local dx,dy=glyph.left+w/2-ax*width,h/2-ay*config.height*sy
            local px,py
            if grouped then px,py=dx*factor,dy*factor
            else px,py=(x+cos*dx-sin*dy)*factor,(y+sin*dx+cos*dy)*factor end
            local pw,ph=w*factor,h*factor
            local old=e._glyphVisuals[i]
            if not (PROFILE.native_ui_submit_candidate and UnityBridge.PublicImageGeometry and
                UnityBridge.PublicImageGeometry(obj,px,py,pw,ph,rotate,not old)) then
            if not old or old.x~=px then obj.X=px end
            if not old or old.y~=py then obj.Y=py end
            if not old or old.w~=pw then obj.Width=pw end
            if not old or old.h~=ph then obj.Height=ph end
            if not old or old.rotate~=rotate then obj.Rotate=rotate end
            end
            old=old or {};old.x,old.y,old.w,old.h,old.rotate=px,py,pw,ph,rotate
            e._glyphVisuals[i]=old
            if color then UnityBridge.Color(obj,color[1],color[2],color[3]) end
        end
    end
end
local function settledLayout(e,t)
    local old=e._settledLayout
    return old and old.layout==e._baseLayout and old.factor==factor and
        old.motion==e.motion and old.definitions==PROFILE.motions[e.motion] and
        old.opacity==e.opacity and old.rotate==e.rotate and
        t>=old.time and math.modf(t)<old.wake
end
local function retainSettledLayout(e,t)
    local animation=e._animation
    if animation and animation.nextWake and math.modf(t)<animation.nextWake then
        e._settledLayout={layout=e._baseLayout,factor=factor,motion=e.motion,
            definitions=PROFILE.motions[e.motion],opacity=e.opacity,rotate=e.rotate,
            time=t,wake=animation.nextWake}
    else e._settledLayout=nil end
end
local function updateEntry(e,t,frameDelta)
    if e.autoplay_frames then e._frameElapsed=(e._frameElapsed or 0)+(frameDelta or 0) end
    local frameClock=e.autoplay_frames and e._frameElapsed or t
    -- Number factories have no image-state animator. Their source value,
    -- interpolation and Combo pulse remain live; frame-bank selection does
    -- not participate in any of those three behaviors.
    if e.number then
        local x,y,w,h=entryLayout(e)
        local sourceText=numberSource(e)
        local n,pulse,drawn=e._number,e._combo,e._numberVisual
        local settled=n and n.value==n.target and sourceText==e._sourceText and
            (not pulse or drawn and drawn.sy==1 and
                (not pulse.start or t>=pulse.start+160) and
                (not pulse.flash or t>=pulse.flash+800 and
                    drawn.r==255 and drawn.g==255 and drawn.b==255))
        if PROFILE.native_ui_schedule_candidate and settled and settledLayout(e,t) then
            -- The native source remains live. A settled 42 ms interpolator
            -- still advances its previous-time clock, so the next value does
            -- not consume the entire sleep interval in one step.
            n.time=t;e._settledLayout.time=t;e._animation.time=math.modf(t)
            return
        end
        local alpha,rotate,skewX,skewY
        x,y,w,h,alpha,rotate,skewX,skewY=animate(e,x,y,w,h,t)
        updateNumber(e,x,y,alpha,rotate,t,skewX,skewY,sourceText)
        retainSettledLayout(e,t)
        return
    end
    local descriptor=e._eventDescriptor
    if not descriptor or descriptor.name~=e.name then
        local name=e.name
        descriptor={name=name,keyLane=tonumber(name:match('^key%-(%d+)$')),
            pressLane=tonumber(name:match('^press%-(%d+)$')),hitLane=tonumber(name:match('^hit%-(%d+)$')),
            hitPrefix=not not name:match('^hit%-'),pressPrefix=not not name:match('^press%-'),
            timing=name=='hit-fast' or name=='hit-slow'}
        e._eventDescriptor=descriptor
    end
    if e._staticEligible==nil then
        local name=e.name
        local eligible=not e.number and not e.fill and not e.musicbar and
            not e.judge_lane and not descriptor.hitPrefix and not descriptor.pressPrefix
        e._staticEligible=not not eligible
    end
    local staticWidth
    if e._staticEligible then
        staticWidth=frameWidth or Game:Width()
        if e._staticRevision==visualRevision and e._staticWidth==staticWidth and e._staticFactor==factor and
           e._staticTime and t>=e._staticTime and e._animation and e._animation.motion==e.motion and
           t<e._animation.nextWake and frameClock<(e._frameNextWake or math.huge) then
            -- Stable bitmap geometry can sleep, but its native text must be
            -- inspected every frame: BPM/metadata may change independently
            -- of skin animations or input events.
            for _,row in ipairs(e._staticBitmapRows or {}) do
                UnityBridge.BitmapText(row.object,e,PROFILE.fonts[e.bitmap_font],row.alpha,row.visual)
            end
            e._staticTime=t;return
        end
    end
    local name=e.name
    local state='1'
    local eventSource
    local elapsed=frameClock
    -- Generic ApplyAttributes' show=0 hides the native node independently
    -- of opacity. Keep clocks and variable readers alive while its draw
    -- surfaces are hidden; an alpha animation must not reveal that node.
    local enabled=e.visible~=false
    local lane=descriptor.keyLane
    if lane then
        if pressed[lane] and e.handles['2'] then state='2' end
    end
    lane=descriptor.pressLane
    local pressLane=lane
    if lane then
        local event=pressEvents[lane]
        eventSource=event
        enabled=event~=nil
        if event then state=event.state;elapsed=t-event.time;enabled=e.handles[state]~=nil end
    end
    lane=descriptor.hitLane
    if lane then
        local event=hits[lane]
        eventSource=event
        enabled=event~=nil
        if event then state=event.state;elapsed=t-event.time;enabled=e.handles[state]~=nil end
    end
    local judgeEvent=e.judge_lane and (globalJudge and hits.judge or hits['judge-'..e.judge_lane])
    if e.judge_lane then
        local event=judgeEvent;enabled=event~=nil
        eventSource=event
        if event then state=e.handles[tostring(event.grade)] and tostring(event.grade) or '1';elapsed=t-event.time end
    end
    if descriptor.timing then
        local event=hits[name];enabled=event~=nil
        eventSource=event
        if event then elapsed=t-event.time end
    end
    if PROFILE.native_ui_schedule_candidate and e._eventDormant and
       e._dormantEvent==eventSource and e._dormantTime and t>=e._dormantTime then
        e._dormantTime=t;return
    end
    local bank=e.handles[state] or {}
    local count=e.reuse_frames and #(e.states[state] or {}) or #bank
    local interval=math.max(1,e.interval)
    local frame=math.floor(math.max(0,elapsed)/interval)%math.max(1,count)+1
    local mode=e.frame_modes[state] or ''
    local heldHit=lane and descriptor.hitPrefix and state=='2'
    local keepLast=not e.autoplay_frames and not heldHit and mode~='+' and (mode=='~' or (pressLane and state=='1'))
    if keepLast then frame=math.min(count,math.floor(math.max(0,elapsed)/interval)+1) end
    if e._staticEligible then
        -- Keep full render frequency. An unchanged frame has no new layout;
        -- wake on its exact source frame boundary, animation or input change.
        e._frameNextWake=(count<=1 or keepLast and frame==count) and math.huge or
            (frameClock-elapsed)+(math.floor(math.max(0,elapsed)/interval)+1)*interval
    end
    if e.judge_lane and tonumber(e.attrs.type or '1')==1 and judgeEvent then
        frame=math.max(1,math.min(count,judgeEvent.grade))
    end
    if (lane and descriptor.hitPrefix) or e.judge_lane or descriptor.timing then
        if elapsed>=count*interval and not heldHit and mode~='+' and not keepLast then enabled=false end
    end
    if pressLane and state=='2' and elapsed>=count*interval and mode~='+' and not keepLast then enabled=false end
    if e.judge_lane and tonumber(e.attrs.type or '1')==1 and judgeEvent then enabled=elapsed<320 end
    if not enabled and not e.number and not e.fill and not e.bitmap_font and
       #(PROFILE.motions[e.motion] or {})==0 then
        -- Invisible event sprites without attached actions have no visible
        -- transform/UV work. Re-evaluate their event and clock above on every
        -- Update; refresh all geometry before their next visible frame.
        if not e._eventDormant then
            e._drawVisible=e._drawVisible or {}
            for _,handles in pairs(e.handles) do for _,key in ipairs(handles) do
                if objects[key] then UnityBridge.AlphaByte(objects[key],0);e._drawVisible[key]=false end
            end end
            e._eventDormant=true
            e._eventFrame=nil
        end
        e._dormantEvent=eventSource;e._dormantTime=t
        return
    end
    e._eventDormant=false
    local eventVisual=not e.judge_lane and not e.number and not e.fill and not e.bitmap_font and
        (pressLane or descriptor.hitPrefix) and #(PROFILE.motions[e.motion] or {})==0
    local eventViewWidth=eventVisual and (frameWidth or Game:Width())
    if eventVisual and e._eventFrame==frame and e._eventState==state and
       e._eventViewWidth==eventViewWidth and e._eventFactor==factor and
       e._eventDrawRevision==visualRevision and e._drawVisible then return end
    local x,y,w,h=entryLayout(e)
    local fillTarget
    if e.fill then
        e._fillImage=e._fillImage or objects[e.value_handle].image
        fillTarget=e._fillImage.fillAmount
        if PROFILE.native_ui_schedule_candidate and e._fill and e._fill.value==fillTarget and
           settledLayout(e,t) and e._fillLayoutVisible==enabled and
           e._fillLayoutState==state and e._fillLayoutFrame==frame then
            -- Keep the slew clock current even when its target and geometry
            -- are unchanged. A later HP change uses the latest frame delta.
            e._fill.time=t;e._settledLayout.time=t;e._animation.time=math.modf(t)
            return
        end
    end
    local alpha,rotate,skewX,skewY
    x,y,w,h,alpha,rotate,skewX,skewY=animate(e,x,y,w,h,t)
    if e.judge_lane and tonumber(e.attrs.type or '1')==1 and judgeEvent then
        local p=UnityBridge.Float(math.min(1,math.max(0,elapsed)/160))
        local initial=UnityBridge.Float(1.15)
        local scale=UnityBridge.Float((1-initial)*p+initial)
        w,h=w*scale,h*scale
        alpha=255*(1-UnityBridge.Float(math.min(1,math.max(0,elapsed-160)/160)))
        enabled=elapsed<320
    end
    if e.number then updateNumber(e,x,y,alpha,rotate,t,skewX,skewY);return end
    local fill
    if e.fill then
        local target=fillTarget
        local previous=e._fill or {value=0,time=t}
        if target~=previous.value then
            local step=UnityBridge.Float(UnityBridge.Float(UnityBridge.Float(math.max(0,t-previous.time)/1000)*1000)/2500)
            if target>previous.value then previous.value=math.min(target,UnityBridge.Float(previous.value+step))
            elseif target<previous.value then previous.value=math.max(target,UnityBridge.Float(previous.value-step)) end
        end
        previous.time=t;e._fill=previous;fill=previous.value
        -- Actual ProgressBarLine is a parent Node plus a child Sprite with
        -- cascade color/opacity disabled. Parent fade/tint does not reach the
        -- fill child, although its transform and visibility still do.
        alpha=255
    end
    e._drawVisible=e._drawVisible or {}
    if e.bitmap_font and e._staticEligible then e._staticBitmapRows={} end
    for bankid,handles in pairs(e.handles) do
        for index,key in ipairs(handles) do
            local obj=objects[key]
            if obj then
                local visible=enabled and bankid==state and (e.reuse_frames or index==frame)
                local texture=e.states[bankid] and e.states[bankid][e.reuse_frames and frame or index]
                if visible and e.reuse_frames and texture then
                    e._frameTextures=e._frameTextures or {}
                    if e._frameTextures[key]~=texture then
                        UnityBridge.SpriteFile(obj,texture.file,texture.alpha_encoding,e.legacy_blend,texture.sample_rect)
                        e._frameTextures[key]=texture
                    end
                end
                -- Hidden frame banks have no visible geometry to update.
                -- Keep the element's animation clock advancing above; fully
                -- refresh a frame before showing it again. Bitmap text owns
                -- additional meshes/cache state and keeps its full update.
                if visible or e.bitmap_font then
                    -- BitmapText owns the actual glyph meshes and their
                    -- alpha below. The disabled TMP only resolves variables;
                    -- recoloring it every frame rebuilds an unused visual.
                    if not e.bitmap_font then UnityBridge.AlphaByte(obj,visible and alpha or 0) end
                    local ww,hh
                    if not e.number and texture then
                        if e.autoplay_frames then
                            -- GenericFactory sizes the initial frame once.
                            -- SetDisplayFrame later changes Sprite content
                            -- size, retaining those initial X/Y scales.
                            local initial=assert(e.states['1'] and e.states['1'][1])
                            local iw,ih=dimensions(w,h,initial,true)
                            ww,hh=iw*texture.width/initial.width,ih*texture.height/initial.height
                        else ww,hh=dimensions(w,h,texture,true) end
                    end
                    if ww then applySkew(e,x,y,rotate,skewX,skewY,ww,hh) end
                    e._visuals=e._visuals or {};local previous=e._visuals[key]
                    if not previous or e._drawVisible[key]~=true or previous.x~=x or previous.y~=y or
                       previous.w~=ww or previous.h~=hh or previous.rotate~=rotate or previous.factor~=factor then
                        local nativeX,nativeY
                        if e.retained_text_plane and not PROFILE.native_canvas_text_candidate then
                            nativeX,nativeY=UnityBridge.OwnedTextPosition(obj,x*factor,y*factor)
                        end
                        if nativeX==nil then obj.X=x*factor;obj.Y=y*factor;obj.Rotate=rotate end
                        if ww then obj.Width=ww*factor;obj.Height=hh*factor end
                        e._visuals[key]={x=x,y=y,w=ww,h=hh,rotate=rotate,factor=factor}
                        if e.bitmap_font then
                            -- Retain the native setter/getter round trip,
                            -- including its float32 UI-unit rounding.
                            e._visuals[key].native_x=nativeX or obj.X;e._visuals[key].native_y=nativeY or obj.Y
                        end
                    end
                    e._drawFill=e._drawFill or {}
                    if fill and e._drawFill[key]~=fill then
                        UnityBridge.Fill(obj,fill,e.fill.reverse);e._drawFill[key]=fill
                    end
                    if e.bitmap_font then
                        local textAlpha=visible and alpha or 0
                        UnityBridge.BitmapText(obj,e,PROFILE.fonts[e.bitmap_font],textAlpha,e._visuals[key])
                        if e._staticEligible then
                            e._staticBitmapRows[#e._staticBitmapRows+1]={object=obj,alpha=textAlpha,visual=e._visuals[key]}
                        end
                    end
                elseif e._drawVisible[key]~=false then
                    UnityBridge.AlphaByte(obj,0)
                end
                e._drawVisible[key]=visible
            end
        end
    end
    if e._staticEligible then
        e._staticRevision=visualRevision;e._staticWidth=staticWidth;e._staticFactor=factor;e._staticTime=t
    end
    if eventVisual then
        e._eventFrame=frame;e._eventState=state;e._eventViewWidth=eventViewWidth
        e._eventFactor=factor;e._eventDrawRevision=visualRevision
    end
    if e.fill then
        retainSettledLayout(e,t)
        e._fillLayoutVisible=enabled;e._fillLayoutState=state;e._fillLayoutFrame=frame
    end
end
function CanPlay() return UnityBridge.Available() end
function OnProcessNote()
    chordTimes={}
    local groups={}
    for i=0,Chart:NoteCount()-1 do
        local note=Chart:NoteAt(i)
        if note.x>=1 and note.x<=PROFILE.keys and (note.type or 0)<17 then
            -- Native 0x4b6000 / 0x4c73e0 marks equal integer millisecond
            -- neighbours. Repeated notes in the same lane also count.
            local time=noteTime(note);groups[time]=(groups[time] or 0)+1
        end
    end
    for time,count in pairs(groups) do
        if count>1 then chordTimes[time]=true end
    end
end
function Init()
    -- Original InsertClone adds the attachment clock to relative time= tracks.
    -- Game.SystemTime is independent of chart speed, pause and rewinds.
    if PROFILE.has_system_motions then motionSystemEpoch=Game:SystemTime();motionSystemTime=0 end
    if PROFILE.native_math_module then UnityBridge.LoadNativeMath() end
    if UnityBridge.PrepareMeshUploads then UnityBridge.PrepareMeshUploads() end
    if NativeKeyJudge then NativeKeyJudge.Bind() end
    factor=Game:Height()/720
    if PROFILE.native_clock_candidate then
        local input=UnityBridge.LegacyClockInput(PROFILE.native_scroll_candidate)
        local timeline=not input.absolute and LegacyClock.Build(input.timepoints)
        legacyTimes={}
        for _,n in ipairs(input.notes) do
            legacyTimes[n.nid]={time=input.absolute and n.time or LegacyClock.Time(timeline,n.beat),
                endtime=input.absolute and n.endtime or LegacyClock.Time(timeline,n.endbeat),
                beat=LegacyClock.Beat(n.beat)}
        end
        OnProcessNote()
        if PROFILE.native_scroll_candidate then legacyScroll=LegacyScroll.Build(input);legacyScrollLayer=input.layer end
    end
    for _,e in ipairs(PROFILE.entries) do
        if e.reuse_frames then e._frameTextures={};UnityBridge.PrepareUIFrames(e) end
        for state,bank in pairs(e.handles) do
            for index,key in ipairs(bank) do
                local obj=Module:Find(key);objects[key]=obj
                UnityBridge.UISurface(obj,e.order,tonumber(e.attrs.blend or '0'),e)
                if e.bitmap_font and UnityBridge.PrepareTextReader then UnityBridge.PrepareTextReader(obj) end
                -- MusicBar's four projected parts retain their disabled
                -- source Graphic. Density bars are the actual UI renderer;
                -- absent bins must leave Canvas registration as well.
                if not e.bitmap_font then UnityBridge.OwnUIVisual(obj,not e.musicbar or index>4) end
                local texture=e.musicbar and e.musicbar.textures[math.min(index,4)] or e.number and e.number.glyphs[0] or e.states[state] and e.states[state][index]
                if e.musicbar and index>4 then texture=e.musicbar.body_texture end
                if texture then UnityBridge.SpriteFile(obj,texture.file,texture.alpha_encoding,e.legacy_blend,texture.sample_rect) end
                if texture and e.reuse_frames then e._frameTextures[key]=texture end
                -- Background factory 0x60eb10 calls Sprite::setRectFixed(true).
                -- Markers and the seek sprite retain the full atlas UV span.
                if e.musicbar and index==1 then UnityBridge.FixedImage(obj,texture) end
                local color=(e.fill or e.musicbar) and '#FFFFFF' or e.attrs.color
                if color and #color==7 then UnityBridge.Color(obj,tonumber(color:sub(2,3),16),tonumber(color:sub(4,5),16),tonumber(color:sub(6,7),16)) end
            end
        end
        if e.fixed_uv and not e.number and not e.fill then
            for state,bank in pairs(e.handles) do
                for i,key in ipairs(bank) do UnityBridge.FixedImage(objects[key],e.states[state][i]) end
            end
        end
        if e.strip then
            local _,_,width,height=geometry(e)
            local texture=e.states['1'][1]
            width,height=dimensions(width,height,texture,true)
            local scale=(PROFILE.ui_rounding_height or 720)/720
            local secondary
            if e.strip.secondary then
                local sw,sh=screen();local axis=e.strip.kind==1 or e.strip.kind==3
                secondary=scalar(e.strip.secondary[axis and 2 or 1],axis and sh or sw)*scale
            end
            for _,key in ipairs(e.handles['1']) do
                LegacyStrip.Prepare(objects[key],e.strip,texture,width*scale,height*scale,secondary)
            end
        end
        if e.value_handle then
            objects[e.value_handle]=Module:Find(e.value_handle)
            if e.number and UnityBridge.PrepareTextReader then UnityBridge.PrepareTextReader(objects[e.value_handle]) end
        end
        if e.number and UnityBridge.PrepareNumberGroup then UnityBridge.PrepareNumberGroup(e,objects) end
    end
    for grade,path in pairs(PROFILE.sounds) do audio[grade]=Audio:Load(path) end
    for _,region in ipairs(PROFILE.touches) do objects[region.handle]=Module:Find(region.handle) end
    -- Group.AddSprite may CREATE only while SkinScriptRuntime is Loading.
    -- Reserve the chart's bar sprites during Init, before that phase ends.
    for _,e in ipairs(PROFILE.entries) do
        if e.name=='bar' then prepareBars(e) elseif e.musicbar then prepareMusicbar(e) end
    end
    UnityBridge.FinalizeUIBatches()
    if PROFILE.native_lifetime_candidate then prepareLifetime() end
    if PROFILE.native_prelude_candidate and PROFILE.legacy_prelude_needed then legacyPrelude=UnityBridge.PreparePrelude(legacyTimes) end
    Update()
end
local function profilePhase(phases,name,start)
    local now=CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    phases[name]=phases[name]+(now-start)*1000
    return now
end
function Update()
    if PROFILE.native_instruction_profile_candidate then InstructionProfile.Begin(legacyLifetime) end
    -- Ordinary packages retain evidence counters, not two public clock
    -- reads per Update. Detailed durations belong to the explicit profiler.
    local profileStart=PROFILE.runtime_phase_profile and legacyLifetime and CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    local phaseTimes
    local phaseStart=profileStart
    if PROFILE.runtime_phase_profile and legacyLifetime then
        phaseTimes=legacyLifetime.update_profile.phases or {calls=0,ui_frames_ms=0,lifetime_ms=0,entries_ms=0,trace_touch_ms=0}
        legacyLifetime.update_profile.phases=phaseTimes;phaseTimes.calls=phaseTimes.calls+1
        if not phaseTimes.entries then
            phaseTimes.entries={}
            for i,e in ipairs(PROFILE.entries) do phaseTimes.entries[i]={name=e.name,
                kind=e.number and 'number' or e.bitmap_font and 'bitmap_text' or e.musicbar and 'musicbar' or e.name=='bar' and 'bar' or 'sprite',
                calls=0,total_ms=0,max_ms=0} end
        end
    end
    UnityBridge.UpdateUIFrames()
    if UnityBridge.BeginTextFrame then UnityBridge.BeginTextFrame() end
    if PROFILE.native_layer_order_candidate then LegacyLayers.Flush() end
    if phaseTimes then phaseStart=profilePhase(phaseTimes,'ui_frames_ms',phaseStart) end
    local t=Game:Time()
    if PROFILE.has_system_motions then motionSystemTime=math.modf(Game:SystemTime()-motionSystemEpoch) end
    local frameDelta=PROFILE.has_autoplay_frames and UnityBridge.FrameDeltaMilliseconds() or 0
    frameWidth=UnityBridge.FrameGLSize and UnityBridge.UIViewport.width or Game:Width();frameTime=t
    -- All retained draws in this Update share one sampled viewport. Source
    -- lane definitions are immutable here; cache their endpoints once per
    -- lane while keeping each note's progress, size and held state separate.
    if PROFILE.native_lifetime_candidate then
        -- Compiled note endpoints/sizes are immutable source definitions.
        -- Progress, held state and source scroll change every frame; this
        -- viewport-derived lane layout does not. Retry invalidates it below.
        if not retainedNoteLayouts or retainedNoteWidth~=frameWidth or retainedNoteFactor~=factor then
            retainedNoteLayouts={};retainedNoteWidth=frameWidth;retainedNoteFactor=factor
        end
        noteFrameLayouts=retainedNoteLayouts
    elseif PROFILE.native_note_layout_candidate then noteFrameLayouts={} end
    if legacyPrelude then t=legacyPrelude:Update(t) end
    if PROFILE.native_lifetime_candidate then updateLifetime(legacyLifetime,t) end
    updateHoldEnds(t)
    if phaseTimes then phaseStart=profilePhase(phaseTimes,'lifetime_ms',phaseStart) end
    local entries=PROFILE.entries
    local rebuildSchedule=false
    if PROFILE.native_ui_schedule_candidate then
        local clock=math.modf(t)
        local width=frameWidth or Game:Width()
        rebuildSchedule=not uiSchedule or uiSchedule.entries~=entries or uiSchedule.revision~=visualRevision or
            uiSchedule.width~=width or uiSchedule.factor~=factor or t<uiSchedule.time or
            clock>=uiSchedule.motion_wake or t>=uiSchedule.frame_wake
        if rebuildSchedule then
            uiSchedule={entries=entries,revision=visualRevision,width=width,factor=factor,time=t,
                live={},bitmaps={},motion_wake=math.huge,frame_wake=math.huge}
        else
            entries=uiSchedule.live;uiSchedule.time=t
            -- Native variables can change independently of hit/input events.
            -- Retain their text/dirty checks even while geometry sleeps.
            for _,entry in ipairs(uiSchedule.bitmaps) do
                for _,row in ipairs(entry._staticBitmapRows or {}) do
                    UnityBridge.BitmapText(row.object,entry,PROFILE.fonts[entry.bitmap_font],row.alpha,row.visual)
                end
            end
        end
    end
    for index,entry in ipairs(entries) do
        local entryStarted=phaseTimes and CS.UnityEngine.Time.realtimeSinceStartupAsDouble
        if entry.name=='bar' then updateBars(entry,t) elseif entry.musicbar then updateMusicbar(entry,t) else updateEntry(entry,t,frameDelta) end
        if entryStarted then
            local elapsed=(CS.UnityEngine.Time.realtimeSinceStartupAsDouble-entryStarted)*1000
            local measured=phaseTimes.entries[entry._profileIndex or index];measured.calls=measured.calls+1
            measured.total_ms=measured.total_ms+elapsed;measured.max_ms=math.max(measured.max_ms,elapsed)
        end
        if rebuildSchedule then
            entry._profileIndex=index
            local motionWake=entry._animation and entry._animation.nextWake
            local frameWake=entry._frameNextWake
            -- Autoplay frame clocks are independent of chart time. Keep
            -- those entries live, including while gameplay is paused.
            if entry._staticEligible and not entry.autoplay_frames and motionWake and frameWake and
               math.modf(t)<motionWake and t<frameWake then
                uiSchedule.motion_wake=math.min(uiSchedule.motion_wake,motionWake)
                uiSchedule.frame_wake=math.min(uiSchedule.frame_wake,frameWake)
                if entry.bitmap_font then uiSchedule.bitmaps[#uiSchedule.bitmaps+1]=entry end
            else uiSchedule.live[#uiSchedule.live+1]=entry end
        elseif PROFILE.native_ui_schedule_candidate and entry._staticEligible and not entry.autoplay_frames and
               entry._animation and entry._animation.nextWake and entry._frameNextWake and
               math.modf(t)<entry._animation.nextWake and t<entry._frameNextWake then
            -- A live animation/frame sequence may have just settled. Rebuild
            -- once on the next Update instead of retaining it in the live set.
            uiSchedule.time=math.huge
        end
    end
    if phaseTimes then phaseStart=profilePhase(phaseTimes,'entries_ms',phaseStart) end
    if PROFILE.native_lifetime_candidate then
        -- This readback list is not the bar renderer's active queue. Traverse
        -- only actual bar factories, not every picture/text/input component.
        local entries=legacyLifetime.bar_entries
        if entries and #entries>0 then
          legacyLifetime.bars={}
          for _,entry in ipairs(entries) do
            for _,bar in ipairs(entry._barLifetimeActive or {}) do
                legacyLifetime.bars[#legacyLifetime.bars+1]={offset=bar.offset,display_y=bar.displayY,
                    progress=1-UnityBridge.Float((bar.displayY-legacyLifetime.display_y)/legacyLifetime.distance)}
            end
          end
        end
    end
    local sw,sh=screen()
    for _,region in ipairs(PROFILE.touches) do
        if region.width~=sw then
            local obj=objects[region.handle];local points={}
            obj.X=sw/2*factor;obj.Y=sh/2*factor;obj.Width=sw*factor;obj.Height=sh*factor
            for i,p in ipairs(region.points) do points[i]={(axis(p[1],sw)-sw/2)*factor,(axis(p[2],sh)-sh/2)*factor} end
            UnityBridge.TouchPolygon(obj,points,region.lane);region.width=sw
        end
    end
    if phaseTimes then phaseStart=profilePhase(phaseTimes,'trace_touch_ms',phaseStart) end
    if legacyLifetime then
        local stats=legacyLifetime.update_profile
        stats.native_submissions=UnityBridge.NotePerformance
        stats.retained_text=UnityBridge.RetainedTextPerformance
        stats.calls=stats.calls+1
        local active=#(legacyLifetime.active or {})>0
        if active then stats.active_calls=stats.active_calls+1 end
        if profileStart then
            local elapsed=(CS.UnityEngine.Time.realtimeSinceStartupAsDouble-profileStart)*1000
            stats.total_ms=stats.total_ms+elapsed;stats.max_ms=math.max(stats.max_ms,elapsed)
            if active then stats.active_total_ms=stats.active_total_ms+elapsed end
        end
    end
    frameWidth=nil;frameTime=nil;UnityBridge.FrameGLSize=nil
    noteFrameLayouts=nil
    if PROFILE.native_instruction_profile_candidate then InstructionProfile.End() end
end
function OnRetry()
    UnityBridge.InvalidateUIVisuals()
    uiSchedule=nil
    visualRevision=visualRevision+1
    pressed={};hits={};noteStates={};pressEvents={};heldNotesByLane={};pendingHoldEnds={}
    retainedNoteLayouts=nil
    if legacyPrelude then legacyPrelude:Reset();legacyPrelude=UnityBridge.PreparePrelude(legacyTimes) end
    if PROFILE.native_lifetime_candidate and legacyLifetime then resetLifetime() end
    for _,e in ipairs(PROFILE.entries) do
        e._animation=nil;e._judgeFrozen=nil;e._fill=nil;e._number=nil;e._combo=nil;e._drawVisible=nil;e._nativePosition=nil;e._settledLayout=nil
        e._numberVisual=nil;e._numberPlan=nil;e._sourceText=nil;e._sourceNumber=nil;e._fillImage=nil;e._visuals=nil;e._drawFill=nil
        e._eventDormant=nil;e._glyphCount=nil;e._glyphVisuals=nil
        e._frameTextures=nil;e._formattedValue=nil;e._formattedText=nil;e._frameNextWake=nil
        if e._barProvider then e._barProvider.list=nil end
        if e.musicbar then prepareMusicbar(e) end
        for _,object in ipairs(e._barPool or {}) do UnityBridge.AlphaByte(object,0) end
        if e.number then
            local color=e.attrs.color or '#FFFFFF'
            local r,g,b=tonumber(color:sub(2,3),16),tonumber(color:sub(4,5),16),tonumber(color:sub(6,7),16)
            for _,key in ipairs(e.handles.glyphs) do UnityBridge.Color(objects[key],r,g,b) end
        end
    end
    Update()
end
function OnInput()
    visualRevision=visualRevision+1
    local event=Game:InputEvent()
    local lane=event:HitX()
    if event:Type()==1 then
        if not pressed[lane] then pressEvents[lane]={time=Game:Time(),state='1'} end
        pressed[lane]=true
    elseif event:Type()==3 then
        local time=Game:Time()
        pressed[lane]=false
        pressEvents[lane]={time=time,state='2'}
        releaseHit(lane,time)
        local held=heldNotesByLane[lane]
        for nid,state in pairs(held or {}) do
            if state.held then
                state._drawEpoch=nil
                if state.endtime and time>=state.endtime then playEnd(state) end
                -- A successful tail release may arrive before the last draw
                -- update. Keep the old Part3 contraction alive until its head
                -- reaches the tail; an early release still resumes scrolling.
                if state.endtime and time>=state.endtime then state.tailCommitted=true
                else state.held=false end
            end
            held[nid]=nil;pendingHoldEnds[nid]=nil
        end
    end
end
function OnHit()
    visualRevision=visualRevision+1
    local event=Game:HitEvent()
    local judgementTime=event:Time()
    local result=event:JudgeResult()
    local lane=event:HitX()
    local t=Game:Time()
    local note=event:NoteInfoEx()
    local headTime,endTime
    if note then headTime,endTime=noteTime(note) end
    local tailEvent=note and endTime>headTime and judgementTime>=endTime
    if note and result>=1 and result<=4 then
        for _,entry in ipairs(PROFILE.entries) do if entry.musicbar then judgeMusicbar(entry,headTime,result) end end
    end
    if note then
        local state=noteStates[note.nid] or {lane=note.x,fraction=0};noteStates[note.nid]=state
        state._drawEpoch=nil
        state.hit=true
        if endTime>headTime then
            state.hit_callback_time=t;state.hit_event_time=event:Time();state.hit_offset=event:Offset()
            if not state.firstHitTime then
                state.firstHitTime=t;state.firstHitEventTime=event:Time();state.firstHitOffset=event:Offset();state.firstHitResult=result
            end
            state.endtime=endTime
            if judgementTime<endTime and result>=1 and result<=3 then state.grade=result end
            if judgementTime>=endTime and result~=4 and state.held then playEnd(state) end
            if result~=4 and judgementTime>=endTime and state.held then state.tailCommitted=true
            else state.held=(result~=4 and judgementTime<endTime) end
            heldNotesByLane[lane]=heldNotesByLane[lane] or {}
            if state.held and not state.tailCommitted then
                heldNotesByLane[lane][note.nid]=state;pendingHoldEnds[note.nid]=state
            else
                heldNotesByLane[lane][note.nid]=nil;pendingHoldEnds[note.nid]=nil
            end
            if PROFILE.native_scroll_candidate and state.held and state.holdOffset==nil then
                local original=legacyScroll.notes[note.nid]
                state.holdHeadY=state.holdHeadY or original.display_y
                -- The old input callback precedes that frame's Part3 move.
                -- maV can call us after Update; sample at the actual hit
                -- callback now instead of waiting an additional draw frame.
                state.holdOffset=UnityBridge.Float(state.holdHeadY-LegacyScroll.CurrentY(legacyScroll,judgementTime))
            end
        end
    end
    if result>=1 and result<=3 and not tailEvent then
        hits[lane]={time=t,state=event:NoteType()==2 and '2' or '1',nid=note and note.nid}
    elseif tailEvent then releaseHit(lane,t,note.nid) end
    if result>=1 and result<=4 then
        -- Original KeyUIS dispatches these judge widgets on the head/tap
        -- callback. A maV hold-tail callback must not restart that effect.
        if not tailEvent then
            local judgement={time=t,grade=result}
            hits.judge=judgement;hits['judge-'..lane]=judgement
            for _,entry in ipairs(PROFILE.entries) do
                if entry.judge_lane and (globalJudge or entry.judge_lane==lane) and
                   tonumber(entry.attrs.type or '1')==1 and
                   result<=#(entry.states and entry.states['1'] or {}) then
                    stopStaticJudgeMotion(entry)
                end
            end
        end
        if result==2 or result==3 then
            if event:Offset()>0 then hits['hit-fast']={time=t} else hits['hit-slow']={time=t} end
        end
        local grade=({'best','cool','good','miss'})[result]
        if result~=4 and not tailEvent and audio[grade] then Audio:Play(audio[grade],100) end
    end
end
local function noteVisual(mod,key,texture,grid)
    if not texture then return nil end
    if grid then
        local obj=mod:AddGrid(key,texture.file,'');UnityBridge.NoteGrid(obj,texture.file);return obj
    end
    local obj=mod:AddSprite(key,texture.file,'')
    UnityBridge.NoteSprite(obj,texture.file)
    return obj
end
function OnDrawNote(note)
    local e=PROFILE.notes[note.x]
    if not e then return end
    local isHold=note.endtime>note.time
    local typeName='legacy_lane_'..tostring(note.x)..(isHold and '_hold' or '_tap')
    local poolPlan=PROFILE.native_note_pool_candidate and LegacyLayers.BeforeCheckout(typeName)
    local mod=lifetimeModule or Note:GetNoteModule(typeName,'')
    if not mod then error('Ma Skin Bridge: GetNoteModule failed') end
    -- Keep maV's native carrier, input and judge active, but use separately
    -- retained public visual groups for old admission/retirement semantics.
    if PROFILE.native_lifetime_candidate and not lifetimeModule then return end
    if poolPlan then LegacyLayers.AfterCheckout(mod,poolPlan) end
    local headTexture=isHold and (e.states['5'] or e.states['1']) or e.states['1']
    local baseTexture=headTexture
    if chordTimes[noteTime(note)] and e.states['4'] then headTexture=e.states['4'] end
    noteVisual(mod,'head',headTexture and headTexture[1])
    if isHold then
        local texture=e.states['2'] and e.states['2'][1]
        if texture and texture.tiles then
            for index,tile in ipairs(texture.tiles) do
                local child=noteVisual(mod,'body-'..index,tile,true)
                if not PROFILE.native_layer_order_candidate then child.Order=e.order end
            end
        else noteVisual(mod,'body',texture,true) end
        local tailTexture=e.states['3'] or baseTexture
        noteVisual(mod,'tail',tailTexture and tailTexture[1])
    end
    if lifetimeModule then
        local children={}
        for _,name in ipairs({'head','body','tail'}) do children[name]=mod:GetChild(name) end
        local bodyTexture=e.states['2'] and e.states['2'][1]
        for i in ipairs(bodyTexture and bodyTexture.tiles or {}) do
            local name='body-'..i;children[name]=mod:GetChild(name)
        end
        ownedNoteChildren[mod]=children
    end
    for role,offset in pairs({body=0,tail=1,held=2,head=3}) do
        local child=mod:GetChild(role)
        if child then
            if not PROFILE.native_layer_order_candidate then child.Order=e.order+offset end
            -- Original Part3's ShapeSprite uploads its separate float RGBA
            -- array (all ones). ApplyAttributes changes the inherited Node
            -- tint/opacity, which this custom draw never reads.
            local color=role=='body' and '#FFFFFF' or e.attrs.color
            if color and #color==7 then UnityBridge.Color(child,tonumber(color:sub(2,3),16),tonumber(color:sub(4,5),16),tonumber(color:sub(6,7),16)) end
        end
    end
    if PROFILE.native_layer_order_candidate and not lifetimeModule then LegacyLayers.Note(mod,e) end
end
local function place(obj,x,y,w,h,texture,anchor,rotate,alpha)
    if not obj or not texture then return end
    w,h=dimensions(w,h,texture)
    local coefficients=(PROFILE.native_lifetime_candidate or PROFILE.native_note_layout_candidate) and rotationCoefficients(anchor,rotate)
    local ax=coefficients and coefficients.ax or (anchor%3)*0.5
    local ay=coefficients and coefficients.ay or 1-math.floor(anchor/3)*0.5
    local ox,oy=(0.5-ax)*w,(0.5-ay)*h
    local rad=-rotate*math.pi/180
    local cos,sin=coefficients and coefficients.cos or math.cos(rad),coefficients and coefficients.sin or math.sin(rad)
    local dx,dy=ox*cos-oy*sin,ox*sin+oy*cos
    local sw=screen()
    UnityBridge.NoteGeometry(obj,(x+dx-sw/2)*factor,(y+dy-360)*factor,w*factor,h*factor,rotate)
    UnityBridge.AlphaByte(obj,UnityBridge.BytePercent(alpha))
end
prepareMusicbar=function(e)
    local f=UnityBridge.Float
    local _,_,w,h=geometry(e);local scale=(PROFILE.ui_rounding_height or 720)/720
    w,h=f(w*scale),f(h*scale)
    local spec=e.musicbar;local a,b=spec.textures[2],spec.textures[3]
    local marker=f(h*.6)
    local left=f(a.width*f(marker/a.height));local right=f(b.width*f(marker/b.height))
    local available=f(f(f(w-left)-right)-40)
    assert(available>0,'Ma Skin Bridge: musicbar native markers exceed width')
    local state={width=w,height=h,left=left,right=right,marker=marker,available=available,
        cursor=f(available/100),bodyX=f(f(w-available)*.5),bodyY=f(h*.2),scale=scale,
        totals={},judged={},flags={},colors={},color_dirty={}}
    for i=1,spec.count do state.totals[i]=0;state.judged[i]=0;state.flags[i]=0;state.colors[i]={102,102,102} end
    local count=Chart:NoteCount();local first,last,lastBeat
    for i=0,count-1 do
        local note=Chart:NoteAt(i)
        if note.x>=1 and note.x<=PROFILE.keys and (note.type or 0)<17 then
            local time,finish=noteTime(note);local source=legacyTimes[note.nid]
            local beat=source and source.beat or note.time
            first=first and math.min(first,time) or time
            if lastBeat==nil or beat>=lastBeat then
                lastBeat=beat;last=PROFILE.native_clock_candidate and finish or time
            end
        end
    end
    state.start=first or 0;state.finish=math.max(state.start+1,last or 0)
    state.step=f((state.finish-state.start)/spec.count)
    for i=0,count-1 do
        local note=Chart:NoteAt(i)
        if note.x>=1 and note.x<=PROFILE.keys and (note.type or 0)<17 then
            local time=noteTime(note);local bin=math.floor(f(f(time-state.start)/state.step))+1
            if bin>=1 and bin<=spec.count then state.totals[bin]=math.min(100,state.totals[bin]+1) end
        end
    end
    e._musicbar=state
    -- Native MusicBarSprite adds its seek sprite at local z=2, after the body.
    objects[e.handles.musicbar[4]].transform:SetAsLastSibling()
end
judgeMusicbar=function(e,time,result)
    local s=e._musicbar;if not s then return end
    local f=UnityBridge.Float;local bin=math.floor(f(f(time-s.start)/s.step))+1
    if bin<1 or bin>e.musicbar.count then return end
    local flag=({8,4,2,16})[result]
    -- Original Key UIS 0x5adc90 includes the base callback inline and calls
    -- MusicBarBody::AddResult twice. Keep this visible, gated candidate rather
    -- than silently assuming one callback means one legacy accumulation.
    for _=1,2 do
        s.flags[bin]=s.flags[bin]|flag;s.judged[bin]=(s.judged[bin]+1)&255
        if s.judged[bin]==s.totals[bin] then
            local flags=s.flags[bin]
            s.colors[bin]=(flags&16)~=0 and {102,102,102} or (flags&8)~=0 and {47,186,141} or (flags&4)~=0 and {244,208,85} or {238,102,102}
            s.color_dirty[bin]=true
        end
    end
end
local function musicbarPhase(e,name,started)
    if not started then return end
    local now=CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    local phases=legacyLifetime.update_profile.phases
    local key='musicbar/'..name
    local row=phases[key]
    if not row then
        row={name=e.name..'/'..name,kind='musicbar_section',calls=0,total_ms=0,max_ms=0}
        phases[key]=row;phases.entries[#phases.entries+1]=row
    end
    local elapsed=(now-started)*1000
    row.calls=row.calls+1;row.total_ms=row.total_ms+elapsed;row.max_ms=math.max(row.max_ms,elapsed)
    return now
end
updateMusicbar=function(e,t)
    local s=e._musicbar;if not s then return end
    local measured=PROFILE.runtime_phase_profile and legacyLifetime and legacyLifetime.update_profile.phases and CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    local f=UnityBridge.Float;local x,y,w,h=geometry(e)
    local alpha,rotate;x,y,w,h,alpha,rotate=animate(e,x,y,w,h,t)
    x,y=legacyRound(x),legacyRound(y)
    local view=UnityBridge.MusicbarFrame and UnityBridge.MusicbarFrame()
    local viewportWidth,viewportHeight=view and view.width or Game:Width(),view and view.height or Game:Height()
    measured=musicbarPhase(e,'context',measured)
    local old=s.render_context
    local layoutChanged=not old or old.x~=x or old.y~=y or old.w~=w or old.h~=h or old.rotate~=rotate or
        old.width~=viewportWidth or old.height~=viewportHeight or old.view_revision~=(view and view.revision)
    if layoutChanged then
        local r=-rotate*math.pi/180
        s.render_context={x=x,y=y,w=w,h=h,rotate=rotate,width=viewportWidth,height=viewportHeight,
            c=math.cos(r),sn=math.sin(r),ax=e.anchor%3/2,ay=1-math.floor(e.anchor/3)/2,view_revision=view and view.revision}
        if PROFILE.native_musicbar_geometry_candidate then
            s.native_root=LegacyMusicbarGeometry.Root(f(x*s.scale),f(y*s.scale),f(w*s.scale),f(h*s.scale),e.anchor,rotate)
        end
    end
    s.render_context.layoutChanged=layoutChanged;s.render_context.view=view
    s.render_parts=s.render_parts or {}
    measured=musicbarPhase(e,'layout',measured)
    if not s.part then s.part=function(index,cx,cy,width,height,color,opacity)
        -- This retained closure reads the current context on every call.
        -- Do not capture one frame's geometry/camera or allocate closures,
        -- default colors and replacement part records on each cursor tick.
        local context=s.render_context
        local x,y,w,h,rotate=context.x,context.y,context.w,context.h,context.rotate
        local c,sn,ax,ay=context.c,context.sn,context.ax,context.ay
        local viewportWidth,viewportHeight=context.width,context.height
        local layoutChanged,view,nativeRoot=context.layoutChanged,context.view,s.native_root
        local f=UnityBridge.Float
        local object=objects[e.handles.musicbar[index]]
        local red,green,blue=table.unpack(color or musicbarWhite);opacity=opacity or 255
        local previous=s.render_parts[index]
        local geometryChanged=layoutChanged or not previous or previous.cx~=cx or previous.cy~=cy or previous.w~=width or previous.h~=height
        local colorChanged=not previous or previous.r~=red or previous.g~=green or previous.b~=blue
        local alphaChanged=not previous or previous.alpha~=opacity
        if not geometryChanged and not colorChanged and not alphaChanged then return end
        -- The projective mesh is the actual renderer for these four owned
        -- parts. Its disabled Image only supplies texture/color. Moving that
        -- unused RectTransform also dirties Canvas layout every frame.
        if geometryChanged and not (nativeRoot and index<=4) then
        local dx,dy=cx/s.scale-ax*w,cy/s.scale-ay*h
        local px,py=(x+dx*c-dy*sn)*factor,(y+dx*sn+dy*c)*factor
        local pw,ph=width/s.scale*factor,height/s.scale*factor
        local projection=PROFILE.native_ui_projection
        if projection then
            local p=projection.matrix;local unit=projection.logical_height/viewportHeight
            local ox,oy=f(px*unit),f(py*unit)
            px=(f(f(f(p[1]*ox)+p[13])/p[16])+1)*viewportWidth/2
            py=(f(f(f(p[6]*oy)+p[14])/p[16])+1)*viewportHeight/2
            pw=pw*p[1]*projection.logical_width/(2*p[16])
            ph=ph*p[6]*projection.logical_height/(2*p[16])
        end
        object.X=px;object.Y=py;object.Width=pw;object.Height=ph;object.Rotate=rotate
        end
        if colorChanged then UnityBridge.Color(object,red,green,blue) end
        -- Parent Node opacity/tint do not cascade to these native children.
        if alphaChanged or colorChanged then UnityBridge.AlphaByte(object,opacity) end
        if nativeRoot and index<=4 then
            local texture=e.musicbar.textures[index]
            s.native_parts=s.native_parts or {}
            local points,prepared=LegacyMusicbarGeometry.MovingQuad(nativeRoot,f(cx-width/2),f(cy-height/2),
                width,height,texture.width,texture.height,PROFILE.native_ui_projection,
                PROFILE.native_musicbar_clip_w_candidate,s.native_parts[index],view)
            s.native_parts[index]=prepared
            local part=(index==1 and -1 or index==4 and 2 or 1)+index/10000
            UnityBridge.MusicbarQuad(object,points,e.order+(index==1 and -1 or index==4 and 2 or 1),texture.native_uv,e,part,view,colorChanged or alphaChanged)
        end
        previous=previous or {};s.render_parts[index]=previous
        previous.cx,previous.cy,previous.w,previous.h=cx,cy,width,height
        previous.r,previous.g,previous.b,previous.alpha=red,green,blue,opacity
    end end
    local part=s.part
    part(1,s.width/2,s.height/2,s.width,s.height,nil,40)
    part(2,10+s.left/2,s.height/2,s.left,s.marker)
    part(3,s.width-10-s.right/2,s.height/2,s.right,s.marker)
    local time=math.max(s.start,math.min(s.finish,t))
    local cursor=f(f(f(f(s.available-s.cursor)*f(time-s.start))/f(s.finish-s.start))+s.bodyX)
    part(4,cursor+s.cursor/2,s.height/2,s.cursor,s.height)
    measured=musicbarPhase(e,'parts',measured)
    if not s.density_geometry then
        s.density_geometry={};s.render_colors={}
        local step=f(s.available/e.musicbar.count)
        for i=1,e.musicbar.count do
            local x0=f(f(f(step*.15)+f(step*(i-1)))-.5)
            local x1=f(f(f(step*.85)+f(step*(i-1)))+.5)
            local y1=f(f(s.marker*f(math.min(s.totals[i],10)/10))+.5)
            -- Nonempty DrawNode rectangles expand by half a logical pixel.
            -- Empty bins retain no drawable; density() excludes them below.
            s.density_geometry[i]={s.bodyX+(x0+x1)/2,s.bodyY+(y1-.5)/2,x1-x0,y1+.5}
        end
    end
    if not s.density then s.density=function(i)
        -- Original MusicBarBody::DrawBin (4.3.7 VA 0x4efaf5) returns
        -- before emitting any vertices when its density byte is zero.
        -- Expanding a zero-height rectangle invents a visible gray stripe.
        if s.totals[i]==0 then
            s.empty_density_hidden=s.empty_density_hidden or {}
            if not s.empty_density_hidden[i] then
                UnityBridge.AlphaByte(objects[e.handles.musicbar[i+4]],0)
                s.empty_density_hidden[i]=true
            end
            return
        end
        if s.render_context.layoutChanged or s.render_colors[i]~=s.colors[i] then
            local g=s.density_geometry[i]
            s.part(i+4,g[1],g[2],g[3],g[4],s.colors[i])
            s.render_colors[i]=s.colors[i]
        end
    end end
    local density=s.density
    -- Prepared state owns every color write, committed by judgeMusicbar.
    -- Layout/viewport changes still visit every bin. Hand-built older state
    -- without this dirty set keeps the complete reference scan.
    if layoutChanged or not s.color_dirty then
        for i=1,e.musicbar.count do density(i) end
        if s.color_dirty then for i in pairs(s.color_dirty) do s.color_dirty[i]=nil end end
    else
        for i in pairs(s.color_dirty) do density(i);s.color_dirty[i]=nil end
    end
    musicbarPhase(e,'density',measured)
end
prepareBars=function(e)
    e._barProvider=e._barProvider or UnityBridge.BarProvider()
    if PROFILE.legacy_play_plane and not e._barProvider.plane_prepared then
        UnityBridge.ProjectLifetimeGroup(e._barProvider.group);e._barProvider.plane_prepared=true
    end
    e._barPool=e._barPool or {}
    local bars=assert(UnityBridge.Bars(e._barProvider),'Ma Skin Bridge: native bars must be available during Init')
    local texture=e.states['1'] and e.states['1'][1]
    if not texture then return end
    for i=1,#bars do
        local object=e._barProvider.group:AddSprite('bar-'..i,texture.file,'')
        assert(object~=nil,'Ma Skin Bridge: native bar sprite must be created during skin loading')
        UnityBridge.NoteSprite(object,texture.file);object.Order=e.order
        if PROFILE.native_layer_order_candidate then LegacyLayers.Bar(object,e,i) end
        object.gameObject.layer=CS.UnityEngine.LayerMask.NameToLayer('Note')
        local color=e.attrs.color or '#FFFFFF'
        UnityBridge.Color(object,tonumber(color:sub(2,3),16),tonumber(color:sub(4,5),16),tonumber(color:sub(6,7),16))
        UnityBridge.AlphaByte(object,0);e._barPool[i]=object
    end
end
updateBars=function(e,t)
    -- Keep the schema template available to the loader, but never show it as
    -- a stationary bar. Each actual native bar has its own fractional timing.
    for _,bank in pairs(e.handles) do for _,key in ipairs(bank) do UnityBridge.AlphaByte(objects[key],0) end end
    e._barProvider=e._barProvider or UnityBridge.BarProvider()
    e._barPool=e._barPool or {}
    local bars=UnityBridge.Bars(e._barProvider)
    if bars==nil then
        assert(t<0,'Ma Skin Bridge: native bar list is not ready during play')
        for i=1,e._barDrawCount or 0 do UnityBridge.AlphaByte(e._barPool[i],0) end
        e._barDrawCount=0
        return
    end
    local sw,sh=screen();local sx,sy,w,h=geometry(e)
    local finish=e.pos2
    local ex,ey=axis(finish[1],sw),axis(finish[2],sh)
    local sizeEnd=e.attrs.size2 and e.size2 or e.size
    local ew,eh=axis(sizeEnd[1],sw),axis(sizeEnd[2],sh)
    local texture=e.states['1'] and e.states['1'][1]
    if not texture then return end
    local count=0
    local visible=bars
    if PROFILE.native_lifetime_candidate then
        e._barLifetime=e._barLifetime or LegacyLifetime.NewBars(bars)
        visible=LegacyLifetime.StepBars(e._barLifetime,t,legacyLifetime.display_y,legacyLifetime.distance)
        e._barLifetimeActive=visible
    end
    for _,bar in ipairs(visible) do
        local p=PROFILE.native_lifetime_candidate and
            1-UnityBridge.Float((bar.displayY-legacyLifetime.display_y)/legacyLifetime.distance) or UnityBridge.BarProgress(e._barProvider,bar)
        if p>=0 then
            local x,y=sx+(ex-sx)*p,sy+(ey-sy)*p
            local ww,hh=dimensions(w+(ew-w)*p,h+(eh-h)*p,texture)
            -- A conservative bounding circle around the declared anchor can
            -- reject only entirely offscreen sprites, at any rotation/pivot.
            -- Do not grow a new sprite for every bar already behind the view.
            local radius=math.sqrt(ww*ww+hh*hh)
            if PROFILE.legacy_play_plane or x+radius>=0 and x-radius<=sw and y+radius>=0 and y-radius<=sh then
            count=count+1;local object=e._barPool[count]
            assert(object~=nil,'Ma Skin Bridge: native bar list exceeds the pool reserved during Init')
            place(object,x,y,ww,hh,texture,e.anchor,e.rotate,e.opacity)
            end
        end
    end
    -- Slots are indexed by the current visible traversal. Keep unchanged
    -- sprites visible; only shortened tails leave traversal. Hiding and
    -- restoring every reserved bar dirties native colors twice per frame.
    for i=count+1,e._barDrawCount or 0 do UnityBridge.AlphaByte(e._barPool[i],0) end
    e._barDrawCount=count
end
local function center(x,y,w,h,anchor,rotate)
    if PROFILE.native_lifetime_candidate or PROFILE.native_note_layout_candidate then
        local c=rotationCoefficients(anchor,rotate)
        local ox,oy=(.5-c.ax)*w,(.5-c.ay)*h
        return x+ox*c.cos-oy*c.sin,y+ox*c.sin+oy*c.cos
    end
    local ax=(anchor%3)*0.5
    local ay=1-math.floor(anchor/3)*0.5
    local ox,oy=(0.5-ax)*w,(0.5-ay)*h
    local r=-rotate*math.pi/180
    return x+ox*math.cos(r)-oy*math.sin(r),y+ox*math.sin(r)+oy*math.cos(r)
end
local function bodyGeometry(body,points,sw,hidden,rect,weights)
    -- The owned mesh path normally needs no Lua SetVertex calls. Keep the
    -- fallback inline instead of allocating two closures for every LN tick.
    if not UnityBridge.RectangleBody(body,points,sw,factor,rect~=nil) and
       not UnityBridge.OwnedGridQuad(body,points,sw,factor,rect,weights) then
        for i,p in ipairs(points) do body:SetVertex(i-1,(p[1]-sw/2)*factor,(p[2]-360)*factor) end
        UnityBridge.LegacyGridUV(body,points,rect,weights)
    end
    UnityBridge.AlphaByte(body,hidden and 0 or 255)
end
function OnNoteMove(note,mod,percent)
    if PROFILE.native_lifetime_candidate and not lifetimeDrawing then return end
    local e=PROFILE.notes[note.x]
    if not e then return end
    -- Lifetime groups are initialized in Loading and registered at admission.
    -- Their movement setters do not reset Order; Update flushes the registry
    -- once. Native carrier modules still need the checkout/reset path.
    if PROFILE.native_layer_order_candidate and not PROFILE.native_lifetime_candidate then LegacyLayers.Note(mod,e) end
    local layout=noteFrameLayouts and noteFrameLayouts[e]
    local sw,sh,sx,sy,w,h,ex,ey,ew,eh
    if layout then
        sw,sh,sx,sy,w,h,ex,ey,ew,eh=table.unpack(layout)
    else
        sw,sh=screen();sx,sy,w,h=geometry(e)
        ex,ey=axis(e['end'][1],sw),axis(e['end'][2],sh)
        ew,eh=axis(e.size2[1],sw),axis(e.size2[2],sh)
        if UnityBridge.ResolveNoteDimensions then w,h,ew,eh=UnityBridge.ResolveNoteDimensions(e,sw,sh) end
        if noteFrameLayouts then noteFrameLayouts[e]={sw,sh,sx,sy,w,h,ex,ey,ew,eh} end
    end
    local p=percent[0]
    local state=noteStates[note.nid] or {lane=note.x,fraction=0};noteStates[note.nid]=state
    local toggle=tonumber(e.attrs.toggle or '0') or 0
    -- Expressions are already parsed safely by the compiler into the numeric mask.
    toggle=e.toggle or toggle
    local isHold=note.endtime>note.time
    local q=percent.Length>1 and percent[1] or p
    if PROFILE.native_scroll_candidate then
        local time=frameTime or Game:Time();local distance=PROFILE.native_lifetime_candidate and legacyLifetime.distance or UnityBridge.ScrollDistance(legacyScrollLayer)
        if PROFILE.native_lifetime_candidate then
            local original=legacyScroll.notes[note.nid];local y=legacyLifetime.display_y
            p,q=1-UnityBridge.Float((original.display_y-y)/distance),1-UnityBridge.Float((original.end_y-y)/distance)
        else p,q=LegacyScroll.Progress(legacyScroll,note.nid,time,distance) end
        local progress=state.legacyProgress or {};state.legacyProgress=progress
        progress.time,progress.head,progress.tail,progress.distance=time,p,q,distance
    end
    local gap=p-q
    local v
    if isHold and PROFILE.native_scroll_candidate then
        local original=legacyScroll.notes[note.nid]
        local current=PROFILE.native_lifetime_candidate and legacyLifetime.display_y or LegacyScroll.CurrentY(legacyScroll,Game:Time())
        state.holdHeadY=state.holdHeadY or original.display_y
        if state.held and (toggle & 2)~=0 then
            -- Original Part3 uses the double constant 0.0001 after taking
            -- fabs of its retained float32 distance (0x4f15b0..0x4f15e1).
            if state.holdOffset==nil or math.abs(state.holdOffset)<0.0001 then
                state.holdOffset=UnityBridge.Float(state.holdHeadY-current)
            end
            state.holdHeadY=current+state.holdOffset
            if state.holdHeadY>=original.end_y then state.holdHeadY=original.end_y;state.finished=true end
        end
        local distance=state.legacyProgress.distance
        v=1-UnityBridge.Float((state.holdHeadY-current)/distance)
        -- Part3 places a future head at its original start, but allows the
        -- hit end to overshoot. Do not clamp the tail to the hit circle.
        v=math.max(0,v)
    elseif isHold and state.held and (toggle & 2)~=0 and math.abs(gap)>1e-12 then
        if state.offset==nil or math.abs(state.offset)<1e-12 then
            state.offset=(1-p+state.fraction*gap)/gap
        end
        state.fraction=(p-1+state.offset*gap)/gap
        if state.fraction>=1 then state.fraction=1;state.finished=true end
    end
    v=v or math.max(0,p-state.fraction*gap)
    local hidden=(toggle & 1)~=0 and ((isHold and state.finished) or (not isHold and state.hit))
    if PROFILE.native_scroll_candidate and isHold then
        hidden=hidden or LegacyScroll.Hide(legacyScroll.notes[note.nid],toggle)
        state.legacyProgress.hold_hidden=hidden
    end
    local x,y=sx+(ex-sx)*v,sy+(ey-sy)*v
    local ww,hh=w+(ew-w)*v,h+(eh-h)*v
    if state.legacyProgress then
        state.legacyProgress.visual_hidden=not not hidden
        local geometry=state.legacyProgress.head_geometry or {};state.legacyProgress.head_geometry=geometry
        geometry.x,geometry.y,geometry.width,geometry.height=x,y,ww,hh
        state.legacyProgress.held=state.held or false
        state.legacyProgress.hold_toggle=toggle
        state.legacyProgress.hold_fraction=state.fraction
        state.legacyProgress.hold_offset=state.offset
        state.legacyProgress.hold_scroll_head=state.holdHeadY
        state.legacyProgress.hold_scroll_offset=state.holdOffset
        state.legacyProgress.finished=state.finished or false
        state.legacyProgress.hit_callback_time=state.hit_callback_time
        state.legacyProgress.hit_event_time=state.hit_event_time
        state.legacyProgress.hit_offset=state.hit_offset
        state.legacyProgress.first_hit_time=state.firstHitTime
        state.legacyProgress.first_hit_event_time=state.firstHitEventTime
        state.legacyProgress.first_hit_offset=state.firstHitOffset
        state.legacyProgress.first_hit_result=state.firstHitResult
    end
    if hidden and PROFILE.native_lifetime_candidate then
        state._drawEpoch=nil
        -- Retain logical progress/retirement and hit state above, but an
        -- invisible owned drawable does not need another mesh/UV upload.
        if state._hiddenModule~=mod then
            lifetimeHide(mod,e)
            -- Legacy setVisible(false) removes this drawable from traversal.
            -- Alpha zero alone still submits all its native render surfaces.
            -- This is our visual group; native judge/carrier objects are separate.
            mod.gameObject:SetActive(false);state._hiddenModule=mod
        end
        if isHold and state.legacyProgress then state.legacyProgress.tail_geometry=math.max(0,q) end
        return
    end
    if state._hiddenModule then mod.gameObject:SetActive(true) end
    state._hiddenModule=nil
    local motion=PROFILE.native_lifetime_candidate and legacyLifetime.lane_motions and legacyLifetime.lane_motions[note.x]
    local offsetX,offsetY=motion and motion.offset_x or 0,motion and motion.offset_y or 0
    local capped=state.finished and PROFILE.native_lifetime_candidate and isHold and
        state.holdHeadY==legacyScroll.notes[note.nid].end_y and
        legacyLifetime.display_y+(state.holdOffset or 0)>=legacyScroll.notes[note.nid].end_y
    local reusable=motion and p>=0 and (not isHold or q>=0) and not (state.held and (toggle & 2)~=0 and not capped)
    local drawNeeded=not reusable or state._drawEpoch~=motion.epoch
    if not drawNeeded then UnityBridge.NotePerformance.lane_static_skips=UnityBridge.NotePerformance.lane_static_skips+1 end
    local rotate=e.rotate
    local head=drawNeeded and noteChild(mod,'head')
    local headTexture=isHold and (e.states['5'] or e.states['1'])[1] or e.states['1'][1]
    local baseTexture=headTexture
    if chordTimes[noteTime(note)] and e.states['4'] then headTexture=e.states['4'][1] end
    local headDisplayW,headDisplayH=dimensions(ww,hh,headTexture)
    if state.legacyProgress then
        state.legacyProgress.head_geometry.center_x,state.legacyProgress.head_geometry.center_y=center(x,y,headDisplayW,headDisplayH,e.anchor,rotate)
    end
    local rigid
    if reusable then
        rigid=state._rigid or {};state._rigid=rigid
        rigid.sx=sx;rigid.sy=sy;rigid.dx=ex-sx;rigid.dy=ey-sy;rigid.width=ww;rigid.height=hh;rigid.toggle=toggle
        rigid.head_offset_x=state.legacyProgress.head_geometry.center_x-x;rigid.head_offset_y=state.legacyProgress.head_geometry.center_y-y
    end
    if drawNeeded then place(head,x-offsetX,y-offsetY,ww,hh,headTexture,e.anchor,rotate,hidden and 0 or e.opacity) end
    if note.endtime>note.time and percent.Length>1 then
        local tailProgress=math.max(0,q)
        if PROFILE.native_scroll_candidate then state.legacyProgress.tail_geometry=tailProgress end
        local tx,ty=sx+(ex-sx)*tailProgress,sy+(ey-sy)*tailProgress
        local tw,th=w+(ew-w)*tailProgress,h+(eh-h)*tailProgress
        local headw,headh=dimensions(ww,hh,headTexture)
        local tailTexture=e.states['3'] and e.states['3'][1] or baseTexture
        tw,th=dimensions(tw,th,tailTexture)
        local hx,hy=center(x,y,headw,headh,e.anchor,rotate)
        local tailx,taily=center(tx,ty,tw,th,e.anchor,rotate)
        local dx,dy=tailx-hx,taily-hy
        local length=math.sqrt(dx*dx+dy*dy)
        -- atan2(0,0) in the native axis=0 path yields a vertical edge.
        local nx,ny=0,-1
        if length>0 then nx,ny=dy/length,-dx/length end
        local headedge,tailedge=headw,tw
        -- Native Part3 0x4f1580: explicit axes are WORLD axes; sprite
        -- rotation only moves their bounding-box centers. The vertical path
        -- deliberately reuses head height for both end edges.
        if e.body_axis==1 then nx,ny=-1,0
        elseif e.body_axis==2 then nx,ny=0,-1;headedge,tailedge=headh,headh end
        if rigid then
            rigid.tail_offset_x=tailx-tx;rigid.tail_offset_y=taily-ty;rigid.headedge=headedge;rigid.tailedge=tailedge;rigid.axis=e.body_axis
        end
        local fullPoints=state.bodyPoints or {{},{},{},{}};state.bodyPoints=fullPoints
        fullPoints[1][1],fullPoints[1][2]=hx-nx*headedge/2,hy-ny*headedge/2
        fullPoints[2][1],fullPoints[2][2]=hx+nx*headedge/2,hy+ny*headedge/2
        fullPoints[3][1],fullPoints[3][2]=tailx-nx*tailedge/2,taily-ny*tailedge/2
        fullPoints[4][1],fullPoints[4][2]=tailx+nx*tailedge/2,taily+ny*tailedge/2
        if state.legacyProgress then state.legacyProgress.body_geometry=fullPoints end
        if drawNeeded then
        local drawPoints=fullPoints
        if motion then
            drawPoints=state.drawPoints or {{},{},{},{}};state.drawPoints=drawPoints
            for i=1,4 do drawPoints[i][1]=fullPoints[i][1]-offsetX;drawPoints[i][2]=fullPoints[i][2]-offsetY end
        end
        local texture=e.states['2'] and e.states['2'][1]
        if texture and texture.tiles then
            for index,tile in ipairs(texture.tiles) do
                UnityBridge.TileMesh(noteChild(mod,'body-'..index),drawPoints,texture,tile,sw,'#FFFFFF',hidden and 0 or 100)
            end
        elseif noteChild(mod,'body') then bodyGeometry(noteChild(mod,'body'),drawPoints,sw,hidden) end
        place(noteChild(mod,'tail'),tx-offsetX,ty-offsetY,tw,th,tailTexture,e.anchor,rotate,hidden and 0 or e.opacity)
        end
    end
    state._drawEpoch=reusable and motion.epoch or nil
end
updateRigidProgress=function(state,n,motion,y,time,distance)
    if not state or not motion or not state._rigid or state._drawEpoch~=motion.epoch then return false end
    local original=legacyScroll.notes[n.nid];local rigid=state._rigid;local hold=n.endtime>n.time
    local sourceHead=hold and state.holdHeadY or original.display_y
    if y+distance<sourceHead or hold and y+distance<original.end_y then return false end
    if state.held and (rigid.toggle & 2)~=0 then
        if not state.finished or state.holdOffset==nil or math.abs(state.holdOffset)<.0001 or
            y+state.holdOffset<original.end_y then return false end
    end
    local p=1-UnityBridge.Float((original.display_y-y)/distance)
    local q=1-UnityBridge.Float((original.end_y-y)/distance)
    local v=hold and 1-UnityBridge.Float((sourceHead-y)/distance) or p
    local progress=state.legacyProgress;progress.time=time;progress.head=p;progress.tail=q;progress.distance=distance
    local x,yhead=rigid.sx+rigid.dx*v,rigid.sy+rigid.dy*v
    local head=progress.head_geometry;head.x=x;head.y=yhead
    local hx,hy=x+rigid.head_offset_x,yhead+rigid.head_offset_y;head.center_x=hx;head.center_y=hy
    if hold then
        local tx,ty=rigid.sx+rigid.dx*q+rigid.tail_offset_x,rigid.sy+rigid.dy*q+rigid.tail_offset_y
        local dx,dy=tx-hx,ty-hy;local length=math.sqrt(dx*dx+dy*dy);local nx,ny=0,-1
        if length>0 then nx,ny=dy/length,-dx/length end
        if rigid.axis==1 then nx,ny=-1,0 elseif rigid.axis==2 then nx,ny=0,-1 end
        local points=progress.body_geometry
        points[1][1],points[1][2]=hx-nx*rigid.headedge/2,hy-ny*rigid.headedge/2
        points[2][1],points[2][2]=hx+nx*rigid.headedge/2,hy+ny*rigid.headedge/2
        points[3][1],points[3][2]=tx-nx*rigid.tailedge/2,ty-ny*rigid.tailedge/2
        points[4][1],points[4][2]=tx+nx*rigid.tailedge/2,ty+ny*rigid.tailedge/2
        progress.tail_geometry=q
    end
    UnityBridge.NotePerformance.lane_static_skips=UnityBridge.NotePerformance.lane_static_skips+1
    return true
end
lifetimeHide=function(mod,e)
    local names={'head','body','tail'}
    local texture=e.states['2'] and e.states['2'][1]
    for i in ipairs(texture and texture.tiles or {}) do names[#names+1]='body-'..i end
    for _,name in ipairs(names) do
        local child=noteChild(mod,name)
        if child then
            child.gameObject.layer=CS.UnityEngine.LayerMask.NameToLayer('Note')
            UnityBridge.AlphaByte(child,0)
        end
    end
end
prepareLifetime=function()
    local pool,notes,motions,templates={},{},{},{}
    for lane,e in pairs(PROFILE.notes) do motions[lane]=UnityBridge.PrepareLaneMotion(e,lane) end
    -- Original pointer-vector sort is checked through 16384 entries. Build
    -- immutable prototypes while AddSprite is allowed; display slots grow
    -- separately from the chart's complete logical carrier list.
    assert(Chart:NoteCount()<=16384,'Ma Skin Bridge: chart exceeds the currently verified 16384-note sort range')
    for i=0,Chart:NoteCount()-1 do
        local note=Chart:NoteAt(i)
        if legacyScroll.notes[note.nid] then
            -- Immutable visual metadata: keep per-frame movement in Lua.
            -- The original C# note objects still own native judge/callbacks.
            notes[note.nid]={nid=note.nid,x=note.x,time=note.time,endtime=note.endtime}
            local kind=tostring(note.x)..(note.endtime>note.time and ':hold' or ':tap')
            pool[kind]=pool[kind] or {}
            if not templates[kind] then
            local index=#pool[kind]+1
            local mod=Note:GetGroup('legacy_lifetime_'..note.x..'_'..(note.endtime>note.time and 'hold' or 'tap')..'_'..index)
            assert(mod,'Ma Skin Bridge: public lifetime visual group unavailable')
            lifetimeModule=mod;OnDrawNote(note);lifetimeModule=nil
            if motions[note.x] then UnityBridge.AttachLaneMotion(mod,motions[note.x]) else UnityBridge.ProjectLifetimeGroup(mod) end
            lifetimeHide(mod,PROFILE.notes[note.x]);mod.gameObject:SetActive(false)
            local template=UnityBridge.PrepareLifetimeTemplate and UnityBridge.PrepareLifetimeTemplate(mod,PROFILE.notes[note.x],note.endtime>note.time)
            if template then templates[kind]=template
            else pool[kind][index]=mod end
            end
        end
    end
    local barEntries={}
    for _,entry in ipairs(PROFILE.entries) do if entry.name=='bar' then barEntries[#barEntries+1]=entry end end
    if UnityBridge.NotePerformance then
        local initial=0
        for _,list in pairs(pool) do initial=initial+#list end
        for _ in pairs(templates) do initial=initial+1 end
        UnityBridge.NotePerformance.lifetime_initial_visual_groups=initial
        UnityBridge.NotePerformance.lifetime_logical_note_count=Chart:NoteCount()
    end
    legacyLifetime={pool=pool,notes=notes,lane_motions=motions,templates=templates,bar_entries=barEntries,bars={},assigned={},counts={},distance=632.5,judge_ahead=160,attempt=0}
    resetLifetime()
end
resetLifetime=function()
    local state=legacyLifetime
    if PROFILE.native_carrier_window_candidate then state.carrier_window=UnityBridge.CarrierWindow(legacyScrollLayer) end
    state.queue=LegacyLifetime.New(legacyScroll,state.distance,state.judge_ahead)
    state.assigned={};state.counts={};state.samples={};state.events={};state.visibility={};state.bars={};state.attempt=state.attempt+1
    state.trace_idle_index=nil;state.trace_idle_compressed=0
    state.frame=nil;state.active_lane_source=nil
    state.trace_capacity_exceeded=false
    state.update_profile={calls=0,total_ms=0,max_ms=0,active_calls=0,active_total_ms=0}
    for _,motion in pairs(state.lane_motions or {}) do motion.base_y=nil end
    for _,entry in ipairs(PROFILE.entries) do
        entry._barLifetime=nil;entry._barLifetimeActive={}
    end
    for kind,groups in pairs(state.pool) do
        for _,mod in ipairs(groups) do
            -- The inactive parent hides every child. Restore child render
            -- properties only when checked out, rather than reinitialize
            -- thousands of untouched reservations inside native retry.
            mod.gameObject:SetActive(false)
        end
    end
end
local function drawLifetimeActive(state,time)
    for _,row in ipairs(state.drawables) do
        -- Original carriers may retain a reused drawable owned by a newer
        -- note. Only its current owner may change its geometry/visibility.
        if row.slot.owner==row.note and not row.slot.cullHidden then
            local note=state.notes[row.note.nid];local mod=state.assigned[row.module]
            local status=noteStates[note.nid];local motion=state.lane_motions and state.lane_motions[note.x]
            if not updateRigidProgress(status,note,motion,state.display_y,frameTime or time,state.distance) then
                OnNoteMove(note,mod,note.endtime>note.time and lifetimeHoldProgress or lifetimeTapProgress)
            end
            local progress=noteStates[note.nid].legacyProgress
            if LegacyLifetime.Visibility(state.queue,row.module,not progress.visual_hidden) and not state.trace_capacity_exceeded then
                state.visibility[#state.visibility+1]={sample=#state.samples,module=row.module,
                    visible=not progress.visual_hidden,nid=note.nid}
            end
        end
    end
end
updateLifetime=function(state,time)
    if not state then return end
    if PROFILE.native_carrier_window_candidate and
       (legacyScrollLayer.displayWindowUpY~=0 or legacyScrollLayer.displayWindowDownY~=0) then
        state.carrier_window=UnityBridge.CarrierWindow(legacyScrollLayer)
    end
    state.distance=632.5/UnityBridge.ScrollScale(legacyScrollLayer)/(PROFILE.legacy_play_plane and PROFILE.legacy_play_plane.scroll_scale or 1)
    state.queue.distance=state.distance
    local frame=LegacyLifetime.Step(state.queue,time,time,state.frame);state.frame=frame
    local idle=state.queue.next>#state.queue.notes and #frame.active==0 and #frame.events==0
    for _,entry in ipairs(PROFILE.entries) do
        if entry.name=='bar' and not (entry._barProvider and entry._barProvider.legacy_bars_disabled) then
            local bars=entry._barLifetime
            if not bars or bars.next<=#bars.bars or #(entry._barLifetimeActive or {})>0 then idle=false end
        end
    end
    LegacyLifetime.RecordSample(state,time,idle)
    state.active=frame.active;state.drawables=frame.drawables;state.display_y=frame.display_y
    local activeLanes=state.active_lanes or {};state.active_lanes=activeLanes
    if state.active_lane_source~=frame.drawables then
        for lane in pairs(activeLanes) do activeLanes[lane]=nil end
        for _,row in ipairs(frame.drawables) do
            if row.slot.owner==row.note and not row.slot.cullHidden then activeLanes[row.note.lane]=true end
        end
        state.active_lane_source=frame.drawables
    end
    for lane,motion in pairs(state.lane_motions or {}) do
        UnityBridge.UpdateLaneMotion(motion,frame.display_y,state.distance,screen(),activeLanes[lane]==true)
    end
    if PROFILE.native_layer_order_candidate then LegacyLayers.BeginNotes() end
    for _,event in ipairs(frame.events) do
        local n=event.note;local kind=tostring(n.lane)..(n.endtime>n.time and ':hold' or ':tap')
        local mod=state.assigned[event.module]
        if not mod then
            local index=(state.counts[kind] or 0)+1;state.counts[kind]=index
            mod=state.pool[kind][index]
            if not mod and state.templates and state.templates[kind] then
                local children
                mod,children=UnityBridge.CloneLifetimeTemplate(state.templates[kind],'legacy_lifetime_'..n.lane..'_'..(n.endtime>n.time and 'hold' or 'tap')..'_'..index)
                ownedNoteChildren[mod]=children;state.pool[kind][index]=mod
            end
            assert(mod,'Ma Skin Bridge: lifetime visual reservation exhausted')
            state.assigned[event.module]=mod
        end
        state.events[#state.events+1]={operation=event.operation,time=time,nid=n.nid,module=event.module,
            group_id=mod:GetInstanceID(),lane=n.lane,head_time=n.time,end_time=n.endtime}
        if event.operation=='retire' then
            if event.hide then lifetimeHide(mod,PROFILE.notes[n.lane]);mod.gameObject:SetActive(false) end
        else
            local e=PROFILE.notes[n.lane]
            lifetimeHide(mod,e)
            local base=n.endtime>n.time and (e.states['5'] or e.states['1']) or e.states['1']
            local bank=chordTimes[n.time] and e.states['4'] or base
            -- A retained visual slot may move between chord and single-note
            -- appearances. Refresh its existing Sprite through the public
            -- renderer; creating new children outside Loading is forbidden.
            UnityBridge.NoteSprite(noteChild(mod,'head'),bank[1].file)
            local tail=noteChild(mod,'tail')
            if tail then UnityBridge.NoteSprite(tail,(e.states['3'] or base)[1].file) end
            mod.gameObject:SetActive(true);LegacyLayers.Note(mod,PROFILE.notes[n.lane])
        end
    end
    if PROFILE.native_layer_order_candidate then LegacyLayers.EndNotes() end
    lifetimeDrawing=true
    state.draw_time=time
    state.draw_callback=state.draw_callback or function()drawLifetimeActive(state,state.draw_time)end
    UnityBridge.WithNoteMeshUploads(state.draw_callback)
    lifetimeDrawing=false
end
function ReportCustomInfo() return 'Ma Skin Bridge 0.3-dev7; strict acceptance pending' end
