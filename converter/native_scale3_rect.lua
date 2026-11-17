-- Geometry candidate: original three Sprites, laid out by the game's own
-- UISpriteRect components before rendering. No Lua vertex/transform draw
-- loop. The source-window adapter can explicitly repair changed offscreen
-- body bounds through the original C++ layout. Note lifetime is separate.
-- Requires scale3Parts from native_scale3_sprite.lua in the same scope.
local function nativeScale3RectObject(name,parent,layer)
    local U=CS.UnityEngine
    -- xLua's params wrapper accepts Type arguments, not one Type[] userdata.
    -- This is the same retained call used by the existing native UI bridge.
    local object=U.GameObject(name,typeof(U.RectTransform))
    object.layer=layer
    local rect=object:GetComponent(typeof(U.RectTransform))
    rect:SetParent(parent,false)
    rect.pivot=U.Vector2(0,0)
    rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(0,0)
    rect.anchoredPosition=U.Vector2(0,0)
    return object,rect
end

local function captureNativeScale3Renderer(renderer)
    local U=CS.UnityEngine
    local object,rect=renderer.gameObject,renderer.transform
    assert(rect:GetType().FullName=='UnityEngine.RectTransform','Borrowed source segment must have a RectTransform')
    local saved={renderer=renderer,rect=rect,parent=rect.parent,sibling=rect:GetSiblingIndex(),
        pivot=rect.pivot,anchorMin=rect.anchorMin,anchorMax=rect.anchorMax,
        sizeDelta=rect.sizeDelta,anchoredPosition=rect.anchoredPosition3D,
        scale=rect.localScale,rotation=rect.localRotation,active=object.activeSelf,
        sprite=renderer.sprite,enabled=renderer.enabled,color=renderer.color,
        material=renderer.sharedMaterial,sortingLayerID=renderer.sortingLayerID,
        sortingOrder=renderer.sortingOrder,drawMode=renderer.drawMode,size=renderer.size,components={}}
    -- These components cache the ORIGINAL rectangle's offsets and scale.
    -- Their LateUpdate must not overwrite the source segment's new rectangle.
    for _,kind in ipairs({typeof(CS.Malody.UI.UIOffsetScale),typeof(CS.Malody.Scene.Play.PlayKeyTrackScaledObject)}) do
        local component=object:GetComponent(kind)
        if component then
            saved.components[#saved.components+1]={object=component,enabled=component.enabled}
        end
    end
    local layout=object:GetComponent(typeof(CS.Malody.UI.UISpriteRect))
    assert(layout,'Borrowed native renderer requires its existing UISpriteRect')
    saved.layout=layout;saved.layoutEnabled=layout.enabled
    return saved
end

local function borrowNativeScale3Renderer(saved,root)
    local U=CS.UnityEngine
    local object,rect=saved.renderer.gameObject,saved.rect
    for _,c in ipairs(saved.components) do c.object.enabled=false end
    rect:SetParent(root,false)
    rect.pivot=U.Vector2(0,0)
    rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(0,0)
    rect.anchoredPosition=U.Vector2(0,0)
    rect.localRotation=U.Quaternion.identity;rect.localScale=U.Vector3(1,1,1)
    object:SetActive(true)
end

local function restoreNativeScale3Renderer(saved)
    local r,t=saved.renderer,saved.rect
    t:SetParent(saved.parent,false);t:SetSiblingIndex(saved.sibling)
    r.sprite=saved.sprite;r.enabled=saved.enabled;r.color=saved.color
    r.sharedMaterial=saved.material;r.sortingLayerID=saved.sortingLayerID
    r.sortingOrder=saved.sortingOrder;r.drawMode=saved.drawMode;r.size=saved.size
    if saved.layout then saved.layout.enabled=saved.layoutEnabled end
    for _,c in ipairs(saved.components) do c.object.enabled=c.enabled end
    t.pivot=saved.pivot;t.anchorMin=saved.anchorMin;t.anchorMax=saved.anchorMax
    t.sizeDelta=saved.sizeDelta;t.anchoredPosition3D=saved.anchoredPosition
    t.localRotation=saved.rotation;t.localScale=saved.scale
    r.gameObject:SetActive(saved.active)
end

-- Optional renderers are BORROWED from the native note, never replaced in
-- its fields. C++ colour/Mod updates therefore still address those objects.
-- Caller must separately handle cached native sizes, pool ownership and
-- per-factory admission/lifetime. Borrowing alone does not implement them.
local function nativeScale3SampleRect(sourceRect,height,cut)
    -- Original Sprite_SetRectFixed(1) moves both UV endpoints to texel
    -- centres. Geometry still uses the FULL cut, independently of this rect.
    assert(cut[3]>=1 and cut[4]>=1,'Sprite-only inverted source UV span is not implemented')
    local epsilon=1/65536
    local w,h=cut[3]-1,cut[4]-1
    local x=sourceRect.x+cut[1]+.5
    local y=sourceRect.y+height-cut[2]-cut[4]+.5
    -- Sprite.Create needs positive geometry. A tiny positive source span
    -- represents a constant one-texel UV; C++ Sliced size owns geometry.
    if w==0 then w=epsilon;x=x-epsilon*.5 end
    if h==0 then h=epsilon;y=y-epsilon*.5 end
    return {scale3float(x),scale3float(y),scale3float(w),scale3float(h)}
end
local function newNativeScale3Rect(source,reference,parent,part,cache,renderers)
    assert(cache,'Native Scale3 rect requires an explicitly owned Sprite cache')
    local U=CS.UnityEngine
    local sourceRect=source.textureRect
    local width,height=sourceRect.width,sourceRect.height
    local plan=scale3Parts(width,height,height,part)
    local snapshots={}
    if renderers then
        assert(#renderers==3,'Exactly three native renderers must be borrowed')
        for i=1,3 do
            for j=1,i-1 do assert(not renderers[i]:Equals(renderers[j]),'Cannot borrow one renderer for two source parts') end
            snapshots[i]=captureNativeScale3Renderer(renderers[i])
        end
    end
    local material,color=reference.sharedMaterial,reference.color
    local sortingLayerID,sortingOrder=reference.sortingLayerID,reference.sortingOrder
    local object,root=nativeScale3RectObject('legacy-scale3-native-rect',parent,reference.gameObject.layer)
    -- Native head/body RectTransforms have large logical rectangles. Anchor
    -- at the parent's pivot to reproduce Transform local origin, rather than
    -- shifting to its bottom-left by half that logical rectangle.
    if parent:GetType().FullName=='UnityEngine.RectTransform' then
        root.anchorMin=parent.pivot;root.anchorMax=parent.pivot
        root.anchoredPosition=U.Vector2(0,0)
    end
    root.sizeDelta=U.Vector2(width,height)
    local state={object=object,root=root,parts={},width=width,height=height,part=part,heightWrites=0,borrowed={}}
    for i,p in ipairs(plan) do
        local cut=p.rect
        local child,rect,renderer,saved
        if renderers then
            renderer=renderers[i]
            saved=snapshots[i];borrowNativeScale3Renderer(saved,root)
            state.borrowed[#state.borrowed+1]=saved
            child,rect=renderer.gameObject,renderer.transform
        end
        if cut[4]>0 then
            if not child then child,rect=nativeScale3RectObject('legacy-scale3-native-part-'..i,root,object.layer) end
            local sampled=nativeScale3SampleRect(sourceRect,height,cut)
            local key='texel-centres-v1:'..table.concat({source.texture:GetInstanceID(),table.unpack(sampled)},':')
            if not cache[key] then
                cache[key]=U.Sprite.Create(source.texture,
                    U.Rect(table.unpack(sampled)),
                    U.Vector2(0,0),1,0,U.SpriteMeshType.FullRect,U.Vector4(0,0,0,0),false)
                cache[key].name='legacy-scale3-texel-centres-v1'
            end
            if not renderer then renderer=child:AddComponent(typeof(U.SpriteRenderer)) end
            renderer.sprite=cache[key]
            renderer.sharedMaterial=material
            if not renderers then renderer.color=color end
            renderer.enabled=true
            renderer.sortingLayerID=sortingLayerID
            -- Source sorted Node children are middle, upper cap, lower cap
            -- (roles 3,1,2), not the geometry table's roles 1,2,3.
            renderer.sortingOrder=sortingOrder+({1,2,0})[i]
            if i==1 then
                rect.anchorMin=U.Vector2(0,1);rect.anchorMax=U.Vector2(0,1)
                rect.sizeDelta=U.Vector2(width,cut[4]);rect.anchoredPosition=U.Vector2(0,-cut[4])
            elseif i==2 then
                rect.sizeDelta=U.Vector2(width,cut[4]);rect.anchoredPosition=U.Vector2(0,0)
            else
                rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(0,1)
                rect.offsetMin=U.Vector2(0,plan[2].rect[4])
                rect.offsetMax=U.Vector2(width,-plan[1].rect[4])
            end
            local layout=saved and saved.layout or child:AddComponent(typeof(CS.Malody.UI.UISpriteRect))
            layout.enabled=true
            state.parts[i]={object=child,rect=rect,renderer=renderer,layout=layout}
        elseif renderer then
            -- Retain the valid C++ field even when the source cap is empty.
            rect.anchorMin=U.Vector2(0,1);rect.anchorMax=U.Vector2(0,1)
            rect.sizeDelta=U.Vector2(width,0);rect.anchoredPosition=U.Vector2(0,0)
            renderer.sprite=nil;renderer.enabled=false
        end
    end
    function state:SetHeight(contentHeight)
        scale3Parts(self.width,self.height,contentHeight,self.part)
        self.root.sizeDelta=U.Vector2(self.width,contentHeight)
        self.heightWrites=self.heightWrites+1
    end
    function state:BindRange(spec)
        local parent=self.root.parent
        assert(parent:GetType().FullName=='UnityEngine.RectTransform','Native motion range must be a RectTransform')
        self.root.pivot=U.Vector2(spec.pivot[1],spec.pivot[2])
        if spec.fixed_at_admission then
            -- Default Scale3 admits one whole image ONCE. It must not inherit
            -- the later shrinking native head/tail range used by Part3.
            local sourceHeight=spec.unclipped_range_height
            if sourceHeight==nil then sourceHeight=parent.rect.height end -- controlled geometry sampler only
            assert(sourceHeight==sourceHeight and math.abs(sourceHeight)<math.huge,'Non-finite admission range')
            self.admissionRangeHeight=sourceHeight
            self.admittedHeight=spec.source_admitted_height or scale3float(scale3float(sourceHeight*scale3float(spec.anchor_y[2]-spec.anchor_y[1]))+spec.size_delta[2])
            self.root.anchorMin=U.Vector2(parent.pivot.x,0)
            self.root.anchorMax=U.Vector2(parent.pivot.x,0)
            self.root.sizeDelta=U.Vector2(spec.size_delta[1],self.admittedHeight)
        else
            self.root.anchorMin=U.Vector2(parent.pivot.x,spec.anchor_y[1])
            self.root.anchorMax=U.Vector2(parent.pivot.x,spec.anchor_y[2])
            self.root.sizeDelta=U.Vector2(spec.size_delta[1],spec.size_delta[2])
        end
        self.root.localScale=U.Vector3(spec.scale[1],spec.scale[2],1)
        self.root.anchoredPosition=U.Vector2(spec.offset[1],spec.offset[2])
        self.rangeBindings=(self.rangeBindings or 0)+1
    end
    function state:RefreshBodyBounds()
        -- OnWillRenderObject cannot repair a stale offscreen bounding box:
        -- culling happens first. Only repair a changed Sliced body, through
        -- the ORIGINAL C++ layout; fixed caps and unchanged sizes do no work.
        local piece=self.parts[3]
        if not piece then return end
        local rect,size=piece.rect.rect,piece.renderer.size
        if rect.width~=size.x or rect.height~=size.y then
            piece.layout:UpdateSpriteSize()
            self.boundsRepairs=(self.boundsRepairs or 0)+1
        end
    end
    function state:Dispose()
        assert(self.object,'Native Scale3 rect disposed twice')
        for _,saved in ipairs(self.borrowed) do
            assert(saved.rect.parent:Equals(self.root),'Native source renderer changed ownership before restore')
        end
        -- Original sibling positions were captured before any reparenting.
        -- Restore in increasing order per parent, including permuted roles.
        table.sort(self.borrowed,function(a,b)
            if a.parent:Equals(b.parent) then return a.sibling<b.sibling end
            return a.parent:GetInstanceID()<b.parent:GetInstanceID()
        end)
        for _,saved in ipairs(self.borrowed) do restoreNativeScale3Renderer(saved) end
        self.borrowed={}
        U.Object.Destroy(self.object);self.object=nil;self.parts={}
    end
    return state
end

local function disposeNativeScale3RectCache(cache)
    for key,sprite in pairs(cache) do CS.UnityEngine.Object.Destroy(sprite);cache[key]=nil end
end
