-- Candidate reconstruction of the old z-only quaternion Node transform.
-- Keep float operations separate: its nominal 270-degree diagonal is 2^-24.
local LegacyMusicbarGeometry={}
function LegacyMusicbarGeometry.Root(x,y,w,h,anchor,rotation)
    local f=UnityBridge.Float
    local angle=-rotation*math.pi/360
    local z,q=f(math.sin(angle)),f(math.cos(angle))
    local c,s=f(1-f(2*f(z*z))),f(2*f(q*z))
    local ax,ay=f((anchor%3)*.5*w),f((1-math.floor(anchor/3)*.5)*h)
    return {c,s,-s,c,f(x-f(f(c*ax)+f(-s*ay))),f(y-f(f(s*ax)+f(c*ay)))}
end
function LegacyMusicbarGeometry.Part(root,left,bottom,width,height,sourceWidth,sourceHeight)
    local f=UnityBridge.Float
    local sx,sy=f(width/sourceWidth),f(height/sourceHeight)
    return {f(root[1]*sx),f(root[2]*sx),f(root[3]*sy),f(root[4]*sy),
        f(f(f(root[1]*left)+f(root[3]*bottom))+root[5]),
        f(f(f(root[2]*left)+f(root[4]*bottom))+root[6])}
end
function LegacyMusicbarGeometry.World(matrix,width,height)
    local f=UnityBridge.Float;local result={}
    for _,v in ipairs({{0,height},{0,0},{width,height},{width,0}}) do
        local x=f(f(f(matrix[1]*v[1])+f(matrix[3]*v[2]))+matrix[5])
        local y=f(f(f(matrix[2]*v[1])+f(matrix[4]*v[2]))+matrix[6])
        result[#result+1]={x,y}
    end
    return result
end
function LegacyMusicbarGeometry.Clip(matrix,width,height,projection)
    local f=UnityBridge.Float;local p=projection.matrix;local result={}
    for _,v in ipairs(LegacyMusicbarGeometry.World(matrix,width,height)) do
        result[#result+1]={f(f(f(p[1]*v[1])+p[13])/p[16]),f(f(f(p[6]*v[2])+p[14])/p[16])}
    end
    return result
end
function LegacyMusicbarGeometry.Homogeneous(matrix,width,height,projection)
    local f=UnityBridge.Float;local p=projection.matrix;local result={}
    for _,v in ipairs(LegacyMusicbarGeometry.World(matrix,width,height)) do
        result[#result+1]={f(f(p[1]*v[1])+p[13]),f(f(p[6]*v[2])+p[14]),p[16]}
    end
    return result
end
-- A moving cursor changes its translation, not its source quad's products.
-- Retain the exact rounded corner sums instead of rebuilding its full matrix
-- and multiplying the same four source vertices on every update.
function LegacyMusicbarGeometry.MovingQuad(root,left,bottom,width,height,sourceWidth,sourceHeight,projection,homogeneous,cache,view)
    if UnityBridge.NativeMusicbarQuad then
        local p=projection.matrix
        local a,b,c,d,e,f,g,h,i,j,k,l,bytes=UnityBridge.NativeMusicbarQuad(root[1],root[2],root[3],root[4],root[5],root[6],
            left,bottom,width,height,sourceWidth,sourceHeight,p[1],p[6],p[13],p[14],p[16],homogeneous and 1 or 0,
            view and view.projectionX or 1,view and view.projectionY or 1)
        cache=cache or {};cache.points=cache.points or {{},{},{},{}}
        local points=cache.points
        points[1][1],points[1][2],points[1][3]=a,b,homogeneous and c or nil
        points[2][1],points[2][2],points[2][3]=d,e,homogeneous and f or nil
        points[3][1],points[3][2],points[3][3]=g,h,homogeneous and i or nil
        points[4][1],points[4][2],points[4][3]=j,k,homogeneous and l or nil
        points.native_vertices=view and view.camera and bytes or nil
        return points,cache
    end
    local f=UnityBridge.Float
    if not cache or cache.root~=root or cache.width~=width or cache.height~=height or
        cache.sourceWidth~=sourceWidth or cache.sourceHeight~=sourceHeight then
        local matrix=LegacyMusicbarGeometry.Part(root,0,0,width,height,sourceWidth,sourceHeight)
        cache={root=root,width=width,height=height,sourceWidth=sourceWidth,sourceHeight=sourceHeight,corners={}}
        for _,v in ipairs({{0,sourceHeight},{0,0},{sourceWidth,sourceHeight},{sourceWidth,0}}) do
            cache.corners[#cache.corners+1]={f(f(matrix[1]*v[1])+f(matrix[3]*v[2])),
                f(f(matrix[2]*v[1])+f(matrix[4]*v[2]))}
        end
    end
    if cache.bottom~=bottom then
        cache.bottom=bottom;cache.bottomX=f(root[3]*bottom);cache.bottomY=f(root[4]*bottom)
    end
    local tx=f(f(f(root[1]*left)+cache.bottomX)+root[5])
    local ty=f(f(f(root[2]*left)+cache.bottomY)+root[6])
    local p=projection.matrix
    local changedX=cache.tx~=tx or cache.px~=p[1] or cache.bx~=p[13] or cache.clipW~=p[16] or cache.homogeneous~=homogeneous
    local changedY=cache.ty~=ty or cache.py~=p[6] or cache.by~=p[14] or cache.clipW~=p[16] or cache.homogeneous~=homogeneous
    cache.points=cache.points or {{},{},{},{}}
    for i,v in ipairs(cache.corners) do
        local point=cache.points[i]
        if changedX then
            local px=f(f(p[1]*f(v[1]+tx))+p[13])
            point[1]=homogeneous and px or f(px/p[16])
        end
        if changedY then
            local py=f(f(p[6]*f(v[2]+ty))+p[14])
            point[2]=homogeneous and py or f(py/p[16])
        end
        point[3]=homogeneous and p[16] or nil
    end
    cache.tx,cache.ty,cache.px,cache.py,cache.bx,cache.by=tx,ty,p[1],p[6],p[13],p[14]
    cache.clipW,cache.homogeneous=p[16],homogeneous
    return cache.points,cache
end
