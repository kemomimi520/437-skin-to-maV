-- Preserve 437 standalone texture CLAMP_TO_EDGE through the original maV
-- texture loader. Its UI atlas has no equivalent boundary at a Sprite rect;
-- a low-resolution image stretched to a background otherwise samples the
-- neighbouring atlas cells over tens of screen pixels.
local NativeUiSampling={sprites={}}
function NativeUiSampling.Sprite(file)
    local U=CS.UnityEngine
    local sprite=NativeUiSampling.sprites[file]
    if not sprite then
        sprite=CS.Malody.Scene.Play.Skin.SkinRuntime.instance:GetTexture(file)
        assert(sprite,'Original native texture loader omitted source UI image')
        local texture=sprite.texture
        texture.wrapMode=U.TextureWrapMode.Clamp
        texture.filterMode=U.FilterMode.Bilinear
        NativeUiSampling.sprites[file]=sprite
    end
    return sprite
end
function NativeUiSampling.Image(module)
    local U=CS.UnityEngine
    xlua.load_assembly('UnityEngine.UI')
    local graphics={}
    local function visit(transform)
        local image=transform.gameObject:GetComponent(typeof(U.UI.Image))
        if image then graphics[#graphics+1]=image end
        for i=0,transform.childCount-1 do visit(transform:GetChild(i)) end
    end
    visit(module.transform)
    assert(#graphics==1,'Source UI sampling requires one original Image provider')
    return graphics[1]
end
function NativeUiSampling.Bind(module,entry)
    NativeUiSampling.Image(module).sprite=NativeUiSampling.Sprite(entry.source_texture)
end
