-- Exact old glyph alpha/metrics, rendered with shipped projective meshes.
-- Native TMP continues resolving dynamic variables.
-- Candidate path: full font/layout/lifecycle acceptance remains blocked.
local bitmapTextStates=setmetatable({},{__mode='k'})
local bitmapTextMaterials={}
local retainedTextStats={layouts=0,mesh_builds=0,transform_updates=0}
UnityBridge.RetainedTextPerformance=retainedTextStats
local function positionRetainedText(surface,parent,placement,entry)
    local V=CS.UnityEngine.Vector3
    if surface.direct_plane then
        -- UIWorldPoint already maps clip coordinates into this owned plane.
        -- Keep glyphs here instead of cancelling the moving TMP parent's
        -- position/rotation/scale through six cross-bridge transforms.
        local viewport=UnityBridge.UIViewport;local gl=UnityBridge.FrameGLSize
        local basis=surface.basis
        local sameBasis=basis and basis.m00==placement.m00 and basis.m01==placement.m01 and
            basis.m10==placement.m10 and basis.m11==placement.m11 and basis.w==placement.clipW and
            basis.width==viewport.width and basis.height==viewport.height and basis.gl==gl
        -- Widget's rounded matrix can stay identical while the source moves
        -- fractionally. The owned plane does not inherit the TMP's motion,
        -- so identical final geometry requires no inverse or native setters.
        if sameBasis and basis.m03==placement.m03 and basis.m13==placement.m13 then return end
        local function point(x,y)
            local cx,cy=UnityBridge.BitmapTextClip(placement,x,y)
            return V(cx*viewport.width/(2*gl),cy*viewport.height/(2*gl),0)
        end
        local origin=point(0,0)
        surface.transform.localPosition=origin
        if not sameBasis then
            local u,v=(point(512,0)-origin)/512,(point(0,512)-origin)/512
            assert(u.magnitude>0 and v.magnitude>0 and math.abs(V.Dot(u.normalized,v.normalized))<.0001,
                'Ma Skin Bridge: owned-plane glyph basis is not orthogonal')
            surface.transform.localRotation=CS.UnityEngine.Quaternion.LookRotation(V.Cross(u,v),v)
            surface.transform.localScale=V(u.magnitude,v.magnitude,1)
            surface.basis={m00=placement.m00,m01=placement.m01,m10=placement.m10,m11=placement.m11,
                w=placement.clipW,width=viewport.width,height=viewport.height,gl=gl}
        end
        surface.basis.m03,surface.basis.m13=placement.m03,placement.m13
        retainedTextStats.transform_updates=retainedTextStats.transform_updates+1
        return
    end
    local function point(x,y)
        local cx,cy=UnityBridge.BitmapTextClip(placement,x,y)
        return parent:InverseTransformPoint(UnityBridge.UIWorldPoint(cx,cy,entry))
    end
    local origin=point(0,0)
    local basis=surface.basis
    local rotation,scale,viewport
    if PROFILE.native_stable_text_basis_candidate then
        rotation,scale=parent.localRotation,parent.localScale
        viewport=UnityBridge.UIViewport
        if basis and basis.m00==placement.m00 and basis.m11==placement.m11 and
            basis.m01==placement.m01 and basis.m10==placement.m10 and basis.w==placement.clipW and
            basis.width==viewport.width and basis.height==viewport.height and basis.gl==UnityBridge.FrameGLSize and
            basis.rx==rotation.x and basis.ry==rotation.y and basis.rz==rotation.z and basis.rw==rotation.w and
            basis.sx==scale.x and basis.sy==scale.y and basis.sz==scale.z then
            surface.transform.localPosition=origin
            retainedTextStats.transform_updates=retainedTextStats.transform_updates+1
            return
        end
    end
    local px,py=point(512,0),point(0,512)
    local u,v=(px-origin)/512,(py-origin)/512
    assert(u.magnitude>0 and v.magnitude>0 and math.abs(V.Dot(u.normalized,v.normalized))<.0001,
        'Ma Skin Bridge: retained glyph basis is not orthogonal')
    surface.transform.localPosition=origin
    surface.transform.localRotation=CS.UnityEngine.Quaternion.LookRotation(V.Cross(u,v),v)
    surface.transform.localScale=V(u.magnitude,v.magnitude,1)
    if rotation then
        surface.basis={m00=placement.m00,m11=placement.m11,m01=placement.m01,m10=placement.m10,w=placement.clipW,
            width=viewport.width,height=viewport.height,gl=UnityBridge.FrameGLSize,
            rx=rotation.x,ry=rotation.y,rz=rotation.z,rw=rotation.w,sx=scale.x,sy=scale.y,sz=scale.z}
    end
    retainedTextStats.transform_updates=retainedTextStats.transform_updates+1
end
local viewportProjections=setmetatable({},{__mode='k'})
function UnityBridge.BitmapViewportProjection(context,screenWidth,screenHeight)
    local cached=viewportProjections[context]
    if cached and cached.width==screenWidth and cached.height==screenHeight then return cached.projection end
    local f=UnityBridge.Float
    local width=f(screenWidth/screenHeight*context.logical_height)
    local result=context
    if width~=context.logical_width then
        local p={};for i,v in ipairs(context.matrix)do p[i]=v end
        -- Original Director::setProjection (0x6ba010), perspective builder
        -- (0x6e6650): float reciprocal(aspect) * cot(FOV/2), then LookAt.
        -- Keep logical height, glyph rounding and Z clipping unchanged.
        p[1]=f(f(1/f(width/context.logical_height))*p[6])
        p[13]=f(-f(width*.5)*p[1])
        result={matrix=p,logical_width=width,logical_height=context.logical_height,
            scale_x=p[1]*width/(2*p[16]),scale_y=context.scale_y}
    end
    viewportProjections[context]={width=screenWidth,height=screenHeight,projection=result}
    return result
end
function UnityBridge.BitmapTextPlan(font,text)
    local definitions,pages=UnityBridge.PrepareBitmapFont(font,text)
    local codes=UnityBridge.FontCodes(font,text);local lines=1
    for _,code in ipairs(codes) do if code==10 then lines=lines+1 end end
    local pen,width,line,lineWidth=0,0,0,0;local glyphs={}
    for _,code in ipairs(codes) do
        local g=assert(definitions[code],string.format('Ma Skin Bridge: font bank has no U+%04X',code))
        if code==10 then width=math.max(width,lineWidth);lineWidth=0;pen=0;line=line+1
        elseif g[4]>0 and g[5]>0 then
            local x,top=pen+g[6],(lines-line)*font.line_height-g[7]
            glyphs[#glyphs+1]={page=g[1],x=x,top=top,width=g[4],height=g[5],u=g[2],v=g[3]}
            lineWidth=x+g[4]
        end
        if code~=10 then pen=pen+g[8] end
    end
    return glyphs,math.max(width,lineWidth),text~='' and lines*font.line_height or 0,pages
end
local function snapTextOrigin(origin,scale,f)
    local scaled=f(origin*scale)
    local delta=f(f(math.floor(f(scaled+.5))-scaled)/scale)
    return f(origin+delta)
end
function UnityBridge.BitmapTextPlacement(font,width,height,x,y,screenWidth,screenHeight,anchor,rotate,previous)
    local projection=UnityBridge.BitmapViewportProjection(
        assert(font.native_ui_projection,'Ma Skin Bridge: native font projection context missing'),screenWidth,screenHeight)
    local f=UnityBridge.Float
    local oldHeight=font.logical_height;local oldWidth=screenWidth/screenHeight*oldHeight
    local oldX=f(x*oldHeight/screenHeight);local oldY=f(y*oldHeight/screenHeight)
    local basis=previous
    if not basis or basis.font~=font or basis.width~=width or basis.height~=height or
       basis.screenWidth~=screenWidth or basis.screenHeight~=screenHeight or
       basis.anchor~=anchor or basis.rotate~=rotate or basis.projection~=projection or
       basis.renderScale~=font.render_scale or basis.logicalHeight~=oldHeight then
      local ax=(anchor%3)*.5;local ay=1-math.floor(anchor/3)*.5
      local glyphScale=f(1/font.render_scale)
      local offsetX=f(f(ax*width)*glyphScale)
      local offsetY=f(f(ay*height)*glyphScale)
      local a,b,c,d=glyphScale,0,0,glyphScale
      if rotate and rotate~=0 then
        -- Original Node.SetRotation3D (0x6cb210) builds a float quaternion;
        -- Mat4.createRotation (0x6e6760) then scales its columns. Using a
        -- double sin/cos rotation directly changes the captured matrix bits.
        local half=-f(f(rotate*.5)*f(math.pi/180))
        local z,w=f(math.sin(half)),f(math.cos(half));local twice=f(z+z)
        a=f(f(1-f(z*twice))*glyphScale);d=a
        b=f(f(w*twice)*glyphScale);c=-b
        -- Rotate the anchor offset before Widget's parent-space rounding.
        local anchorX,anchorY=f(ax*width),f(ay*height)
        offsetX=f(f(a*anchorX)+f(c*anchorY))
        offsetY=f(f(b*anchorX)+f(d*anchorY))
      end
      local p=projection.matrix
      basis={font=font,width=width,height=height,screenWidth=screenWidth,screenHeight=screenHeight,
          anchor=anchor,rotate=rotate,projection=projection,renderScale=font.render_scale,logicalHeight=oldHeight,
          glyphScale=glyphScale,offsetX=offsetX,offsetY=offsetY,
          m00=f(p[1]*a),m01=f(p[1]*c),m10=f(p[6]*b),m11=f(p[6]*d)}
    end
    -- Only translation and Widget rounding depend on the moving label's
    -- position. Keep all float32 operation boundaries of the source matrix;
    -- immutable glyph metrics/anchor/rotation need not be rebuilt per tick.
    -- Native Widget rounds in parent coordinates BEFORE the camera projects
    -- its Label. UnityPixelSnap would round in a different coordinate space.
    local p=projection.matrix;local zoomX,zoomY=projection.scale_x,projection.scale_y
    local unitScale=screenHeight/oldHeight
    local placement=basis.placement
    if not placement then
        placement={m00=basis.m00,m01=basis.m01,m10=basis.m10,m11=basis.m11,clipW=p[16],
            scaleX=basis.glyphScale*zoomX*unitScale,scaleY=basis.glyphScale*zoomY*unitScale}
        basis.placement=placement
    end
    -- A horizontal marquee does not change its vertical Widget/projection
    -- arithmetic. Retain each axis independently with the same float32 and
    -- snapping operations, and reuse the placement record between frames.
    if basis.oldX~=oldX then
        local origin=snapTextOrigin(f(oldX-basis.offsetX),font.render_scale,f)
        placement.nativeOriginX=origin
        placement.m03=f(f(p[1]*origin)+p[13])
        local bias=p[13]/p[16]+zoomX
        basis.targetX=((origin-oldWidth*.5)*zoomX)*unitScale+screenWidth*.5+bias*screenWidth*.5
        basis.oldX=oldX
    end
    if basis.oldY~=oldY then
        local origin=snapTextOrigin(f(oldY-basis.offsetY),font.render_scale,f)
        placement.nativeOriginY=origin
        placement.m13=f(f(p[6]*origin)+p[14])
        local bias=p[14]/p[16]+zoomY
        basis.targetY=((origin-oldHeight*.5)*zoomY)*unitScale+screenHeight*.5+bias*screenHeight*.5
        basis.oldY=oldY
    end
    placement.x,placement.y=basis.targetX-x,basis.targetY-y
    return placement,basis
end
function UnityBridge.BitmapTextClip(placement,x,y)
    local f=UnityBridge.Float
    -- Preserve the old CPU matrix product and vertex rounding separately.
    -- Combining the whole affine mapping in double precision changes the
    -- last bits away from the viewport center, then filtered edge bytes.
    local cx,cy=f(placement.m00*x),f(placement.m11*y)
    if placement.m01 and placement.m01~=0 then cx=f(cx+f(placement.m01*y)) end
    if placement.m10 and placement.m10~=0 then cy=f(f(placement.m10*x)+cy) end
    return f(f(cx+placement.m03)/placement.clipW),f(f(cy+placement.m13)/placement.clipW)
end
function UnityBridge.BitmapTextBatches(plan)
    local batches={}
    for _,glyph in ipairs(plan) do
        local batch=batches[#batches]
        -- Preserve painter order even when fallback glyphs switch pages and
        -- later return to an earlier page. Never sort all glyphs by texture.
        -- UInt16 indices retain the target player's default mesh index type.
        if not batch or batch.page~=glyph.page or #batch.glyphs>=16383 then
            batch={page=glyph.page,glyphs={}};batches[#batches+1]=batch
        end
        batch.glyphs[#batch.glyphs+1]=glyph
    end
    return batches
end
local function fontMaterial(page)
    local found=bitmapTextMaterials[page.file]
    if not found then
        found=CS.UnityEngine.Material(assert(CS.UnityEngine.Shader.Find('Malody/Play/TrackFadeWithW')))
        found:SetVector('_WorldOrigin',CS.UnityEngine.Vector4(0,0,0,0))
        found:SetVector('_WorldDirection',CS.UnityEngine.Vector4(0,1,0,0))
        found:SetVector('_RangeFade',CS.UnityEngine.Vector4(-1e20,-1e19,1e19,1e20))
        found:SetVector('_RangeCutoff',CS.UnityEngine.Vector4(-1e20,1e20,0,0))
        local texture=page.texture
        if not texture then
            local sprite=CS.Malody.Scene.Play.Skin.SkinRuntime.instance:GetTexture(page.file)
            assert(sprite~=nil,'Ma Skin Bridge: native font page missing '..page.file)
            texture=sprite.texture
        end
        found:SetTexture('_MainTex',texture)
        bitmapTextMaterials[page.file]=found
    end
    return found
end
function UnityBridge.BitmapText(obj,entry,font,alpha,visual)
    local state=bitmapTextStates[obj]
    if not state then
        local x=obj.X;obj.X=1080
        local unit=obj.transform.anchoredPosition3D.x/1080;obj.X=x
        assert(unit>0,'Ma Skin Bridge: native text UI unit missing')
        local nativeText=obj.text
        nativeText.enabled=false
        state={glyphs={},unit=unit,nativeText=nativeText};bitmapTextStates[obj]=state
    end
    -- The native text module keeps resolving chart/player/BPM variables.
    -- Its TMP renderer is disabled only; no replacement metadata is invented.
    local text
    if UnityBridge.NativeTextValue then text=UnityBridge.NativeTextValue(obj)
    else
        if state.nativeText.enabled then state.nativeText.enabled=false end
        text=state.nativeText.text or ''
    end
    local viewport=UnityBridge.UIViewport
    local screenWidth,screenHeight
    if viewport then screenWidth,screenHeight=viewport.width,viewport.height
    else screenWidth,screenHeight=Game:Width(),Game:Height() end
    local x,y
    if visual then x,y=visual.native_x,visual.native_y else x,y=obj.X,obj.Y end
    local rotate=visual and visual.rotate or 0
    local scale=screenHeight/font.logical_height/font.render_scale*state.unit
    local changed=text~=state.text or scale~=state.scale or x~=state.x or y~=state.y or rotate~=state.rotate or
        screenWidth~=state.screenWidth or screenHeight~=state.screenHeight
    local retained=PROFILE and PROFILE.native_retained_text_candidate
    local rebuild=changed
    if retained then rebuild=text~=state.text or not state.plan end
    if changed then
        local plan,width,height,pages,batches
        if retained and not rebuild then
            plan,width,height,pages=state.plan,state.width,state.height,state.pages
            batches=state.batches
        else
            plan,width,height,pages=UnityBridge.BitmapTextPlan(font,text)
            batches=UnityBridge.BitmapTextBatches(plan)
            retainedTextStats.layouts=retainedTextStats.layouts+1
            if retained then
                -- Batch membership depends only on this immutable glyph plan,
                -- not its position, alpha, viewport, rotation or parent. Keep
                -- consecutive page runs in source order with their geometry.
                state.plan,state.width,state.height,state.pages=plan,width,height,pages
                state.batches=batches
            end
        end
        local placement,basis=UnityBridge.BitmapTextPlacement(font,width,height,x,y,screenWidth,screenHeight,entry.anchor,rotate,state.placementBasis)
        state.placementBasis=basis
        for i,batch in ipairs(batches) do
            local surface=state.glyphs[i]
            if not surface then
                local go=CS.UnityEngine.GameObject('MaSkinBridgeBitmapText',typeof(CS.UnityEngine.RectTransform))
                local directPlane=retained and (entry.retained_text_plane or PROFILE.native_plane_text_candidate) and
                    not PROFILE.native_canvas_text_candidate
                if directPlane then go.name='MaSkinBridgeBitmapText@'..entry.name end
                go.transform:SetParent(directPlane and UnityBridge.TextPlane(entry) or obj.transform,false);go.layer=obj.gameObject.layer
                -- The disabled native TMP can still collapse its parent rect
                -- after mesh creation (actual 80x44 -> 0x0 native readback).
                -- Anchor at the parent's pivot: changing its size must not
                -- translate already positioned source glyphs a second time.
                local rect=go.transform
                local pivot=directPlane and CS.UnityEngine.Vector2(0,0) or obj.transform.pivot
                rect.anchorMin=CS.UnityEngine.Vector2(pivot.x,pivot.y)
                rect.anchorMax=CS.UnityEngine.Vector2(pivot.x,pivot.y)
                rect.pivot=CS.UnityEngine.Vector2(0,0)
                local mesh=CS.UnityEngine.Mesh()
                local draw
                if PROFILE and PROFILE.native_canvas_text_candidate then
                    -- Native UGUI consumes the same full Mesh, including
                    -- float4 UV0. Keep source glyph order inside the entry's
                    -- existing Canvas instead of issuing separate 3D draws.
                    draw=go:AddComponent(typeof(CS.UnityEngine.CanvasRenderer))
                    draw.materialCount=1
                    draw:SetColor(CS.UnityEngine.Color(1,1,1,1))
                else
                    go:AddComponent(typeof(CS.UnityEngine.MeshFilter)).sharedMesh=mesh
                    draw=go:AddComponent(typeof(CS.UnityEngine.MeshRenderer))
                    draw.sortingLayerName='Notes';draw.sortingOrder=entry.order
                    if PROFILE and PROFILE.native_layer_order_candidate then LegacyLayers.Mesh(draw,entry,i) end
                end
                surface={object=go,transform=go.transform,mesh=mesh,renderer=draw,
                    direct_plane=directPlane,canvas=PROFILE and PROFILE.native_canvas_text_candidate};state.glyphs[i]=surface
            end
            if not surface.visible then surface.object:SetActive(true) end
            surface.visible=true
            if retained then positionRetainedText(surface,obj.transform,placement,entry) end
            if rebuild then
            local page=pages[batch.page]
            assert(font.native_v_coordinates,'Ma Skin Bridge: native font V encoding missing')
            local vertices=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector3),4*#batch.glyphs)
            local uv=CS.System.Collections.Generic.List(CS.UnityEngine.Vector4)()
            local triangles=CS.System.Array.CreateInstance(typeof(CS.System.Int32),6*#batch.glyphs)
            local q=font.native_ui_projection.matrix[16]
            for glyphIndex,g in ipairs(batch.glyphs) do
                local base=(glyphIndex-1)*4
                for j,p in ipairs({{g.x,g.top},{g.x,g.top-g.height},{g.x+g.width,g.top},{g.x+g.width,g.top-g.height}}) do
                    if retained then vertices[base+j-1]=CS.UnityEngine.Vector3(p[1],p[2],0)
                    else
                        local cx,cy=UnityBridge.BitmapTextClip(placement,p[1],p[2])
                        vertices[base+j-1]=surface.transform:InverseTransformPoint(UnityBridge.UIWorldPoint(cx,cy,entry))
                    end
                end
                for _,p in ipairs({{g.u,g.v},{g.u,g.v+g.height},{g.u+g.width,g.v},{g.u+g.width,g.v+g.height}}) do
                    uv:Add(CS.UnityEngine.Vector4(p[1]/page.width*q,p[2]/page.height*q,0,q))
                end
                for j,v in ipairs({0,1,2,3,2,1}) do triangles[(glyphIndex-1)*6+j-1]=base+v end
            end
            -- Clear before shrinking vertices, so previous triangle indices
            -- cannot refer past the new vertex buffer during a live text edit.
            surface.mesh:Clear()
            surface.mesh.vertices=vertices;surface.mesh:SetUVs(0,uv);surface.mesh.triangles=triangles
            surface.mesh:RecalculateBounds()
            local material=fontMaterial(page)
            if surface.canvas then
                surface.renderer:SetMaterial(material,0)
                surface.renderer:SetTexture(material.mainTexture)
            else surface.renderer.sharedMaterial=material end
            surface.vertex_count=4*#batch.glyphs
            retainedTextStats.mesh_builds=retainedTextStats.mesh_builds+1
            end
        end
        for i=#batches+1,#state.glyphs do
            local surface=state.glyphs[i]
            surface.visible=false;surface.mesh:Clear()
            if surface.canvas then surface.renderer:Clear() end
            surface.object:SetActive(false)
        end
        state.text=text;state.scale=scale;state.x=x;state.y=y;state.rotate=rotate
        state.screenWidth,state.screenHeight=screenWidth,screenHeight
    end
    if rebuild or alpha~=state.alpha then
        local color=entry.attrs.color or '#FFFFFF'
        local r,g,b=tonumber(color:sub(2,3),16),tonumber(color:sub(4,5),16),tonumber(color:sub(6,7),16)
        for _,surface in ipairs(state.glyphs) do
            if surface.visible then
                local colors=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Color32),surface.vertex_count)
                for i=0,surface.vertex_count-1 do colors[i]=CS.UnityEngine.Color32(r,g,b,UnityBridge.Byte(alpha)) end
                surface.mesh.colors32=colors
                if surface.canvas then surface.renderer:SetMesh(surface.mesh) end
            end
        end
        state.alpha=alpha
    end
end
