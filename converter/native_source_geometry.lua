-- 4.3.7 Part3 geometry after the native source clock has supplied a
-- head/tail distance.  This module contains only the old visual formulas;
-- the chart carrier, judge and score remain owned by maV.
local NativeSourceGeometry={}
local function f(v)return scale3float(v)end
function NativeSourceGeometry.BodyUvWeights(points)
    -- 437 Shape_UpdateUV (0x4fe030): homogeneous UV weights are the
    -- smaller edge width divided by the larger, before camera projection.
    local function length(a,b)
        local x,y=f(a[1]-b[1]),f(a[2]-b[2])
        return f(math.sqrt(f(f(x*x)+f(y*y))))
    end
    local head,tail=length(points[1],points[2]),length(points[3],points[4])
    local hq,tq=1,1
    if head<=tail and tail>0 then hq=f(head/tail)
    elseif head>0 then tq=f(tail/head) end
    return {hq,hq,tq,tq}
end
-- Inverse the actual perspective matrix using the camera's supported forward
-- projection path. This maV build strips xLua's ScreenToWorldPoint binding,
-- and the IL2CPP reflection surface does not retain that overload either.
-- The round-trip check prevents assuming that the Camera Transform is its view
-- matrix if a future scene installs a custom camera matrix.
function NativeSourceGeometry.ScreenToWorld(camera,x,yTop,depth,width,height)
    local rect=camera.pixelRect
    local projection=camera.projectionMatrix
    assert(rect.width>0 and rect.height>0 and width>0 and height>0 and depth>0,
        'Invalid native camera unprojection context')
    assert(math.abs(projection.m30)<1e-6 and math.abs(projection.m31)<1e-6 and
        projection.m32<-.999 and math.abs(projection.m33)<1e-6,
        'Original note camera is not a verified perspective projection')
    local ndcX=((x-rect.x)/rect.width)*2-1
    local ndcY=((height-yTop-rect.y)/rect.height)*2-1
    local z=-depth;local clipW=-z
    local rhsX=ndcX*clipW-projection.m02*z-projection.m03
    local rhsY=ndcY*clipW-projection.m12*z-projection.m13
    local determinant=projection.m00*projection.m11-projection.m01*projection.m10
    assert(math.abs(determinant)>1e-9,'Singular native camera perspective projection')
    local vx=(rhsX*projection.m11-projection.m01*rhsY)/determinant
    local vy=(projection.m00*rhsY-rhsX*projection.m10)/determinant
    local U=CS.UnityEngine
    -- Unity's view matrix flips camera-local +Z to view-space -Z. Projection
    -- uses z=-depth above; TransformPoint consumes the opposite local Z.
    local world=camera.transform:TransformPoint(U.Vector3(vx,vy,depth))
    local projected=camera:WorldToScreenPoint(world)
    local projectedTopY=height-projected.y
    assert(math.abs(projected.x-x)<.02 and math.abs(projectedTopY-yTop)<.02 and
        math.abs(projected.z-depth)<.02,
        'Native camera unprojection failed its WorldToScreenPoint round trip')
    return world
end

function NativeSourceGeometry.Position(first,last,ratio)
    return f(f(f(first-last)*ratio)+last)
end

function NativeSourceGeometry.Center(x,y,width,height,anchor,rotate)
    local ax=(anchor%3)*.5
    local ay=1-math.floor(anchor/3)*.5
    local ox,oy=f((.5-ax)*width),f((.5-ay)*height)
    local r=f(-rotate*math.pi/180)
    local c,s=f(math.cos(r)),f(math.sin(r))
    return f(x+ox*c-oy*s),f(y+ox*s+oy*c)
end

function NativeSourceGeometry.BodyPoints(head,tail,headSize,tailSize,anchor,rotate,axis)
    local hx,hy=NativeSourceGeometry.Center(head[1],head[2],headSize[1],headSize[2],anchor,rotate)
    local tx,ty=NativeSourceGeometry.Center(tail[1],tail[2],tailSize[1],tailSize[2],anchor,rotate)
    local dx,dy=f(tx-hx),f(ty-hy)
    local length=math.sqrt(dx*dx+dy*dy)
    local nx,ny=0,-1
    if length>0 then nx,ny=f(dy/length),f(-dx/length) end
    local headEdge,tailEdge=headSize[1],tailSize[1]
    if axis==1 then nx,ny=-1,0
    elseif axis==2 then nx,ny=0,-1;headEdge,tailEdge=headSize[2],tailSize[2] end
    return {
        {f(hx-nx*headEdge/2),f(hy-ny*headEdge/2)},
        {f(hx+nx*headEdge/2),f(hy+ny*headEdge/2)},
        {f(tx-nx*tailEdge/2),f(ty-ny*tailEdge/2)},
        {f(tx+nx*tailEdge/2),f(ty+ny*tailEdge/2)},
    },{head={hx,hy},tail={tx,ty},normal={nx,ny},head_edge=headEdge,tail_edge=tailEdge}
end

function NativeSourceGeometry.HeadPoints(cx,cy,size,rotate)
    local halfWidth,halfHeight=f(size[1]/2),f(size[2]/2)
    local r=f(-rotate*math.pi/180)
    local c,s=f(math.cos(r)),f(math.sin(r))
    local points={{-halfWidth,halfHeight},{halfWidth,halfHeight},
        {-halfWidth,-halfHeight},{halfWidth,-halfHeight}}
    for i,p in ipairs(points) do
        local x,y=p[1],p[2]
        points[i]={f(cx+x*c-y*s),f(cy+x*s+y*c)}
    end
    return points
end

function NativeSourceGeometry.ClipW(px,py,plane)
    local scale=plane.logical_height/720
    local transform,projection=plane.matrix,plane.source_projection
    assert(#transform==16 and #projection==16,'Invalid original KeyUIS projection context')
    local vx,vy=px*scale,py*scale
    local wx=transform[1]*vx+transform[5]*vy+transform[13]
    local wy=transform[2]*vx+transform[6]*vy+transform[14]
    local wz=transform[3]*vx+transform[7]*vy+transform[15]
    local ww=transform[4]*vx+transform[8]*vy+transform[16]
    return projection[4]*wx+projection[8]*wy+projection[12]*wz+projection[16]*ww
end

function NativeSourceGeometry.TryProjectLegacyXY(px,py,plane,width,height,minW)
    local scale=plane.logical_height/720
    local transform,projection=plane.matrix,plane.source_projection
    assert(#transform==16 and #projection==16 and width>0 and height>0,
        'Invalid original KeyUIS projection context')
    local vx,vy=px*scale,py*scale
    local wx=transform[1]*vx+transform[5]*vy+transform[13]
    local wy=transform[2]*vx+transform[6]*vy+transform[14]
    local wz=transform[3]*vx+transform[7]*vy+transform[15]
    local ww=transform[4]*vx+transform[8]*vy+transform[16]
    local cw=projection[4]*wx+projection[8]*wy+projection[12]*wz+projection[16]*ww
    if cw<=(minW or 0) then return nil,nil,cw end
    local cx=projection[1]*wx+projection[5]*wy+projection[9]*wz+projection[13]*ww
    local cy=projection[2]*wx+projection[6]*wy+projection[10]*wz+projection[14]*ww
    return (cx/cw+1)*width/2,(1-cy/cw)*height/2,cw
end

function NativeSourceGeometry.ProjectLegacyXY(px,py,plane,width,height)
    local sx,sy,cw=NativeSourceGeometry.TryProjectLegacyXY(px,py,plane,width,height,0)
    assert(sx~=nil,'Original KeyUIS point lies behind its captured camera')
    return sx,sy,cw
end

function NativeSourceGeometry.TryProjectLegacy(point,plane,width,height,minW)
    local sx,sy,cw=NativeSourceGeometry.TryProjectLegacyXY(point[1],point[2],plane,width,height,minW)
    if sx==nil then return nil,cw end
    return {sx,sy},cw
end

function NativeSourceGeometry.ProjectLegacy(point,plane,width,height)
    local sx,sy,cw=NativeSourceGeometry.ProjectLegacyXY(point[1],point[2],plane,width,height)
    return {sx,sy},cw
end

function NativeSourceGeometry.ScreenToLocalMapper(camera,screenRoot,depth,width,height)
    local sw=NativeSourceGeometry.ScreenToWorld
    local p0=screenRoot:InverseTransformPoint(sw(camera,0,0,depth,width,height))
    local px=screenRoot:InverseTransformPoint(sw(camera,width,0,depth,width,height))
    local py=screenRoot:InverseTransformPoint(sw(camera,0,height,depth,width,height))
    local p0x,p0y,p0z=p0.x,p0.y,p0.z
    return {w=width,h=height,d=depth,p0x=p0x,p0y=p0y,p0z=p0z,
        ux=(px.x-p0x)/width,uy=(px.y-p0y)/width,uz=(px.z-p0z)/width,
        vx=(py.x-p0x)/height,vy=(py.y-p0y)/height,vz=(py.z-p0z)/height}
end

function NativeSourceGeometry.TryProjectMapped(point,plane,mapper,minW)
    local sx,sy,cw=NativeSourceGeometry.TryProjectLegacyXY(point[1],point[2],plane,mapper.w,mapper.h,minW)
    if sx==nil then return nil,nil,nil,cw end
    return mapper.p0x+mapper.ux*sx+mapper.vx*sy,
        mapper.p0y+mapper.uy*sx+mapper.vy*sy,
        mapper.p0z+mapper.uz*sx+mapper.vz*sy,
        cw
end

function NativeSourceGeometry.ProjectMapped(point,plane,mapper)
    local sx,sy,cw=NativeSourceGeometry.ProjectLegacyXY(point[1],point[2],plane,mapper.w,mapper.h)
    return mapper.p0x+mapper.ux*sx+mapper.vx*sy,
        mapper.p0y+mapper.uy*sx+mapper.vy*sy,
        mapper.p0z+mapper.uz*sx+mapper.vz*sy,
        cw
end

