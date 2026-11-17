-- Reuse the exact retained MC multiset/source-sort reader without its old
-- Free bridge globals. The generated block binds publicGetter locally.
local function sourceLegacyOrder(chart,notes,mods,getter)
    local publicGetter=getter
    local UnityBridge={}
    -- SOURCE_ORDER_BODY
    UnityBridge.LegacySourceOrder(chart,notes,mods)
end
