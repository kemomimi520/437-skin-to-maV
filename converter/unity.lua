-- Public Unity components, reached through xLua's existing CS bridge.
-- No private access, binary patching, native injection, or replacement game files.
local UnityBridge={cache=setmetatable({},{__mode='k'})}
local nativeMath
local LegacyLayers
local touchAreas=setmetatable({},{__mode='k'})
local uiGroups=setmetatable({},{__mode='k'})
local uiCanvasBatches={}
local uiRoot
local noteSprites={}
local noteGeometry=setmetatable({},{__mode='k'})
local rectangleBodies=setmetatable({},{__mode='k'})
local ownedGridMeshes=setmetatable({},{__mode='k'})
local sourceSprites={}
local regionSprites={}
local premultipliedSprites=setmetatable({},{__mode='k'})
local premultipliedGraphics=setmetatable({},{__mode='k'})
local lastAlphaBytes=setmetatable({},{__mode='k'})
local appliedNoteAlpha=setmetatable({},{__mode='k'})
-- The chart owns these reserved children until its Lua environment ends.
-- Retain their xLua userdata too: weak-only keys can vanish on Lua GC even
-- while the native GameObject lives, losing ownership and all write caches.
local ownedNoteVisuals={}
local ownedNoteSizing=setmetatable({},{__mode='k'})
local ownedNotePositions=setmetatable({},{__mode='k'})
local ownedPositionContracts=setmetatable({},{__mode='k'})
local notePositionContractTypes={}
local ownedNativeTransforms=setmetatable({},{__mode='k'})
local ownedUIVisuals=setmetatable({},{__mode='k'})
local ownedUIVisibility=setmetatable({},{__mode='k'})
local nativeTextReaders=setmetatable({},{__mode='k'})
local textVariables,textVariableList={},{}
local ownedTextPositions=setmetatable({},{__mode='k'})
local nativeImageWriters=setmetatable({},{__mode='k'})
local nativeCameraReaders={}
local submissions={alpha_calls=0,alpha_cache_hits=0,rectangle_calls=0,rectangle_builds=0,note_geometry_calls=0,note_resizes=0,lane_static_skips=0}
UnityBridge.NotePerformance=submissions
local sourceTints=setmetatable({},{__mode='k'})
local premultipliedMaterials={}
local function sourceSprite(file)
    local sprite=sourceSprites[file]
    if not sprite then
        sprite=CS.Malody.Scene.Play.Skin.SkinRuntime.instance:GetTexture(file)
        assert(sprite~=nil,'Ma Skin Bridge: native texture missing '..file)
        sourceSprites[file]=sprite
    end
    return sprite
end
-- This player's xLua assembly search list does not initially include the split
-- Unity modules. Load the already present assemblies before importing types.
if xlua and xlua.load_assembly then
    xlua.load_assembly('Assembly-CSharp')
    xlua.load_assembly('UnityEngine.CoreModule')
    xlua.load_assembly('UnityEngine.UI')
    xlua.load_assembly('UnityEngine.UIModule')
end
function UnityBridge.Float(v)
    local n=string.unpack('f',string.pack('f',v))
    return n
end
do
    local packedFloat=UnityBridge.Float
    local fullRange=PROFILE and PROFILE.native_numeric_float_candidate
    local offsets={}
    if fullRange then for exponent=-126,128 do offsets[exponent]=2.0^(exponent+29) end end
    local floor,log=math.floor,math.log
    local whole,small,tiny={},{},{}
    local exponent=0
    for value=1,4095 do
        if value>=2.0^(exponent+1) then exponent=exponent+1 end
        whole[value]=2.0^(exponent+29)
        small[value]=2.0^(exponent+17)
        tiny[value]=2.0^(exponent+5)
    end
    local function arithmeticFloat(value)
        -- Adding an exact power of two moves the binary64 ULP to the
        -- binary32 ULP. The two separate Lua arithmetic instructions round
        -- to nearest/even, then remove the offset without string allocation.
        -- Keep the existing conversion for exceptional/subnormal inputs.
        if value==0 then return value*1.0 end
        local negative=value<0
        local magnitude=negative and -value or value
        if magnitude~=magnitude or magnitude<2.0^-126 or magnitude>=2.0^128 then
            return packedFloat(value)
        end
        -- Integer bins cannot cross a binary exponent boundary. Keep the
        -- same exact arithmetic rounding while avoiding log for ordinary
        -- geometry/progress magnitudes; exceptional ranges retain fallback.
        local offset
        if magnitude>=1 and magnitude<4096 then offset=whole[floor(magnitude)]
        elseif magnitude>=2.0^-12 and magnitude<1 then offset=small[floor(magnitude*4096)]
        elseif magnitude>=2.0^-24 and magnitude<2.0^-12 then offset=tiny[floor(magnitude*16777216)]
        elseif fullRange then offset=offsets[floor(log(magnitude,2))]
        else return packedFloat(value) end
        local rounded=(magnitude+offset)-offset
        if rounded>=2.0^128 then rounded=math.huge end
        return negative and -rounded or rounded
    end
    -- Ordinary packages only use exact integer-bin exponent selection in
    -- [2^-24,4096). No logarithm/exponent guess is promoted from the research
    -- path. Check this Lua VM's arithmetic against its shipped pack routine;
    -- unexpected rounding or APIs keep the old conversion for the whole env.
    local verified=pcall(function()
        for exponent=-24,11 do
            local base=2.0^exponent;local step=2.0^(exponent-23)
            for _,value in ipairs({base,base-step/2,base+step/2,base+step*1.5,
                base-step*.499999,base+step*.500001}) do
                for _,sign in ipairs({1,-1}) do
                    assert(string.pack('f',arithmeticFloat(value*sign))==string.pack('f',value*sign))
                end
            end
        end
        for _,value in ipairs({0,-0.0,4096,1e20,1e-30,math.huge,-math.huge}) do
            assert(string.pack('f',arithmeticFloat(value))==string.pack('f',value))
        end
    end)
    submissions.bounded_float_arithmetic=verified
    if verified then UnityBridge.Float=arithmeticFloat end
end
local meshMemory
local meshUploadScope
local sharedMeshUpload
local automaticPackedMeshes=false
local meshCapabilitiesChecked=false
local function initializeGridBytes(state)
    state.vertexBytes={};state.uvBytes={}
    for index=1,16 do
        state.vertexBytes[index]=string.rep('\0',12)
        state.uvBytes[index]=string.pack('<ffff',0,0,0,1)
    end
end
function UnityBridge.WithNoteMeshUploads(callback)
    if not automaticPackedMeshes and not (PROFILE.native_frame_mesh_candidate and PROFILE.native_packed_mesh_candidate) then return callback() end
    -- Native Mesh setters copy their input. Share only the two upload arrays;
    -- every drawable still has its own Mesh, topology, UV domain and order.
    -- Pins live for this draw loop only, including exceptional exits.
    if meshUploadScope then return callback() end
    if not sharedMeshUpload then
        sharedMeshUpload={
            vertices=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector3),16),
            uvs=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector4),16)}
    end
    local scope={handles={},pointers={}}
    meshUploadScope=scope
    local ok,reason=pcall(callback)
    meshUploadScope=nil
    for i=#scope.handles,1,-1 do scope.handles[i]:Free() end
    assert(ok,'Ma Skin Bridge: scoped note mesh update failed: '..tostring(reason))
end
function UnityBridge.PrepareMeshUploads()
    if meshCapabilitiesChecked then return automaticPackedMeshes end
    meshCapabilitiesChecked=true
    if PROFILE.native_math_module then return false end
    local ok,reason=pcall(function()
        local vectors={
            {CS.UnityEngine.Vector3,12,{'x','y','z'},{-0.0,1.25,-3.5,123456.75,1e-20,-4096.5}},
            {CS.UnityEngine.Vector4,16,{'x','y','z','w'},{-0.0,1.25,-3.5,1,123456.75,1e-20,-4096.5,.125}}}
        for _,spec in ipairs(vectors) do
            local array=CS.System.Array.CreateInstance(typeof(spec[1]),2)
            local fields,values=spec[3],spec[4];local bytes={}
            for i,v in ipairs(values) do bytes[i]=string.pack('<f',v) end
            UnityBridge.CopyMeshBytes(array,table.concat(bytes),spec[2])
            for index=0,1 do for field,name in ipairs(fields) do
                assert(string.pack('<f',array[index][name])==bytes[index*#fields+field],
                    'public packed Vector array layout differs')
            end end
        end
    end)
    automaticPackedMeshes=ok;submissions.packed_mesh_available=ok
    if not ok then
        -- Missing/stripped/nonblittable public APIs retain the original value
        -- setters. Never make a mobile package depend on a Windows DLL or an
        -- unchecked memory layout, and never leave pins beyond a draw scope.
        PROFILE.native_packed_mesh_candidate=false;PROFILE.native_frame_mesh_candidate=false
        submissions.packed_mesh_fallback_reason=tostring(reason)
    end
    return ok
end
function UnityBridge.CopyMeshBytes(array,bytes,stride)
    -- Exact-size writes into arrays allocated by this renderer only. Pin for
    -- this call, then always release the handle: no persistent pins or native
    -- memory allocations survive a scene/retry/Lua-environment teardown.
    assert((stride==12 or stride==16) and #bytes==array.Length*stride,
        'Ma Skin Bridge: packed mesh buffer length mismatch')
    if not meshMemory then
        meshMemory=CS.System.Runtime.InteropServices
    end
    if meshUploadScope and (array==sharedMeshUpload.vertices or array==sharedMeshUpload.uvs) then
        local pointer=meshUploadScope.pointers[array]
        if not pointer then
            local handle=meshMemory.GCHandle.Alloc(array,meshMemory.GCHandleType.Pinned)
            meshUploadScope.handles[#meshUploadScope.handles+1]=handle
            pointer=handle:AddrOfPinnedObject();meshUploadScope.pointers[array]=pointer
        end
        meshMemory.Marshal.Copy(bytes,0,pointer,#bytes)
        return
    end
    local handle=meshMemory.GCHandle.Alloc(array,meshMemory.GCHandleType.Pinned)
    local ok,reason=pcall(function()
        meshMemory.Marshal.Copy(bytes,0,handle:AddrOfPinnedObject(),#bytes)
    end)
    handle:Free()
    assert(ok,'Ma Skin Bridge: native packed mesh copy failed: '..tostring(reason))
end
local lastFrameClock
function UnityBridge.FrameDeltaMilliseconds()
    local now=CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    assert(type(now)=='number','Ma Skin Bridge: native realtime clock is unavailable')
    local previous=lastFrameClock;lastFrameClock=now
    if not previous then return 0 end
    -- maV throttles Lua Update independently of rendering. One render-frame
    -- delta loses the intervening frames; sample actual unscaled elapsed.
    -- This preserves the running clock across chart speed/seek. Exact old
    -- scheduler phase and rendering during native pause remain unverified.
    return UnityBridge.Float(UnityBridge.Float(math.max(0,now-previous))*1000)
end
function UnityBridge.ProjectLifetimeGroup(mod)
    local projection=PROFILE.native_note_projection
    if not projection then return end
    local p=projection.matrix
    -- Proven old Sprite commands have z=0 and affine world transforms.
    -- Scale the entire owned group so head, body, tail and rotation share
    -- the original plane projection. Retain native group depth and units.
    assert(p[4]==0 and p[8]==0 and p[16]>0,'Ma Skin Bridge: unverified note projection plane')
    local transform=mod.gameObject.transform;local scale=transform.localScale
    local sx=p[1]*projection.logical_width/(2*p[16])
    local sy=p[6]*projection.logical_height/(2*p[16])
    transform.localScale=CS.UnityEngine.Vector3(scale.x*sx,scale.y*sy,scale.z)
    UnityBridge.ApplyLegacyPlane(transform)
end
local planeCamera
local appliedPlanes=setmetatable({},{__mode='k'})
function UnityBridge.ApplyLegacyPlane(transform)
    local plane=PROFILE.legacy_play_plane
    if not plane or appliedPlanes[transform] then return end
    if not planeCamera then
        local cameras=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.UnityEngine.Camera))
        for i=0,cameras.Length-1 do if cameras[i].name=='CameraNote' then planeCamera=cameras[i] end end
    end
    local camera=assert(planeCamera,'Ma Skin Bridge: original note camera unavailable for play plane')
    local p=assert(PROFILE.native_note_projection).matrix;local t=plane.matrix
    local projection=camera.projectionMatrix
    assert(projection.m02==0 and projection.m12==0 and projection.m32==-1,
        'Ma Skin Bridge: unsupported native camera projection for play plane')
    local V=CS.UnityEngine.Vector3
    local depth=camera:WorldToScreenPoint(transform:TransformPoint(V(0,0,0))).z
    assert(depth>0,'Ma Skin Bridge: play plane is behind native camera')
    -- Preserve homogeneous screen XY while scaling the entire owned plane
    -- about the actual camera. Match its far boundary to the old GL far
    -- boundary. This player's public near/far/projection setters are stripped.
    -- For the verified positive plane angles, the XY frustum already rejects
    -- every point near either near plane; assert that instead of inventing a
    -- camera setter or performing per-frame CPU polygon clipping.
    local clip=assert(plane.clip_depth,'Ma Skin Bridge: original plane clip depth missing')
    local k=camera.farClipPlane/clip.far_w
    assert(k>0 and k<math.huge and clip.visible_w_min>clip.near_w and
        clip.visible_w_min>camera.nearClipPlane/k,
        'Ma Skin Bridge: native near plane intersects visible legacy play plane')
    local parent=transform.parent
    local function point(x,y)
        local screen=camera:WorldToScreenPoint(transform:TransformPoint(V(x,y,0)))
        local ox=((2*screen.x/CS.UnityEngine.Screen.width-1)*p[16]-p[13])/p[1]
        local oy=((2*screen.y/CS.UnityEngine.Screen.height-1)*p[16]-p[14])/p[6]
        local px=t[1]*ox+t[5]*oy+t[13]
        local py=t[2]*ox+t[6]*oy+t[14]
        local pz=t[3]*ox+t[7]*oy+t[15]
        local cameraPoint=V(k*(p[1]*px+p[13])/projection.m00,
            k*(p[6]*py+p[14])/projection.m11,-k*(p[16]-pz))
        -- This player strips Camera.cameraToWorldMatrix's managed binding.
        -- The surviving Transform maps camera-local +Z forward, whereas
        -- Unity's view/projection convention uses negative camera-space Z.
        local world=camera.transform:TransformPoint(V(cameraPoint.x,cameraPoint.y,-cameraPoint.z))
        return parent and parent:InverseTransformPoint(world) or world
    end
    -- Sample a viewport-sized basis before converting back to unit vectors.
    -- A one-unit subtraction loses float32 bits against a distant plane
    -- origin, visibly amplified by large near-horizon source coordinates.
    local context=PROFILE.native_note_projection
    local spanX,spanY=context.logical_width,context.logical_height
    local origin,px,py=point(0,0),point(spanX,0),point(0,spanY)
    local dx,dy=px-origin,py-origin
    local u,v=V(dx.x/spanX,dx.y/spanX,dx.z/spanX),V(dy.x/spanY,dy.y/spanY,dy.z/spanY)
    assert(math.abs(V.Dot(u.normalized,v.normalized))<.0001,
        'Ma Skin Bridge: play plane cannot be represented by this native parent transform')
    transform.localPosition=origin
    transform.localRotation=CS.UnityEngine.Quaternion.LookRotation(V.Cross(u,v),v)
    transform.localScale=V(u.magnitude,v.magnitude,1)
    appliedPlanes[transform]=true
end
function UnityBridge.PrepareLaneMotion(e,lane)
    if not PROFILE.native_lifetime_candidate then return end
    local different=false
    for axis=1,2 do for part=1,2 do
        if e.size[axis][part]~=e.size2[axis][part] then different=true end
    end end
    if different then
        if not UnityBridge.ResolveNoteDimensions then return end
        local width=Game:Width()/(Game:Height()/720)
        local w,h,ew,eh=UnityBridge.ResolveNoteDimensions(e,width,720)
        if w~=ew or h~=eh then return end
    end
    local origin=Note:GetGroup('legacy_clock').transform
    local rotation=origin.localRotation
    if rotation.x~=0 or rotation.y~=0 or rotation.z~=0 or rotation.w~=1 then return end
    -- A plain Transform cannot introduce a nested SortingGroup or group
    -- alpha/order driver. Keep the existing native renderer order unchanged.
    local go=CS.UnityEngine.GameObject('legacy_scroll_lane_'..lane)
    local transform=go.transform;transform:SetParent(origin.parent,false)
    transform.localScale=origin.localScale;transform.localPosition=origin.localPosition;transform.localRotation=rotation
    UnityBridge.ProjectLifetimeGroup({gameObject=go})
    local scale=transform.localScale;local position=transform.localPosition
    local motion={entry=e,transform=transform,rotation=rotation,sx=scale.x,sy=scale.y,x=position.x,y=position.y,z=position.z,epoch=0}
    if PROFILE.legacy_play_plane then
        -- The projected play plane is already represented by this parent.
        -- Translate along BOTH of its actual 3D basis vectors, retaining the
        -- depth change; children keep their original local geometry/painter
        -- order. Held, clamped and size-changing parts use full updates.
        local planeRotation=transform.localRotation
        local bx=planeRotation*CS.UnityEngine.Vector3(scale.x,0,0)
        local by=planeRotation*CS.UnityEngine.Vector3(0,scale.y,0)
        motion.basis={bx.x,bx.y,bx.z,by.x,by.y,by.z}
    end
    return motion
end
function UnityBridge.AttachLaneMotion(mod,motion)
    local transform=mod.transform;transform:SetParent(motion.transform,false)
    transform.localPosition=CS.UnityEngine.Vector3(0,0,0)
    transform.localScale=CS.UnityEngine.Vector3(1,1,1)
    transform.localRotation=motion.rotation
end
function UnityBridge.UpdateLaneMotion(motion,y,distance,width,hasDrawable)
    local unit=UnityBridge.FrameGLSize or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    if motion.base_y==nil or motion.distance~=distance or motion.width~=width or motion.unit~=unit or
       math.abs(y-motion.base_y)>distance/2 then
        motion.base_y=y;motion.distance=distance;motion.width=width;motion.unit=unit;motion.epoch=motion.epoch+1
    end
    local e=motion.entry;local delta=(y-motion.base_y)/distance
    local function axis(v,extent)return v[1]*extent+v[2] end
    motion.offset_x=(axis(e['end'][1],width)-axis(e.pos[1],width))*delta
    motion.offset_y=(axis(e['end'][2],720)-axis(e.pos[2],720))*delta
    local x=motion.x+motion.offset_x*1.5/unit*motion.sx
    local targetY=motion.y+motion.offset_y*1.5/unit*motion.sy
    local z=motion.z
    if motion.basis then
        local b=motion.basis;local dx,dy=motion.offset_x*1.5/unit,motion.offset_y*1.5/unit
        x=motion.x+b[1]*dx+b[4]*dy;targetY=motion.y+b[2]*dx+b[5]*dy;z=motion.z+b[3]*dx+b[6]*dy
    end
    -- Continue the original rebase/offset arithmetic even with no drawable.
    -- Admission updates this transform before activating any of its children.
    -- Leave draw_* unchanged while asleep, so waking cannot retain a stale
    -- native position even when the logical target has stopped moving.
    if hasDrawable~=false and (motion.draw_x~=x or motion.draw_y~=targetY or motion.draw_z~=z) then
        if PROFILE.native_transform_submit_candidate then
            motion.native_position=motion.native_position or UnityBridge.BindPublicTransform(motion.transform)
            nativeMath.submit_position(motion.native_position,x,targetY,z)
        else motion.transform.localPosition=CS.UnityEngine.Vector3(x,targetY,z) end
        motion.draw_x=x;motion.draw_y=targetY;motion.draw_z=z
    end
end
function UnityBridge.Byte(v) return math.floor(math.max(0,math.min(255,v))) end
function UnityBridge.BytePercent(v)
    return UnityBridge.Float(math.max(0,math.min(100,v))*2.55)
end
function UnityBridge.Available() return CS~=nil and typeof~=nil end
function UnityBridge.OwnedTextPosition(obj,x,y)
    local state=ownedTextPositions[obj]
    if not state then
        local transform=obj.transform
        local original=transform.anchoredPosition3D
        -- The variable reader need not move with its independent glyphs.
        -- Recover the module's cached float unit with an exact power of two,
        -- then check the PUBLIC setters before replacing their round trips.
        -- Current native set_X/Y compare float(abs(old-new)) against double
        -- 0.0001; get_X/Y divide in float. No private field is accessed.
        local ok,unit=pcall(function()
            obj.X=0;obj.X=1024
            local unit=transform.anchoredPosition3D.x/1024
            assert(unit>0 and unit<math.huge and UnityBridge.Float(unit)==unit)
            local V,f=CS.UnityEngine.Vector3,UnityBridge.Float
            for _,probe in ipairs({{.00005,.0005},{.0005,.00005},
                {.00009999999,.00010000001},{-.0002,-.00005},{123.456,-654.321}}) do
                transform.anchoredPosition3D=V(0,0,original.z)
                local px,py=f(probe[1]/unit),f(probe[2]/unit)
                obj.X=px;obj.Y=py
                local position=transform.anchoredPosition3D
                local tx,ty=f(px*unit),f(py*unit)
                local ex=math.abs(tx)>=.0001 and tx or 0
                local ey=math.abs(ty)>=.0001 and ty or 0
                assert(position.x==ex and position.y==ey and obj.X==f(ex/unit) and obj.Y==f(ey/unit))
            end
            return unit
        end)
        -- Restore the actual vector, not a multiply/divide setter round trip.
        transform.anchoredPosition3D=original
        state={supported=ok,unit=ok and unit or nil,x=original.x,y=original.y}
        ownedTextPositions[obj]=state
        if not ok then
            submissions.text_position_fallbacks=(submissions.text_position_fallbacks or 0)+1
        end
    end
    if not state.supported then return nil end
    local f,unit=UnityBridge.Float,state.unit
    local tx,ty=f(f(x)*unit),f(f(y)*unit)
    if math.abs(f(state.x-tx))>=.0001 then state.x=tx end
    if math.abs(f(state.y-ty))>=.0001 then state.y=ty end
    submissions.virtual_text_positions=(submissions.virtual_text_positions or 0)+1
    return f(state.x/unit),f(state.y/unit)
end
function UnityBridge.NativeTextValue(obj)
    local state=nativeTextReaders[obj]
    if not state then
        -- Only compiler-owned, visually replaced TMP labels use this reader.
        -- Keep the SkinRuntimeText variable resolver running; its renderer is
        -- replaced by our source glyphs. TMP.set_text marks this public flag
        -- even while the TMP component is disabled (current native build).
        state={component=obj.text};nativeTextReaders[obj]=state
    end
    if state.dependencies and state.value~=nil and not state.dependency_dirty then
        submissions.text_dependency_cache_hits=(submissions.text_dependency_cache_hits or 0)+1
        return state.value
    end
    local component=state.component
    if PROFILE.native_text_read_candidate then
        state.native=state.native or UnityBridge.BindPublicText(component)
        local changed=nativeMath.read_text(state.native,state.value==nil and 1 or 0)
        if changed~=nil then state.value=changed end
        state.dependency_dirty=false
        return assert(state.value,'Ma Skin Bridge: native text reader omitted initial value')
    end
    if component.enabled then component.enabled=false;state.value=nil end
    local dirty=component.havePropertiesChanged
    if state.value==nil or dirty~=false then
        state.value=component.text or ''
        submissions.text_value_reads=(submissions.text_value_reads or 0)+1
        -- A component without this API must keep polling. Never infer a
        -- stable value from a missing/unsupported change notification.
        if type(dirty)=='boolean' then component.havePropertiesChanged=false end
    end
    state.dependency_dirty=false
    return state.value
end
local publicGetters=setmetatable({},{__mode='k'})
local publicObjectGetters=setmetatable({},{__mode='k'})
local function publicProperty(object,getterName)
    -- This build's property names and get_ method names differ. xLua omits
    -- several direct accessors. Reflect PUBLIC instance properties only, and
    -- cache their semantic getter names; never enable private access here.
    local found=publicObjectGetters[object]
    local kind
    if not found then kind=object:GetType();found=publicGetters[kind] end
    if not found then
        found={};publicGetters[kind]=found
        local properties=kind:GetProperties(20) -- Public | Instance
        for i=0,properties.Length-1 do
            local property=properties[i];local getter=property:GetGetMethod()
            if getter~=nil then found[getter.Name]=property end
        end
    end
    publicObjectGetters[object]=found
    return assert(found[getterName],'Ma Skin Bridge: missing public property '..getterName)
end
local function publicGetter(object,getterName)
    return publicProperty(object,getterName):GetValue(object,nil)
end
local function publicNumericReader(object,getterName)
    local property=publicProperty(object,getterName)
    local expected=property:GetValue(object,nil)
    assert(type(expected)=='number','native variable is not numeric')
    local getter=property:GetGetMethod();local publicName=getter.Name
    for _,name in ipairs({property.Name,publicName:sub(1,4)=='get_' and publicName:sub(5) or publicName}) do
        local ok,value=pcall(function()return object[name]end)
        if ok and type(value)=='number' and value==expected then
            return function()return object[name]end,expected
        end
    end
    local ok,method=pcall(function()return object[publicName]end)
    if ok and type(method)=='function' then
        local matches,value=pcall(method,object)
        if matches and type(value)=='number' and value==expected then
            return function()return method(object)end,expected
        end
    end
    error('native variable direct getter missing: '..publicName)
end
function UnityBridge.PrepareTextReader(obj)
    local state=nativeTextReaders[obj]
    if not state then state={component=obj.text};nativeTextReaders[obj]=state end
    if state.prepared then return state.dependencies end
    state.prepared=true
    -- Text.Setup already binds its exact dependencies to these public native
    -- watchers. Their callbacks synchronously format the TMP string. Share
    -- their VALUE reads instead of polling each disabled TMP every Lua tick.
    -- No Lua callback is registered with the engine or survives this env.
    local ok,dependencies,pending=pcall(function()
        assert(obj:GetType().FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeText')
        assert(NativeBindings and NativeBindings.TriggerValueType)
        local runtime=CS.Malody.Scene.Play.Skin.SkinRuntime.instance
        local values=CS.System.Enum.GetValues(typeof(CS.Malody.Composer.SkinModuleTrigger))
        local dependencies,pending={},{}
        for i=0,values.Length-1 do
            local trigger=values[i]
            if obj:HasTrigger(trigger) then
                local id=CS.System.Convert.ToInt32(trigger)
                local record=textVariables[id] or pending[id]
                if not record then
                    local kind=CS.System.Convert.ToInt32(NativeBindings.TriggerValueType(trigger))
                    local watcher
                    if kind==1 then watcher=runtime:WatchForInt(trigger)
                    elseif kind==2 or kind==3 then watcher=runtime:WatchForDouble(trigger)
                    else error('unverified native text dependency type') end
                    local read,value=publicNumericReader(watcher,'get_Value')
                    record={read=read,value=value,readers=setmetatable({},{__mode='k'})}
                    pending[id]=record
                end
                dependencies[#dependencies+1]=record
            end
        end
        return dependencies,pending
    end)
    if not ok then
        submissions.text_dependency_fallbacks=(submissions.text_dependency_fallbacks or 0)+1
        submissions.text_dependency_first_error=submissions.text_dependency_first_error or tostring(dependencies)
        state.dependency_error=tostring(dependencies)
        return false
    end
    for id,record in pairs(pending) do
        textVariables[id]=record;textVariableList[#textVariableList+1]=record
    end
    for _,record in ipairs(dependencies) do record.readers[state]=true end
    state.dependencies=true;state.dependency_dirty=true
    submissions.text_dependency_readers=(submissions.text_dependency_readers or 0)+1
    return true
end
function UnityBridge.BeginTextFrame()
    for _,record in ipairs(textVariableList) do
        local value=record.read()
        submissions.text_variable_reads=(submissions.text_variable_reads or 0)+1
        if value~=record.value then
            record.value=value
            for reader in pairs(record.readers) do reader.dependency_dirty=true end
        end
    end
end
function UnityBridge.SkinAssetPath(file)
    assert(type(file)=='string' and not file:find('[/\\]') and not file:find('..',1,true),
        'Ma Skin Bridge: invalid font asset filename')
    local root=publicGetter(CS.Malody.Scene.Play.Skin.SkinRuntime.instance,'get_BaseDir')
    return root..'/'..file
end
function UnityBridge.ReadSkinBytes(file)
    local bytes=CS.System.IO.File.ReadAllBytes(UnityBridge.SkinAssetPath(file))
    assert(type(bytes)=='string','Ma Skin Bridge: unsupported font asset byte-array bridge')
    return bytes
end
function UnityBridge.LoadNativeMath()
    if not PROFILE.native_math_module then return end
    assert(type(package)=='table' and type(package.loadlib)=='function',
        'Ma Skin Bridge: public Lua native module loader unavailable')
    local runtime=CS.Malody.Scene.Play.Skin.SkinRuntime.instance
    local root=publicGetter(runtime,'get_BaseDir')
    assert(type(root)=='string' and #root>0,'Ma Skin Bridge: selected skin directory unavailable')
    local file=PROFILE.native_math_module.file
    assert(not file:find('[/\\]') and file:match('%.dll$'),'Ma Skin Bridge: invalid arithmetic module filename')
    local path=root..'/'..file
    local loader,reason=package.loadlib(path,'luaopen_skinbridge_math')
    if not loader and path:find('[\128-\255]') then
        -- This Lua 5.3 Windows loader uses LoadLibraryExA. CS strings are
        -- UTF-8 in Lua, so encode the filename with the native ANSI codepage
        -- rather than passing UTF-8 bytes to a CP936/1252 loader. Verify the
        -- round trip: never load a '?' substituted, different filename.
        -- Unity's Encoding(0) is UTF-8 on this player. The converter records
        -- GetACP from the Windows host; no game-private API or registry write.
        -- UTF-8 is tried first for systems with the UTF-8 ANSI codepage.
        local codepage=PROFILE.native_math_module.windows_codepage
        assert(codepage,'Ma Skin Bridge: Windows native filename codepage unavailable')
        local encoding=CS.System.Text.Encoding.GetEncoding(codepage)
        local methods=encoding:GetType():GetMethods(20)
        local encode
        for i=0,methods.Length-1 do
            local method=methods[i];local parameters=method:GetParameters()
            if parameters.Length==1 then
                local kind=parameters[0].ParameterType.FullName
                if method.Name=='GetBytes' and kind=='System.String' then encode=method end
            end
        end
        assert(encode,'Ma Skin Bridge: public filename encoding method unavailable')
        local args=CS.System.Array.CreateInstance(typeof(CS.System.Object),1);args[0]=path
        local flags=CS.System.Reflection.BindingFlags.Default
        local bytes=encode:Invoke(encoding,flags,nil,args,nil)
        -- xLua marshals a returned Byte[] as a binary Lua string. The typed
        -- GetString overload converts that string back to Byte[]; placing it
        -- in a reflection Object[] would box System.String instead.
        assert(type(bytes)=='string' and encoding:GetString(bytes,0,#bytes)==path,
            'Ma Skin Bridge: native loader cannot represent this skin directory')
        loader,reason=package.loadlib(bytes,'luaopen_skinbridge_math')
    end
    assert(loader,'Ma Skin Bridge: arithmetic module load failed: '..tostring(reason))
    nativeMath=assert(loader(),'Ma Skin Bridge: arithmetic module ABI unavailable')
    assert(type(nativeMath.float32)=='function' and type(nativeMath.quad_buffers)=='function',
        'Ma Skin Bridge: incomplete arithmetic module')
    UnityBridge.Float=nativeMath.float32
    UnityBridge.NativeMusicbarQuad=nativeMath.musicbar_quad
    UnityBridge.NativeMathLoaded=true
end
function UnityBridge.BarProvider()
    local group=Note:GetGroup('legacy_bars')
    local parent=group.transform;local processor,layer
    while parent~=nil do
        processor=processor or parent.gameObject:GetComponent(typeof(CS.Malody.Play.ProcessorFree))
        layer=layer or parent.gameObject:GetComponent(typeof(CS.Malody.Scene.Play.Skin.SkinNoteLayer))
        parent=parent.parent
    end
    assert(processor~=nil and layer~=nil,'Ma Skin Bridge: bar processor/layer is absent from the native note hierarchy')
    local result={group=group,processor=processor,layer=layer}
    if PROFILE.native_bar_source_candidate then
        result.legacy_bar_begin=UnityBridge.LegacyBarBegin(processor)
        result.legacy_bars_disabled=result.legacy_bar_begin~=nil and result.legacy_bar_begin>=2147483648
    end
    if PROFILE.native_bar_source_candidate and not result.legacy_bars_disabled and publicGetter(processor,'get_ResultBarList')==nil then
        result.generated=assert(UnityBridge.EnsureBarSource,'Ma Skin Bridge: native bar adapter absent')(processor)
    end
    return result
end
function UnityBridge.Bars(provider)
    if provider.legacy_bars_disabled then
        provider.suppressedBars=provider.suppressedBars or {};return provider.suppressedBars
    end
    local list=provider.generated or publicGetter(provider.processor,'get_ResultBarList')
    if list==nil then return nil end
    if provider.list~=list or provider.count~=list.Count then
        local bars={}
        for i=0,list.Count-1 do
            local carrier=list[i]
            -- This reader also serves the non-clock compiler path. Resolve
            -- the two recovered PUBLIC carrier bindings without requiring
            -- the optional chart-timing adapter to have selected a profile.
            local ok,speed=pcall(function()return carrier.bcay end)
            if not ok or type(speed)~='number' then ok,speed=pcall(function()return carrier.sya end) end
            assert(ok and type(speed)=='number','Ma Skin Bridge: native bar speed binding missing')
            bars[#bars+1]={offset=publicGetter(carrier,'get_StartOffset'),
                displayY=publicGetter(carrier,'get_StartY'),hs=speed}
        end
        provider.list,provider.count,provider.bars=list,list.Count,bars
    end
    return provider.bars
end
function UnityBridge.BarProgress(provider,bar)
    return provider.layer:CalculateProgress(bar.displayY,bar.hs,false)
end
function UnityBridge.LegacyClockInput(includeScroll)
    local group=Note:GetGroup('legacy_clock')
    local parent=group.transform;local processor,layer
    while parent~=nil and (processor==nil or includeScroll and layer==nil) do
        processor=processor or parent.gameObject:GetComponent(typeof(CS.Malody.Play.ProcessorFree))
        if includeScroll then layer=layer or parent.gameObject:GetComponent(typeof(CS.Malody.Scene.Play.Skin.SkinNoteLayer)) end
        parent=parent.parent
    end
    assert(processor,'Ma Skin Bridge: native timing processor is absent')
    local function field(object,name)
        name=NativeBindings.Name(name)
        local member=object:GetType():GetField(name,20) -- Public | Instance
        assert(member and member.IsPublic,'Ma Skin Bridge: public timing field missing '..name)
        return member:GetValue(object)
    end
    local function fraction(value)
        assert(publicGetter(value,'get_IsBeatValid'),'Ma Skin Bridge: absolute chart timings are not certified for this candidate')
        local f=publicGetter(value,'get_Beat')
        return {publicGetter(f,'get_Int'),publicGetter(f,'get_Numer'),publicGetter(f,'get_Denom')}
    end
    local chart=publicGetter(processor,'get_ChartToProcess')
    NativeBindings.Select(chart)
    local nativeMods=CS.System.Convert.ToInt32(publicGetter(processor,'get_UseMod'))
    local format=CS.System.Convert.ToInt32(publicGetter(chart,'get_Format'))
    if format==5 then return UnityBridge.LegacyOsuInput(chart,processor,layer,includeScroll) end
    assert(format==1,'Ma Skin Bridge: this clock candidate requires MC or mania OSU input')
    local timepoints=field(chart,'bifq');local points={}
    for i=0,timepoints.Count-1 do
        local point=timepoints[i]
        points[#points+1]={beat=fraction(field(point,'start')),beat_length=field(point,'beatLength')}
    end
    local list=publicGetter(processor,'get_ResultNoteList');local notes={}
    assert(list.Count==Chart:NoteCount(),'Ma Skin Bridge: native note timing count mismatch')
    for i=0,list.Count-1 do
        local source=field(list[i],'bcbb');local note=Chart:NoteAt(i)
        if includeScroll then assert(field(list[i],'bcay')==1,'Ma Skin Bridge: per-note speed is not certified for this scroll candidate') end
        -- ProcessorFree keeps the original NoteKey on bcbb while Flip/Luck
        -- changes ScriptNote.x. Match source order with the former, draw and
        -- judge with the latter; they are different identities after Mods.
        notes[#notes+1]={nid=note.nid,lane=note.x,source_lane=publicGetter(source,'get_X')+1,beat=fraction(field(source,'start')),
            endbeat=fraction(publicGetter(source,'get_EndOrStart'))}
    end
    if PROFILE.native_lifetime_candidate then UnityBridge.LegacySourceOrder(chart,notes,nativeMods) end
    local effects={}
    if includeScroll then
        local list=field(chart,'bifs')
        for i=0,list.Count-1 do
            local e=list[i];local value=field(e,'value')
            effects[#effects+1]={beat=fraction(field(e,'start')),type=CS.System.Convert.ToInt32(field(e,'type')),
                variant_type=CS.System.Convert.ToInt32(publicGetter(value,'get_Type')),value=publicGetter(value,'get_Double')}
        end
    end
    if includeScroll then assert(layer,'Ma Skin Bridge: native scroll layer is absent') end
    return {timepoints=points,notes=notes,effects=effects,layer=layer,native_mods=nativeMods}
end
local speedProperties=setmetatable({},{__mode='k'})
local carrierWindows=setmetatable({},{__mode='k'})
function UnityBridge.CarrierWindow(layer)
    assert(PROFILE.native_lifetime_candidate and PROFILE.native_key_judge_candidate,
        'Ma Skin Bridge: carrier window requires independent lifetime visuals and native Key judge')
    assert(layer:GetType().FullName=='Malody.Scene.Play.Skin.SkinNoteLayer',
        'Ma Skin Bridge: carrier window requires the Free compatibility layer')
    local state=carrierWindows[layer]
    if not state then
        state={original_up=layer.displayWindowUpY,original_down=layer.displayWindowDownY,
            judge_up=layer.judgeWindowUp,judge_down=layer.judgeWindowDown}
        carrierWindows[layer]=state
    end
    -- These are only the unused Free carrier's display distances. The owned
    -- legacy queue retains its full scroll window, and the native judge's
    -- mandatory visual timing guard remains unchanged. Do not clear the
    -- required runNoteMove delegate: this player's UpdateObject dereferences it.
    local judgeUp,judgeDown=layer.judgeWindowUp,layer.judgeWindowDown
    layer.displayWindowUpY=0;layer.displayWindowDownY=0
    assert(layer.judgeWindowUp==judgeUp and layer.judgeWindowDown==judgeDown,
        'Ma Skin Bridge: native carrier judge guard changed')
    return state
end
function UnityBridge.ScrollScale(layer)
    local member=speedProperties[layer]
    local scale
    if member==nil then
        local property=publicProperty(layer,'get_SpeedScale')
        scale=property:GetValue(layer,nil)
        -- Use only the public property's actual metadata name, and only
        -- after its real bridge getter agrees with reflection. Some builds
        -- omit it; those retain the proved public reflection route.
        local ok,name,value=pcall(function()
            local name=property.Name
            local readable,value=pcall(function()return layer[name]end)
            if readable and type(value)=='number' and value==scale then return name,value end
            -- The IL2CPP property's metadata name can be obfuscated while
            -- xLua's generated public binding uses its surviving getter name.
            -- Derive that name from the actual public MethodInfo, never from
            -- a guessed field or a cached speed setting.
            local getter=property:GetGetMethod()
            local publicName=getter.Name
            if publicName:sub(1,4)=='get_' then
                name=publicName:sub(5);readable,value=pcall(function()return layer[name]end)
                if readable and type(value)=='number' and value==scale then return name,value end
            end
            local method=layer[publicName]
            if type(method)=='function' and method(layer)==scale then
                return function()return method(layer)end,scale
            end
        end)
        member=ok and (type(name)=='string' or type(name)=='function') and type(value)=='number' and value==scale and name or false
        speedProperties[layer]=member
        submissions.scroll_scale_reflection_reads=(submissions.scroll_scale_reflection_reads or 0)+1
    elseif member then
        scale=type(member)=='function' and member() or layer[member]
        submissions.scroll_scale_direct_reads=(submissions.scroll_scale_direct_reads or 0)+1
    else
        scale=publicGetter(layer,'get_SpeedScale')
        submissions.scroll_scale_reflection_reads=(submissions.scroll_scale_reflection_reads or 0)+1
    end
    assert(scale>0,'Ma Skin Bridge: invalid native speed scale')
    return scale
end
function UnityBridge.ScrollDistance(layer)
    return layer.displayWindowUpY/UnityBridge.ScrollScale(layer)
end
local materials={}
local gridMaterials={}
local function straightMaterial(name)
    if not materials[name] then
        local shader=CS.UnityEngine.Shader.Find(name)
        assert(shader~=nil,'Ma Skin Bridge: native straight-alpha shader missing')
        local material=CS.UnityEngine.Material(shader)
        material:SetVector('_WorldOrigin',CS.UnityEngine.Vector4(0,0,0,0))
        material:SetVector('_WorldDirection',CS.UnityEngine.Vector4(0,1,0,0))
        material:SetVector('_RangeFade',CS.UnityEngine.Vector4(-1e20,-1e19,1e19,1e20))
        material:SetVector('_RangeCutoff',CS.UnityEngine.Vector4(-1e20,1e20,0,0))
        materials[name]=material
    end
    return materials[name]
end
function UnityBridge.NoteGrid(obj,file)
    UnityBridge.OwnNoteVisual(obj)
    ownedGridMeshes[obj]=nil
    -- Original ShapeSprite sampling has no maV track fade/cutoff. The default
    -- Grid material reads global track ranges; whole-plane depth moves a
    -- source-valid body through those unrelated ranges while its tail stays
    -- visible. Retain the shipped projective shader, with explicit local
    -- sampling state and the original standalone source texture.
    if not gridMaterials[file] then
        local material=CS.UnityEngine.Material(straightMaterial('Malody/Play/TrackFadeWithW'))
        material:SetTexture('_MainTex',sourceSprite(file).texture)
        gridMaterials[file]=material
    end
    local mesh=obj:GetComponent(typeof(CS.UnityEngine.MeshRenderer))
    assert(mesh~=nil,'Ma Skin Bridge: native Grid MeshRenderer missing')
    mesh.sharedMaterial=gridMaterials[file]
end
local function premultipliedMaterial(file,blend)
    local key=file..':'..(blend==nil and 'normal' or tostring(blend))
    if not premultipliedMaterials[key] then
        local shader=CS.UnityEngine.Shader.Find('Live2D/Live2D PremultipliedAlpha')
        assert(shader~=nil,'Ma Skin Bridge: shipped premultiplied shader missing')
        local material=CS.UnityEngine.Material(shader)
        local source=blend==1 and 5 or (blend==2 and 4 or 1)
        local destination=blend==nil and 10 or 1
        material:SetFloat('_SrcColor',source);material:SetFloat('_DstColor',destination)
        material:SetFloat('_SrcAlpha',blend==2 and 8 or source);material:SetFloat('_DstAlpha',destination);material:SetFloat('_Cull',0)
        material:SetTexture('_MainTex',sourceSprite(file).texture)
        premultipliedMaterials[key]=material
    end
    return premultipliedMaterials[key]
end
function UnityBridge.NoteSprite(obj,file)
    UnityBridge.OwnNoteVisual(obj)
    -- Cocos ordinary Sprite uses premultiplied texture bytes, byte-quantized
    -- RGB * node opacity, then ONE / ONE_MINUS_SRC_ALPHA. Its ShapeSprite body
    -- is a separate SRC_ALPHA path. This shipped shader's actual DXBC samples
    -- texture * vertex color without multiplying alpha again.
    local sprite=obj:GetComponent(typeof(CS.UnityEngine.SpriteRenderer))
    assert(sprite~=nil,'Ma Skin Bridge: native note SpriteRenderer missing')
    local frame=noteSprites[file]
    if not frame then
        local original=sourceSprite(file)
        assert(original~=nil,'Ma Skin Bridge: native note texture missing '..file)
        local texture=original.texture
        frame=CS.UnityEngine.Sprite.Create(texture,CS.UnityEngine.Rect(0,0,texture.width,texture.height),
            CS.UnityEngine.Vector2(.5,.5),100,0,CS.UnityEngine.SpriteMeshType.FullRect)
        noteSprites[file]=frame
    end
    sprite.sprite=frame
    noteGeometry[obj]=nil -- checkout/texture replacement must refresh all geometry
    ownedNoteSizing[obj]=nil
    ownedNativeTransforms[obj]=nil
    sprite.sharedMaterial=premultipliedMaterial(file)
    premultipliedSprites[obj]=true
    if ownedNoteVisuals[obj] then ownedPositionContracts[obj]=UnityBridge.CheckOwnedNotePosition(obj) end
end
function UnityBridge.Color(obj,r,g,b)
    appliedNoteAlpha[obj]=nil -- SetColor can rewrite native vertex alpha too
    sourceTints[obj]={r,g,b};obj:SetColor(r,g,b)
    if premultipliedSprites[obj] or premultipliedGraphics[obj] then UnityBridge.AlphaByte(obj,lastAlphaBytes[obj] or 255) end
end
function UnityBridge.NoteSize(obj,width,height,unit)
    -- Native setters retain the atlas frame's cached size. Its pack scale can
    -- differ from the standalone file, so set the public renderer scale too.
    local sizing=ownedNoteVisuals[obj] and ownedNoteSizing[obj]
    if not sizing then
        local renderer=obj:GetComponent(typeof(CS.UnityEngine.SpriteRenderer))
        local sprite=renderer.sprite;local rect=sprite.rect
        sizing={transform=obj.transform,ppu=sprite.pixelsPerUnit,width=rect.width,height=rect.height}
        if ownedNoteVisuals[obj] then ownedNoteSizing[obj]=sizing end
    end
    unit=unit or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    -- Keep the original operation ordering; only immutable sprite metadata
    -- and the owned Transform are retained. GL units and sizes stay live.
    sizing.transform.localScale=CS.UnityEngine.Vector3(width*sizing.ppu/(unit*sizing.width),
        height*sizing.ppu/(unit*sizing.height),1)
end
function UnityBridge.CombinedNotePosition(obj,x,y,unit,deadband)
    local state=ownedNotePositions[obj]
    if not state then
        local transform=obj.transform;local position=transform.localPosition
        state={transform=transform,x=position.x,y=position.y,z=position.z};ownedNotePositions[obj]=state
    end
    -- The existing public X/Y setters each fetch and rewrite localPosition.
    -- Preserve their exact float argument/division/subtraction and the
    -- verified per-engine deadband; submit both components together.
    local f=UnityBridge.Float
    deadband=deadband or .001 -- explicit legacy research route only
    local px,py=f(f(x)/unit),f(f(y)/unit)
    local nextX=math.abs(f(state.x-px))<deadband and state.x or px
    local nextY=math.abs(f(state.y-py))<deadband and state.y or py
    if nextX~=state.x or nextY~=state.y then
        state.transform.localPosition=CS.UnityEngine.Vector3(nextX,nextY,state.z)
        state.x,state.y=nextX,nextY
        submissions.combined_note_position_submissions=(submissions.combined_note_position_submissions or 0)+1
    end
end
function UnityBridge.CheckOwnedNotePosition(obj)
    local kind
    local found=pcall(function()kind=obj:GetType()end)
    if not found or not kind then return false end
    if notePositionContractTypes[kind]~=nil then return notePositionContractTypes[kind] end
    local transform,original,deadband
    local ok,reason=pcall(function()
        assert(kind.FullName=='Malody.Scene.Play.Note.PlayNoteFreeSubSprite','unknown note position contract')
        assert(NativeBindings and NativeBindings.NotePositionDeadband,'note position metadata missing')
        deadband=NativeBindings.NotePositionDeadband()
        assert(type(deadband)=='number' and deadband>0,'unproved native note position deadband')
        transform=obj.transform;original=transform.localPosition
        local V,f=CS.UnityEngine.Vector3,UnityBridge.Float
        local unit=f(CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize)
        assert(unit>0 and unit<math.huge,'invalid native GL unit')
        -- PUBLIC setters: Single argument, Single division/subtraction, then
        -- comparison with the inspected engine's double deadband. The accessor's managed wrapper must
        -- not become a second owner of this exclusive renderer's position.
        for _,pair in ipairs({{deadband*.5,deadband*1.5},{deadband*1.5,deadband*.5},
            {-deadband*1.5,-deadband*.5},{deadband*(1-1e-7),deadband*(1+1e-7)},{123.456,-654.321}}) do
            transform.localPosition=V(0,0,original.z)
            local x,y=f(pair[1]*unit),f(pair[2]*unit)
            obj.X=x;obj.Y=y
            local position=transform.localPosition
            local tx,ty=f(f(x)/unit),f(f(y)/unit)
            local ex=math.abs(f(tx))<deadband and 0 or tx
            local ey=math.abs(f(ty))<deadband and 0 or ty
            if position.x~=ex or position.y~=ey or position.z~=original.z then
                error(string.format('native note setter differs: unit=%.17g deadband=%.17g input=(%.17g,%.17g) actual=(%.17g,%.17g,%.17g) expected=(%.17g,%.17g,%.17g)',
                    unit,deadband,x,y,position.x,position.y,position.z,ex,ey,original.z))
            end
        end
    end)
    if original then transform.localPosition=original end
    notePositionContractTypes[kind]=ok and deadband or false
    if ok then submissions.owned_position_contract_types=(submissions.owned_position_contract_types or 0)+1
    else
        submissions.owned_position_contract_fallbacks=(submissions.owned_position_contract_fallbacks or 0)+1
        submissions.owned_position_contract_first_error=submissions.owned_position_contract_first_error or tostring(reason)
    end
    return notePositionContractTypes[kind]
end
function UnityBridge.BindPublicTransform(transform)
    assert(PROFILE.native_transform_submit_candidate and nativeMath,
        'Ma Skin Bridge: owned native Transform candidate is not enabled')
    local interop=CS.System.Runtime.InteropServices
    local handle=interop.GCHandle.Alloc(transform)
    local point=transform.localPosition
    local ok,value=pcall(function()
        -- xLua exposes System.IntPtr as Lua light userdata, not a boxed
        -- managed IntPtr with instance methods. Pass that exact token.
        local id=interop.GCHandle.ToIntPtr(handle)
        return nativeMath.bind_transform(id,point.x,point.y,point.z)
    end)
    if not ok then handle:Free();error(value) end
    -- Ownership of this normal managed handle transfers to a Lua userdata.
    -- Its C __gc finalizer frees it on cache retirement / Lua environment
    -- teardown. No permanent pin or engine-object pointer is exposed to Lua.
    return value
end
function UnityBridge.BindPublicVertices(mesh,vertices)
    assert(PROFILE.native_vertex_upload_candidate and nativeMath,
        'Ma Skin Bridge: native vertex candidate is not enabled')
    local interop=CS.System.Runtime.InteropServices
    local mh=interop.GCHandle.Alloc(mesh)
    local ah=interop.GCHandle.Alloc(vertices)
    local ok,value=pcall(function()
        return nativeMath.bind_vertices(interop.GCHandle.ToIntPtr(mh),interop.GCHandle.ToIntPtr(ah))
    end)
    if not ok then ah:Free();mh:Free();error(value) end
    return value
end
function UnityBridge.BindPublicText(component)
    assert(PROFILE.native_text_read_candidate and nativeMath,
        'Ma Skin Bridge: native text candidate is not enabled')
    local interop=CS.System.Runtime.InteropServices
    local handle=interop.GCHandle.Alloc(component)
    local ok,value=pcall(function()return nativeMath.bind_text(interop.GCHandle.ToIntPtr(handle))end)
    if not ok then handle:Free();error(value) end
    return value
end
function UnityBridge.PublicImageGeometry(obj,x,y,width,height,rotate,force)
    if not PROFILE.native_ui_submit_candidate or not ownedUIVisuals[obj] then return false end
    local binding=nativeImageWriters[obj]
    if not binding then
        local interop=CS.System.Runtime.InteropServices
        local handle=interop.GCHandle.Alloc(obj)
        local ok,value=pcall(function()return nativeMath.bind_image(interop.GCHandle.ToIntPtr(handle))end)
        if not ok then handle:Free();error(value) end
        binding=value;nativeImageWriters[obj]=binding
    end
    nativeMath.submit_image(binding,x,y,width,height,rotate,force and 1 or 0)
    return true
end
function UnityBridge.UploadPublicVertices(binding,bytes)
    return nativeMath.upload_vertices(binding,bytes)
end
function UnityBridge.BindPublicGrid(mesh,vertices,uvs)
    local interop=CS.System.Runtime.InteropServices
    local mh=interop.GCHandle.Alloc(mesh)
    local vh=interop.GCHandle.Alloc(vertices)
    local uh=interop.GCHandle.Alloc(uvs)
    local ok,value=pcall(function()
        return nativeMath.bind_grid(interop.GCHandle.ToIntPtr(mh),interop.GCHandle.ToIntPtr(vh),interop.GCHandle.ToIntPtr(uh))
    end)
    if not ok then uh:Free();vh:Free();mh:Free();error(value) end
    return value
end
function UnityBridge.ReadMusicbarCamera(camera)
    if not (PROFILE.native_vertex_upload_candidate and PROFILE.native_musicbar_camera_local_candidate) then return nil end
    local state=nativeCameraReaders[camera]
    if not state then
        local interop=CS.System.Runtime.InteropServices;local handle=interop.GCHandle.Alloc(camera)
        local ok,value=pcall(function()return nativeMath.bind_camera(interop.GCHandle.ToIntPtr(handle))end)
        if not ok then handle:Free();error(value) end
        state={binding=value};nativeCameraReaders[camera]=state
    end
    local enabled,bytes=nativeMath.read_camera(state.binding)
    if bytes then
        assert(#bytes==64,'Ma Skin Bridge: invalid public Camera matrix size')
        local function member(i)return (string.unpack('f',bytes,i*4+1))end
        state.projection={native_public_snapshot=true,m00=member(0),m11=member(5),
            m02=member(8),m12=member(9),m32=member(11),m33=member(15)}
    end
    return enabled~=0,state.projection
end
function UnityBridge.NoteGeometry(obj,x,y,width,height,rotate)
    submissions.note_geometry_calls=submissions.note_geometry_calls+1
    -- Only our retained groups own their transforms exclusively. Native
    -- pooled carriers can reset properties between calls and must refresh.
    local unit=UnityBridge.FrameGLSize or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    local previous=PROFILE.native_lifetime_candidate and noteGeometry[obj] or nil
    if previous and previous.unit~=unit then previous=nil end
    if PROFILE.native_transform_submit_candidate and ownedNoteVisuals[obj] and premultipliedSprites[obj] then
        local binding=ownedNativeTransforms[obj]
        local sizing=ownedNoteSizing[obj]
        if not sizing then
            local sprite=obj:GetComponent(typeof(CS.UnityEngine.SpriteRenderer)).sprite
            local rect=sprite.rect
            sizing={transform=obj.transform,ppu=sprite.pixelsPerUnit,width=rect.width,height=rect.height}
            ownedNoteSizing[obj]=sizing
        end
        if not binding then
            binding=UnityBridge.BindPublicTransform(sizing.transform);ownedNativeTransforms[obj]=binding
        end
        local resized=not previous or previous.w~=width or previous.h~=height
        if not previous or previous.rotate~=rotate then obj.Rotate=rotate end
        if resized or not previous or previous.x~=x or previous.y~=y then
            nativeMath.submit_transform(binding,x,y,unit,resized and 1 or 0,
                width*sizing.ppu/(unit*sizing.width),height*sizing.ppu/(unit*sizing.height),0)
            submissions.native_transform_submissions=(submissions.native_transform_submissions or 0)+1
        end
        if resized then submissions.note_resizes=submissions.note_resizes+1 end
        previous=previous or {};previous.x=x;previous.y=y;previous.w=width;previous.h=height
        previous.rotate=rotate;previous.unit=unit;noteGeometry[obj]=previous
        return
    end
    if (PROFILE.native_combined_position_candidate or ownedPositionContracts[obj]) and ownedNoteVisuals[obj] and premultipliedSprites[obj] then
        if not previous or previous.x~=x or previous.y~=y then
            local threshold=ownedPositionContracts[obj]
            UnityBridge.CombinedNotePosition(obj,x,y,unit,type(threshold)=='number' and threshold or nil)
        end
    else
        if not previous or previous.x~=x then obj.X=x end
        if not previous or previous.y~=y then obj.Y=y end
    end
    local resized=not previous or previous.w~=width or previous.h~=height
    -- The native Sprite size setters scale from the importer's old rect;
    -- NoteSize immediately replaces that scale from our actual source rect.
    -- Exclusive source-bound Sprites need only the final transform upload.
    -- Native pool objects and Grids retain the public setters/size fields.
    if resized and not (PROFILE.native_lifetime_candidate and ownedNoteVisuals[obj] and premultipliedSprites[obj]) then obj.Width=width;obj.Height=height end
    if not previous or previous.rotate~=rotate then obj.Rotate=rotate end
    if resized then UnityBridge.NoteSize(obj,width,height,unit);submissions.note_resizes=submissions.note_resizes+1 end
    if PROFILE.native_lifetime_candidate then
        previous=previous or {};previous.x=x;previous.y=y;previous.w=width;previous.h=height
        previous.rotate=rotate;previous.unit=unit;noteGeometry[obj]=previous
    end
end
local function components(obj,kind)
    -- The non-generic GetComponentsInChildren(Type,bool) overload is stripped
    -- from this player. GetComponent(Type) and Transform traversal survive.
    local result={Length=0}
    local function visit(transform)
        local component=transform.gameObject:GetComponent(kind)
        if component~=nil then result[result.Length]=component;result.Length=result.Length+1 end
        for i=0,transform.childCount-1 do visit(transform:GetChild(i)) end
    end
    visit(obj.transform)
    return result
end
local function renderer(obj)
    local found=UnityBridge.cache[obj]
    if found then return found end
    assert(UnityBridge.Available(),'Ma Skin Bridge requires the public xLua CS bridge')
    local graphics=components(obj,typeof(CS.UnityEngine.UI.Graphic))
    local sprites=components(obj,typeof(CS.UnityEngine.SpriteRenderer))
    local meshes=components(obj,typeof(CS.UnityEngine.MeshFilter))
    assert(graphics.Length+sprites.Length+meshes.Length>0,'Ma Skin Bridge: no render surface for module')
    found={graphics=graphics,sprites=sprites,meshes=meshes};UnityBridge.cache[obj]=found
    return found
end
local function updateUIFrame(layer,width,height,gl)
    -- SkinModuleBase caches its parent's CanvasScaler/RectTransform unit in
    -- Awake. It can differ from SkinRuntime.UnitSize and survives reparenting.
    local unit=layer.nativeUnit
    if width==nil then
        gl=CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
        width,height=Game:Width(),Game:Height()
    end
    if layer.width==width and layer.height==height and layer.unit==unit and layer.gl==gl then return end
    assert(unit>0 and gl>0,'Ma Skin Bridge: native render units not initialized')
    local transform=layer.transform
    transform.sizeDelta=CS.UnityEngine.Vector2(width*unit,height*unit)
    local projection=layer.projection
    if projection then
        local p=projection.matrix
        assert(p[4]==0 and p[8]==0 and p[16]>0,'Ma Skin Bridge: unverified UI projection plane')
        local sx=p[1]*projection.logical_width/(2*p[16])
        local sy=p[6]*projection.logical_height/(2*p[16])
        transform.localScale=CS.UnityEngine.Vector3(sx/(gl*unit),sy/(gl*unit),1/(gl*unit))
        transform.localPosition=CS.UnityEngine.Vector3(p[13]*width/(2*p[16]*gl),p[14]*height/(2*p[16]*gl),0)
    else
        transform.localScale=CS.UnityEngine.Vector3(1/(gl*unit),1/(gl*unit),1/(gl*unit))
        transform.localPosition=CS.UnityEngine.Vector3(-width/(2*gl),-height/(2*gl),0)
    end
    layer.width,layer.height,layer.unit,layer.gl=width,height,unit,gl
end
function UnityBridge.UpdateUIFrames()
    if next(uiGroups)==nil then return end
    -- All canvases share this frame's viewport and GL unit. Read them once
    -- across xLua, retaining each canvas's original cached native UI unit.
    local width,height=Game:Width(),Game:Height()
    local viewport=UnityBridge.UIViewport or {}
    viewport.width,viewport.height=width,height;UnityBridge.UIViewport=viewport
    local gl=CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    UnityBridge.FrameGLSize=gl
    for _,layer in pairs(uiGroups) do updateUIFrame(layer,width,height,gl) end
end
function UnityBridge.UIWorldPoint(x,y,entry)
    assert(uiRoot,'Ma Skin Bridge: native UI group missing')
    local gl=UnityBridge.FrameGLSize or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    local layer=entry and uiGroups[entry]
    local transform=layer and layer.planeTransform or uiRoot.transform
    local viewport=UnityBridge.UIViewport
    local width,height
    if viewport then width,height=viewport.width,viewport.height else width,height=Game:Width(),Game:Height() end
    return transform:TransformPoint(CS.UnityEngine.Vector3(x*width/(2*gl),y*height/(2*gl),0))
end
function UnityBridge.TextPlane(entry)
    assert(uiRoot,'Ma Skin Bridge: native UI group missing')
    local layer=assert(uiGroups[entry],'Ma Skin Bridge: text UI layer missing')
    return layer.planeTransform or uiRoot.transform
end
function UnityBridge.UISurface(obj,order,blend,group)
    -- UI/Default's reduced precision also changes final blend rounding.
    -- UI vertices carry UV.xy with w=0: use the non-projective shipped shader.
    local surfaces=renderer(obj)
    assert(surfaces.graphics.Length>0,'Ma Skin Bridge: native UI surface missing')
    -- Free uses separate cameras for AboveNote UI and Note renderers. Sorting
    -- layer alone cannot interleave their draws. Host visual UI on the public
    -- Notes group so the actual note camera draws both in legacy zindex order.
    -- Keep every glyph/frame of ONE legacy element in the same canvas. Equal
    -- sortingOrder on separate canvases reverses overlapping glyphs in maV.
    local layer=uiGroups[group]
    if not layer then
        local rect=obj.transform.rect
        local unit
        if obj.Width>0 and rect.width>0 then unit=rect.width/obj.Width
        elseif obj.Height>0 and rect.height>0 then unit=rect.height/obj.Height end
        if not unit then
            -- Text modules can expose zero logical width/height while keeping
            -- an auto-sized RectTransform. Measure the public position setter's
            -- cached unit before the first frame, then restore its position.
            local x=obj.X;obj.X=1080
            unit=obj.transform.anchoredPosition3D.x/1080;obj.X=x
        end
        assert(unit and unit>0,'Ma Skin Bridge: native UI dimensions not initialized')
        if not uiRoot then uiRoot=Note:GetGroup('legacy_ui') end
        local go=CS.UnityEngine.GameObject('MaSkinBridgeLayer',typeof(CS.UnityEngine.RectTransform))
        local noteLayer=CS.UnityEngine.LayerMask.NameToLayer('Note')
        assert(noteLayer>=0,'Ma Skin Bridge: native Note layer missing')
        go.layer=noteLayer
        local transform=go.transform;transform:SetParent(uiRoot.transform,false)
        local onPlayPlane=PROFILE.legacy_play_plane and group.scene_key and group.scene_key[1]==1 and group.scene_key[2]==0
        local planeTransform
        if onPlayPlane then
            local planeRoot=CS.UnityEngine.GameObject('legacy_play_plane_ui')
            planeRoot.transform:SetParent(uiRoot.transform,false)
            UnityBridge.ApplyLegacyPlane(planeRoot.transform)
            planeTransform=planeRoot.transform
            transform:SetParent(planeRoot.transform,false)
        end
        transform.anchorMin=CS.UnityEngine.Vector2(0,0);transform.anchorMax=CS.UnityEngine.Vector2(0,0)
        transform.pivot=CS.UnityEngine.Vector2(0,0)
        local batch=group.canvas_batch
        local shared=batch and uiCanvasBatches[batch.id]
        local canvas
        if batch then
            if not shared then
                local root=CS.UnityEngine.GameObject('MaSkinBridgeCanvasBatch',typeof(CS.UnityEngine.RectTransform))
                root.layer=noteLayer;root.transform:SetParent(transform.parent,false)
                shared={transform=root.transform,unit=unit,members={}}
                uiCanvasBatches[batch.id]=shared
                shared.canvas=root:AddComponent(typeof(CS.UnityEngine.Canvas))
                shared.canvas.renderMode=CS.UnityEngine.RenderMode.WorldSpace
                shared.canvas.overrideSorting=true;shared.canvas.sortingLayerName='Notes';shared.canvas.sortingOrder=order
                LegacyLayers.UI(shared.canvas,{scene_key=batch.scene_key})
            end
            assert(shared.unit==unit,'Ma Skin Bridge: contiguous UI units differ')
            transform:SetParent(shared.transform,false)
            shared.members[batch.rank+1]=transform;canvas=shared.canvas
        else
            canvas=go:AddComponent(typeof(CS.UnityEngine.Canvas))
            canvas.renderMode=CS.UnityEngine.RenderMode.WorldSpace
            canvas.overrideSorting=true;canvas.sortingLayerName='Notes';canvas.sortingOrder=order
            if PROFILE.native_layer_order_candidate then LegacyLayers.UI(canvas,group) end
        end
        -- Bitmap text and MusicBar meshes already carry their own old clip
        -- projection. Ordinary Sprite/Image geometry needs it BEFORE the 3D
        -- plane too: ApplyLegacyPlane inverts the incoming flat projection.
        -- Omitting it shifts/sizes images by the old camera's bias, magnified
        -- near the horizon, while notes and glyphs follow a different mapping.
        layer={transform=transform,canvas=canvas,nativeUnit=unit,planeTransform=planeTransform,
            projection=not group.bitmap_font and not group.musicbar and PROFILE.native_note_projection or nil};uiGroups[group]=layer
        updateUIFrame(layer)
    end
    obj.transform:SetParent(layer.transform,false)
    local function setLayer(transform)
        transform.gameObject.layer=layer.transform.gameObject.layer
        for i=0,transform.childCount-1 do setLayer(transform:GetChild(i)) end
    end
    setLayer(obj.transform)
    for i=0,surfaces.graphics.Length-1 do
        local graphic=surfaces.graphics[i]
        if graphic:GetType().FullName=='TMPro.TextMeshProUGUI' then
            -- SDF font atlases require the font's own material. A bitmap
            -- straight-alpha shader interprets distance values as image pixels.
        elseif blend==1 then
            assert(graphic.material.shader.name=='Malody/UI/Additive','Ma Skin Bridge: native additive UI material missing')
        else graphic.material=straightMaterial('Malody/Play/TrackFade') end
    end
end
function UnityBridge.FinalizeUIBatches()
    for _,batch in pairs(uiCanvasBatches) do
        -- Init follows declaration order; recover actual painter order after
        -- all sibling parents exist, keeping each element's frame/glyph order.
        for _,transform in ipairs(batch.members) do transform:SetAsLastSibling() end
    end
end

function UnityBridge.PrepareNumberGroup(entry,objects)
    if not entry.number or entry._numberGroup then return end
    -- Preserve the existing skew decomposition for definitions that need it.
    if entry.attrs.skew then return end
    for _,track in ipairs(PROFILE.motions[entry.motion] or {}) do
        if track.kind=='skew' or track.kind=='skewx' or track.kind=='skewy' then return end
    end
    local layer=assert(uiGroups[entry],'Ma Skin Bridge: numeric UI layer missing')
    local go=CS.UnityEngine.GameObject('MaSkinBridgeNumber@'..entry.name,typeof(CS.UnityEngine.RectTransform))
    go.layer=layer.transform.gameObject.layer
    local transform=go.transform
    transform:SetParent(layer.transform,false)
    local zero=CS.UnityEngine.Vector2(0,0)
    transform.anchorMin=zero;transform.anchorMax=zero;transform.pivot=zero;transform.sizeDelta=zero
    for _,key in ipairs(entry.handles.glyphs) do
        objects[key].transform:SetParent(transform,false)
        objects[key].Rotate=0
    end
    entry._numberGroup={transform=transform,unit=layer.nativeUnit}
end

function UnityBridge.NumberGroupTransform(entry,x,y,rotate,sy)
    local group=entry._numberGroup
    if not group then return false end
    local transform=group.transform
    if group.x~=x or group.y~=y then
        transform.localPosition=CS.UnityEngine.Vector3(x*group.unit,y*group.unit,0)
        group.x,group.y=x,y
        submissions.number_parent_positions=(submissions.number_parent_positions or 0)+1
    end
    if group.rotate~=rotate then
        transform.localRotation=CS.UnityEngine.Quaternion.Euler(0,0,-rotate)
        group.rotate=rotate
    end
    if group.sy~=sy then
        transform.localScale=CS.UnityEngine.Vector3(1,sy,1);group.sy=sy
        submissions.number_parent_scales=(submissions.number_parent_scales or 0)+1
    end
    return true
end

function UnityBridge.SkewMatrix(rotate,skewX,skewY)
    local f=UnityBridge.Float
    local radians=f(math.pi/180)
    local kx=f(math.tan(f(skewX*radians)))
    local ky=f(math.tan(f(skewY*radians)))
    local angle=-rotate*math.pi/180;local c,s=math.cos(angle),math.sin(angle)
    -- Conjugate the native shear around geometry already rotated by the
    -- public image/glyph setters. This moves the complete widget together.
    return 1-c*s*(kx+ky),c*c*kx-s*s*ky,c*c*ky-s*s*kx,1+c*s*(kx+ky)
end
function UnityBridge.SkewFactors(a,b,c,d)
    local aa,bb,ab=a*a+c*c,b*b+d*d,a*b+c*d
    local phi=.5*math.atan(2*ab,aa-bb)
    local largest=.5*(aa+bb+math.sqrt((aa-bb)^2+4*ab*ab))
    local sx=math.sqrt(largest)
    assert(sx>0 and sx<math.huge,'Ma Skin Bridge: non-finite native skew')
    local vx,vy=math.cos(phi),math.sin(phi)
    local theta=math.atan((c*vx+d*vy)/sx,(a*vx+b*vy)/sx)
    return theta*180/math.pi,sx,(a*d-b*c)/sx,-phi*180/math.pi
end
function UnityBridge.SkewAnchor(rotate,anchor,width,height,skewX,skewY)
    if skewX==0 and skewY==0 then return 0,0 end
    local ax=(anchor%3)*.5*width
    local ay=(1-math.floor(anchor/3)*.5)*height
    local angle=-rotate*math.pi/180;local co,si=math.cos(angle),math.sin(angle)
    return ax-co*ax+si*ay,ay-si*ax-co*ay
end
function UnityBridge.SkewEntry(entry,x,y,rotate,skewX,skewY,width,height)
    local layer=uiGroups[entry]
    if not layer or not UnityBridge.Available() then return end
    local state=layer.skew
    if not state and skewX==0 and skewY==0 then return end
    if state and state.x==x and state.y==y and state.rotate==rotate and state.skewX==skewX and state.skewY==skewY and
        state.width==layer.width and state.height==layer.height and state.imageWidth==width and state.imageHeight==height then return end
    local V,Q=CS.UnityEngine.Vector3,CS.UnityEngine.Quaternion
    if not state then
        local children={}
        for i=0,layer.transform.childCount-1 do children[#children+1]=layer.transform:GetChild(i) end
        local function rect(name,parent)
            local go=CS.UnityEngine.GameObject(name,typeof(CS.UnityEngine.RectTransform));go.layer=layer.transform.gameObject.layer
            local transform=go.transform;transform:SetParent(parent,false)
            transform.anchorMin=CS.UnityEngine.Vector2(0,0);transform.anchorMax=CS.UnityEngine.Vector2(0,0)
            transform.pivot=CS.UnityEngine.Vector2(0,0)
            return transform
        end
        local outer=rect('legacy_skew_origin',layer.transform)
        local scale=rect('legacy_skew_scale',outer)
        local turn=rect('legacy_skew_basis',scale)
        local content=rect('legacy_skew_content',turn)
        for _,child in ipairs(children) do child:SetParent(content,false) end
        state={outer=outer,scale=scale,turn=turn,content=content};layer.skew=state
    end
    for _,transform in ipairs({state.outer,state.scale,state.turn,state.content}) do transform.sizeDelta=layer.transform.sizeDelta end
    local a,b,c,d=UnityBridge.SkewMatrix(rotate,skewX,skewY)
    local theta,sx,sy,phi=UnityBridge.SkewFactors(a,b,c,d)
    local px,py=x*layer.nativeUnit,y*layer.nativeUnit
    local dx,dy=0,0
    if skewX~=0 or skewY~=0 then
        -- Original Node_GetParentTransform has an additional anchor/rotation
        -- translation whenever skew is nonzero. Preserve that native branch,
        -- even though a conventional shear would keep the pivot stationary.
        dx,dy=UnityBridge.SkewAnchor(rotate,entry.anchor,width,height,skewX,skewY)
        dx,dy=dx*layer.nativeUnit,dy*layer.nativeUnit
    end
    state.outer.localPosition=V(px+dx,py+dy,0);state.outer.localRotation=Q.Euler(0,0,theta)
    state.scale.localScale=V(sx,sy,1);state.turn.localRotation=Q.Euler(0,0,phi)
    state.content.localPosition=V(-px,-py,0)
    state.x,state.y,state.rotate,state.skewX,state.skewY=x,y,rotate,skewX,skewY
    state.width,state.height=layer.width,layer.height
    state.imageWidth,state.imageHeight=width,height
end
function UnityBridge.AlphaByte(obj,value)
    local byte=UnityBridge.Byte(value)
    lastAlphaBytes[obj]=byte
    if ownedNoteVisuals[obj] or ownedUIVisuals[obj] then
        submissions.alpha_calls=submissions.alpha_calls+1
        if appliedNoteAlpha[obj]==byte then submissions.alpha_cache_hits=submissions.alpha_cache_hits+1;return end
    end
    local r=renderer(obj)
    -- Only our known premultiplied material has a proved zero-contribution
    -- RGBA=(0,0,0,0) path for every supported legacy blend. Alpha alone is
    -- insufficient for arbitrary materials (e.g. color-based additive blend).
    local visibility=premultipliedGraphics[obj] and ownedUIVisibility[obj]
    local visible=byte~=0
    local changeVisibility=visibility and visibility.enabled~=visible
    local function premultipliedColor(c)
        local tint=sourceTints[obj] or {255,255,255};local opacity=UnityBridge.Float(byte/255)
        c.r=UnityBridge.Byte(UnityBridge.Float(tint[1]*opacity))/255
        c.g=UnityBridge.Byte(UnityBridge.Float(tint[2]*opacity))/255
        c.b=UnityBridge.Byte(UnityBridge.Float(tint[3]*opacity))/255
        return c
    end
    for i=0,r.graphics.Length-1 do
        local g=r.graphics[i];local c=g.color
        if premultipliedGraphics[obj] then c=premultipliedColor(c) end
        c.a=byte/255;g.color=c
        if changeVisibility then
            -- Alpha-zero source sprites are absent from visual traversal.
            -- Keep the module/variable/event component alive; only its owned
            -- plain Graphic leaves Canvas rendering until it becomes visible.
            g.enabled=visible
            if byte==0 then g.canvasRenderer:Clear() end
        end
    end
    if visibility then visibility.enabled=visible end
    for i=0,r.sprites.Length-1 do
        local s=r.sprites[i];local c=s.color
        if premultipliedSprites[obj] then c=premultipliedColor(c) end
        c.a=byte/255;s.color=c
    end
    for i=0,r.meshes.Length-1 do
        local mesh=r.meshes[i].sharedMesh
        if mesh then
            local colors=mesh.colors32
            for j=0,colors.Length-1 do local c=colors[j];c.a=byte;colors[j]=c end
            mesh.colors32=colors
        end
    end
    if ownedNoteVisuals[obj] or ownedUIVisuals[obj] then appliedNoteAlpha[obj]=byte end
end
function UnityBridge.OwnUIVisual(obj,manageVisibility)
    -- Only compiler-created usage=99, type=5000 pictures reach this path.
    -- Plain SkinRuntimeImage has no frame Update/score/input writer; its
    -- derived multi-frame, progress and text components retain full writes.
    -- Rebinding after native setup/retry invalidates the cached alpha.
    if obj.GetType and obj:GetType().FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeImage' then
        ownedUIVisuals[obj]=true;appliedNoteAlpha[obj]=nil
        ownedUIVisibility[obj]=manageVisibility==true and {} or nil
    end
end
function UnityBridge.InvalidateUIVisuals()
    for _,reader in pairs(nativeTextReaders) do reader.value=nil end
    for obj in pairs(ownedUIVisuals) do
        nativeImageWriters[obj]=nil
        appliedNoteAlpha[obj]=nil
        if ownedUIVisibility[obj] then ownedUIVisibility[obj].enabled=nil end
    end
end
function UnityBridge.OwnNoteVisual(obj)
    if PROFILE.native_lifetime_candidate then ownedNoteVisuals[obj]=true end
end
function UnityBridge.PrepareLifetimeTemplate(mod,e,isHold)
    -- Group.AddSprite is Loading-only and its public Clone returns nil.
    -- Keep one immutable prototype instead. A Unity clone gets fresh managed
    -- dictionaries, so resolve its actual components into our own child map;
    -- never expect native GetChild or a Grid's private mesh cache to copy.
    if PROFILE.native_math_module then return end
    local body=e.states['2'] and e.states['2'][1]
    -- OnDrawNote builds these same unsliced head/Grid/tail components for
    -- every source type. Type alone is not a cloning capability: the actual
    -- child layout, independent Grid state and slicing semantics decide it.
    if isHold and (e.attrs.part or not body or body.tiles) then return end
    local parts={};local names=isHold and {'head','body','tail'} or {'head'}
    for _,name in ipairs(names) do
        local child=mod:GetChild(name)
        if not child or child.transform.parent~=mod.transform or child.gameObject.name~=name then return end
        parts[name]={source=child,kind=child:GetType()}
    end
    if isHold then
        -- Initialize the importer UV rectangle through the original public
        -- Grid while Loading; later copies own independent public Mesh data.
        UnityBridge.OwnedGridQuad(parts.body.source,{{0,0},{1,0},{0,1},{1,1}},0,1)
        local grid=ownedGridMeshes[parts.body.source]
        if not grid then return end
        parts.body.grid=grid
    end
    return {source=mod,parts=parts}
end
function UnityBridge.CloneLifetimeTemplate(template,name)
    local engine=CS.UnityEngine
    local go=engine.Object.Instantiate(template.source.gameObject,template.source.transform.parent,false)
    go.name=name;go:SetActive(false)
    local component=go:GetComponent(template.source:GetType())
    local children={}
    for part,source in pairs(template.parts) do
        local transform=assert(go.transform:Find(part),'Ma Skin Bridge: lifetime prototype child missing')
        local child=assert(transform.gameObject:GetComponent(source.kind),'Ma Skin Bridge: lifetime prototype component missing')
        children[part]=child;ownedNoteVisuals[child]=true
        if source.grid then
            local original=source.grid
            local mesh=engine.Object.Instantiate(original.mesh)
            transform.gameObject:GetComponent(typeof(engine.MeshFilter)).sharedMesh=mesh
            local state={mesh=mesh,u0=original.u0,v0=original.v0,u1=original.u1,v1=original.v1,
                independent_copy=true,
                vertices=CS.System.Array.CreateInstance(typeof(engine.Vector3),16),
                uvs=CS.System.Array.CreateInstance(typeof(engine.Vector4),16)}
            if automaticPackedMeshes or PROFILE.native_packed_mesh_candidate then initializeGridBytes(state) end
            for i=0,15 do state.vertices[i]=engine.Vector3(0,0,0);state.uvs[i]=engine.Vector4(0,0,0,1) end
            ownedGridMeshes[child]=state
        else
            premultipliedSprites[child]=premultipliedSprites[source.source]
            sourceTints[child]=sourceTints[source.source]
        end
    end
    -- Unity's component identity remains visible to independent renderer
    -- readback. The wrapper replaces only the nonserialized child dictionary.
    local mod={gameObject=go,transform=go.transform,
        GetInstanceID=function()return component:GetInstanceID()end,
        GetChild=function(_,part)return children[part]end}
    submissions.lifetime_visual_clones=(submissions.lifetime_visual_clones or 0)+1
    return mod,children
end
local function sourceRegionSprite(file,region)
    -- UI atlas padding does not clamp to a frame edge. Direct source PNGs in
    -- the legacy game do clamp; keep the original file texture for sampling.
    local atlas=PROFILE.ui_atlas and PROFILE.ui_atlas[file]
    if atlas then
        assert(not region,'Ma Skin Bridge: source subrect cannot be substituted by a UI atlas')
        region=atlas.rect;file=atlas.file
    end
    local sprite=sourceSprite(file)
    assert(sprite~=nil,'Ma Skin Bridge: missing glyph sprite '..file)
    if region then
        local key=file..':'..table.concat(region,',')
        if not regionSprites[key] then
            regionSprites[key]=CS.UnityEngine.Sprite.Create(sprite.texture,CS.UnityEngine.Rect(table.unpack(region)),
                CS.UnityEngine.Vector2(.5,.5),100,0,CS.UnityEngine.SpriteMeshType.FullRect)
        end
        sprite=regionSprites[key]
    end
    return sprite
end
function UnityBridge.PrepareUIFrames(entry)
    for _,frames in pairs(entry.states) do for _,texture in ipairs(frames) do
        sourceRegionSprite(texture.file,texture.sample_rect)
        local atlas=PROFILE.ui_atlas and PROFILE.ui_atlas[texture.file]
        if texture.alpha_encoding=='cocos-premultiplied-rgb' then premultipliedMaterial(atlas and atlas.file or texture.file,entry.legacy_blend) end
    end end
end
function UnityBridge.SpriteFile(obj,file,alphaEncoding,blend,region)
    local r=renderer(obj)
    assert(r.graphics.Length==1,'Ma Skin Bridge: expected one bitmap glyph surface')
    r.graphics[0].sprite=sourceRegionSprite(file,region)
    if alphaEncoding=='cocos-premultiplied-rgb' then
        local atlas=PROFILE.ui_atlas and PROFILE.ui_atlas[file]
        r.graphics[0].material=premultipliedMaterial(atlas and atlas.file or file,blend)
        premultipliedGraphics[obj]=true
    end
end
function UnityBridge.GridWeights(points)
    if nativeMath then
        return nativeMath.grid_weights(points[1][1],points[1][2],points[2][1],points[2][2],
            points[3][1],points[3][2],points[4][1],points[4][2])
    end
    local function length(a,b)
        local dx=UnityBridge.Float(UnityBridge.Float(a[1])-UnityBridge.Float(b[1]))
        local dy=UnityBridge.Float(UnityBridge.Float(a[2])-UnityBridge.Float(b[2]))
        return UnityBridge.Float(math.sqrt(UnityBridge.Float(UnityBridge.Float(dx*dx)+UnityBridge.Float(dy*dy))))
    end
    local head,tail=length(points[1],points[2]),length(points[3],points[4])
    local hq,tq=1,1
    if head<=tail and tail>0 then hq=UnityBridge.Float(head/tail)
    elseif head>0 then tq=UnityBridge.Float(tail/head) end
    return hq,tq
end
function UnityBridge.TileMesh(obj,points,texture,tile,sw,color,alpha)
    appliedNoteAlpha[obj]=nil -- this path replaces mesh colors directly
    local hq,tq=UnityBridge.GridWeights(points)
    -- Clip each ORIGINAL triangle in homogeneous UV space. Replacing its
    -- diagonal by a new quad changes the legacy piecewise interpolation.
    local source={
        {points[3][1],points[3][2],0,0,tq},
        {points[4][1],points[4][2],tq,0,tq},
        {points[1][1],points[1][2],0,hq,hq},
        {points[2][1],points[2][2],hq,hq,hq}}
    local left,top,right,bottom=table.unpack(tile.range)
    local planes={{3,left,1},{3,right,-1},{4,top,1},{4,bottom,-1}}
    local vertices,indices={},{}
    for _,triangle in ipairs({{3,4,1},{1,4,2}}) do
        local polygon={source[triangle[1]],source[triangle[2]],source[triangle[3]]}
        for _,plane in ipairs(planes) do
            local clipped={}
            if #polygon>0 then
                local previous=polygon[#polygon]
                local dp=(previous[plane[1]]-plane[2]*previous[5])*plane[3]
                for _,current in ipairs(polygon) do
                    local dc=(current[plane[1]]-plane[2]*current[5])*plane[3]
                    if (dc>=0)~=(dp>=0) then
                        local t=dp/(dp-dc);local crossing={}
                        for j=1,5 do crossing[j]=previous[j]+(current[j]-previous[j])*t end
                        clipped[#clipped+1]=crossing
                    end
                    if dc>=0 then clipped[#clipped+1]=current end
                    previous,dp=current,dc
                end
            end
            polygon=clipped
        end
        local offset=#vertices
        for _,v in ipairs(polygon) do vertices[#vertices+1]=v end
        for i=2,#polygon-1 do
            indices[#indices+1]=offset;indices[#indices+1]=offset+i-1;indices[#indices+1]=offset+i
        end
    end
    local surfaces=renderer(obj);surfaces.tileBuffers=surfaces.tileBuffers or {}
    local unit=CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    local red,green,blue=255,255,255
    if color and #color==7 then red,green,blue=tonumber(color:sub(2,3),16),tonumber(color:sub(4,5),16),tonumber(color:sub(6,7),16) end
    local rgba=CS.UnityEngine.Color32(red,green,blue,UnityBridge.Byte(UnityBridge.BytePercent(alpha)))
    for k=0,surfaces.meshes.Length-1 do
        local mesh=surfaces.meshes[k].sharedMesh
        local buffer=surfaces.tileBuffers[k]
        if not buffer then
            -- AddGrid starts with an EMPTY mesh. SetVertex builds the native
            -- 4x4 surface and its texture UVs before we capture its UV domain.
            -- The independent CPU bridge must not invent those initial UVs.
            for i,p in ipairs(points) do obj:SetVertex(i-1,(p[1]-sw/2)*1.5,(p[2]-360)*1.5) end
            local list=CS.System.Collections.Generic.List(CS.UnityEngine.Vector4)();mesh:GetUVs(0,list)
            assert(list.Count==16,'Ma Skin Bridge: tiled Grid native UV initialization failed')
            local lo,hi=list[0],list[15]
            buffer={base={lo.x/lo.w,lo.y/lo.w,hi.x/hi.w,hi.y/hi.w},sizes={}};surfaces.tileBuffers[k]=buffer
        end
        local key=#vertices..':'..#indices;local arrays=buffer.sizes[key]
        if not arrays then
            local function array(kind,count) return CS.System.Array.CreateInstance(typeof(kind),count) end
            arrays={positions=array(CS.UnityEngine.Vector3,#vertices),uvs=array(CS.UnityEngine.Vector4,#vertices),
                colors=array(CS.UnityEngine.Color32,#vertices),indices=array(CS.System.Int32,#indices)}
            buffer.sizes[key]=arrays
        end
        local x0,y0=tile.source_rect[1],tile.source_rect[2]
        for i,v in ipairs(vertices) do
            local uq=(v[3]*texture.width-x0*v[5])/tile.width
            local vq=(v[4]*texture.height-y0*v[5])/tile.height
            local base=buffer.base
            arrays.positions[i-1]=CS.UnityEngine.Vector3((v[1]-sw/2)*1.5/unit,(v[2]-360)*1.5/unit,0)
            arrays.uvs[i-1]=CS.UnityEngine.Vector4(base[1]*v[5]+(base[3]-base[1])*uq,
                base[2]*v[5]+(base[4]-base[2])*(v[5]-vq),0,v[5])
            arrays.colors[i-1]=rgba
        end
        for i,index in ipairs(indices) do arrays.indices[i-1]=index end
        mesh:Clear();mesh.vertices=arrays.positions;mesh.triangles=arrays.indices
        mesh:SetUVs(0,arrays.uvs);mesh.colors32=arrays.colors;mesh:RecalculateBounds()
    end
end
function UnityBridge.LegacyGridUV(obj,points,rect,weights)
    local hq,tq
    if weights then hq,tq=weights[1],weights[2] else hq,tq=UnityBridge.GridWeights(points) end
    local surfaces=renderer(obj)
    surfaces.uvBuffers=surfaces.uvBuffers or {}
    for i=0,surfaces.meshes.Length-1 do
        local mesh=surfaces.meshes[i].sharedMesh
        local buffer=surfaces.uvBuffers[i]
        if not buffer then
            buffer={list=CS.System.Collections.Generic.List(CS.UnityEngine.Vector4)(),
                array=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector4),16),
                triangles=CS.System.Array.CreateInstance(typeof(CS.System.Int32),6)}
            -- Legacy ShapeSprite submits head-L, head-R, tail-L, tail-R as
            -- GL_TRIANGLE_STRIP. Native Grid's default diagonal is opposite.
            for j,index in ipairs({0,3,12,12,3,15}) do buffer.triangles[j-1]=index end
            surfaces.uvBuffers[i]=buffer
        end
        local list,uvs=buffer.list,buffer.array
        mesh:GetUVs(0,list)
        assert(list.Count==16,'Ma Skin Bridge: unexpected native Grid topology')
        local lo,hi=list[0],list[15]
        local u0,u1=lo.w~=0 and lo.x/lo.w or 0,hi.w~=0 and hi.x/hi.w or 1
        local v0,v1=lo.w~=0 and lo.y/lo.w or 0,hi.w~=0 and hi.y/hi.w or 1
        -- The strip topology below references only these four corners.
        -- The other twelve UVs never reach a triangle/rasterized fragment.
        for _,index in ipairs({0,3,12,15}) do
            local v=list[index];local q=index<8 and hq or tq
            if rect then
                local u=index%4<2 and rect[1] or rect[3]
                local y=index<8 and 1-rect[4] or 1-rect[2]
                uvs[index]=CS.UnityEngine.Vector4((u0+(u1-u0)*u)*q,(v0+(v1-v0)*y)*q,0,q)
            else
                local ratio=v.w~=0 and q/v.w or 0
                uvs[index]=CS.UnityEngine.Vector4(v.x*ratio,v.y*ratio,v.z*ratio,q)
            end
        end
        mesh:SetUVs(0,uvs)
        mesh.triangles=buffer.triangles
    end
end
function UnityBridge.OwnedGridQuad(obj,points,screenWidth,factor,rect,weights)
    if not ownedNoteVisuals[obj] or rect or weights then return false end
    local state=ownedGridMeshes[obj]
    if not state then
        -- SetVertex rebuilds the native 4x4 sliced grid and UVs on EACH
        -- call. These exclusive, unsliced bodies draw only four corners.
        -- Obtain the actual importer UV rectangle once at unit q, retaining
        -- the existing topology, material, colors and renderer order.
        obj:SetVertex(0,0,0);obj:SetVertex(1,1,0)
        obj:SetVertex(2,0,1);obj:SetVertex(3,1,1)
        local surface=renderer(obj)
        assert(surface.meshes.Length==1,'Ma Skin Bridge: unexpected owned Grid surfaces')
        local mesh=surface.meshes[0].sharedMesh
        if PROFILE.native_dynamic_mesh_candidate then mesh:MarkDynamic() end
        local list=CS.System.Collections.Generic.List(CS.UnityEngine.Vector4)()
        mesh:GetUVs(0,list)
        assert(list.Count==16,'Ma Skin Bridge: unexpected owned Grid topology')
        local lo,hi=list[0],list[15]
        assert(lo.w==1 and hi.w==1,'Ma Skin Bridge: native unit Grid UV weights differ')
        state={mesh=mesh,u0=lo.x,v0=lo.y,u1=hi.x,v1=hi.y,
            vertices=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector3),16),
            uvs=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector4),16)}
        if automaticPackedMeshes or PROFILE.native_packed_mesh_candidate then initializeGridBytes(state) end
        for index=0,15 do
            state.vertices[index]=CS.UnityEngine.Vector3(0,0,0)
            state.uvs[index]=CS.UnityEngine.Vector4(0,0,0,1)
        end
        local triangles=CS.System.Array.CreateInstance(typeof(CS.System.Int32),6)
        for i,index in ipairs({0,3,12,12,3,15}) do triangles[i-1]=index end
        mesh.triangles=triangles;ownedGridMeshes[obj]=state
    end
    local f=UnityBridge.Float
    local unit=f(UnityBridge.FrameGLSize or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize)
    if nativeMath then
        if PROFILE.native_vertex_upload_candidate then
            state.native_grid=state.native_grid or UnityBridge.BindPublicGrid(state.mesh,state.vertices,state.uvs)
            nativeMath.quad_upload(state.native_grid,points[1][1],points[1][2],points[2][1],points[2][2],
                points[3][1],points[3][2],points[4][1],points[4][2],screenWidth,factor,unit,
                state.u0,state.v0,state.u1,state.v1)
            return true
        end
        local vertexBytes,uvBytes=nativeMath.quad_buffers(points[1][1],points[1][2],points[2][1],points[2][2],
            points[3][1],points[3][2],points[4][1],points[4][2],screenWidth,factor,unit,
            state.u0,state.v0,state.u1,state.v1)
        local vertices=meshUploadScope and sharedMeshUpload.vertices or state.vertices
        local uvs=meshUploadScope and sharedMeshUpload.uvs or state.uvs
        local nativeUpload=PROFILE.native_vertex_upload_candidate
        if nativeUpload then
            state.native_upload=state.native_upload or UnityBridge.BindPublicVertices(state.mesh,state.vertices)
            UnityBridge.UploadPublicVertices(state.native_upload,vertexBytes)
        else UnityBridge.CopyMeshBytes(vertices,vertexBytes,12) end
        UnityBridge.CopyMeshBytes(uvs,uvBytes,16)
        if not nativeUpload then state.mesh.vertices=vertices end
        state.mesh:SetUVs(0,uvs)
        if not nativeUpload then state.mesh:RecalculateBounds() end
        return true
    end
    local hq,tq=UnityBridge.GridWeights(points)
    for i,index in ipairs({0,3,12,15}) do
        local p=points[i];local q=i<=2 and hq or tq
        -- Match SetVertex's managed float argument followed by float / GL.
        local x,y=f(f((p[1]-screenWidth/2)*factor)/unit),f(f((p[2]-360)*factor)/unit)
        local u,v=(i%2==1 and state.u0 or state.u1)*q,(i<=2 and state.v0 or state.v1)*q
        if automaticPackedMeshes or PROFILE.native_packed_mesh_candidate then
            state.vertexBytes[index+1]=string.pack('<fff',x,y,0)
            state.uvBytes[index+1]=string.pack('<ffff',u,v,0,q)
        else
            state.vertices[index]=CS.UnityEngine.Vector3(x,y,0)
            state.uvs[index]=CS.UnityEngine.Vector4(u,v,0,q)
        end
    end
    local vertices,uvs=state.vertices,state.uvs
    if automaticPackedMeshes or PROFILE.native_packed_mesh_candidate then
        if meshUploadScope then vertices,uvs=sharedMeshUpload.vertices,sharedMeshUpload.uvs end
        UnityBridge.CopyMeshBytes(vertices,table.concat(state.vertexBytes),12)
        UnityBridge.CopyMeshBytes(uvs,table.concat(state.uvBytes),16)
        submissions.packed_grid_uploads=(submissions.packed_grid_uploads or 0)+1
    end
    state.mesh.vertices=vertices
    state.mesh:SetUVs(0,uvs)
    state.mesh:RecalculateBounds()
    return true
end
function UnityBridge.RectangleBody(obj,points,screenWidth,factor,cropped)
    submissions.rectangle_calls=submissions.rectangle_calls+1
    local previous=rectangleBodies[obj]
    local rectangle=PROFILE.native_lifetime_candidate and not cropped and
        points[1][1]==points[3][1] and points[2][1]==points[4][1] and
        points[1][2]==points[2][2] and points[3][2]==points[4][2]
    if not rectangle then
        if previous then
            previous.transform.localPosition=CS.UnityEngine.Vector3(0,0,previous.z)
            previous.transform.localScale=CS.UnityEngine.Vector3(1,1,1)
            rectangleBodies[obj]=nil
        end
        return false
    end
    local unit=UnityBridge.FrameGLSize or CS.Malody.Scene.Play.Skin.SkinRuntime.GLSize
    if not previous or previous.unit~=unit then
        submissions.rectangle_builds=submissions.rectangle_builds+1
        local transform=obj.transform
        previous={transform=transform,z=transform.localPosition.z,unit=unit}
        -- Build a real native Grid once. Its four referenced corners form a
        -- unit rectangle with constant q=1 UVs; later frames only transform it.
        local state=ownedGridMeshes[obj]
        if state and state.independent_copy then
            -- A cloned Grid's private native buffers are intentionally unused.
            -- Keep SetVertex's float argument/division and its referenced
            -- corner/UV topology, using the independent public Mesh only.
            local f=UnityBridge.Float
            for i,index in ipairs({0,3,12,15}) do
                local x=i%2==1 and -.5 or .5;local y=i<=2 and -.5 or .5
                state.vertices[index]=CS.UnityEngine.Vector3(f(f(x)/unit),f(f(y)/unit),0)
                state.uvs[index]=CS.UnityEngine.Vector4(i%2==1 and state.u0 or state.u1,i<=2 and state.v0 or state.v1,0,1)
            end
            state.mesh.vertices=state.vertices;state.mesh:SetUVs(0,state.uvs);state.mesh:RecalculateBounds()
        else
            obj:SetVertex(0,-.5,-.5);obj:SetVertex(1,.5,-.5)
            obj:SetVertex(2,-.5,.5);obj:SetVertex(3,.5,.5)
            UnityBridge.LegacyGridUV(obj,{{0,0},{1,0},{0,1},{1,1}},nil,{1,1})
        end
        rectangleBodies[obj]=previous
    end
    local x=((points[1][1]+points[2][1])/2-screenWidth/2)*factor/unit
    local y=((points[1][2]+points[3][2])/2-360)*factor/unit
    local w=(points[2][1]-points[1][1])*factor
    local h=(points[3][2]-points[1][2])*factor
    if previous.x~=x or previous.y~=y then
        previous.transform.localPosition=CS.UnityEngine.Vector3(x,y,previous.z);previous.x=x;previous.y=y
    end
    if previous.w~=w or previous.h~=h then
        previous.transform.localScale=CS.UnityEngine.Vector3(w,h,1);previous.w=w;previous.h=h
    end
    return true
end
function UnityBridge.Fill(obj,value,reverse)
    local r=renderer(obj)
    assert(r.graphics.Length==1,'Ma Skin Bridge: expected one HP image surface')
    local image=r.graphics[0]
    image.type=CS.UnityEngine.UI.Image.Type.Filled
    image.fillMethod=CS.UnityEngine.UI.Image.FillMethod.Horizontal
    image.fillOrigin=reverse and 1 or 0
    image.fillAmount=value
end
function UnityBridge.FixedImage(obj,texture)
    -- Cocos Sprite::setRectFixed insets the *trimmed frame* by half a texel.
    -- A child RawImage preserves that UV rectangle independently of the canvas
    -- padding, parent size animation, pivot, rotation and runtime atlas packing.
    local r=renderer(obj)
    assert(r.graphics.Length==1 and r.sprites.Length==0 and r.meshes.Length==0,
        'Ma Skin Bridge: fixed UV requires one UI image')
    local graphic=r.graphics[0]
    -- xLua expands a params Type[] constructor from individual Type arguments.
    local child=CS.UnityEngine.GameObject('MaSkinBridgeFixedUV',typeof(CS.UnityEngine.RectTransform))
    child.layer=obj.gameObject.layer
    local raw=child:AddComponent(typeof(CS.UnityEngine.UI.RawImage))
    local rt=raw.rectTransform;rt:SetParent(graphic.rectTransform,false)
    local left,top,w,h=table.unpack(texture.trim)
    local ow,oh=texture.width,texture.height
    rt.anchorMin=CS.UnityEngine.Vector2(left/ow,1-(top+h)/oh)
    rt.anchorMax=CS.UnityEngine.Vector2((left+w)/ow,1-top/oh)
    rt.offsetMin=CS.UnityEngine.Vector2(0,0);rt.offsetMax=CS.UnityEngine.Vector2(0,0)
    local sprite=graphic.sprite;local rect=sprite.rect
    raw.texture=sprite.texture;raw.material=graphic.material;raw.color=graphic.color;raw.raycastTarget=false
    local tw,th=sprite.texture.width,sprite.texture.height
    raw.uvRect=CS.UnityEngine.Rect((rect.x+(left+.5)*rect.width/ow)/tw,
        (rect.y+(oh-top-h+.5)*rect.height/oh)/th,
        (w-1)*rect.width/ow/tw,(h-1)*rect.height/oh/th)
    graphic.enabled=false
    r.graphics={Length=1,[0]=raw}
end
function UnityBridge.TouchPolygon(obj,points,index)
    local area=touchAreas[obj]
    if not area then
        local existing=components(obj,typeof(CS.Malody.Play.TouchAreaBase))
        for i=0,existing.Length-1 do existing[i].enabled=false end
        area=obj.gameObject:AddComponent(typeof(CS.Malody.Play.TouchAreaPolygon))
        area.KeyIndex=index-1;area.allowSlide=true;area.penetrate=false
        touchAreas[obj]=area
    end
    local vertices=CS.System.Array.CreateInstance(typeof(CS.UnityEngine.Vector2),#points)
    local unit=CS.Malody.Scene.Play.Skin.SkinRuntime.UnitSize
    for i,p in ipairs(points) do vertices[i-1]=CS.UnityEngine.Vector2(p[1]*unit,p[2]*unit) end
    area.vertices=vertices
end
