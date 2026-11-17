-- Projects @apply 3d PlayField UI (1 <= zindex <= 98) onto legacy_play_plane
-- using each module's live Canvas RectTransform so animations, frames,
-- events, strips, anchors and aspect ratios stay aligned with 3D notes.
local NativeSourcePlaneUI={items={}}
local whiteSprite,additiveBaseMaterial,dstBlendBaseMaterial
local function ensureUiAssembly()
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UI') end
end
local function ensureWhiteSprite(U)
    if whiteSprite then return whiteSprite end
    local tex=U.Texture2D.whiteTexture
    whiteSprite=U.Sprite.Create(tex,U.Rect(0,0,tex.width,tex.height),U.Vector2(0.5,0.5))
    return whiteSprite
end
local function findBlendMaterial(U,img,cfg)
    if cfg.blend==2 then
        if dstBlendBaseMaterial then return dstBlendBaseMaterial end
        local shader=U.Shader.Find('Live2D/Live2D PremultipliedAlpha')
        if shader then
            local m=U.Material(shader)
            m:SetFloat('_SrcColor',4)
            m:SetFloat('_DstColor',1)
            m:SetFloat('_SrcAlpha',8)
            m:SetFloat('_DstAlpha',1)
            m:SetFloat('_Cull',0)
            dstBlendBaseMaterial=m
            return m
        end
        return nil
    end
    if not cfg.additive then return nil end
    if img and img.material and img.material.shader and img.material.shader.name=='Malody/UI/Additive' then
        additiveBaseMaterial=img.material
        return img.material
    end
    if additiveBaseMaterial then return additiveBaseMaterial end
    local shader=U.Shader.Find('Malody/UI/Additive')
    if shader then
        local m=U.Material(shader)
        if m.EnableKeyword then pcall(function() m:EnableKeyword('BLEND_ADDITIVE') end) end
        pcall(function() m:SetFloat('_Additive',1) end)
        pcall(function() m:SetColor('_Color',U.Color(1,1,1,1)) end)
        additiveBaseMaterial=m
        return m
    end
    return nil
end
local function hideCanvasModule(go)
    if not go then return end
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UIModule') end
    local U=CS.UnityEngine
    local ok,cg=pcall(function()
        return go:GetComponent(typeof(U.CanvasGroup)) or go:AddComponent(typeof(U.CanvasGroup))
    end)
    if ok and cg then
        cg.alpha=0
        cg.blocksRaycasts=false
        cg.interactable=false
        return cg
    end
    return nil
end
local function collectStripGraphics(transform,rootImage)
    ensureUiAssembly()
    local out={}
    local U=CS.UnityEngine
    for i=0,transform.childCount-1 do
        local child=transform:GetChild(i)
        local r=child.gameObject:GetComponent(typeof(U.UI.RawImage))
        if r then
            out[#out+1]={raw=r,rect=r.rectTransform,is_raw=true}
        else
            local g=child.gameObject:GetComponent(typeof(U.UI.Image))
            if g and g~=rootImage then out[#out+1]={image=g,rect=g.rectTransform} end
        end
    end
    return out
end
local function collectNumberSlots(item,U)
    local parent=item.numberTransform or item.transform
    if not parent then return item.slots end
    local count=parent.childCount
    if item.last_child_count==count then return item.slots end
    item.last_child_count=count
    local prevByGo={}
    for _,s in ipairs(item.slots) do
        if s.go then prevByGo[s.go]=s end
    end
    local nextSlots={}
    for i=0,count-1 do
        local child=parent:GetChild(i)
        local img=child.gameObject:GetComponent(typeof(U.UI.Image))
        if img then
            local old=prevByGo[child.gameObject]
            if old then
                old.image=img;old.rect=img.rectTransform
                nextSlots[#nextSlots+1]=old
                prevByGo[child.gameObject]=nil
            else
                nextSlots[#nextSlots+1]={go=child.gameObject,image=img,rect=img.rectTransform,part=nil}
            end
        end
    end
    for _,orphan in pairs(prevByGo) do
        if orphan.part then pcall(NativeSourcePart3Mesh.DisposeSprite,orphan.part) end
    end
    item.slots=nextSlots
    return item.slots
end
function NativeSourcePlaneUI.Clear()
    NativeSourcePlaneUI.Reset()
    NativeSourcePlaneUI.items={}
end
function NativeSourcePlaneUI.Reset()
    for _,item in ipairs(NativeSourcePlaneUI.items) do
        for _,slot in ipairs(item.slots or {}) do
            if slot.part then pcall(NativeSourcePart3Mesh.DisposeSprite,slot.part);slot.part=nil end
        end
    end
end
function NativeSourcePlaneUI.Bind(module,entry)
    local cfg=entry.source_plane_ui
    if not cfg then return end
    ensureUiAssembly()
    local U=CS.UnityEngine
    local img=module.transform.gameObject:GetComponent(typeof(U.UI.Image))
    if not img and not cfg.number then return end
    local cg=hideCanvasModule(module.gameObject)
    local canvas=img and img.canvas or module.transform.gameObject:GetComponentInParent(typeof(U.Canvas))
    local rootCanvas=canvas and canvas.rootCanvas or canvas
    local uiCam=rootCanvas and rootCanvas.worldCamera or (canvas and canvas.worldCamera) or nil
    local numTransform
    if cfg.number then
        if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'Assembly-CSharp') end
        local function findNum(tr)
            if CS.Malody and CS.Malody.UI and CS.Malody.UI.UIDynamicNumber then
                local ok,comp=pcall(function() return tr.gameObject:GetComponent(typeof(CS.Malody.UI.UIDynamicNumber)) end)
                if ok and comp then return tr end
            end
            for i=0,tr.childCount-1 do
                local res=findNum(tr:GetChild(i))
                if res then return res end
            end
            return nil
        end
        numTransform=findNum(module.transform) or module.transform
    end
    local slots={}
    if cfg.number then
        -- Collected dynamically on Update as UIDynamicNumber grows its digit pool.
    elseif entry.source_strip then
        slots=collectStripGraphics(module.transform,img)
    else
        slots={{image=img,rect=img.rectTransform,part=nil}}
    end
    NativeSourcePlaneUI.items[#NativeSourcePlaneUI.items+1]={
        handle=entry.handle,
        cfg=cfg,
        transform=module.transform,
        numberTransform=numTransform,
        rootImage=img,
        uiCam=uiCam,
        cg=cg,
        slots=slots,
    }
end
local function rectToPlanePoints(rt,uiCam,screenH,U)
    local r=rt.rect
    if (r.xMax-r.xMin)<=0 or (r.yMax-r.yMin)<=0 then return nil end
    local wtp=U.RectTransformUtility.WorldToScreenPoint
    local pBL=wtp(uiCam,rt:TransformPoint(U.Vector3(r.xMin,r.yMin,0)))
    local pBR=wtp(uiCam,rt:TransformPoint(U.Vector3(r.xMax,r.yMin,0)))
    local pTL=wtp(uiCam,rt:TransformPoint(U.Vector3(r.xMin,r.yMax,0)))
    local pTR=wtp(uiCam,rt:TransformPoint(U.Vector3(r.xMax,r.yMax,0)))
    local s=720/screenH
    return {
        {pTL.x*s,pTL.y*s},
        {pTR.x*s,pTR.y*s},
        {pBL.x*s,pBL.y*s},
        {pBR.x*s,pBR.y*s},
    }
end
local function hidePart(part)
    if part then
        part.object:SetActive(false)
        part.renderer.enabled=false
    end
end
function NativeSourcePlaneUI.Update(pool)
    if not (pool and pool.root and pool.noteCamera and pool.config and pool.config.motion and pool.config.motion.legacy_play_plane) then
        return
    end
    local U=CS.UnityEngine
    local plane=pool.config.motion.legacy_play_plane
    local cam=pool.noteCamera
    local screenH=cam.pixelHeight
    if not screenH or screenH<=0 then return end
    local rootT=pool.root.transform
    local depth=cam:WorldToScreenPoint(rootT.position).z
    for _,item in ipairs(NativeSourcePlaneUI.items) do
        if item.cg then item.cg.alpha=0 end
        local cfg=item.cfg
        local additiveMat=findBlendMaterial(U,item.rootImage,cfg)
        local parentActive=true
        if item.transform and item.transform.gameObject and item.transform.gameObject.activeInHierarchy==false then
            parentActive=false
        elseif item.rootImage and item.rootImage.gameObject and item.rootImage.gameObject.activeInHierarchy==false then
            parentActive=false
        end
        if cfg.number then collectNumberSlots(item,U) end
        for sIdx,slot in ipairs(item.slots) do
            local g=slot.is_raw and slot.raw or slot.image
            local goActive=true
            if cfg.number and slot.go and not slot.go.activeSelf then goActive=false end
            if not parentActive or not goActive or not g or not g.enabled then
                hidePart(slot.part)
            else
                local c=g.color
                local a=math.max(0,math.min(255,math.floor(c.a*255+0.5)))
                if a<=0 then
                    hidePart(slot.part)
                else
                    local points=rectToPlanePoints(slot.rect,item.uiCam,screenH,U)
                    local tint={
                        math.max(0,math.min(255,math.floor(c.r*255+0.5))),
                        math.max(0,math.min(255,math.floor(c.g*255+0.5))),
                        math.max(0,math.min(255,math.floor(c.b*255+0.5))),
                        a,
                    }
                    if slot.is_raw then
                        local tex=g.texture
                        if not points or not tex then
                            hidePart(slot.part)
                        else
                            local uvr=g.uvRect
                            if not slot.part then
                                slot.part=NativeSourcePart3Mesh.NewRaw(
                                    pool.root,
                                    'legacy-plane-ui-'..tostring(item.handle)..'-'..sIdx,
                                    tex,uvr,cfg.order,additiveMat
                                )
                            end
                            NativeSourcePart3Mesh.UpdateRaw(slot.part,points,plane,cam,rootT,depth,tint,tex,uvr)
                        end
                    else
                        local sprite=cfg.solid and ensureWhiteSprite(U) or g.sprite
                        if not points or not sprite then
                            hidePart(slot.part)
                        else
                            if not slot.part then
                                slot.part=NativeSourcePart3Mesh.NewSprite(
                                    pool.root,
                                    'legacy-plane-ui-'..tostring(item.handle)..'-'..sIdx,
                                    sprite,
                                    cfg.order,
                                    additiveMat
                                )
                            end
                            NativeSourcePart3Mesh.UpdateSprite(slot.part,points,plane,cam,rootT,depth,tint,sprite)
                        end
                    end
                end
            end
        end
    end
end
