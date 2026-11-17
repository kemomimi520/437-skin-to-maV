-- Pure factory geometry recovered from 437 0x4f1c90.  The independent head
-- and tail remain in NativeSourcePart3Mesh; only the body's three quads are
-- generated here. No native renderer is borrowed for two different roles.
local NativeSourceFactory={}
local function bounds(points)
    local left,bottom,right,top=math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(points) do
        left=math.min(left,p[1]);bottom=math.min(bottom,p[2])
        right=math.max(right,p[1]);top=math.max(top,p[2])
    end
    return left,bottom,scale3float(right-left),scale3float(top-bottom)
end
-- 437 TileSprite_Update (0x505ad0): repeat by ORIGINAL frame size, draw by
-- its trimmed rect, keep SpriteFrame offset, and crop the last rectangle.
-- size3 is a source-pixel gap (negative means overlap), not a height scale.
function NativeSourceFactory.Tile3Layout(recipe,height,left,bottom)
    local f=scale3float
    local width=recipe.tile_width
    local tw,th=recipe.body_texture_width,recipe.body_texture_height
    local cut=recipe.body_trim or {0,0,tw,th}
    local ox=f(cut[1]-f((tw-cut[3])/2))
    local oy=f(f((th-cut[4])/2)-cut[2])
    local scale=f(width/tw);local tileHeight=f(th*scale)
    local gap=f((recipe.tile_gap or 0)*scale)
    assert(width>0 and tileHeight>0 and f(tileHeight+gap)>0,
        'Tile3 has nonpositive repeat distance in the original factory')
    local vertices,crops={},{}
    local y=0;left=left or 0;bottom=bottom or 0
    while height>y do
        assert(#crops<16383,'Tile3 source exceeds supported mesh vertex count')
        local nextY=f(y+gap+tileHeight)
        local fraction=1
        if height<nextY then
            local endY=f(nextY-gap)
            fraction=f(1-f(f(endY-height)/tileHeight))
        end
        local rectHeight=f(cut[4]*fraction)
        local rectY=f(cut[2]+f(f(1-fraction)*cut[4]))
        local x=f(left+f(ox*scale));local lo=f(bottom+f(y+f(oy*scale)))
        local right=f(left+f(f(ox+cut[3])*scale))
        local hi=f(bottom+f(y+f(f(oy+rectHeight)*scale)))
        for _,p in ipairs({{x,hi},{right,hi},{x,lo},{right,lo}}) do vertices[#vertices+1]=p end
        crops[#crops+1]={(cut[1]+.5)/tw,(th-rectY-rectHeight+.5)/th,
            (cut[1]+cut[3]-.5)/tw,(th-rectY-.5)/th}
        if height<=nextY then break end
        y=nextY
    end
    return vertices,crops,{scale=scale,tile_height=tileHeight,gap=gap,height=height}
end
function NativeSourceFactory.Tile3(recipe,head,tail)
    local f=scale3float
    local x,y,w,h=bounds(head);local tx,ty,tw,th=bounds(tail)
    local cx,cy=f(x+f(w/2)),f(y+f(h/2))
    local dx,dy=f(f(tx+f(tw/2))-cx),f(f(ty+f(th/2))-cy)
    local height=f(math.sqrt(f(f(dx*dx)+f(dy*dy))))
    return NativeSourceFactory.Tile3Layout(recipe,height,f(cx-f(recipe.tile_width/2)),cy)
end
function NativeSourceFactory.Scale3Part3(recipe,head,tail)
    local f=scale3float
    local left,bottom,width=bounds(head)
    local _,tailBottom,_,tailHeight=bounds(tail)
    local height=f(f(tailBottom+tailHeight)-bottom)
    local textureWidth,textureHeight=recipe.body_texture_width,recipe.body_texture_height
    assert(width>0 and textureWidth>0,'Scale3Part3 requires a positive head/body width')
    local scale=f(width/textureWidth)
    local contentHeight=f(height/scale)
    local plan=scale3Parts(textureWidth,textureHeight,contentHeight,recipe.part)
    local vertices={}
    -- Scale3Sprite visits centre, upper cap, lower cap in that order.
    -- A contracted LN may have a negative centre extent. Preserve it;
    -- clamping the range changes the old overlapping-cap appearance.
    for _,i in ipairs({3,1,2}) do
        local p=plan[i]
        if p.rect[4]>0 then
            local lo=f(bottom+f(p.y*scale))
            local hi=f(bottom+f(f(p.y+f(p.rect[4]*p.sy))*scale))
            local right=f(left+f(textureWidth*scale))
            for _,v in ipairs({{left,hi},{right,hi},{left,lo},{right,lo}}) do
                vertices[#vertices+1]=v
            end
        end
    end
    return vertices,{left=left,bottom=bottom,width=width,height=height,
        scale=scale,content_height=contentHeight}
end
