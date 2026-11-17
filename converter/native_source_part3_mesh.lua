-- Owned Part3 visuals attached to original Key carriers.  The old head and
-- tail art is submitted through maV's overlap/rearOverlap renderers; the head
-- SpriteRenderer itself is only a transparent native placeholder.
local NativeSourcePart3Mesh={}

local function array(kind,n)return CS.System.Array.CreateInstance(typeof(kind),n)end
local function uv4List(count)
    local list=CS.System.Collections.Generic.List(CS.UnityEngine.Vector4)()
    for _=1,count do list:Add(CS.UnityEngine.Vector4(0,0,0,1)) end
    return list
end
local function vector2(v)return CS.UnityEngine.Vector2(v[1],v[2])end
local function blend(a,b,t)
    return CS.UnityEngine.Vector2(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
end

local function spriteCropUvs(sprite,crop)
    local rawUvs,rawVertices=sprite.uv,sprite.vertices
    assert(rawUvs.Length==4 and rawVertices.Length==4,
        'Projected source sprite requires an untrimmed four-corner Sprite')
    local minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
    for i=0,3 do
        local v=rawVertices[i]
        minX=math.min(minX,v.x);maxX=math.max(maxX,v.x)
        minY=math.min(minY,v.y);maxY=math.max(maxY,v.y)
    end
    assert(maxX>minX and maxY>minY,'Projected source sprite has degenerate geometry')
    local corners={}
    for i=0,3 do
        local v=rawVertices[i];local uv=rawUvs[i]
        local x=math.abs(v.x-minX)<1e-6 and 'left' or math.abs(v.x-maxX)<1e-6 and 'right'
        local y=math.abs(v.y-minY)<1e-6 and 'bottom' or math.abs(v.y-maxY)<1e-6 and 'top'
        assert(x and y and not corners[x..y],'Projected source sprite corner mapping is ambiguous')
        corners[x..y]=uv
    end
    local function sample(x,y)
        local tx=(x-minX)/(maxX-minX);local ty=(y-minY)/(maxY-minY)
        local bottom=blend(corners.leftbottom,corners.rightbottom,tx)
        local top=blend(corners.lefttop,corners.righttop,tx)
        return blend(bottom,top,ty)
    end
    crop=crop or {0,0,1,1}
    return {sample(minX+(maxX-minX)*crop[1],minY+(maxY-minY)*crop[4]),
        sample(minX+(maxX-minX)*crop[3],minY+(maxY-minY)*crop[4]),
        sample(minX+(maxX-minX)*crop[1],minY+(maxY-minY)*crop[2]),
        sample(minX+(maxX-minX)*crop[3],minY+(maxY-minY)*crop[2])}
end

local function makeMesh(row,name,material,sortingLayer,sortingOrder,uvs,parent)
    local U=CS.UnityEngine
    local object=U.GameObject(name)
    object.layer=row.object.layer;object.transform:SetParent(parent or row.note.rectNoteRange,false)
    object.transform.localPosition=U.Vector3(0,0,0)
    object.transform.localRotation=U.Quaternion.identity
    object.transform.localScale=U.Vector3(1,1,1)
    local filter=object:AddComponent(typeof(U.MeshFilter))
    local renderer=object:AddComponent(typeof(U.MeshRenderer))
    local mesh=U.Mesh();mesh.name=name..'-mesh';filter.sharedMesh=mesh
    renderer.sharedMaterial=material
    renderer.sortingLayerID=sortingLayer;renderer.sortingOrder=sortingOrder
    local count=uvs and #uvs or 4
    assert(count>0 and count%4==0,'Source body topology must contain complete quads')
    local vertices=array(U.Vector3,count);local uv=array(U.Vector2,count);local colors=array(U.Color32,count)
    local indices=array(CS.System.Int32,count/4*6)
    for q=0,count/4-1 do
        for i,index in ipairs({0,1,2,2,1,3}) do indices[q*6+i-1]=q*4+index end
    end
    for i=0,count-1 do
        vertices[i]=U.Vector3(0,0,0)
        uv[i]=uvs and uvs[i+1] or U.Vector2(0,0)
        colors[i]=U.Color32(255,255,255,255)
    end
    -- Unity rejects triangles and UV arrays until a matching vertex count is
    -- present. Install a valid zero-area quad before enabling this renderer;
    -- Update replaces it with projected geometry in the same admission.
    mesh.vertices=vertices
    mesh.triangles=indices
    mesh.uv=uv
    mesh.colors32=colors
    local part={object=object,mesh=mesh,renderer=renderer,material=material,
        texture=nil,vertices=vertices,uvs=uv,colors=colors,indices=indices,uv_dirty=false}
    if count==4 then
        local u0,u1,u2,u3=uv[0],uv[1],uv[2],uv[3]
        part.uv0x,part.uv0y,part.uv1x,part.uv1y=u0.x,u0.y,u1.x,u1.y
        part.uv2x,part.uv2y,part.uv3x,part.uv3y=u2.x,u2.y,u3.x,u3.y
    end
    return part
end

local cachedTrackFadeBase
local function findTrackFadeBase(U)
    if cachedTrackFadeBase and not cachedTrackFadeBase:Equals(nil) then
        return cachedTrackFadeBase
    end
    local res=U.Resources
    if res and res.FindObjectsOfTypeAll then
        local mats=res.FindObjectsOfTypeAll(typeof(U.Material))
        for i=0,mats.Length-1 do
            local m=mats[i]
            if m and m.shader and m.shader.name=='Malody/Play/TrackFadeWithW' then
                cachedTrackFadeBase=m
                return m
            end
        end
    end
    return nil
end

local function makeSourceMaterial(source,projective)
    local U=CS.UnityEngine
    if not projective then return U.Material(source.sharedMaterial) end
    -- The old ShapeSprite shader divides interpolated UV.xy by UV.w.
    -- Sprites/Default discards w and visibly changes a tapered LN's art.
    -- Clone the shipped TrackFadeWithW material when loaded so Android's
    -- compiled shader keywords (e.g. ETC1_EXTERNAL_ALPHA) are preserved.
    local base=findTrackFadeBase(U)
    local material
    if base then
        material=U.Material(base)
    else
        local shader=assert(U.Shader.Find('Malody/Play/TrackFadeWithW'),'Original projective shader missing')
        material=U.Material(shader)
        if material.EnableKeyword then material:EnableKeyword('ETC1_EXTERNAL_ALPHA') end
    end
    material:SetVector('_WorldOrigin',U.Vector4(0,0,0,0))
    material:SetVector('_WorldDirection',U.Vector4(0,1,0,0))
    material:SetVector('_RangeFade',U.Vector4(-10001,-10000,10000,10001))
    material:SetVector('_RangeCutoff',U.Vector4(-10000,10000,0,0))
    return material
end

local function resizeQuads(part,count)
    if part.vertices.Length==count then return end
    assert(count>=0 and count%4==0 and count<=65532,'Invalid source tile topology')
    local U=CS.UnityEngine
    part.mesh:Clear()
    part.vertices=array(U.Vector3,count);part.uvs=array(U.Vector2,count)
    part.colors=array(U.Color32,count);part.indices=array(CS.System.Int32,count/4*6)
    if part.weightedUvs then part.weightedUvs=uv4List(count) end
    for i=0,count-1 do
        part.vertices[i]=U.Vector3(0,0,0);part.uvs[i]=U.Vector2(0,0)
        part.colors[i]=U.Color32(255,255,255,255)
    end
    for q=0,count/4-1 do
        for i,index in ipairs({0,1,2,2,1,3}) do part.indices[q*6+i-1]=q*4+index end
    end
    part.mesh.vertices=part.vertices;part.mesh.triangles=part.indices
    part.mesh.uv=part.uvs;part.mesh.colors32=part.colors
    part.uv_dirty=false
    part.uv0x=nil
end

local function cachePartUvs(part)
    if part.uvs and part.uvs.Length==4 then
        local u0,u1,u2,u3=part.uvs[0],part.uvs[1],part.uvs[2],part.uvs[3]
        part.uv0x,part.uv0y,part.uv1x,part.uv1y=u0.x,u0.y,u1.x,u1.y
        part.uv2x,part.uv2y,part.uv3x,part.uv3y=u2.x,u2.y,u3.x,u3.y
    else
        part.uv0x=nil
    end
end

local function bindTexture(state,source,uvs)
    local sprite=source.sprite
    assert(sprite,'Projected Part3 source renderer has no Sprite')
    local sourceMaterial=source.sharedMaterial
    if state.sourceMaterial and not state.sourceMaterial:Equals(sourceMaterial) then
        if state.material and not state.material:Equals(nil) then CS.UnityEngine.Object.Destroy(state.material) end
        state.material=makeSourceMaterial(source,state.projective)
        state.renderer.sharedMaterial=state.material
        state.texture=nil
    end
    state.sourceMaterial=source.sharedMaterial
    local texture=sprite.texture
    if state.texture~=texture then state.material:SetTexture('_MainTex',texture);state.texture=texture end
    assert(#uvs==state.uvs.Length,'Reused source body has a different topology')
    for i=0,#uvs-1 do state.uvs[i]=uvs[i+1] end
    cachePartUvs(state)
    if state.clipped_mesh then
        state.mesh:Clear()
        state.mesh.vertices=state.vertices
        state.mesh.triangles=state.indices
        state.mesh.colors32=state.colors
        state.clipped_mesh=false
        state.cr=nil;state.raw_r=nil
    end
    state.mesh.uv=state.uvs
    state.uv_dirty=false
    state.renderer.sortingLayerID=source.sortingLayerID
    state.renderer.sortingOrder=source.sortingOrder
    state.renderer.enabled=true
end

local function sourceSpriteUvs(sprite,crop)
    local values=spriteCropUvs(sprite,crop)
    local result={}
    for i=1,4 do result[i]=values[i] end
    return result
end

-- The overlap/rearOverlap PNGs are padded canvases.  Their crop rectangle
-- already contains the 437 SpriteFrame's source rectangle, including the
-- anchor padding encoded by overlap_image().  Rebuilding a quad from the
-- MUI size applies that anchor and scale a second time and is the source of
-- the large per-skin head/tail size drift.  Resolve the same crop in the
-- loaded Sprite's local vertices, then let maV's native Transform carry the
-- loaded sprite's size, pivot and rotation.
local function bodySpriteUvs(source,recipe)
    local U=CS.UnityEngine
    if recipe.factory~='scale3part3' then
        -- The recipe crop is relative to the emitted PNG, whereas maV may
        -- load that PNG into an atlas. Resolve through the actual Sprite;
        -- sampling 0..1 of its texture reads unrelated atlas entries.
        local uvs=spriteCropUvs(source.sprite,recipe.body_uv)
        if (recipe.factory or 'part3')=='part3' then
            -- ShapeSprite's live vertex order is head, head, tail, tail,
            -- with texture y=1 at the head and y=0 at the tail. Its GL
            -- upload treats PNG row zero as y=0; Unity Sprite UVs treat it
            -- as y=1. Head/tail Sprites use their own corner order, so only
            -- the plain Shape body needs these two rows exchanged. Leaving
            -- them Sprite-ordered moves transparent PNG bottom rows to the
            -- tail, creating a visible gap despite identical geometry/w.
            return {uvs[3],uvs[4],uvs[1],uvs[2]}
        end
        return uvs
    end
    local width,height=recipe.body_texture_width,recipe.body_texture_height
    local plan=scale3Parts(width,height,height,recipe.part)
    local values={}
    for _,i in ipairs({3,1,2}) do
        local cut=plan[i].rect
        if cut[4]>0 then
            -- Sprite_SetRectFixed(1) samples the two texel centres; the
            -- geometry still owns the full cut height, including one-row caps.
            local crop={(cut[1]+.5)/width,(height-cut[2]-cut[4]+.5)/height,
                (cut[1]+cut[3]-.5)/width,(height-cut[2]-.5)/height}
            for _,uv in ipairs(spriteCropUvs(source.sprite,crop)) do values[#values+1]=uv end
        end
    end
    return values
end

local function boundSource(row,source,file)
    if source.sprite or not NativeSourceSprite or not file then return source end
    local sprite=NativeSourceSprite(file)
    if not sprite then return source end
    -- Keep the native renderer's sorting/material domain while replacing only
    -- its absent Sprite with the imported old skin asset.
    local bs=row._bs;if not bs then bs={};row._bs=bs end
    local entry=bs[source];if not entry then entry={};bs[source]=entry end
    entry.sprite=sprite
    entry.sharedMaterial=source.sharedMaterial or row.note.body.sharedMaterial
    entry.color=source.color or row.note.body.color or CS.UnityEngine.Color(1,1,1,1)
    entry.sortingLayerID=source.sortingLayerID or row.note.body.sortingLayerID
    entry.sortingOrder=source.sortingOrder or row.note.body.sortingOrder
    entry.enabled=source.enabled
    return entry
end

local function headBinding(row,recipe,hasTail)
    -- Legacy_CreateNoteSprite stores tex4 on the note's alternate texture
    -- slot.  The source-owned head Mesh can switch to that already-loaded
    -- native Sprite whenever the chart has another note at the same start
    -- offset; no gameplay carrier or judge state is replaced.
    if row.chord and recipe.chord_head_uv and row.note.head and row.note.head.sprite then
        return row.note.head,recipe.chord_head_uv,true,recipe.chord_head_trim
    end
    local file=hasTail and recipe.head_file or recipe.tap_head_file
    return boundSource(row,row.note.overlap,file),hasTail and recipe.head_uv or recipe.tap_head_uv,false,hasTail and recipe.head_trim or recipe.tap_head_trim
end

local function trimQuadPoints(points,trim)
    if not (points and trim) then return points end
    local tl,tr,bl,br=points[1],points[2],points[3],points[4]
    local function lerp2(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t} end
    local function sample(u,v) return lerp2(lerp2(bl,br,u),lerp2(tl,tr,u),v) end
    local u0,v0,u1,v1=trim[1],trim[2],trim[3],trim[4]
    return {sample(u0,v1),sample(u1,v1),sample(u0,v0),sample(u1,v0)}
end

local function newState(row,recipe,projectionRoot)
    local U=CS.UnityEngine
    local bodySource=boundSource(row,row.note.body,recipe.body_file)
    local projective=(recipe.factory or 'part3')=='part3'
    local bodyMaterial=makeSourceMaterial(bodySource,projective)
    local bodyUvs=bodySpriteUvs(bodySource,recipe)
    local body=makeMesh(row,'legacy-source-part3-body',bodyMaterial,
        bodySource.sortingLayerID,bodySource.sortingOrder,bodyUvs,
        recipe.legacy_projected and projectionRoot or nil)
    body.projective=projective
    if projective then body.weightedUvs=uv4List(4) end
    return {factory=recipe.factory or 'part3',body=body,object=body.object,mesh=body.mesh,renderer=body.renderer,
        material=body.material,texture=body.texture,vertices=body.vertices,uvs=body.uvs,
        colors=body.colors,indices=body.indices,
        saved={body=bodySource.enabled,head=row.note.head.enabled,overlap=row.note.overlap.enabled,
            rearOverlap=row.note.rearOverlap.enabled,tail=row.note.tail.enabled}}
end

local function createOrBindProjectedRow(row,recipe,state,hasTail,projectionRoot)
    local U=CS.UnityEngine
    local headSource,headCrop=headBinding(row,recipe,hasTail)
    local headSprite=assert(headSource.sprite,'Projected source head Sprite missing')
    if not state.head then
        state.head=makeMesh(row,'legacy-source-part3-head',U.Material(headSource.sharedMaterial),
            headSource.sortingLayerID,headSource.sortingOrder,nil,projectionRoot)
    end
    bindTexture(state.head,headSource,sourceSpriteUvs(headSprite,headCrop))
    headSource.enabled=false
    -- The alternate slot is only a texture provider for the owned Mesh. Keep
    -- both original head renderers masked so a chord cannot draw twice.
    row.note.overlap.enabled=false
    if recipe.chord_head_uv then row.note.head.enabled=false end
    if recipe.legacy_projected and row.note.tail then row.note.tail.enabled=false end
    row.meshSortedBase=nil

    local tailSource=boundSource(row,row.note.rearOverlap,recipe.tail_file)
    if hasTail then
        -- A 437 hold always has a selected tail resource (tex3, or tex5
        -- through the factory fallback).  Letting a missing maV Sprite fall
        -- back to the native rearOverlap renderer silently drops the owned
        -- Part3 tail and produces a skin that appears to load while being
        -- visually incomplete.  Keep this a hard admission error so the
        -- converter/runtime can fix the resource binding instead of hiding
        -- the mismatch.
        assert(tailSource.sprite,'Projected Part3 hold tail Sprite missing')
        if not state.tail then
            state.tail=makeMesh(row,'legacy-source-part3-tail',U.Material(tailSource.sharedMaterial),
                tailSource.sortingLayerID,tailSource.sortingOrder,nil,projectionRoot)
        end
        bindTexture(state.tail,tailSource,sourceSpriteUvs(tailSource.sprite,recipe.tail_uv))
        tailSource.enabled=false
    else
        tailSource.enabled=state.saved.rearOverlap
        if state.tail then
            state.tail.draw_visible=false
            state.tail.renderer.enabled=false;state.tail.object:SetActive(false)
        end
    end
end

function NativeSourcePart3Mesh.Ensure(row,recipe,hasTail,projectionRoot)
    local U=CS.UnityEngine
    local existing=row.part3Mesh
    local factory=recipe.factory or 'part3'
    if existing and existing.factory==factory and existing.ensured_carrier==row.carrier and
            existing.ensured_recipe==recipe and existing.ensured_tail==hasTail and
            existing.ensured_chord==row.chord and existing.ensured_root==projectionRoot and
            existing.ensured_proj==recipe.legacy_projected and
            existing.ensured_body_sprite==row.note.body.sprite then
        return existing
    end
    if existing and existing.factory~=factory then
        NativeSourcePart3Mesh.Dispose(row)
    end
    local state=row.part3Mesh or newState(row,recipe,projectionRoot)
    local oldProjectionRoot
    if recipe.legacy_projected and not state.projectionRoot then
        state.projectionRoot=U.GameObject(row.object.name)
        state.projectionRoot.layer=row.object.layer
        state.projectionRoot.transform:SetParent(projectionRoot,false)
        state.projectionRoot.transform.localPosition=U.Vector3(0,0,0)
        state.projectionRoot.transform.localRotation=U.Quaternion.identity
        state.projectionRoot.transform.localScale=U.Vector3(1,1,1)
        state.last_pos_x=0;state.last_pos_y=0;state.last_pos_z=0
    elseif not recipe.legacy_projected and state.projectionRoot then
        oldProjectionRoot=state.projectionRoot
        state.projectionRoot=nil
    end
    local meshParent=recipe.legacy_projected and state.projectionRoot.transform or row.note.rectNoteRange
    assert(meshParent,'Projected source geometry requires the stable Key layer root')
    for _,part in ipairs({state.body,state.head,state.tail}) do
        if part and part.object.transform.parent~=meshParent then
            part.object.transform:SetParent(meshParent,false)
            part.object.transform.localPosition=U.Vector3(0,0,0)
            part.object.transform.localRotation=U.Quaternion.identity
            part.object.transform.localScale=U.Vector3(1,1,1)
        end
    end
    if oldProjectionRoot and not oldProjectionRoot:Equals(nil) then U.Object.Destroy(oldProjectionRoot) end
    local bodySource=boundSource(row,row.note.body,recipe.body_file)
    local bodyUvs=bodySpriteUvs(bodySource,recipe)
    if recipe.factory=='tile3' then
        bodyUvs={}
        for i=0,state.body.uvs.Length-1 do bodyUvs[#bodyUvs+1]=state.body.uvs[i] end
    elseif recipe.factory=='scale3part3' and #bodyUvs~=state.body.uvs.Length then
        resizeQuads(state.body,#bodyUvs)
        state.vertices,state.uvs,state.colors,state.indices=state.body.vertices,state.body.uvs,
            state.body.colors,state.body.indices
    end
    bindTexture(state.body,bodySource,bodyUvs)
    bodySource.enabled=false
    createOrBindProjectedRow(row,recipe,state,hasTail,meshParent)
    state.ensured_carrier=row.carrier;state.ensured_recipe=recipe;state.ensured_tail=hasTail
    state.ensured_chord=row.chord;state.ensured_root=projectionRoot;state.ensured_proj=recipe.legacy_projected
    state.ensured_body_sprite=row.note.body.sprite
    row.part3Mesh=state
    return state
end

local function setPartActive(part,visible)
    if part.last_active~=visible then
        part.object:SetActive(visible)
        part.last_active=visible
    end
end

local function applyPartStyle(part,source,sortSource)
    local c=source.color
    local cr,cg,cb,ca=c.r,c.g,c.b,c.a
    if part.raw_r~=cr or part.raw_g~=cg or part.raw_b~=cb or part.raw_a~=ca then
        part.raw_r,part.raw_g,part.raw_b,part.raw_a=cr,cg,cb,ca
        local r=math.floor(cr*255+.5)
        local g=math.floor(cg*255+.5)
        local b=math.floor(cb*255+.5)
        local a=math.floor(ca*255+.5)
        if part.cr~=r or part.cg~=g or part.cb~=b or part.ca~=a then
            local rgba=CS.UnityEngine.Color32(r,g,b,a)
            for i=0,part.colors.Length-1 do part.colors[i]=rgba end
            part.mesh.colors32=part.colors
            part.cr,part.cg,part.cb,part.ca=r,g,b,a
        end
    end
    local ss=sortSource or source
    local lid,ord=ss.sortingLayerID,ss.sortingOrder
    if part.slid~=lid then part.renderer.sortingLayerID=lid;part.slid=lid end
    if part.sord~=ord then part.renderer.sortingOrder=ord;part.sord=ord end
end

local baseTryMapped=NativeSourceGeometry and NativeSourceGeometry.TryProjectMapped
local baseProjMapped=NativeSourceGeometry and NativeSourceGeometry.ProjectMapped

local function bakedPlaneMatrix(mapper,plane)
    if not (mapper and mapper.ux and plane and plane.matrix and plane.source_projection) then return nil end
    if NativeSourceGeometry and (NativeSourceGeometry.TryProjectMapped~=baseTryMapped or NativeSourceGeometry.ProjectMapped~=baseProjMapped) then
        return nil
    end
    local planes=mapper.planes
    if not planes then planes={};mapper.planes=planes end
    local mat=planes[plane]
    if mat then return mat end
    local T,P=plane.matrix,plane.source_projection
    if #T~=16 or #P~=16 or mapper.w<=0 or mapper.h<=0 then return nil end
    local s=plane.logical_height/720
    local ax=s*(P[1]*T[1]+P[5]*T[2]+P[9]*T[3]+P[13]*T[4])
    local bx=s*(P[1]*T[5]+P[5]*T[6]+P[9]*T[7]+P[13]*T[8])
    local cx0=  P[1]*T[13]+P[5]*T[14]+P[9]*T[15]+P[13]*T[16]
    local ay=s*(P[2]*T[1]+P[6]*T[2]+P[10]*T[3]+P[14]*T[4])
    local by=s*(P[2]*T[5]+P[6]*T[6]+P[10]*T[7]+P[14]*T[8])
    local cy0=  P[2]*T[13]+P[6]*T[14]+P[10]*T[15]+P[14]*T[16]
    local mw0=s*(P[4]*T[1]+P[8]*T[2]+P[12]*T[3]+P[16]*T[4])
    local mw1=s*(P[4]*T[5]+P[8]*T[6]+P[12]*T[7]+P[16]*T[8])
    local mw2=   P[4]*T[13]+P[8]*T[14]+P[12]*T[15]+P[16]*T[16]
    local hw,hh=mapper.w*.5,mapper.h*.5
    local k1x,k2x,k0x=mapper.ux*hw,-mapper.vx*hh,mapper.p0x+mapper.ux*hw+mapper.vx*hh
    local k1y,k2y,k0y=mapper.uy*hw,-mapper.vy*hh,mapper.p0y+mapper.uy*hw+mapper.vy*hh
    local k1z,k2z,k0z=mapper.uz*hw,-mapper.vz*hh,mapper.p0z+mapper.uz*hw+mapper.vz*hh
    mat={
        m00=k0x*mw0+k1x*ax+k2x*ay, m01=k0x*mw1+k1x*bx+k2x*by, m02=k0x*mw2+k1x*cx0+k2x*cy0,
        m10=k0y*mw0+k1y*ax+k2y*ay, m11=k0y*mw1+k1y*bx+k2y*by, m12=k0y*mw2+k1y*cx0+k2y*cy0,
        m20=k0z*mw0+k1z*ax+k2z*ay, m21=k0z*mw1+k1z*bx+k2z*by, m22=k0z*mw2+k1z*cx0+k2z*cy0,
        mw0=mw0, mw1=mw1, mw2=mw2,
    }
    planes[plane]=mat
    return mat
end

local function cachedMapper(noteCamera,projectionRoot,rect,screenRoot,row)
    local invRoot=(projectionRoot and projectionRoot.InverseTransformPoint and projectionRoot) or screenRoot
    local time=CS.UnityEngine.Time
    local frame=time and time.frameCount
    local c=NativeSourcePart3Mesh.frame_mapper
    if c and frame~=nil and c.frame==frame and c.cam==noteCamera and c.root==invRoot and
            (c.rect==rect or (row and c.has_mats and row.cached_mat_ver==c.mat_ver and
                row.cached_depth and math.abs(row.cached_depth-c.d)<1e-5)) then
        return c.mapper
    end
    local isUserdata=c and c.has_mats and type(noteCamera)=='userdata' and type(invRoot)=='userdata'
    if isUserdata and row and row.cached_mat_ver==c.mat_ver and row.cached_depth and
            c.cam==noteCamera and c.root==invRoot and
            math.abs(row.cached_depth-c.d)<1e-5 and
            noteCamera.pixelWidth==c.w and noteCamera.pixelHeight==c.h and
            invRoot.worldToLocalMatrix==c.w2l and
            noteCamera.cameraToWorldMatrix==c.c2w and
            noteCamera.projectionMatrix==c.proj then
        c.frame=frame;c.rect=rect
        return c.mapper
    end
    local depth=noteCamera:WorldToScreenPoint(rect.position).z
    assert(depth>0,'Native note parent is behind the original note camera')
    local width,height=noteCamera.pixelWidth,noteCamera.pixelHeight
    if c and c.cam==noteCamera and c.root==invRoot and c.w==width and c.h==height and math.abs(c.d-depth)<1e-5 then
        if frame~=nil and c.frame==frame then
            c.rect=rect
            if row and c.has_mats then row.cached_depth=depth;row.cached_mat_ver=c.mat_ver end
            return c.mapper
        elseif isUserdata
                and invRoot.worldToLocalMatrix==c.w2l
                and noteCamera.cameraToWorldMatrix==c.c2w
                and noteCamera.projectionMatrix==c.proj then
            c.frame=frame;c.rect=rect
            if row then row.cached_depth=depth;row.cached_mat_ver=c.mat_ver end
            return c.mapper
        end
    end
    local mapper
    if NativeSourceGeometry.ScreenToLocalMapper then
        mapper=NativeSourceGeometry.ScreenToLocalMapper(noteCamera,invRoot,depth,width,height)
    else
        local sw=NativeSourceGeometry.ScreenToWorld
        local p0=invRoot:InverseTransformPoint(sw(noteCamera,0,0,depth,width,height))
        local px=invRoot:InverseTransformPoint(sw(noteCamera,width,0,depth,width,height))
        local py=invRoot:InverseTransformPoint(sw(noteCamera,0,height,depth,width,height))
        local p0x,p0y,p0z=p0.x,p0.y,p0.z
        mapper={w=width,h=height,d=depth,p0x=p0x,p0y=p0y,p0z=p0z,
            ux=(px.x-p0x)/width,uy=(px.y-p0y)/width,uz=(px.z-p0z)/width,
            vx=(py.x-p0x)/height,vy=(py.y-p0y)/height,vz=(py.z-p0z)/height}
    end
    if frame~=nil then
        local hasMats=type(noteCamera)=='userdata' and type(invRoot)=='userdata'
            and invRoot.worldToLocalMatrix~=nil and noteCamera.cameraToWorldMatrix~=nil
            and noteCamera.projectionMatrix~=nil
        local matVer=(c and c.mat_ver or 0)+1
        NativeSourcePart3Mesh.frame_mapper={frame=frame,cam=noteCamera,root=invRoot,rect=rect,
            w=width,h=height,d=depth,mapper=mapper,has_mats=hasMats,mat_ver=matVer,
            w2l=hasMats and invRoot.worldToLocalMatrix or nil,
            c2w=hasMats and noteCamera.cameraToWorldMatrix or nil,
            proj=hasMats and noteCamera.projectionMatrix or nil}
        if row and hasMats then row.cached_depth=depth;row.cached_mat_ver=matVer end
    end
    return mapper
end

local function projectMapped(point,legacyPlane,mapper)
    if NativeSourceGeometry.ProjectMapped then
        return NativeSourceGeometry.ProjectMapped(point,legacyPlane,mapper)
    end
    local screen,cw=NativeSourceGeometry.ProjectLegacy(point,legacyPlane,mapper.w,mapper.h)
    local sx,sy=screen[1],screen[2]
    return mapper.p0x+mapper.ux*sx+mapper.vx*sy,
        mapper.p0y+mapper.uy*sx+mapper.vy*sy,
        mapper.p0z+mapper.uz*sx+mapper.vz*sy,
        cw
end

local function resetProjectionOffset(state)
    if state.last_pos_x~=0 or state.last_pos_y~=0 then
        state.projectionRoot.transform.localPosition=CS.UnityEngine.Vector3(0,0,0)
        state.last_pos_x=0;state.last_pos_y=0;state.last_pos_z=0
    end
end

local function tryProjectMapped(point,legacyPlane,mapper,wMin)
    if NativeSourceGeometry.TryProjectMapped then
        return NativeSourceGeometry.TryProjectMapped(point,legacyPlane,mapper,wMin)
    end
    if NativeSourceGeometry.ClipW and NativeSourceGeometry.ClipW(point[1],point[2],legacyPlane)<=(wMin or 0) then
        return nil,nil,nil,0
    end
    local pm=NativeSourceGeometry.ProjectMapped or projectMapped
    local lx,ly,lz,cw=pm(point,legacyPlane,mapper)
    if cw and cw<=(wMin or 0) then return nil,nil,nil,cw end
    return lx,ly,lz,cw
end

local function pointClipW(point,legacyPlane)
    if NativeSourceGeometry.ClipW then
        return NativeSourceGeometry.ClipW(point[1],point[2],legacyPlane)
    end
    local _,w=NativeSourceGeometry.ProjectLegacy(point,legacyPlane,1,1)
    return w
end

local function clipQuadsToWPlane(points,baseUvs,weights,legacyPlane,wMin)
    local outVerts,outIndices={},{}
    for q=0,#points/4-1 do
        local base=q*4
        local corners={}
        local anyFront=false
        for k=1,4 do
            local idx=base+k
            local pt=points[idx]
            local d=pointClipW(pt,legacyPlane)-wMin
            if d>0 then anyFront=true end
            local uv=baseUvs[idx-1]
            local tq=weights and weights[idx] or 1
            corners[k]={x=pt[1],y=pt[2],u=uv.x*tq,v=uv.y*tq,tq=tq,d=d}
        end
        if anyFront then
            for _,tri in ipairs({{1,2,3},{3,2,4}}) do
                local poly={corners[tri[1]],corners[tri[2]],corners[tri[3]]}
                local out={}
                local prev=poly[#poly]
                for _,curr in ipairs(poly) do
                    if (curr.d>=0)~=(prev.d>=0) then
                        local denom=prev.d-curr.d
                        local t=denom~=0 and (prev.d/denom) or 0
                        if t<0 then t=0 elseif t>1 then t=1 end
                        out[#out+1]={
                            x=prev.x+(curr.x-prev.x)*t,
                            y=prev.y+(curr.y-prev.y)*t,
                            u=prev.u+(curr.u-prev.u)*t,
                            v=prev.v+(curr.v-prev.v)*t,
                            tq=prev.tq+(curr.tq-prev.tq)*t,
                            d=0,
                        }
                    end
                    if curr.d>=0 then out[#out+1]=curr end
                    prev=curr
                end
                if #out>=3 then
                    local first=#outVerts
                    for _,v in ipairs(out) do outVerts[#outVerts+1]=v end
                    for i=2,#out-1 do
                        outIndices[#outIndices+1]=first
                        outIndices[#outIndices+1]=first+i-1
                        outIndices[#outIndices+1]=first+i
                    end
                end
            end
        end
    end
    return outVerts,outIndices
end

local function clipMeshBuffer(part,vertCount,idxCount,weighted)
    local U=CS.UnityEngine
    part.clip_bufs=part.clip_bufs or {}
    local mode=weighted and 'W:' or 'P:'
    local key=mode..vertCount..':'..idxCount
    local buf=part.clip_bufs[key]
    if not buf then
        buf={
            vertices=array(U.Vector3,vertCount),
            uvs=not weighted and array(U.Vector2,vertCount) or nil,
            weightedUvs=weighted and uv4List(vertCount) or nil,
            colors=array(U.Color32,vertCount),
            indices=array(CS.System.Int32,idxCount),
        }
        part.clip_bufs[key]=buf
    end
    return buf
end

local function restoreUnclippedMesh(part)
    if not part.clipped_mesh then return end
    part.mesh:Clear()
    part.mesh.vertices=part.vertices
    part.mesh.triangles=part.indices
    part.mesh.uv=part.uvs
    part.mesh.colors32=part.colors
    part.clipped_mesh=false
    part.uv_dirty=false
    part.cr=nil;part.raw_r=nil
end

local function submitProjectedPart(part,source,points,legacyPlane,mapper,weights,sortSource)
    local U=CS.UnityEngine;local V3=U.Vector3
    local wMin=(legacyPlane.clip_depth and legacyPlane.clip_depth.near_w) or 1e-4
    local verts=part.vertices
    local clipWs=weights and part.clip_ws
    if weights and not clipWs then clipWs={};part.clip_ws=clipWs end
    local mat=bakedPlaneMatrix(mapper,legacyPlane)
    local clipped=false
    if mat then
        local m00,m01,m02=mat.m00,mat.m01,mat.m02
        local m10,m11,m12=mat.m10,mat.m11,mat.m12
        local m20,m21,m22=mat.m20,mat.m21,mat.m22
        local mw0,mw1,mw2=mat.mw0,mat.mw1,mat.mw2
        for i,point in ipairs(points) do
            local px,py=point[1],point[2]
            local cw=mw0*px+mw1*py+mw2
            if cw<=wMin then clipped=true;break end
            local inv=1/cw
            verts[i-1]=V3((m00*px+m01*py+m02)*inv,(m10*px+m11*py+m12)*inv,(m20*px+m21*py+m22)*inv)
            if clipWs then clipWs[i]=cw end
        end
    else
        for i,point in ipairs(points) do
            local lx,ly,lz,cw=tryProjectMapped(point,legacyPlane,mapper,wMin)
            if lx==nil then clipped=true;break end
            verts[i-1]=V3(lx,ly,lz)
            if clipWs then clipWs[i]=cw end
        end
    end
    if not clipped then
        if part.clipped_mesh then restoreUnclippedMesh(part)
        else part.mesh.vertices=verts end
        if weights then
            local wuv=part.weightedUvs
            if #points==4 and wuv.Count==4 and part.uv0x~=nil then
                local rw=clipWs[1];local V4=U.Vector4
                local q0=weights[1]
                local q1=weights[2]*rw/clipWs[2]
                local q2=weights[3]*rw/clipWs[3]
                local q3=weights[4]*rw/clipWs[4]
                wuv[0]=V4(part.uv0x*q0,part.uv0y*q0,0,q0)
                wuv[1]=V4(part.uv1x*q1,part.uv1y*q1,0,q1)
                wuv[2]=V4(part.uv2x*q2,part.uv2y*q2,0,q2)
                wuv[3]=V4(part.uv3x*q3,part.uv3y*q3,0,q3)
            else
                local referenceW
                wuv:Clear()
                for i=1,#points do
                    local clipW=clipWs[i]
                    referenceW=referenceW or clipW
                    local q=weights[i]*referenceW/clipW
                    local uv=part.uvs[i-1]
                    wuv:Add(U.Vector4(uv.x*q,uv.y*q,0,q))
                end
            end
            part.mesh:SetUVs(0,wuv)
        elseif part.uv_dirty then
            part.mesh.uv=part.uvs
            part.uv_dirty=false
        end
        applyPartStyle(part,source,sortSource)
        part.mesh:RecalculateBounds()
        return true
    end
    local outVerts,outIndices=clipQuadsToWPlane(points,part.uvs,weights,legacyPlane,wMin)
    if #outVerts==0 then
        part.draw_visible=false;setPartActive(part,false);return false
    end
    local buf=clipMeshBuffer(part,#outVerts,#outIndices,weights~=nil)
    local c=source.color
    local r=math.floor(c.r*255+.5);local g=math.floor(c.g*255+.5)
    local b=math.floor(c.b*255+.5);local a=math.floor(c.a*255+.5)
    local rgba=U.Color32(r,g,b,a)
    local pm=NativeSourceGeometry.ProjectMapped or projectMapped
    local referenceW
    if buf.weightedUvs then buf.weightedUvs:Clear() end
    for i,v in ipairs(outVerts) do
        local lx,ly,lz,cw=pm({v.x,v.y},legacyPlane,mapper)
        buf.vertices[i-1]=V3(lx,ly,lz)
        buf.colors[i-1]=rgba
        if weights then
            local clipW=cw or pointClipW({v.x,v.y},legacyPlane)
            referenceW=referenceW or clipW
            local scale=referenceW/clipW
            buf.weightedUvs:Add(U.Vector4(v.u*scale,v.v*scale,0,v.tq*scale))
        else
            buf.uvs[i-1]=U.Vector2(v.u,v.v)
        end
    end
    for i,index in ipairs(outIndices) do buf.indices[i-1]=index end
    part.mesh:Clear()
    part.mesh.vertices=buf.vertices
    part.mesh.triangles=buf.indices
    if weights then part.mesh:SetUVs(0,buf.weightedUvs)
    else part.mesh.uv=buf.uvs end
    part.mesh.colors32=buf.colors
    part.clipped_mesh=true
    part.cr=nil;part.raw_r=nil
    local ss=sortSource or source
    local lid,ord=ss.sortingLayerID,ss.sortingOrder
    if part.slid~=lid then part.renderer.sortingLayerID=lid;part.slid=lid end
    if part.sord~=ord then part.renderer.sortingOrder=ord;part.sord=ord end
    part.mesh:RecalculateBounds()
    return true
end

local function submitQuad4Projected(part,source,x0,y0,x1,y1,x2,y2,x3,y3,legacyPlane,mapper,mat,isWeighted,hq,tq,sortSource,skipStyle)
    if not mat then
        return submitProjectedPart(part,source,{{x0,y0},{x1,y1},{x2,y2},{x3,y3}},
            legacyPlane,mapper,isWeighted and {hq,hq,tq,tq} or nil,sortSource)
    end
    local wMin=(legacyPlane.clip_depth and legacyPlane.clip_depth.near_w) or 1e-4
    local mw0,mw1,mw2=mat.mw0,mat.mw1,mat.mw2
    local cw0=mw0*x0+mw1*y0+mw2
    local cw1=mw0*x1+mw1*y1+mw2
    local cw2=mw0*x2+mw1*y2+mw2
    local cw3=mw0*x3+mw1*y3+mw2
    if cw0<=wMin or cw1<=wMin or cw2<=wMin or cw3<=wMin then
        return submitProjectedPart(part,source,{{x0,y0},{x1,y1},{x2,y2},{x3,y3}},
            legacyPlane,mapper,isWeighted and {hq,hq,tq,tq} or nil,sortSource)
    end
    local U=CS.UnityEngine;local V3=U.Vector3
    local m00,m01,m02=mat.m00,mat.m01,mat.m02
    local m10,m11,m12=mat.m10,mat.m11,mat.m12
    local m20,m21,m22=mat.m20,mat.m21,mat.m22
    local inv0,inv1,inv2,inv3=1/cw0,1/cw1,1/cw2,1/cw3
    local verts=part.vertices
    verts[0]=V3((m00*x0+m01*y0+m02)*inv0,(m10*x0+m11*y0+m12)*inv0,(m20*x0+m21*y0+m22)*inv0)
    verts[1]=V3((m00*x1+m01*y1+m02)*inv1,(m10*x1+m11*y1+m12)*inv1,(m20*x1+m21*y1+m22)*inv1)
    verts[2]=V3((m00*x2+m01*y2+m02)*inv2,(m10*x2+m11*y2+m12)*inv2,(m20*x2+m21*y2+m22)*inv2)
    verts[3]=V3((m00*x3+m01*y3+m02)*inv3,(m10*x3+m11*y3+m12)*inv3,(m20*x3+m21*y3+m22)*inv3)
    if part.clipped_mesh then restoreUnclippedMesh(part)
    else part.mesh.vertices=verts end
    if isWeighted then
        local wuv=part.weightedUvs
        if wuv.Count==4 and part.uv0x~=nil then
            local V4=U.Vector4
            local q0=hq
            local q1=hq*(cw0*inv1)
            local q2=tq*(cw0*inv2)
            local q3=tq*(cw0*inv3)
            wuv[0]=V4(part.uv0x*q0,part.uv0y*q0,0,q0)
            wuv[1]=V4(part.uv1x*q1,part.uv1y*q1,0,q1)
            wuv[2]=V4(part.uv2x*q2,part.uv2y*q2,0,q2)
            wuv[3]=V4(part.uv3x*q3,part.uv3y*q3,0,q3)
        else
            wuv:Clear()
            local uv0,uv1,uv2,uv3=part.uvs[0],part.uvs[1],part.uvs[2],part.uvs[3]
            local q0,q1,q2,q3=hq,hq*(cw0*inv1),tq*(cw0*inv2),tq*(cw0*inv3)
            wuv:Add(U.Vector4(uv0.x*q0,uv0.y*q0,0,q0))
            wuv:Add(U.Vector4(uv1.x*q1,uv1.y*q1,0,q1))
            wuv:Add(U.Vector4(uv2.x*q2,uv2.y*q2,0,q2))
            wuv:Add(U.Vector4(uv3.x*q3,uv3.y*q3,0,q3))
        end
        part.mesh:SetUVs(0,wuv)
    elseif part.uv_dirty then
        part.mesh.uv=part.uvs
        part.uv_dirty=false
    end
    if not skipStyle then
        applyPartStyle(part,source,sortSource)
    end
    part.mesh:RecalculateBounds()
    return true
end

local function updateProjectedPart(row,state,name,source,points,legacyPlane,mapper,visible,sortSource)
    local part=state[name]
    if not part then return end
    if not points then
        part.draw_visible=false;setPartActive(part,false);return
    end
    part.draw_visible=visible~=false
    setPartActive(part,part.draw_visible)
    if not part.draw_visible then return end
    submitProjectedPart(part,source,points,legacyPlane,mapper,nil,sortSource)
end

local function updateLocalPart(row,state,name,source,points,base,anchor,unit,visible)
    local part=state[name]
    if not part then return end
    if not points then
        part.draw_visible=false;setPartActive(part,false)
        if part.last_ren_enabled~=false then part.renderer.enabled=false;part.last_ren_enabled=false end
        return
    end
    part.draw_visible=visible~=false;setPartActive(part,part.draw_visible)
    if part.last_ren_enabled~=part.draw_visible then
        part.renderer.enabled=part.draw_visible;part.last_ren_enabled=part.draw_visible
    end
    if not part.draw_visible then return end
    local V3=CS.UnityEngine.Vector3;local verts=part.vertices
    for i,point in ipairs(points) do
        verts[i-1]=V3(
            base.x+(point[1]-anchor[1])*unit,
            base.y+(point[2]-anchor[2])*unit,0)
    end
    part.mesh.vertices=verts
    applyPartStyle(part,source)
    part.mesh:RecalculateBounds()
end

function NativeSourcePart3Mesh.Displacement(noteCamera,projectionRoot,rect,legacyPlane,dx720,dy720)
    local mapper=cachedMapper(noteCamera,projectionRoot,rect)
    local pm=NativeSourceGeometry.ProjectMapped or projectMapped
    local x0,y0,z0=pm({0,0},legacyPlane,mapper)
    local x1,y1,z1=pm({dx720,dy720},legacyPlane,mapper)
    return x1-x0,y1-y0,z1-z0
end

function NativeSourcePart3Mesh.UpdateRigid(row,recipe,hasTail,dx,dy,dz)
    local state=row.part3Mesh
    if not (state and state.projectionRoot) then return false end
    state.projectionRoot.transform.localPosition=CS.UnityEngine.Vector3(dx,dy,dz or 0)
    state.last_pos_x=dx;state.last_pos_y=dy;state.last_pos_z=dz or 0
    local bodyVis=row.visible~=false and hasTail
    state.body.draw_visible=bodyVis
    setPartActive(state.body,bodyVis)
    if bodyVis then applyPartStyle(state.body,row.note.body) end
    local headSource=headBinding(row,recipe,hasTail)
    if state.head then
        state.head.draw_visible=row.visible~=false
        setPartActive(state.head,state.head.draw_visible)
        if state.head.draw_visible then applyPartStyle(state.head,headSource) end
    end
    if state.tail then
        if hasTail then
            local tailSource=boundSource(row,row.note.rearOverlap,recipe.tail_file)
            state.tail.draw_visible=row.visible~=false
            setPartActive(state.tail,state.tail.draw_visible)
            if state.tail.draw_visible then applyPartStyle(state.tail,tailSource) end
        else
            state.tail.draw_visible=false;setPartActive(state.tail,false)
        end
    end
    return true
end

local function headQuadTrim(cx,cy,w,h,c,s,trim)
    local f=scale3float
    local hw,hh=f(w*.5),f(h*.5)
    local hwc,hws,hhc,hhs=hw*c,hw*s,hh*c,hh*s
    local x0,y0=f(cx-hwc-hhs),f(cy-hws+hhc)
    local x1,y1=f(cx+hwc-hhs),f(cy+hws+hhc)
    local x2,y2=f(cx-hwc+hhs),f(cy-hws-hhc)
    local x3,y3=f(cx+hwc+hhs),f(cy+hws-hhc)
    if trim then
        local u0,v0,u1,v1=trim[1],trim[2],trim[3],trim[4]
        local b0x,b0y=x2+(x3-x2)*u0,y2+(y3-y2)*u0
        local b1x,b1y=x2+(x3-x2)*u1,y2+(y3-y2)*u1
        local t0x,t0y=x0+(x1-x0)*u0,y0+(y1-y0)*u0
        local t1x,t1y=x0+(x1-x0)*u1,y0+(y1-y0)*u1
        x0,y0=b0x+(t0x-b0x)*v1,b0y+(t0y-b0y)*v1
        x1,y1=b1x+(t1x-b1x)*v1,b1y+(t1y-b1y)*v1
        x2,y2=b0x+(t0x-b0x)*v0,b0y+(t0y-b0y)*v0
        x3,y3=b1x+(t1x-b1x)*v0,b1y+(t1y-b1y)*v0
    end
    return x0,y0,x1,y1,x2,y2,x3,y3
end

local function part3RectSize(recipe,ratio,fallback)
    local start=recipe.legacy_size_start;local finish=recipe.legacy_size_end
    if not (start and finish and start[1] and start[2] and finish[1] and finish[2]) then
        return fallback[1],fallback[2]
    end
    local f=scale3float;local t=f(ratio)
    return f(f(finish[1]-start[1])*t+start[1]),f(f(finish[2]-start[2])*t+start[2])
end

function NativeSourcePart3Mesh.UpdateProjectedFast(row,recipe,isHold,headRatio,tailRatio,legacyPlane,noteCamera,projectionRoot)
    local ready=row.fast_ready_ver~=nil and row.fast_ready_ver==row.slot_ver and row.part3Mesh~=nil
    local state=ready and row.part3Mesh or NativeSourcePart3Mesh.Ensure(row,recipe,isHold,projectionRoot)
    if state.projectionRoot then resetProjectionOffset(state) end
    local vis=row.visible~=false
    local bodyVis=vis and isHold
    state.body.draw_visible=bodyVis
    setPartActive(state.body,bodyVis)
    if not vis then
        if state.head then state.head.draw_visible=false;setPartActive(state.head,false) end
        if state.tail then state.tail.draw_visible=false;setPartActive(state.tail,false) end
        return
    end
    local f=scale3float
    local sx,ex,sy,ey=recipe.start_x,recipe.end_x,recipe.start_y,recipe.end_y
    local hx=f(f(f(sx-ex)*headRatio)+ex)
    local hy=f(f(f(sy-ey)*headRatio)+ey)
    local fixedHead=isHold and recipe.head_size or recipe.tap_head_size or recipe.head_size
    local hw,hh=part3RectSize(recipe,headRatio,fixedHead)
    local geom=recipe._geom
    local anchor,rotate=recipe.anchor,recipe.rotate
    if not geom or geom.anchor~=anchor or geom.rotate~=rotate then
        local r=f(-rotate*math.pi/180)
        geom={anchor=anchor,rotate=rotate,ax=(anchor%3)*.5,ay=1-math.floor(anchor/3)*.5,
            c=f(math.cos(r)),s=f(math.sin(r))}
        recipe._geom=geom
    end
    local ax,ay,c,s=geom.ax,geom.ay,geom.c,geom.s
    local ox,oy=f((.5-ax)*hw),f((.5-ay)*hh)
    local hcx,hcy=f(hx+ox*c-oy*s),f(hy+ox*s+oy*c)
    local screenRoot=state.projectionRoot.transform
    local mapper=cachedMapper(noteCamera,projectionRoot,row.note.rectNoteRange,screenRoot,row)
    local mat=bakedPlaneMatrix(mapper,legacyPlane)
    local headSource,headSort,headTrim
    if ready then
        headSource,headSort,headTrim=state.fast_head_src,state.fast_head_sort,state.fast_head_trim
    else
        local isChordHead
        headSource,isChordHead,_,headTrim=headBinding(row,recipe,isHold)
        headSort=isChordHead and row.note.overlap or nil
        state.fast_head_src,state.fast_head_sort,state.fast_head_trim=headSource,headSort,headTrim
    end
    if isHold then
        local tx=f(f(f(sx-ex)*tailRatio)+ex)
        local ty=f(f(f(sy-ey)*tailRatio)+ey)
        local tw,th=part3RectSize(recipe,tailRatio,recipe.tail_size or recipe.head_size)
        local tox,toy=f((.5-ax)*tw),f((.5-ay)*th)
        local tcx,tcy=f(tx+tox*c-toy*s),f(ty+tox*s+toy*c)
        local dx,dy=f(tcx-hcx),f(tcy-hcy)
        local length=math.sqrt(dx*dx+dy*dy)
        local nx,ny=0,-1
        if length>0 then nx,ny=f(dy/length),f(-dx/length) end
        local headEdge,tailEdge=hw,tw
        local axis=recipe.body_axis
        if axis==1 then nx,ny=-1,0
        elseif axis==2 then nx,ny=0,-1;headEdge,tailEdge=hh,th end
        local bx0,by0=f(hcx-nx*headEdge*.5),f(hcy-ny*headEdge*.5)
        local bx1,by1=f(hcx+nx*headEdge*.5),f(hcy+ny*headEdge*.5)
        local bx2,by2=f(tcx-nx*tailEdge*.5),f(tcy-ny*tailEdge*.5)
        local bx3,by3=f(tcx+nx*tailEdge*.5),f(tcy+ny*tailEdge*.5)
        local hq,tq=1,1
        if state.body.projective then
            local lx1,ly1=f(bx0-bx1),f(by0-by1)
            local hl=f(math.sqrt(f(f(lx1*lx1)+f(ly1*ly1))))
            local lx2,ly2=f(bx2-bx3),f(by2-by3)
            local tl=f(math.sqrt(f(f(lx2*lx2)+f(ly2*ly2))))
            if hl<=tl and tl>0 then hq=f(hl/tl)
            elseif hl>0 then tq=f(tl/hl) end
        end
        submitQuad4Projected(state.body,row.note.body,bx0,by0,bx1,by1,bx2,by2,bx3,by3,
            legacyPlane,mapper,mat,state.body.projective,hq,tq,nil,ready)
        if state.head then
            state.head.draw_visible=true;setPartActive(state.head,true)
            local hx0,hy0,hx1,hy1,hx2,hy2,hx3,hy3=headQuadTrim(hcx,hcy,hw,hh,c,s,headTrim)
            submitQuad4Projected(state.head,headSource,hx0,hy0,hx1,hy1,hx2,hy2,hx3,hy3,
                legacyPlane,mapper,mat,false,nil,nil,headSort,ready)
        end
        if state.tail then
            local tailSource
            if ready then
                tailSource=state.fast_tail_src
            else
                tailSource=boundSource(row,row.note.rearOverlap,recipe.tail_file)
                state.fast_tail_src=tailSource
            end
            state.tail.draw_visible=true;setPartActive(state.tail,true)
            local tx0,ty0,tx1,ty1,tx2,ty2,tx3,ty3=headQuadTrim(tcx,tcy,tw,th,c,s,recipe.tail_trim)
            submitQuad4Projected(state.tail,tailSource,tx0,ty0,tx1,ty1,tx2,ty2,tx3,ty3,
                legacyPlane,mapper,mat,false,nil,nil,nil,ready)
        end
    else
        if state.head then
            state.head.draw_visible=true;setPartActive(state.head,true)
            local hx0,hy0,hx1,hy1,hx2,hy2,hx3,hy3=headQuadTrim(hcx,hcy,hw,hh,c,s,headTrim)
            submitQuad4Projected(state.head,headSource,hx0,hy0,hx1,hy1,hx2,hy2,hx3,hy3,
                legacyPlane,mapper,mat,false,nil,nil,headSort,ready)
        end
        if state.tail then state.tail.draw_visible=false;setPartActive(state.tail,false) end
    end
    if not ready and row.slot_ver~=nil and not (state.body.clipped_mesh
            or (state.head and state.head.clipped_mesh)
            or (state.tail and state.tail.clipped_mesh)) then
        row.fast_ready_ver=row.slot_ver
    end
end

function NativeSourcePart3Mesh.Update(row,recipe,geometry,unit,legacyPlane,noteCamera,projectionRoot)
    assert(not recipe.legacy_projected or legacyPlane,
        'Projected Part3 recipe lost its original KeyUIS plane')
    local state=NativeSourcePart3Mesh.Ensure(row,recipe,geometry.has_tail,projectionRoot)
    if recipe.factory=='tile3' then
        resizeQuads(state.body,#geometry.vertices)
        for _,name in ipairs({'vertices','uvs','colors','indices'}) do state[name]=state.body[name] end
        local index=0
        for _,crop in ipairs(geometry.body_crops) do
            for _,uv in ipairs(spriteCropUvs(row.note.body.sprite,crop)) do
                state.uvs[index]=uv;index=index+1
            end
        end
        assert(index==state.vertices.Length,'Tile3 geometry/UV topology differs')
        state.body.uv_dirty=true
    end
    local U=CS.UnityEngine;local rect=row.note.rectNoteRange
    local screenRoot=recipe.legacy_projected and state.projectionRoot.transform or nil
    local meshParent=recipe.legacy_projected and screenRoot or rect
    assert(meshParent,'Projected source geometry requires the stable Key layer root')
    if state.object.transform.parent~=meshParent then
        state.object.transform:SetParent(meshParent,false)
        state.object.transform.localPosition=U.Vector3(0,0,0)
        state.object.transform.localRotation=U.Quaternion.identity
        state.object.transform.localScale=U.Vector3(1,1,1)
    end
    if state.projectionRoot then resetProjectionOffset(state) end
    state.body.draw_visible=row.visible~=false and geometry.has_tail
    setPartActive(state.body,state.body.draw_visible)
    if legacyPlane then
        assert(noteCamera and geometry.vertices and #geometry.vertices==state.vertices.Length,
            'Projected legacy body requires source quad and original note camera')
        local mapper=cachedMapper(noteCamera,projectionRoot,rect,screenRoot)
        assert(screenRoot,'Projected source geometry requires the stable Key layer root')
        if state.body.draw_visible then
            local weights=state.body.projective and NativeSourceGeometry.BodyUvWeights(geometry.vertices) or nil
            submitProjectedPart(state.body,row.note.body,geometry.vertices,legacyPlane,mapper,weights)
        end
        local headSource,isChordHead,_,headTrim=headBinding(row,recipe,geometry.has_tail)
        local tailSource=boundSource(row,row.note.rearOverlap,recipe.tail_file)
        updateProjectedPart(row,state,'head',headSource,trimQuadPoints(geometry.head_vertices,headTrim),
            legacyPlane,mapper,row.visible,isChordHead and row.note.overlap or nil)
        updateProjectedPart(row,state,'tail',tailSource,trimQuadPoints(geometry.tail_vertices,recipe.tail_trim),
            legacyPlane,mapper,row.visible and geometry.has_tail)
    else
        local head=rect:InverseTransformPoint(row.note.head.transform.position)
        local tail=rect:InverseTransformPoint(row.note.tail.transform.position)
        head.x=head.x+(geometry.head_x-recipe.start_x)*unit
        tail.x=tail.x+(geometry.tail_x-recipe.start_x)*unit
        if recipe.factory=='scale3part3' or recipe.factory=='tile3' then
            updateLocalPart(row,state,'body',row.note.body,geometry.vertices,
                head,{geometry.head_x,geometry.head_y},unit,state.body.draw_visible)
        else
            local points=geometry.points
            local hx,hy=head.x,head.y;local tx,ty=tail.x,tail.y
            local nx,ny=points.normal[1],points.normal[2]
            local hw,tw=points.head_edge*unit,points.tail_edge*unit
            state.vertices[0]=U.Vector3(hx-nx*hw/2,hy-ny*hw/2,0)
            state.vertices[1]=U.Vector3(hx+nx*hw/2,hy+ny*hw/2,0)
            state.vertices[2]=U.Vector3(tx-nx*tw/2,ty-ny*tw/2,0)
            state.vertices[3]=U.Vector3(tx+nx*tw/2,ty+ny*tw/2,0)
        end
        if state.body.draw_visible then
            state.mesh.vertices=state.vertices
            if state.body.projective then
                local weights=NativeSourceGeometry.BodyUvWeights(geometry.vertices)
                state.body.weightedUvs:Clear()
                for i,_ in ipairs(geometry.vertices) do
                    local q=weights[i];local uv=state.body.uvs[i-1]
                    state.body.weightedUvs:Add(U.Vector4(uv.x*q,uv.y*q,0,q))
                end
                state.mesh:SetUVs(0,state.body.weightedUvs)
            else state.mesh.uv=state.uvs end
            applyPartStyle(state.body,row.note.body)
            state.mesh:RecalculateBounds()
        end
        local headSource=headBinding(row,recipe,geometry.has_tail)
        local tailSource=boundSource(row,row.note.rearOverlap,recipe.tail_file)
        updateLocalPart(row,state,'head',headSource,geometry.head_vertices,
            head,{geometry.head_x,geometry.head_y},unit,row.visible)
        updateLocalPart(row,state,'tail',tailSource,geometry.tail_vertices,
            tail,{geometry.tail_x,geometry.tail_y},unit,row.visible and geometry.has_tail)
    end
end

local function disposePart(part)
    if not part then return end
    if part.material and not part.material:Equals(nil) then CS.UnityEngine.Object.Destroy(part.material) end
    if part.mesh and not part.mesh:Equals(nil) then CS.UnityEngine.Object.Destroy(part.mesh) end
    if part.object and not part.object:Equals(nil) then CS.UnityEngine.Object.Destroy(part.object) end
end

-- A 437 bar is one ordinary Sprite, independent of the LN factory. Reuse
-- only the owned mesh/atlas projection primitives, never a note's state.
local function makeAdditiveMaterial(base)
    local U=CS.UnityEngine
    local m=U.Material(base)
    if base and base.shader and base.shader.name=='Live2D/Live2D PremultipliedAlpha' then
        return m
    end
    pcall(function() m:SetFloat('_Additive',1) end)
    pcall(function() m:SetColor('_Color',U.Color(1,1,1,1)) end)
    if m.EnableKeyword then pcall(function() m:EnableKeyword('BLEND_ADDITIVE') end) end
    return m
end
local function subdividePlaneQuad(points,uvs,nx,ny)
    local pBL,pBR,pTL,pTR=points[1],points[2],points[3],points[4]
    local u0,u1,u2,u3=uvs[0],uvs[1],uvs[2],uvs[3]
    local outPts,outUvs={},{}
    local function lerpP(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t} end
    local function lerpU(a,b,t) return {x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t} end
    local function sampleP(tx,ty) return lerpP(lerpP(pBL,pBR,tx),lerpP(pTL,pTR,tx),ty) end
    local function sampleU(tx,ty) return lerpU(lerpU(u0,u1,tx),lerpU(u2,u3,tx),ty) end
    local idx=0
    for iy=0,ny-1 do
        local ty0,ty1=iy/ny,(iy+1)/ny
        for ix=0,nx-1 do
            local tx0,tx1=ix/nx,(ix+1)/nx
            outPts[#outPts+1]=sampleP(tx0,ty0)
            outPts[#outPts+1]=sampleP(tx1,ty0)
            outPts[#outPts+1]=sampleP(tx0,ty1)
            outPts[#outPts+1]=sampleP(tx1,ty1)
            outUvs[idx]=sampleU(tx0,ty0);idx=idx+1
            outUvs[idx]=sampleU(tx1,ty0);idx=idx+1
            outUvs[idx]=sampleU(tx0,ty1);idx=idx+1
            outUvs[idx]=sampleU(tx1,ty1);idx=idx+1
        end
    end
    return outPts,outUvs
end
local function rawRectUvs(r)
    local V2=CS.UnityEngine.Vector2
    local u0,v0,u1,v1=r.x,r.y,r.x+r.width,r.y+r.height
    return {V2(u0,v1),V2(u1,v1),V2(u0,v0),V2(u1,v0)}
end
function NativeSourcePart3Mesh.NewSprite(root,name,sprite,order,additiveMaterial)
    local U=CS.UnityEngine
    local source={sharedMaterial=nil}
    local material=additiveMaterial and makeAdditiveMaterial(additiveMaterial) or makeSourceMaterial(source,true)
    local part=makeMesh({object=root},name,material,0,order,sourceSpriteUvs(sprite),root.transform)
    part.renderer.sortingLayerName='Notes'
    part.material:SetTexture('_MainTex',sprite.texture)
    part.currentSprite=sprite
    part.additive=additiveMaterial~=nil
    part.weightedUvs=uv4List(4)
    return part
end
function NativeSourcePart3Mesh.NewRaw(root,name,texture,uvRect,order,additiveMaterial)
    local source={sharedMaterial=nil}
    local material=additiveMaterial and makeAdditiveMaterial(additiveMaterial) or makeSourceMaterial(source,true)
    local part=makeMesh({object=root},name,material,0,order,rawRectUvs(uvRect),root.transform)
    part.renderer.sortingLayerName='Notes'
    part.material:SetTexture('_MainTex',texture)
    part.currentTexture=texture
    part.additive=additiveMaterial~=nil
    part.weightedUvs=uv4List(4)
    return part
end
function NativeSourcePart3Mesh.SetSprite(part,sprite)
    if not sprite or part.currentSprite==sprite then return end
    part.currentSprite=sprite
    part.material:SetTexture('_MainTex',sprite.texture)
    local uvs=sourceSpriteUvs(sprite)
    for i=1,4 do part.uvs[i-1]=uvs[i] end
    cachePartUvs(part)
    part.uv_dirty=true
end
function NativeSourcePart3Mesh.SetRaw(part,texture,uvRect)
    if texture and part.currentTexture~=texture then
        part.currentTexture=texture
        part.material:SetTexture('_MainTex',texture)
    end
    if uvRect then
        local uvs=rawRectUvs(uvRect)
        for i=1,4 do part.uvs[i-1]=uvs[i] end
    end
end
local function submitQuadMesh(part,points,plane,camera,root,depth,tint)
    local U=CS.UnityEngine
    local alpha=tint[4]~=nil and tint[4] or 255
    if alpha<=0 then
        part.object:SetActive(false);part.renderer.enabled=false;return
    end
    local wMin=(plane.clip_depth and plane.clip_depth.near_w) or 1e-4
    local tryProj=NativeSourceGeometry.TryProjectLegacy
    local rgba=U.Color32(tint[1],tint[2],tint[3],alpha)
    if part.additive then
        local subPts,subUvs=subdividePlaneQuad(points,part.uvs,4,6)
        local outVerts,outIndices=clipQuadsToWPlane(subPts,subUvs,nil,plane,wMin)
        if #outVerts==0 then
            part.object:SetActive(false);part.renderer.enabled=false;return
        end
        local buf=clipMeshBuffer(part,#outVerts,#outIndices,true)
        buf.weightedUvs:Clear()
        for i,v in ipairs(outVerts) do
            local screen=NativeSourceGeometry.ProjectLegacy({v.x,v.y},plane,camera.pixelWidth,camera.pixelHeight)
            local world=NativeSourceGeometry.ScreenToWorld(camera,screen[1],screen[2],depth,camera.pixelWidth,camera.pixelHeight)
            buf.vertices[i-1]=root:InverseTransformPoint(world)
            buf.weightedUvs:Add(U.Vector4(v.u,v.v,0,1))
            buf.colors[i-1]=rgba
        end
        for i,index in ipairs(outIndices) do buf.indices[i-1]=index end
        part.mesh:Clear()
        part.mesh.vertices=buf.vertices;part.mesh.triangles=buf.indices
        part.mesh:SetUVs(0,buf.weightedUvs)
        part.mesh.colors32=buf.colors;part.mesh:RecalculateBounds()
        part.clipped_mesh=true;part.cr=nil
        part.object:SetActive(true);part.renderer.enabled=true
        return
    end
    local screens,ws={},{}
    local clipped=false
    for i,point in ipairs(points) do
        local screen,w
        if tryProj then
            screen,w=tryProj(point,plane,camera.pixelWidth,camera.pixelHeight,wMin)
        elseif NativeSourceGeometry.ClipW and NativeSourceGeometry.ClipW(point[1],point[2],plane)<=wMin then
            screen,w=nil,0
        else
            screen,w=NativeSourceGeometry.ProjectLegacy(point,plane,camera.pixelWidth,camera.pixelHeight)
            if w and w<=wMin then screen=nil end
        end
        if not screen then clipped=true;break end
        screens[i]=screen;ws[i]=w
    end
    if not clipped then
        restoreUnclippedMesh(part)
        local reference
        part.weightedUvs:Clear()
        for i=1,#points do
            local screen,w=screens[i],ws[i]
            local world=NativeSourceGeometry.ScreenToWorld(camera,screen[1],screen[2],depth,camera.pixelWidth,camera.pixelHeight)
            part.vertices[i-1]=root:InverseTransformPoint(world)
            reference=reference or w
            local q=reference/w;local uv=part.uvs[i-1]
            part.weightedUvs:Add(U.Vector4(uv.x*q,uv.y*q,0,q))
            part.colors[i-1]=rgba
        end
        part.mesh.vertices=part.vertices;part.mesh:SetUVs(0,part.weightedUvs)
        part.mesh.colors32=part.colors;part.mesh:RecalculateBounds()
        part.object:SetActive(true);part.renderer.enabled=true
        return
    end
    local outVerts,outIndices=clipQuadsToWPlane(points,part.uvs,nil,plane,wMin)
    if #outVerts==0 then
        part.object:SetActive(false);part.renderer.enabled=false;return
    end
    local buf=clipMeshBuffer(part,#outVerts,#outIndices,true)
    local reference
    buf.weightedUvs:Clear()
    for i,v in ipairs(outVerts) do
        local screen,w=NativeSourceGeometry.ProjectLegacy({v.x,v.y},plane,camera.pixelWidth,camera.pixelHeight)
        local world=NativeSourceGeometry.ScreenToWorld(camera,screen[1],screen[2],depth,camera.pixelWidth,camera.pixelHeight)
        buf.vertices[i-1]=root:InverseTransformPoint(world)
        reference=reference or w
        local q=reference/w
        buf.weightedUvs:Add(U.Vector4(v.u*q,v.v*q,0,q))
        buf.colors[i-1]=rgba
    end
    for i,index in ipairs(outIndices) do buf.indices[i-1]=index end
    part.mesh:Clear()
    part.mesh.vertices=buf.vertices;part.mesh.triangles=buf.indices
    part.mesh:SetUVs(0,buf.weightedUvs)
    part.mesh.colors32=buf.colors;part.mesh:RecalculateBounds()
    part.clipped_mesh=true;part.cr=nil
    part.object:SetActive(true);part.renderer.enabled=true
end
function NativeSourcePart3Mesh.UpdateSprite(part,points,plane,camera,root,depth,tint,sprite)
    if sprite then NativeSourcePart3Mesh.SetSprite(part,sprite) end
    submitQuadMesh(part,points,plane,camera,root,depth,tint)
end
function NativeSourcePart3Mesh.UpdateRaw(part,points,plane,camera,root,depth,tint,texture,uvRect)
    NativeSourcePart3Mesh.SetRaw(part,texture,uvRect)
    submitQuadMesh(part,points,plane,camera,root,depth,tint)
end
NativeSourcePart3Mesh.DisposeSprite=disposePart

function NativeSourcePart3Mesh.Dispose(row)
    local state=row.part3Mesh
    if not state then return end
    row.note.body.enabled=state.saved.body
    row.note.head.enabled=state.saved.head
    row.note.overlap.enabled=state.saved.overlap
    row.note.rearOverlap.enabled=state.saved.rearOverlap
    row.note.tail.enabled=state.saved.tail
    disposePart(state.head);disposePart(state.tail);disposePart(state.body)
    if state.projectionRoot and not state.projectionRoot:Equals(nil) then
        CS.UnityEngine.Object.Destroy(state.projectionRoot)
    end
    row.part3Mesh=nil
    row.fast_ready_ver=nil;row.cached_depth=nil;row.cached_mat_ver=nil
end

