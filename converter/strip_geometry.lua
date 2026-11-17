-- Original GenericFactory type 4: middle, first cap, final cap, in that order.
local LegacyStrip={}
function LegacyStrip.Geometry(kind,textureWidth,textureHeight,first,last,width,height,secondary)
    local f=LegacyStrip.Float or UnityBridge.Float
    local vertical=kind==1 or kind==3
    local sourceAxis=vertical and textureHeight or textureWidth
    local sourceCross=vertical and textureWidth or textureHeight
    local desiredAxis=vertical and height or width
    local desiredCross=vertical and width or height
    local crossScale=f(desiredCross/sourceCross)
    local contentAxis=secondary or f(desiredAxis/crossScale)
    local axisScale=f(desiredAxis/contentAxis)
    local middle=f(last-first)
    local before,after=first,f(sourceAxis-last)
    if kind==2 or kind==3 then
        before=f(f(contentAxis-middle)/2);after=before
    else middle=f(f(contentAxis-before)-after) end
    local result={vertical=vertical,content=vertical and {sourceCross,contentAxis} or {contentAxis,sourceCross},
        scale=vertical and {crossScale,axisScale} or {axisScale,crossScale},parts={}}
    local rects=vertical and {
        {0,after,sourceCross,middle,0,first,textureWidth,last-first},
        {0,f(contentAxis-before),sourceCross,before,0,0,textureWidth,first},
        {0,0,sourceCross,after,0,last,textureWidth,textureHeight-last}
    } or {
        {before,0,middle,sourceCross,first,0,last-first,textureHeight},
        {0,0,before,sourceCross,0,0,first,textureHeight},
        {f(contentAxis-after),0,after,sourceCross,last,0,textureWidth-last,textureHeight}
    }
    result.parts=rects
    return result
end

function LegacyStrip.Prepare(obj,configuration,texture,width,height,secondary,surface)
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UI') end
    local layout=LegacyStrip.Geometry(configuration.kind,texture.width,texture.height,
        configuration.first,configuration.last,width,height,secondary)
    assert(layout.content[1]>0 and layout.content[2]>0,'Ma Skin Bridge: invalid native strip extent')
    surface=surface or renderer(obj)
    assert(surface.graphics.Length==1,'Ma Skin Bridge: strip needs one initial image')
    local original=surface.graphics[0]
    local sprite=original.sprite;local rect=sprite.rect
    local tw,th=sprite.texture.width,sprite.texture.height
    local graphics={Length=3}
    local V=CS.UnityEngine.Vector2
    for i,p in ipairs(layout.parts) do
        local child=CS.UnityEngine.GameObject('MaSkinBridgeStripPart',typeof(CS.UnityEngine.RectTransform))
        child.layer=obj.gameObject.layer
        local image=child:AddComponent(typeof(CS.UnityEngine.UI.RawImage))
        local transform=image.rectTransform
        transform:SetParent(original.rectTransform,false)
        local x,y,w,h,sx,sy,sw,sh=table.unpack(p)
        transform.anchorMin=V(math.min(x,x+w)/layout.content[1],math.min(y,y+h)/layout.content[2])
        transform.anchorMax=V(math.max(x,x+w)/layout.content[1],math.max(y,y+h)/layout.content[2])
        transform.offsetMin=V(0,0);transform.offsetMax=V(0,0)
        transform.pivot=V(0,0)
        local u=(rect.x+(sx+.5)*rect.width/texture.width)/tw
        local v=(rect.y+(texture.height-sy-sh+.5)*rect.height/texture.height)/th
        local uw=(sw-1)*rect.width/texture.width/tw
        local vh=(sh-1)*rect.height/texture.height/th
        -- Cocos permits a negative middle extent when caps exceed the target.
        -- Keep that reversal; Unity's normal sliced Image clamps its borders.
        if w<0 then u=u+uw;uw=-uw end
        if h<0 then v=v+vh;vh=-vh end
        image.texture=sprite.texture;image.material=original.material
        image.color=original.color;image.raycastTarget=false
        image.uvRect=CS.UnityEngine.Rect(u,v,uw,vh)
        graphics[i-1]=image
    end
    original.enabled=false
    surface.graphics=graphics
end
