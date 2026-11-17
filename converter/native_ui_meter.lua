-- Original SkinRuntimeFill remains the native HP/progress value provider.
-- Only its display is adapted to 437 ProgressBarLine / ProgressBarDot.
local NativeUiMeter={items={}}
local function meterFloat(v) local n=string.unpack('f',string.pack('f',v));return n end
function NativeUiMeter.Step(current,target,dt)
    local step=meterFloat(meterFloat(meterFloat(dt)*1000)/2500)
    target=meterFloat(target)
    if current<target then return math.min(target,meterFloat(current+step)) end
    if current>target then return math.max(target,meterFloat(current-step)) end
    return current
end
function NativeUiMeter.Plan(config,value)
    local rows={};local first=config.frames[1]
    if config.kind=='line' then
        local sx=meterFloat(config.size[1]/first.width)
        local sy=meterFloat(config.size[2]/first.height)
        local crop=meterFloat(first.trim[3]*value)
        local x=meterFloat(first.offset[1]-(config.reverse and crop or 0))
        rows[1]={frame=1,left=meterFloat((config.reverse and config.size[1] or 0)+meterFloat(x*sx)),
            bottom=meterFloat(first.offset[2]*sy),width=meterFloat(crop*sx),
            height=meterFloat(first.trim[4]*sy),
            uv={(first.trim[1]+(config.reverse and first.trim[3]-crop or 0))/first.width,
                (first.height-first.trim[2]-first.trim[4])/first.height,crop/first.width,first.trim[4]/first.height}}
    else
        local scale=meterFloat(config.size[2]/first.trim[4])
        local spacing=config.spacing
        if spacing==nil or spacing<.0001 then spacing=meterFloat(scale*config.size[1]) end
        local step=meterFloat(scale*spacing);local x=0
        local lit=math.max(0,math.floor(meterFloat(config.count*value)))
        assert(lit<=config.count,'Native meter value exceeds source frame bank')
        for i=1,config.count do
            local frame=i>config.count-lit and 1 or 2
            local texture=config.frames[frame]
            rows[i]={frame=frame,left=x,bottom=0,width=meterFloat(texture.width*scale),
                height=meterFloat(texture.height*scale),uv={0,0,1,1}}
            x=meterFloat(x+step)
        end
    end
    return rows
end
function NativeUiMeter.Bind(module,entry)
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UI') end
    local U=CS.UnityEngine;local image=NativeUiSampling.Image(module)
    local cfg=entry.source_meter
    if cfg then
        local aspect
        if Game and Game.Width and Game.Height then
            local gw,gh=Game:Width(),Game:Height()
            if type(gw)=='number' and type(gh)=='number' and gh>0 then aspect=gw/gh end
        end
        if not aspect and U and U.Screen then
            local sw,sh=U.Screen.width,U.Screen.height
            if type(sw)=='number' and type(sh)=='number' and sh>0 then aspect=sw/sh end
        end
        if aspect then
            if cfg.size_pct_x then cfg.size[1]=cfg.size_pct_x*aspect+cfg.size_px_x end
            if cfg.spacing_pct_x then cfg.spacing=cfg.spacing_pct_x*aspect+cfg.spacing_px_x end
        end
    end
    local item={config=cfg,image=image,children={},rects={},sprite_meta={},current=0,last_frame=nil}
    for i=1,item.config.kind=='line' and 1 or item.config.count do
        local go=U.GameObject('437-meter-'..i,typeof(U.RectTransform))
        go.layer=image.gameObject.layer
        local raw=go:AddComponent(typeof(U.UI.RawImage));local rect=raw.rectTransform
        rect:SetParent(image.rectTransform,false)
        rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(0,0);rect.pivot=U.Vector2(0,0)
        raw.raycastTarget=false
        item.children[i]=raw;item.rects[i]=rect
    end
    image.enabled=false
    NativeUiMeter.items[#NativeUiMeter.items+1]=item
end
function NativeUiMeter.Draw(item)
    local visible=item.config.visible~=false
    if item.drawn_current==item.current and item.drawn_visible==visible then return end
    local U=CS.UnityEngine;local factor=item.config.units_per_pixel
    local plan=NativeUiMeter.Plan(item.config,item.current)
    local metaCache=item.sprite_meta
    if not metaCache then metaCache={};item.sprite_meta=metaCache end
    for i,row in ipairs(plan) do
        local raw=item.children[i];local frame=item.config.frames[row.frame]
        local meta=metaCache[frame.file]
        if not meta then
            local sprite=NativeUiSampling.Sprite(frame.file);local rect=sprite.rect;local texture=sprite.texture
            meta={texture=texture,rx=rect.x,ry=rect.y,rw=rect.width,rh=rect.height,tw=texture.width,th=texture.height}
            metaCache[frame.file]=meta
        end
        raw.texture=meta.texture
        raw.uvRect=U.Rect((meta.rx+meta.rw*row.uv[1])/meta.tw,
            (meta.ry+meta.rh*row.uv[2])/meta.th,
            meta.rw*row.uv[3]/meta.tw,meta.rh*row.uv[4]/meta.th)
        if not item.color_init then raw.color=U.Color(1,1,1,1) end
        -- 437 show=0 hides the whole Node, independently of opacity. These
        -- children deliberately ignore parent tint/alpha, so an alpha-zero
        -- native provider alone must not leave them visible.
        raw.enabled=visible and row.width>0 and row.height>0
        local rt=(item.rects and item.rects[i]) or raw.rectTransform
        rt.anchoredPosition=U.Vector2(row.left*factor,row.bottom*factor)
        rt.sizeDelta=U.Vector2(row.width*factor,row.height*factor)
    end
    item.color_init=true
    item.drawn_current=item.current;item.drawn_visible=visible
end
function NativeUiMeter.Reset()
    for _,item in ipairs(NativeUiMeter.items) do
        item.current=0;item.last_frame=nil;item.drawn_current=nil;NativeUiMeter.Draw(item)
    end
end
function NativeUiMeter.Update()
    local time=CS.UnityEngine.Time
    for _,item in ipairs(NativeUiMeter.items) do
        local image=item.image
        if item.last_frame~=time.frameCount then
            local target=image.fillAmount
            if target~=item.current then
                item.current=NativeUiMeter.Step(item.current,target,time.deltaTime)
            end
            item.last_frame=time.frameCount
        end
        if image.enabled~=false then image.enabled=false end
        NativeUiMeter.Draw(item)
    end
end
