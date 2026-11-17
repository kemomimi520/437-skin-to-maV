-- Original 437 MusicBarSprite as ordinary scene-owned Key UI children.
-- Read the existing source visual context; never write a chart/carrier,
-- input, judge, score, Replay, eligibility, clock or original default widget.
local NativeUiMusicbar={items={},pending={}}
local function musicbarFloat(v)local n=string.unpack('f',string.pack('f',v));return n end
local function musicbarColor(flags)
    if flags&16~=0 then return {102,102,102,255} end
    if flags&8~=0 then return {47,186,141,255} end
    if flags&4~=0 then return {244,208,85,255} end
    return {238,102,102,255}
end
function NativeUiMusicbar.Layout(config)
    local f=musicbarFloat;local w,h=config.size[1],config.size[2]
    local a,b=config.textures[2],config.textures[3];local marker=f(h*.6)
    local left=f(a.width*f(marker/a.height));local right=f(b.width*f(marker/b.height))
    local available=f(f(f(w-left)-right)-40)
    assert(available>0,'Source musicbar markers exceed width')
    return {width=w,height=h,marker=marker,left=left,right=right,available=available,
        cursor=f(available/100),bodyX=f(f(w-available)*.5),bodyY=f(h*.2)}
end
function NativeUiMusicbar.New(count,start,finish,notes)
    assert(math.type(count)=='integer' and count>=1 and count<=4096,'Invalid source musicbar count')
    finish=math.max(start+1,finish)
    local state={count=count,start=start,finish=finish,step=musicbarFloat((finish-start)/count),
        totals={},judged={},flags={},colors={},commits={},version=1}
    for i=1,count do state.totals[i]=0;state.judged[i]=0;state.flags[i]=0;state.colors[i]={102,102,102,255} end
    for _,note in ipairs(notes) do
        local index=math.floor(musicbarFloat(musicbarFloat(note.time-start)/state.step))+1
        if index>=1 and index<=count then state.totals[index]=math.min(100,state.totals[index]+1) end
    end
    return state
end
function NativeUiMusicbar.Judge(state,time,flags)
    local index=math.floor(musicbarFloat(musicbarFloat(time-state.start)/state.step))+1
    if index<1 or index>state.count then return end
    local bit=flags&2~=0 and 2 or flags&4~=0 and 4 or flags&8~=0 and 8 or flags&1~=0 and 16
    if not bit then return end
    state.flags[index]=state.flags[index]|bit;state.judged[index]=(state.judged[index]+1)&255
    if state.judged[index]==state.totals[index] then
        state.colors[index]=musicbarColor(state.flags[index])
        state.commits[#state.commits+1]=index
        state.version=(state.version or 1)+1
    end
end
function NativeUiMusicbar.Plan(config,state,time)
    local f=musicbarFloat;local l=NativeUiMusicbar.Layout(config)
    local rows={
        {texture=1,left=0,bottom=0,width=l.width,height=l.height,color={255,255,255,40}},
        {texture=2,left=10,bottom=f(l.height*.2),width=l.left,height=l.marker,color={255,255,255,255}},
        {texture=3,left=l.width-10-l.right,bottom=f(l.height*.2),width=l.right,height=l.marker,color={255,255,255,255}}}
    local step=f(l.available/config.count)
    for i=1,config.count do
        local total=state and state.totals[i] or 0
        if total>0 then
            local x0=f(f(f(step*.15)+f(step*(i-1)))-.5)
            local x1=f(f(f(step*.85)+f(step*(i-1)))+.5)
            local y1=f(f(l.marker*f(math.min(total,10)/10))+.5)
            rows[#rows+1]={bin=i,left=l.bodyX+x0,bottom=l.bodyY-.5,
                width=x1-x0,height=y1+.5,color=state.colors[i]}
        end
    end
    local cursor=l.bodyX
    if state then
        time=math.max(state.start,math.min(state.finish,time))
        cursor=f(f(f(f(l.available-l.cursor)*f(time-state.start))/f(state.finish-state.start))+l.bodyX)
    end
    -- Seek is added at local z=2, after density (z=1), not before it.
    rows[#rows+1]={texture=4,left=cursor,bottom=0,width=l.cursor,height=l.height,color={255,255,255,255}}
    return rows
end
function NativeUiMusicbar.FromSource(count,pool)
    if not pool or not pool.input or not pool.scroll then return nil end
    local notes={}
    for _,note in pairs(pool.scroll.notes) do notes[#notes+1]=note end
    table.sort(notes,function(a,b)
        if a.legacy_order and b.legacy_order then return a.legacy_order<b.legacy_order end
        return a.beat==b.beat and (a.source_order or a.nid)<(b.source_order or b.nid) or a.beat<b.beat
    end)
    assert(#notes>0,'Source musicbar requires recovered source notes')
    return NativeUiMusicbar.New(count,notes[1].time,notes[#notes].endtime,notes)
end
function NativeUiMusicbar.Bind(module,entry)
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UI') end
    local config=assert(entry.source_musicbar);local U=CS.UnityEngine
    assert(config.scope=='legacy-musicbar-static-v1','Unmapped source musicbar scope')
    if config.size_pct_x then
        local aspect
        if Game and Game.Width and Game.Height then
            local gw,gh=Game:Width(),Game:Height()
            if type(gw)=='number' and type(gh)=='number' and gh>0 then aspect=gw/gh end
        end
        if not aspect and U and U.Screen then
            local sw,sh=U.Screen.width,U.Screen.height
            if type(sw)=='number' and type(sh)=='number' and sh>0 then aspect=sw/sh end
        end
        if aspect then config.size[1]=config.size_pct_x*aspect+config.size_px_x end
    end
    if config.projection then
        assert(NativeUiProjection and config.source_position and config.source_anchor,
            'Source musicbar projection binding is incomplete')
        NativeUiProjection.Bind(module,config.projection,config.source_position,config.source_anchor,config)
    end
    local image=NativeUiSampling.Image(module)
    local item={module=module,image=image,config=config,children={}}
    -- 437 plain Node opacity/color do not cascade to these widget children.
    module.Alpha=100;image.enabled=false
    for i=1,config.count+4 do
        local go=U.GameObject('437-musicbar-'..i,typeof(U.RectTransform));go.layer=image.gameObject.layer
        local raw=go:AddComponent(typeof(U.UI.RawImage));raw.raycastTarget=false
        raw.enabled=false
        local rect=raw.rectTransform;rect:SetParent(image.rectTransform,false)
        rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(0,0);rect.pivot=U.Vector2(0,0)
        item.children[i]=raw
    end
    NativeUiMusicbar.items[#NativeUiMusicbar.items+1]=item
end
function NativeUiMusicbar.Draw(item,time)
    local U=CS.UnityEngine;local config=item.config;local factor=config.units_per_pixel
    local visible=config.visible~=false;local state=item.state
    local version=state and (state.version or 0) or -1
    if item.drawn_state==state and item.drawn_version==version and item.drawn_visible==visible and item.cursor_index then
        local layout=item.layout or NativeUiMusicbar.Layout(config);item.layout=layout
        local cursor=layout.bodyX
        if state then
            local f=musicbarFloat
            local t=math.max(state.start,math.min(state.finish,time))
            cursor=f(f(f(f(layout.available-layout.cursor)*f(t-state.start))/f(state.finish-state.start))+layout.bodyX)
        end
        if item.drawn_cursor~=cursor then
            local cr=item.cursor_rect
            if not cr then cr=item.children[item.cursor_index].rectTransform;item.cursor_rect=cr end
            cr.anchoredPosition=U.Vector2(cursor*factor,0)
            item.drawn_cursor=cursor
        end
        if not item._img_disabled then
            if item.image.enabled~=false then item.image.enabled=false end
            item._img_disabled=true
        end
        return
    end
    local plan=NativeUiMusicbar.Plan(config,state,time)
    for i,raw in ipairs(item.children) do
        local row=plan[i];raw.enabled=row~=nil and visible
        if row then
            if row.texture then
                local frame=config.textures[row.texture];local sprite=NativeUiSampling.Sprite(frame.file)
                local rect=sprite.rect;local sample=frame.sample_rect or {0,0,frame.width,frame.height}
                raw.texture=sprite.texture
                raw.uvRect=U.Rect((rect.x+sample[1])/raw.texture.width,(rect.y+sample[2])/raw.texture.height,
                    sample[3]/raw.texture.width,sample[4]/raw.texture.height)
            else raw.texture=nil;raw.uvRect=U.Rect(0,0,1,1) end
            local c=row.color;raw.color=U.Color(c[1]/255,c[2]/255,c[3]/255,c[4]/255)
            raw.rectTransform.anchoredPosition=U.Vector2(row.left*factor,row.bottom*factor)
            raw.rectTransform.sizeDelta=U.Vector2(row.width*factor,row.height*factor)
        end
    end
    item.drawn_state=state;item.drawn_version=version;item.drawn_visible=visible
    item.cursor_index=#plan;item.cursor_rect=item.children[#plan].rectTransform
    item.drawn_cursor=plan[#plan].left
    if item.image.enabled~=false then item.image.enabled=false end
    item._img_disabled=true
end
function NativeUiMusicbar.Update(pool)
    assert(pool,'Source musicbar requires the original source visual pool')
    -- Init/variable notification can precede ChartPlayer.IsPlaying. The
    -- existing source reader deliberately waits for that native lifecycle.
    -- Keep the widget hidden until its full density is available, rather
    -- than showing a convincing but empty progress strip. Ready()/the
    -- unverified source-widget gate must be checked by native validation.
    if not pool.input or not pool.scroll then return end
    if pool and pool.input and pool.scroll and #NativeUiMusicbar.pending>0 then
        local pending=NativeUiMusicbar.pending;NativeUiMusicbar.pending={}
        for _,hit in ipairs(pending) do NativeUiMusicbar.Dispatch(hit.carrier,hit.note,hit.grade,pool) end
    end
    for _,item in ipairs(NativeUiMusicbar.items) do
        if not item.state then item.state=NativeUiMusicbar.FromSource(item.config.count,pool) end
        NativeUiMusicbar.Draw(item,Game:Time())
    end
end
function NativeUiMusicbar.Ready()
    if #NativeUiMusicbar.items==0 or #NativeUiMusicbar.pending>0 then return false end
    for _,item in ipairs(NativeUiMusicbar.items) do if not item.state then return false end end
    return true
end
function NativeUiMusicbar.Flag(grade)
    -- 0x4fc6d0 dispatches 2/4/8/1 to best/cool/good/miss. KeyUIS passes
    -- that SAME flag to MusicBarBody::AddResult; it never reverses grades.
    -- Actual paired native captures: JudgeResult=1, old dispatch=34 (2|32).
    return ({2,4,8,1})[grade]
end
function NativeUiMusicbar.Resolve(pool,carrier,hitNote)
    -- ChartPlayer carrier wrappers need not inherit UnityEngine.Object.
    -- Compare the original managed carrier or its real NoteObject, never a
    -- class-name tostring fallback or native lane/time approximation.
    for nid,candidate in pairs(pool.input.carriers) do
        local same=candidate==carrier or candidate:Equals(carrier)
        if same then return assert(pool.scroll.notes[nid],'Original musicbar source note missing') end
    end
    local matched
    if hitNote then
        for nid,candidate in pairs(pool.input.carriers) do
            local original=NativeSourceInput.Get(candidate,'get_NoteObject')
            if original and (original==hitNote or original:Equals(hitNote)) then
                assert(not matched,'Source musicbar NoteObject identity is ambiguous')
                matched=assert(pool.scroll.notes[nid],'Original musicbar source note missing')
            end
        end
    end
    if matched then return matched end
    error('Source musicbar cannot match original native hit carrier')
end
function NativeUiMusicbar.Dispatch(carrier,hitNote,grade,pool)
    local flags=assert(NativeUiMusicbar.Flag(grade),'Invalid native musicbar grade')
    local note=NativeUiMusicbar.Resolve(pool,carrier,hitNote)
    for _,item in ipairs(NativeUiMusicbar.items) do
        if not item.state then item.state=NativeUiMusicbar.FromSource(item.config.count,pool) end
        if item.state then
            -- KeyUIS0x5adc90 calls AddResult twice, including LN callbacks.
            -- Both address the original HitObject's START time, never the
            -- early/late input timestamp or current music cursor time.
            NativeUiMusicbar.Judge(item.state,note.time,flags)
            NativeUiMusicbar.Judge(item.state,note.time,flags)
        end
    end
end
function NativeUiMusicbar.Hit(event,pool)
    if not event or #NativeUiMusicbar.items==0 then return end
    local kind,grade=event:NoteType(),event:JudgeResult()
    if kind~=1 and kind~=2 or not NativeUiMusicbar.Flag(grade) then return end
    local carrier,note=scale3HitCarrier(event)
    assert(carrier,'Original Key musicbar hit carrier missing')
    if not pool or not pool.input or not pool.scroll then
        assert(#NativeUiMusicbar.pending<32768,'Pending source musicbar hits exceed bound')
        NativeUiMusicbar.pending[#NativeUiMusicbar.pending+1]={carrier=carrier,note=note,grade=grade}
        return
    end
    NativeUiMusicbar.Dispatch(carrier,note,grade,pool)
end
function NativeUiMusicbar.Reset()
    NativeUiMusicbar.pending={}
    for _,item in ipairs(NativeUiMusicbar.items) do
        item.state=nil;item.drawn_state=nil;item.drawn_version=nil;item.cursor_index=nil;item.drawn_cursor=nil
        for _,raw in ipairs(item.children or {}) do raw.enabled=false end
    end
end
