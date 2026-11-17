-- Experimental public-mesh backend; included only by the native geometry diagnostic.
local musicbarMeshes=setmetatable({},{__mode='k'})
local musicbarCamera,musicbarFrame
local function cameraState(camera)
    if UnityBridge.ReadMusicbarCamera then
        local enabled,projection=UnityBridge.ReadMusicbarCamera(camera)
        if enabled~=nil then return enabled,projection end
    end
    return camera.enabled
end
local function legacyNoteCamera()
    if musicbarCamera then
        local enabled,projection=cameraState(musicbarCamera)
        if enabled then return musicbarCamera,projection end
    end
    local cameras=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.UnityEngine.Camera),false)
    for i=0,cameras.Length-1 do
        local camera=cameras[i]
        if camera.cullingMask==1024 then
            local enabled,projection=cameraState(camera)
            if enabled then musicbarCamera=camera;return camera,projection end
        end
    end
    return nil -- Init can precede camera creation; retain the Canvas until Update.
end
function UnityBridge.MusicbarFrame()
    local camera,snapshot
    if PROFILE.native_musicbar_clip_w_candidate then camera,snapshot=legacyNoteCamera() end
    local viewport=UnityBridge.FrameGLSize and UnityBridge.UIViewport
    local width,height
    if viewport then width,height=viewport.width,viewport.height else width,height=Game:Width(),Game:Height() end
    local unit=UnityBridge.FrameGLSize or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    local projection,matrix,transform
    if camera then
        projection=snapshot or camera.projectionMatrix
        transform=musicbarFrame and musicbarFrame.camera==camera and musicbarFrame.transform or camera.transform
        if not PROFILE.native_musicbar_camera_local_candidate then matrix=transform.localToWorldMatrix end
    end
    -- Matrix4x4.Equals compares exact components, unlike the approximate ==
    -- operator. Keep checking all camera values without 16 scalar bridge reads.
    local same=musicbarFrame and musicbarFrame.camera==camera and musicbarFrame.width==width and
        musicbarFrame.height==height and musicbarFrame.unit==unit and
        (not camera or (snapshot and projection==musicbarFrame.projection or
            not snapshot and projection:Equals(musicbarFrame.projection)) and
            (PROFILE.native_musicbar_camera_local_candidate or matrix:Equals(musicbarFrame.matrix)))
    if not same then
        if projection then assert(projection.m02==0 and projection.m12==0 and projection.m32==-1 and projection.m33==0,'Ma Skin Bridge: off-centre/non-perspective Note camera is not certified') end
        musicbarFrame={camera=camera,transform=transform,projection=projection,matrix=matrix,
            projectionX=projection and projection.m00,projectionY=projection and projection.m11,
            width=width,height=height,unit=unit,
            revision=musicbarFrame and musicbarFrame.revision+1 or 1}
    end
    return musicbarFrame
end
function UnityBridge.MusicbarQuad(obj,points,order,nativeUV,entry,part,frame,colorDirty)
    frame=frame or UnityBridge.MusicbarFrame()
    local camera=frame.camera
    if PROFILE.native_musicbar_clip_w_candidate and not camera then return false end
    local state=musicbarMeshes[obj];local graphic=renderer(obj).graphics[0]
    if not state then
        local go=CS.UnityEngine.GameObject('MaSkinBridgeMusicbarQuad')
        if PROFILE.native_musicbar_camera_local_candidate and camera then go.transform:SetParent(frame.transform,false)
        elseif not PROFILE.native_musicbar_clip_w_candidate then go.transform:SetParent(assert(uiRoot).transform,false) end
        go.layer=obj.gameObject.layer
        local mesh=CS.UnityEngine.Mesh()
        go:AddComponent(typeof(CS.UnityEngine.MeshFilter)).sharedMesh=mesh
        local draw=go:AddComponent(typeof(CS.UnityEngine.MeshRenderer))
        draw.sortingLayerName='Notes';draw.sortingOrder=order
        local material=CS.UnityEngine.Material(graphic.material)
        local uv
        if graphic:GetType().FullName=='UnityEngine.UI.RawImage' then
            local r=graphic.uvRect;uv={r.x,r.y,r.x+r.width,r.y+r.height}
            material:SetTexture('_MainTex',graphic.texture)
        else
            local sprite=graphic.sprite;local r=sprite.rect;local tw,th=sprite.texture.width,sprite.texture.height
            uv={r.x/tw,r.y/th,(r.x+r.width)/tw,(r.y+r.height)/th}
            material:SetTexture('_MainTex',sprite.texture)
        end
        draw.sharedMaterial=material
        local positions=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector3),4)
        local colors=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Color32),4)
        local coords=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector2),4)
        for i,p in ipairs(nativeUV or {{uv[1],uv[4]},{uv[1],uv[2]},{uv[3],uv[4]},{uv[3],uv[2]}}) do coords[i-1]=CS.UnityEngine.Vector2(p[1],p[2]) end
        local indices=CS.System.Array.CreateInstance(typeof(CS.System.Int32),6)
        for i,v in ipairs({0,1,2,3,2,1}) do indices[i-1]=v end
        state={mesh=mesh,draw=draw,transform=go.transform,camera=camera,positions=positions,colors=colors,coords=coords,indices=indices};musicbarMeshes[obj]=state
        if PROFILE.native_layer_order_candidate then LegacyLayers.Mesh(draw,entry,part) end
    end
    local geometryChanged=state.frame_revision~=frame.revision or not state.points
    if not geometryChanged then
        for i,p in ipairs(points) do for j,value in ipairs(p) do
            if value~=state.points[i][j] then geometryChanged=true;break end
        end end
    end
    if geometryChanged then
        if PROFILE.native_musicbar_camera_local_candidate and camera and state.camera~=camera then
            state.transform:SetParent(frame.transform,false);state.camera=camera
        end
        state.points=state.points or {{},{},{},{}}
        local packed=PROFILE.native_musicbar_camera_local_candidate and camera and points.native_vertices
        local nativeUpload=packed and PROFILE.native_vertex_upload_candidate
        if nativeUpload then
            state.native_upload=state.native_upload or UnityBridge.BindPublicVertices(state.mesh,state.positions)
            UnityBridge.UploadPublicVertices(state.native_upload,packed)
        elseif packed then UnityBridge.CopyMeshBytes(state.positions,packed,12) end
        for i,p in ipairs(points) do
            if packed then -- the exact four native Vector3 bytes were uploaded together
            elseif PROFILE.native_musicbar_camera_local_candidate and camera then
                state.positions[i-1]=CS.UnityEngine.Vector3(p[1]/frame.projectionX,p[2]/frame.projectionY,p[3])
            elseif camera then state.positions[i-1]=frame.transform:TransformPoint(CS.UnityEngine.Vector3(p[1]/frame.projectionX,p[2]/frame.projectionY,p[3]))
            else state.positions[i-1]=CS.UnityEngine.Vector3(p[1]*frame.width/(2*frame.unit),p[2]*frame.height/(2*frame.unit),0) end
            local retained=state.points[i]
            for j,value in ipairs(p) do retained[j]=value end
            -- A switch between 3D and 2D points must not retain stale Z.
            for j=#retained,#p+1,-1 do retained[j]=nil end
        end
        if not nativeUpload then state.mesh.vertices=state.positions;state.mesh:RecalculateBounds() end
        state.frame_revision=frame.revision
    end
    if not state.color or colorDirty~=false then
      local c=graphic.color
      if not state.color or state.color[1]~=c.r or state.color[2]~=c.g or state.color[3]~=c.b or state.color[4]~=c.a then
        local rgba=CS.UnityEngine.Color32(math.floor(c.r*255+.5),math.floor(c.g*255+.5),math.floor(c.b*255+.5),math.floor(c.a*255+.5))
        for i=0,3 do state.colors[i]=rgba end
        state.mesh.colors32=state.colors;state.color={c.r,c.g,c.b,c.a}
      end
    end
    if not state.initialized then state.mesh.uv=state.coords;state.mesh.triangles=state.indices;state.initialized=true end
    if graphic.enabled then graphic.enabled=false;graphic.canvasRenderer:Clear() end
    return true
end
