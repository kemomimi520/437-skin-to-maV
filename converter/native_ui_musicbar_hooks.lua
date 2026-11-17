-- Install only for packages containing a recovered source musicbar. Keep
-- packages without this feature byte-identical to their audited template.
local function findNativeMusicbarModule(name)
    local module=Module:Find(name)
    if not module then return nil end
    local tp=module.GetType and module:GetType()
    if tp and tp.FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeDummy' then return nil end
    return module
end
local musicbarOriginalInit=Init
function Init()
    NativeUiMusicbar.items={};NativeUiMusicbar.pending={}
    musicbarOriginalInit()
    local expected,bound=false,0
    for _,entry in ipairs(DATA.entries) do
        if entry.source_musicbar then
            expected=true
            local module=findNativeMusicbarModule(entry.handle)
            if module then
                bound=bound+1
                NativeUiMusicbar.Bind(module,entry)
            end
        end
    end
    assert(not expected or bound>0,'Source musicbar module missing')
end
local musicbarOriginalHit=OnHit
function OnHit(...)
    NativeUiMusicbar.Hit(Game:HitEvent(),nativeSourceVisualContext())
    if musicbarOriginalHit then return musicbarOriginalHit(...) end
end
local musicbarOriginalRetry=OnRetry
function OnRetry(...)
    NativeUiMusicbar.Reset()
    if musicbarOriginalRetry then return musicbarOriginalRetry(...) end
end
local musicbarOriginalAppearance=OnVarChange
function OnVarChange(...)
    if musicbarOriginalAppearance then musicbarOriginalAppearance(...) end
    local pool=nativeSourceVisualContext()
    if pool then NativeUiMusicbar.Update(pool) end
end
