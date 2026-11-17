-- Original KeyUIS touch regions on the game's own TouchAreaPolygon input.
-- No input, judge, score or replay event is synthesized here.
local NativeUiTouch={items={},bound={}}
local function findNativeTouchModule(name)
    local module=Module:Find(name)
    if not module then return nil end
    local tp=module.GetType and module:GetType()
    if tp and tp.FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeDummy' then return nil end
    return module
end
local function resolveTouchRoot(anchor)
    local cur=anchor
    while cur and cur.parent do
        if cur.parent.name=='RootPlay' then return cur end
        cur=cur.parent
    end
    return anchor
end
local function resolveCanvasMetrics(U,root)
    local aspect,height
    local rt=root and root.GetComponent and U.RectTransform and root:GetComponent(typeof(U.RectTransform))
    if rt and rt.rect and rt.rect.height>0 and rt.rect.width>0 then
        aspect=rt.rect.width/rt.rect.height
        height=rt.rect.height
    end
    if not aspect and Game and Game.Width and Game.Height then
        local gw,gh=Game:Width(),Game:Height()
        if type(gw)=='number' and type(gh)=='number' and gh>0 then aspect=gw/gh end
    end
    if not aspect and U and U.Screen then
        local sw,sh=U.Screen.width,U.Screen.height
        if type(sw)=='number' and type(sh)=='number' and sh>0 then aspect=sw/sh end
    end
    return aspect or (16/9),height or 1080
end
local function disableForeignTouchAreas(U)
    local touchNS=CS.Malody and CS.Malody.Play and CS.Malody.Play.TouchAreaBase
    if not touchNS then return end
    local active=touchNS.activeAreasOrdered
    if active and active.Count<=#NativeUiTouch.items then return end
    if not (U.Object and U.Object.FindObjectsOfType) then return end
    local own={}
    for _,existing in ipairs(NativeUiTouch.items) do own[existing]=true end
    local ok,areas=pcall(U.Object.FindObjectsOfType,typeof(touchNS))
    if ok and areas then
        for i=0,areas.Length-1 do
            local other=areas[i]
            if other and not own[other] and other.enabled then other.enabled=false end
        end
    end
end
local function applyRegionVertices(U,area,region,aspect,height,unit)
    local halfW=aspect*height*0.5
    local halfH=height*0.5
    local scale=height/720
    local vertices=CS.System.Array.CreateInstance(typeof(U.Vector2),#region.points)
    for i,point in ipairs(region.points) do
        local px=point[1]
        if aspect and region.points_pct and region.points_pct[i] and region.points_pct[i]~=0 then
            px=region.points_px[i]+region.points_pct[i]*aspect
        end
        vertices[i-1]=U.Vector2((px*scale-halfW)*unit,(point[2]*scale-halfH)*unit)
    end
    area.vertices=vertices
end
function NativeUiTouch.Bind(data)
    if not data.touches or #data.touches==0 then return end
    local U=CS.UnityEngine;local anchor
    for _,entry in ipairs(data.entries or {}) do
        local module=findNativeTouchModule(entry.handle)
        if module then anchor=module.transform;break end
    end
    assert(anchor,'Native touch regions require an original Key module owner')
    local root=resolveTouchRoot(anchor)
    local unit=CS.Malody.Scene.Play.Skin.SkinRuntime.UnitSize
    local aspect,height=resolveCanvasMetrics(U,root)
    disableForeignTouchAreas(U)
    NativeUiTouch.root=root;NativeUiTouch.lastAspect=aspect
    for _,region in ipairs(data.touches) do
        local go=U.GameObject('native-touch-area-'..region.lane,typeof(U.RectTransform))
        go.layer=root.gameObject.layer;go.transform:SetParent(root,false)
        if go.GetComponent and U.Vector3 and U.Quaternion then
            local rt=go:GetComponent(typeof(U.RectTransform))
            if rt then
                rt.anchorMin=U.Vector2(0.5,0.5);rt.anchorMax=U.Vector2(0.5,0.5);rt.pivot=U.Vector2(0.5,0.5)
                rt.anchoredPosition=U.Vector2(0,0);rt.localScale=U.Vector3(1,1,1);rt.localRotation=U.Quaternion.identity
            end
        end
        local area=go:AddComponent(typeof(CS.Malody.Play.TouchAreaPolygon))
        area.KeyIndex=region.lane-1;area.allowSlide=true;area.penetrate=false
        applyRegionVertices(U,area,region,aspect,height,unit)
        NativeUiTouch.items[#NativeUiTouch.items+1]=area
        NativeUiTouch.bound[#NativeUiTouch.bound+1]={area=area,region=region}
    end
end
function NativeUiTouch.Update()
    if #NativeUiTouch.bound==0 then return end
    local U=CS.UnityEngine;local root=NativeUiTouch.root
    disableForeignTouchAreas(U)
    local aspect,height=resolveCanvasMetrics(U,root)
    if NativeUiTouch.lastAspect and math.abs(aspect-NativeUiTouch.lastAspect)<=1e-5 then return end
    NativeUiTouch.lastAspect=aspect
    local unit=CS.Malody.Scene.Play.Skin.SkinRuntime.UnitSize
    for _,item in ipairs(NativeUiTouch.bound) do
        applyRegionVertices(U,item.area,item.region,aspect,height,unit)
    end
end
