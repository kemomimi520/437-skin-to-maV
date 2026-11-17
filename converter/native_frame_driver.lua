-- Research-only scheduling through ORIGINAL NotifyVarChanged/OnVarChange.
-- No Lua delegate is registered on an external C# event. A closed native
-- delegate targets the existing SkinScriptRuntime itself; its OnDestroy
-- clears its OWN Lua actions before disposing the environment.
local nativeFrameDriver
local function initNativeFrameDriver(data)
    local U=CS.UnityEngine
    if nativeFrameDriver then
        local old=nativeFrameDriver
        if U.Object.op_Implicit(old.layer) then old.layer.onAfterUpdate:RemoveListener(old.callback) end
        nativeFrameDriver=nil
    end
    NATIVE_FRAME_DRIVER=nil
    if not data.native_frame_driver then return end
    assert(data.admission_policy,'Native frame driver requires ordinary Key admission')
    xlua.load_assembly('Assembly-CSharp');xlua.load_assembly('UnityEngine.CoreModule')
    local runtimes=U.Object.FindObjectsOfType(typeof(CS.Malody.Scene.Play.Skin.SkinScriptRuntime),true)
    local layers=U.Object.FindObjectsOfType(typeof(CS.Malody.Play.NoteLayer),false)
    local runtime
    for i=0,runtimes.Length-1 do
        if runtimes[i].gameObject.activeInHierarchy then
            assert(not runtime,'Ambiguous active original script runtime');runtime=runtimes[i]
        end
    end
    assert(runtime and layers.Length==1,'Native frame driver requires one runtime and Key layer')
    local layer=layers[0]
    local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic, DeclaredOnly')
    local methods=runtime:GetType():GetMethods(flags)
    local method
    for i=0,methods.Length-1 do
        local m=methods[i]
        if m.Name=='NotifyVarChanged' and m.ReturnType.FullName=='System.Void' and m:GetParameters().Length==0 then
            assert(not method,'Ambiguous original ordinary-script notification');method=m
        end
    end
    assert(method and layer.onAfterUpdate,'Original native script notification missing')
    local callback=CS.System.Delegate.CreateDelegate(typeof(U.Events.UnityAction),runtime,method)
    assert(callback and callback.Target:Equals(runtime) and callback.Method.Name=='NotifyVarChanged' and
        callback.Method.DeclaringType.FullName=='Malody.Scene.Play.Skin.SkinScriptRuntime',
        'Frame callback must target original C# runtime, never a Lua delegate bridge')
    nativeFrameDriver={runtime=runtime,layer=layer,callback=callback}
    layer.onAfterUpdate:AddListener(callback)
    -- Keep the runtime enabled and leave its scheduler intact. The original
    -- notification invokes its OWN OnVarChange action (+78 in this build),
    -- which OnDestroy clears. No external Lua action survives disposal.
    NATIVE_FRAME_DRIVER={calls=0,last_unity_frame=-1,native_target=1,
        hits=0,inputs=0,note_type_1=0,note_type_2=0,note_type_3=0,note_type_4=0,
        hit_bank_calls=0,hit_bank_found=0,hit_bank_play=0,
        runtime_id=runtime:GetInstanceID(),phase_scope='original-layer-onAfterUpdate'}
end
local function beginNativeFrame()
    if not nativeFrameDriver then return end
    NATIVE_FRAME_DRIVER.calls=NATIVE_FRAME_DRIVER.calls+1
    NATIVE_FRAME_DRIVER.last_unity_frame=CS.UnityEngine.Time.frameCount
end
