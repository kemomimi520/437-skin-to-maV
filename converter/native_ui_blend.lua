-- Destination-color blending (437 blend=2: GL_ONE_MINUS_DST_COLOR, GL_ONE)
-- mapped via MaV's shipped Live2D/Live2D PremultipliedAlpha shader.
local NativeUiBlend={}
local dstBlendMaterial
function NativeUiBlend.Material(blend)
    if blend~=2 then return nil end
    if dstBlendMaterial then return dstBlendMaterial end
    local U=CS.UnityEngine
    local shader=assert(U.Shader.Find('Live2D/Live2D PremultipliedAlpha'),
        'Ma Skin Bridge: Live2D/Live2D PremultipliedAlpha shader missing')
    local material=U.Material(shader)
    material:SetFloat('_SrcColor',4)
    material:SetFloat('_DstColor',1)
    material:SetFloat('_SrcAlpha',8)
    material:SetFloat('_DstAlpha',1)
    material:SetFloat('_Cull',0)
    dstBlendMaterial=material
    return material
end
function NativeUiBlend.Bind(module,entry)
    local blend=entry.source_blend
    if blend~=2 then return end
    local material=NativeUiBlend.Material(blend)
    local U=CS.UnityEngine
    if xlua and xlua.load_assembly then pcall(xlua.load_assembly,'UnityEngine.UI') end
    local kinds={U.UI.Image,U.UI.RawImage}
    local function visit(transform)
        for _,kind in ipairs(kinds) do
            local graphic=transform.gameObject:GetComponent(typeof(kind))
            if graphic then graphic.material=material end
        end
        for i=0,transform.childCount-1 do visit(transform:GetChild(i)) end
    end
    visit(module.transform)
end
