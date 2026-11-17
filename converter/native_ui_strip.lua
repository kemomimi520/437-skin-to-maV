-- One ordinary native Image is the parent of all three source strip parts.
-- Normalized child anchors preserve the original factory layout when the
-- parent moves, rotates or changes scale. No source art is pre-resampled.
local NativeUiStrip={items={}}
LegacyStrip.Float=function(value)
    local n=string.unpack('f',string.pack('f',value));return n
end
function NativeUiStrip.Bind(module,entry)
    local config=entry.source_strip
    local U=CS.UnityEngine
    local aspect
    if Game and Game.Width and Game.Height then
        local gw,gh=Game:Width(),Game:Height()
        if type(gw)=='number' and type(gh)=='number' and gh>0 then aspect=gw/gh end
    end
    if not aspect and U and U.Screen then
        local sw,sh=U.Screen.width,U.Screen.height
        if type(sw)=='number' and type(sh)=='number' and sh>0 then aspect=sw/sh end
    end
    if aspect then
        if config.size_pct_x then
            local w=config.size_pct_x*aspect+config.size_px_x
            config.size[1]=w
            if config.size_auto_h then config.size[2]=w*config.height/config.width end
        end
        if config.secondary_pct_x then
            config.secondary=config.secondary_pct_x*aspect+config.secondary_px_x
        end
    end
    local original=NativeUiSampling.Image(module)
    original.sprite=NativeUiSampling.Sprite(config.file)
    local surface={graphics={Length=1,[0]=original}}
    LegacyStrip.Prepare(module,config,{width=config.width,height=config.height},
        config.size[1],config.size[2],config.secondary,surface)
    NativeUiStrip.items[#NativeUiStrip.items+1]={original=original,graphics=surface.graphics}
end
function NativeUiStrip.Update()
    for _,item in ipairs(NativeUiStrip.items) do
        if item.original.enabled~=false then item.original.enabled=false end
        local c=item.original.color
        if (not item.has_color) or item.cr~=c.r or item.cg~=c.g or item.cb~=c.b or item.ca~=c.a then
            for i=0,item.graphics.Length-1 do
                -- Native public Alpha/SetColor setters address the provider.
                -- Scale3Sprite's overrides explicitly copy both to its children.
                item.graphics[i].color=c
            end
            item.cr=c.r;item.cg=c.g;item.cb=c.b;item.ca=c.a;item.has_color=true
        end
    end
end
