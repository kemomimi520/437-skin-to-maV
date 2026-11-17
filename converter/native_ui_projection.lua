-- Map an ordinary native UI node through the captured 437 Director plane.
-- A non-uniform screen projection must PRECEDE the source node rotation:
-- changing the node Width/Height after rotation cannot express that matrix.
local NativeUiProjection={items={},caches={}}

function NativeUiProjection.ScreenMap(projection,width,height)
    local p=projection.matrix
    assert(#p==16 and p[4]==0 and p[8]==0 and p[16]>0 and
        p[2]==0 and p[5]==0 and width>0 and height>0,
        'Unsupported original UI projection plane')
    local sx=width/height*projection.logical_height*p[1]/(2*p[16])
    local sy=projection.logical_height*p[6]/(2*p[16])
    return sx,sy,width*(1+p[13]/p[16])/2,height*(1+p[14]/p[16])/2
end

-- Return A=R(left)*diag(sx,sy)*R(right), with column vectors. This also
-- preserves shear introduced by a rotated/scaled native parent coordinate
-- system; a single RectTransform cannot represent that general affine map.
function NativeUiProjection.Factor(a,b,c,d)
    local determinant=a*d-b*c
    assert(determinant>1e-12,'Singular or reflected UI projection')
    local xx,xy,yy=a*a+c*c,a*b+c*d,b*b+d*d
    local angle=.5*math.atan(2*xy,xx-yy)
    local vx,vy=math.cos(angle),math.sin(angle)
    local ux,uy=a*vx+b*vy,c*vx+d*vy
    local sx=math.sqrt(ux*ux+uy*uy)
    assert(sx>1e-12,'Singular UI projection basis')
    local sy=determinant/sx
    return math.atan(uy,ux),sx,sy,-angle
end

-- Conjugate screen-axis projection into the actual parent coordinate basis.
function NativeUiProjection.ParentMap(b00,b01,b10,b11,sx,sy)
    local det=b00*b11-b01*b10
    assert(math.abs(det)>1e-12,'Native UI parent has singular screen basis')
    return (b11*sx*b00-b01*sy*b10)/det,
        (b11*sx*b01-b01*sy*b11)/det,
        (-b10*sx*b00+b00*sy*b10)/det,
        (-b10*sx*b01+b00*sy*b11)/det
end

local function cameraFor(object)
    local U=CS.UnityEngine;local cameras=U.Object.FindObjectsOfType(typeof(U.Camera),false)
    local mask=1<<object.layer;local camera
    for i=0,cameras.Length-1 do
        local candidate=cameras[i]
        if candidate.enabled and candidate.gameObject.activeInHierarchy and candidate.cullingMask&mask~=0 then
            assert(not camera,'Ambiguous native UI camera');camera=candidate
        end
    end
    return assert(camera,'Native UI camera missing')
end

local function originalPivot(saved,parent)
    -- RectTransform anchor reference relative to the ORIGINAL parent pivot.
    local pivot=parent.pivot;local size=parent.rect
    local ax=saved.anchorMin.x+(saved.anchorMax.x-saved.anchorMin.x)*saved.pivot.x
    local ay=saved.anchorMin.y+(saved.anchorMax.y-saved.anchorMin.y)*saved.pivot.y
    return (ax-pivot.x)*size.width+saved.position.x,
        (ay-pivot.y)*size.height+saved.position.y
end

local function getParentCache(parent,camera,screenWidth,screenHeight,frameCache)
    local U=CS.UnityEngine
    local shared
    if frameCache then
        local byCam=frameCache.by_parent[camera]
        if not byCam then byCam={};frameCache.by_parent[camera]=byCam end
        shared=byCam[parent]
        if shared then return shared end
    end
    local byCamPersist=NativeUiProjection.caches[camera]
    if not byCamPersist then byCamPersist={};NativeUiProjection.caches[camera]=byCamPersist end
    local pc=byCamPersist[parent]
    local viewport=camera.pixelRect
    local vx,vy,vw,vh=viewport.x,viewport.y,viewport.width,viewport.height
    local size=parent.rect;local pivot=parent.pivot
    local w,h=size.width,size.height;local px0,py0=pivot.x,pivot.y
    local span=math.max(w,h,1)
    local origin=camera:WorldToScreenPoint(parent:TransformPoint(U.Vector3(0,0,0)))
    local px=camera:WorldToScreenPoint(parent:TransformPoint(U.Vector3(span,0,0)))
    local py=camera:WorldToScreenPoint(parent:TransformPoint(U.Vector3(0,span,0)))
    local ox,oy,oz=origin.x,origin.y,origin.z
    local pxx,pxy,pxz=px.x,px.y,px.z
    local pyx,pyy,pyz=py.x,py.y,py.z
    if not pc or pc.sw~=screenWidth or pc.sh~=screenHeight or
            pc.w~=w or pc.h~=h or pc.px0~=px0 or pc.py0~=py0 or
            pc.ox~=ox or pc.oy~=oy or pc.pxx~=pxx or pc.pxy~=pxy or
            pc.pyx~=pyx or pc.pyy~=pyy or
            pc.vx~=vx or pc.vy~=vy or pc.vw~=vw or pc.vh~=vh then
        assert(math.abs(vx)<.01 and math.abs(vy)<.01 and
            math.abs(vw-screenWidth)<.01 and math.abs(vh-screenHeight)<.01,
            'Original UI projection requires the full native viewport')
        local diagonal=camera:WorldToScreenPoint(parent:TransformPoint(U.Vector3(span,span,0)))
        assert(math.abs(oz-pxz)<.01 and math.abs(oz-pyz)<.01 and
            math.abs(diagonal.x-pxx-pyx+ox)<.02 and
            math.abs(diagonal.y-pxy-pyy+oy)<.02,
            'Native UI parent is not an affine screen plane')
        local b00,b10=(pxx-ox)/span,(pxy-oy)/span
        local b01,b11=(pyx-ox)/span,(pyy-oy)/span
        local det=b00*b11-b01*b10
        pc={ver=(pc and pc.ver or 0)+1,sw=screenWidth,sh=screenHeight,
            w=w,h=h,px0=px0,py0=py0,ox=ox,oy=oy,pxx=pxx,pxy=pxy,pyx=pyx,pyy=pyy,
            vx=vx,vy=vy,vw=vw,vh=vh,b00=b00,b01=b01,b10=b10,b11=b11,det=det,smap={}}
        byCamPersist[parent]=pc
    end
    if frameCache then frameCache.by_parent[camera][parent]=pc end
    return pc
end

local function resolveProjection(item,shared,screenWidth,screenHeight)
    local proj=item.projection
    local cr=item.compiled_ratio
    if not cr or screenHeight<=0 then return proj,item.sourcePosition[1] end
    local aspect=screenWidth/screenHeight
    if math.abs(aspect-cr)<=1e-5 then return proj,item.sourcePosition[1] end
    local adapted=shared.adapted and shared.adapted[proj]
    if not adapted then
        if not shared.adapted then shared.adapted={} end
        local m={};for i=1,16 do m[i]=proj.matrix[i] end
        m[1]=m[6]/aspect
        adapted={logical_height=proj.logical_height,matrix=m}
        shared.adapted[proj]=adapted
    end
    local oldX=item.sourcePosition[1]+(item.source_pct_x or 0)*proj.logical_height*(aspect-cr)
    return adapted,oldX
end

local function liveScreenDimensions(U,camera)
    local S=U and U.Screen
    if S then
        local sw,sh=S.width,S.height
        if type(sw)=='number' and type(sh)=='number' and sh>0 then return sw,sh end
    end
    if camera and camera.pixelRect then
        local vp=camera.pixelRect
        if type(vp.width)=='number' and type(vp.height)=='number' and vp.height>0 then
            return vp.width,vp.height
        end
    end
    if Game and Game.Width and Game.Height then
        local gw,gh=Game:Width(),Game:Height()
        if type(gw)=='number' and type(gh)=='number' and gh>0 then return gw,gh end
    end
    return 0,0
end

local function update(item,frameCache)
    local U=CS.UnityEngine;local parent=item.parent;local camera=item.camera
    local screenWidth,screenHeight
    if frameCache then
        screenWidth,screenHeight=frameCache.sw,frameCache.sh
    else
        screenWidth,screenHeight=liveScreenDimensions(U,camera)
    end
    local shared=getParentCache(parent,camera,screenWidth,screenHeight,frameCache)
    if item.c_ver==shared.ver and item.c_proj==item.projection then return end
    local proj,oldX=resolveProjection(item,shared,screenWidth,screenHeight)
    local smap=shared.smap[proj]
    if not smap then
        local sx,sy,biasX,biasY=NativeUiProjection.ScreenMap(proj,screenWidth,screenHeight)
        local a,b,c,d=NativeUiProjection.ParentMap(shared.b00,shared.b01,shared.b10,shared.b11,sx,sy)
        local left,scaleX,scaleY,right=NativeUiProjection.Factor(a,b,c,d)
        smap={sx=sx,sy=sy,biasX=biasX,biasY=biasY,left=left,scaleX=scaleX,scaleY=scaleY,right=right}
        shared.smap[proj]=smap
    end
    local sx,sy,biasX,biasY=smap.sx,smap.sy,smap.biasX,smap.biasY
    local left,scaleX,scaleY,right=smap.left,smap.scaleX,smap.scaleY,smap.right
    local w,h,px0,py0=shared.w,shared.h,shared.px0,shared.py0
    local ax=item.saved_ax;local ay=item.saved_ay
    local x,y
    if ax then
        x=(ax-px0)*w+item.saved_px;y=(ay-py0)*h+item.saved_py
    else
        x,y=originalPivot(item.saved,parent)
    end
    local ox,oy=shared.ox,shared.oy
    local b00,b01,b10,b11,det=shared.b00,shared.b01,shared.b10,shared.b11,shared.det
    local originalX=ox+b00*x+b01*y
    local originalY=oy+b10*x+b11*y
    local old=item.sourcePosition;local height=proj.logical_height
    local sourceX,sourceY=oldX*screenHeight/height,old[2]*screenHeight/height
    local targetX,targetY=sx*sourceX+biasX,sy*sourceY+biasY
    local deltaX=targetX-ox-sx*(originalX-ox)
    local deltaY=targetY-oy-sy*(originalY-oy)
    local dx,dy=(b11*deltaX-b01*deltaY)/det,(-b10*deltaX+b00*deltaY)/det
    local one,two=item.outer,item.inner
    if item.c_w~=w or item.c_h~=h or item.c_px0~=px0 or item.c_py0~=py0 then
        local pv=U.Vector2(px0,py0);local sd=U.Vector2(w,h)
        for _,rect in ipairs({one,two}) do
            rect.anchorMin=pv;rect.anchorMax=pv;rect.pivot=pv;rect.sizeDelta=sd
        end
    end
    one.anchoredPosition=U.Vector2(dx,dy)
    one.localRotation=U.Quaternion.Euler(0,0,left*180/math.pi)
    one.localScale=U.Vector3(scaleX,scaleY,1)
    if not item.two_zeroed then
        two.anchoredPosition=U.Vector2(0,0)
        two.localRotation=U.Quaternion.Euler(0,0,right*180/math.pi)
        two.localScale=U.Vector3(1,1,1)
        item.two_zeroed=true;item.last_right=right
    elseif item.last_right~=right then
        two.localRotation=U.Quaternion.Euler(0,0,right*180/math.pi)
        item.last_right=right
    end
    item.c_ver=shared.ver;item.c_proj=item.projection
    item.c_w=w;item.c_h=h;item.c_px0=px0;item.c_py0=py0
end

function NativeUiProjection.Bind(module,projection,sourcePosition,anchor,options)
    if #NativeUiProjection.items==0 then NativeUiProjection.caches={};NativeUiProjection._stable=0;NativeUiProjection._last_fc=nil end
    local U=CS.UnityEngine;local rect=module.transform;local parent=assert(rect.parent,'Native UI parent missing')
    -- Keep the original anchor/offset position as the new pivot point. The
    -- compound Draw applies the source anchor to both children afterwards.
    rect.pivot=U.Vector2(anchor[1],anchor[2])
    local saved={anchorMin=rect.anchorMin,anchorMax=rect.anchorMax,pivot=rect.pivot,
        position=rect.anchoredPosition3D,size=rect.sizeDelta,rotation=rect.localRotation,scale=rect.localScale}
    local savedAx=saved.anchorMin.x+(saved.anchorMax.x-saved.anchorMin.x)*saved.pivot.x
    local savedAy=saved.anchorMin.y+(saved.anchorMax.y-saved.anchorMin.y)*saved.pivot.y
    local savedPx=saved.position.x;local savedPy=saved.position.y
    local sibling=rect:GetSiblingIndex()
    local camera=cameraFor(module.gameObject)
    local one=U.GameObject('legacy-ui-projection',typeof(U.RectTransform))
    local two=U.GameObject('legacy-ui-projection-basis',typeof(U.RectTransform))
    one.layer=module.gameObject.layer;two.layer=module.gameObject.layer
    one.transform:SetParent(parent,false);one.transform:SetSiblingIndex(sibling)
    two.transform:SetParent(one.transform,false)
    local item={parent=parent,camera=camera,outer=one.transform,inner=two.transform,
        saved=saved,saved_ax=savedAx,saved_ay=savedAy,saved_px=savedPx,saved_py=savedPy,
        projection=projection,sourcePosition=sourcePosition,
        compiled_ratio=options and options.compiled_ratio,
        source_pct_x=options and options.source_pct_x}
    update(item)
    rect:SetParent(two.transform,false)
    rect.anchorMin=saved.anchorMin;rect.anchorMax=saved.anchorMax;rect.pivot=saved.pivot
    rect.sizeDelta=saved.size;rect.anchoredPosition3D=saved.position
    rect.localRotation=saved.rotation;rect.localScale=saved.scale
    NativeUiProjection.items[#NativeUiProjection.items+1]=item
    NativeUiProjection._dirty=true
    return item
end

function NativeUiProjection.Update()
    local items=NativeUiProjection.items
    if #items==0 then return end
    local U=CS.UnityEngine
    local time=U.Time;local fc=time and time.frameCount
    if fc~=nil and NativeUiProjection._last_fc~=nil and fc~=NativeUiProjection._last_fc
            and not NativeUiProjection._dirty
            and (NativeUiProjection._stable or 0)>10 and (fc%180)~=0 then
        NativeUiProjection._last_fc=fc
        return
    end
    local sw,sh=liveScreenDimensions(U,items[1] and items[1].camera)
    if fc~=nil and NativeUiProjection._last_fc~=nil and fc~=NativeUiProjection._last_fc
            and not NativeUiProjection._dirty and sw==NativeUiProjection._sw and sh==NativeUiProjection._sh
            and (NativeUiProjection._stable or 0)>10 and (fc%180)~=0 then
        NativeUiProjection._last_fc=fc
        return
    end
    local frameCache=NativeUiProjection._frameCache
    if not frameCache then
        frameCache={by_parent={}};NativeUiProjection._frameCache=frameCache
    else
        for k in pairs(frameCache.by_parent) do frameCache.by_parent[k]=nil end
    end
    frameCache.sw=sw;frameCache.sh=sh
    for _,item in ipairs(items) do update(item,frameCache) end
    if fc~=nil then
        if sw==NativeUiProjection._sw and sh==NativeUiProjection._sh and not NativeUiProjection._dirty then
            NativeUiProjection._stable=(NativeUiProjection._stable or 0)+1
        else
            NativeUiProjection._stable=1
        end
        NativeUiProjection._sw=sw;NativeUiProjection._sh=sh;NativeUiProjection._last_fc=fc
    end
    NativeUiProjection._dirty=false
end
