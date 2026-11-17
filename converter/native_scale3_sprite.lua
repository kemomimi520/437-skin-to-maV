-- Original Scale3Sprite's three quads in one static Unity mesh.
-- This geometry primitive is not a note driver. The caller owns admission,
-- native-parent selection, head/tail policy and disposal. Public export still
-- blocks Scale3 until those separate contracts have been verified.
-- No texture copies, generated per-duration images, Lua draw loop or clock.
-- One mesh keeps all three quads contiguous in the native sorting order;
-- separate SpriteRenderers could interleave with another note's segments.
local function scale3float(value)
    -- string.unpack also returns the next byte offset. This numeric helper
    -- must return ONE value when used at the end of an argument/table list.
    -- Veltkamp 29-bit split rounds normal float64 values to binary32 without
    -- allocating a temporary pack string on every per-frame geometry call.
    if value==0 or value~=value then return value end
    local abs=value<0 and -value or value
    if abs<1e-37 or abs>1e35 then
        local number=string.unpack('f',string.pack('f',value))
        return number
    end
    local p=value*536870913.0
    return p-(p-value)
end
local function scale3Parts(width,height,contentHeight,part)
    local f=scale3float
    assert(width>0 and height>0 and contentHeight==contentHeight and math.abs(contentHeight)<math.huge,
        'Scale3 requires a positive source rectangle and finite content height')
    local first,last=0,1
    if part then first,last=f(part[1]),f(part[2]) end
    if math.abs(first)<2^-23 and math.abs(last)<2^-23 then first,last=f(width/3),f(f(width+width)/3) end
    assert(first>=0 and first<last and last<=height,'Unverified Scale3 source interval')
    local bottom,centre=f(height-last),f(last-first)
    local scale=f(f(f(contentHeight-first)-bottom)/centre)
    return {
        {rect={0,0,width,first},x=0,y=f(f(centre*scale)+bottom),sy=1},
        {rect={0,last,width,bottom},x=0,y=0,sy=1},
        {rect={0,first,width,centre},x=0,y=bottom,sy=scale},
    }
end

local function newNativeScale3(source,reference,parent,part,cache)
    local U=CS.UnityEngine
    assert(cache,'The native owner must supply an explicitly disposable material cache')
    local sourceRect=source.textureRect
    local width,height=sourceRect.width,sourceRect.height
    local parts=scale3Parts(width,height,height,part)
    local object=U.GameObject('legacy-scale3')
    object.layer=reference.gameObject.layer
    object.transform:SetParent(parent,false)
    local r=object:AddComponent(typeof(U.MeshRenderer))
    local filter=object:AddComponent(typeof(U.MeshFilter))
    local mesh=U.Mesh()
    filter.sharedMesh=mesh
    local materialKey=source.texture:GetInstanceID()..':'..reference.sharedMaterial:GetInstanceID()
    if not cache[materialKey] then
        cache[materialKey]=U.Material(reference.sharedMaterial)
        -- The installed IL2CPP build retains the getter only for mainTexture.
        cache[materialKey]:SetTexture('_MainTex',source.texture)
    end
    r.sharedMaterial=cache[materialKey]
    r.sortingLayerID=reference.sortingLayerID
    r.sortingOrder=reference.sortingOrder
    local count=0
    for i,p in ipairs(parts) do
        if p.rect[4]>0 then count=count+1 end
    end
    local function array(t,n)return CS.System.Array.CreateInstance(typeof(t),n)end
    local vertices=array(U.Vector3,count*4)
    local uv=array(U.Vector2,count*4)
    local colors=array(U.Color32,count*4)
    local indices=array(CS.System.Int32,count*6)
    local state={object=object,mesh=mesh,renderer=r,width=width,height=height,part=part,updates=0}
    local index=0
    local color=reference.color
    -- Set topology and source UVs only once. Rect Y is converted from Cocos
    -- top-down to the actual imported texture's bottom-up pixel coordinates.
    for _,p in ipairs(parts) do
        if p.rect[4]>0 then
            local left=(sourceRect.x+p.rect[1])/source.texture.width
            local right=(sourceRect.x+p.rect[1]+p.rect[3])/source.texture.width
            local top=(sourceRect.y+height-p.rect[2])/source.texture.height
            local bottom=(sourceRect.y+height-p.rect[2]-p.rect[4])/source.texture.height
            for j,v in ipairs({{left,bottom},{right,bottom},{left,top},{right,top}}) do
                uv[index*4+j-1]=U.Vector2(v[1],v[2])
                colors[index*4+j-1]=U.Color32(math.floor(color.r*255+.5),math.floor(color.g*255+.5),math.floor(color.b*255+.5),math.floor(color.a*255+.5))
            end
            for j,v in ipairs({0,1,2,2,1,3}) do indices[index*6+j-1]=index*4+v end
            index=index+1
        end
    end
    function state:Resize(contentHeight,scaleX,scaleY,anchorX,anchorY)
        local plan=scale3Parts(self.width,self.height,scale3float(contentHeight),self.part)
        self.object.transform.localPosition=U.Vector3(-anchorX*self.width*scaleX,-anchorY*contentHeight*scaleY,0)
        self.object.transform.localScale=U.Vector3(scaleX,scaleY,1)
        local offset=0
        for _,p in ipairs(plan) do
            if p.rect[4]>0 then
                local top=scale3float(p.y+scale3float(p.rect[4]*p.sy))
                for j,v in ipairs({{p.x,p.y},{p.x+p.rect[3],p.y},{p.x,top},{p.x+p.rect[3],top}}) do
                    vertices[offset+j-1]=U.Vector3(v[1],v[2],0)
                end
                offset=offset+4
            end
        end
        mesh.vertices=vertices
        if self.updates==0 then mesh.uv=uv;mesh.colors32=colors;mesh.triangles=indices end
        mesh:RecalculateBounds()
        self.updates=self.updates+1
        return plan
    end
    function state:Dispose()
        assert(self.object,'Scale3 disposed twice')
        U.Object.Destroy(self.object)
        U.Object.Destroy(mesh)
        self.object=nil;self.mesh=nil
    end
    state:Resize(height,1,1,0,0)
    return state
end
local function disposeNativeScale3Cache(cache)
    for key,material in pairs(cache) do CS.UnityEngine.Object.Destroy(material);cache[key]=nil end
end
