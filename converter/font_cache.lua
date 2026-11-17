-- Stateful candidate for the exact 4.3.7 x86 FontAtlas allocator. Native
-- coverage comes from the verified bank; this never rasterizes another font.
function UnityBridge.FontCodes(font,text)
    local codes={}
    for _,code in utf8.codes(text) do
        if font.utf16_code_units and code>65535 then
            local value=code-65536
            codes[#codes+1]=55296+math.floor(value/1024)
            codes[#codes+1]=56320+value%1024
        else codes[#codes+1]=code end
    end
    return codes
end
function UnityBridge.FontAllocationOrder(codes)
    local groups,order,known={}, {}, {};local capacity=8;local count=0
    local function bucket(code)
        local h=((2166136261 ~ (code & 255))*16777619) & 0xffffffff
        h=((h ~ (code >> 8))*16777619) & 0xffffffff
        return h & (capacity-1)
    end
    local function insert(code)
        local b=bucket(code)
        if not groups[b] then groups[b]={};order[#order+1]=b end
        table.insert(groups[b],1,code)
    end
    for _,code in ipairs(codes) do
        assert(code>=0 and code<=65535,'Ma Skin Bridge: font cache expects UTF-16 code units')
        if not known[code] then
            known[code]=true;count=count+1;insert(code)
            if count>capacity then
                local previous={}
                for _,b in ipairs(order) do for _,c in ipairs(groups[b]) do previous[#previous+1]=c end end
                capacity=capacity*(capacity<512 and 8 or 2);groups={};order={}
                for _,c in ipairs(previous) do insert(c) end
            end
        end
    end
    local result={}
    for _,b in ipairs(order) do for _,c in ipairs(groups[b]) do result[#result+1]=c end end
    return result
end
local fontPixelBytes={}
for alpha=0,255 do fontPixelBytes[string.char(alpha)]=string.char(255,255,255,alpha) end
local blankFontRow=string.rep(fontPixelBytes['\0'],512)
local function blankPage(font,index)
    local texture=CS.UnityEngine.Texture2D(512,512,CS.UnityEngine.TextureFormat.RGBA32,false,true)
    texture.name='runtime-native-font-'..font.pixel_size..'-'..index
    texture.filterMode=CS.UnityEngine.FilterMode.Bilinear
    texture.wrapMode=CS.UnityEngine.TextureWrapMode.Clamp
    local rows={};for row=1,512 do rows[row]=blankFontRow end
    return {file='runtime-native-font-'..font.pixel_size..'-'..index,width=512,height=512,texture=texture,rows=rows}
end
function UnityBridge.FontInflate(coverage)
    local input=CS.System.IO.MemoryStream(coverage)
    local unzip=CS.System.IO.Compression.GZipStream(input,CS.System.IO.Compression.CompressionMode.Decompress)
    local output=CS.System.IO.MemoryStream()
    unzip:CopyTo(output,81920)
    local data=output:ToArray()
    unzip:Dispose();output:Dispose();input:Dispose()
    return data
end
function UnityBridge.LoadPackedGlyph(font,code)
    if font.native_outline_file then return UnityBridge.LoadOutlineGlyph(font,code) end
    if not font._packedIndex then
        if font.packed_block_format==2 or font.packed_block_format==3 then
            font._packedIndex=UnityBridge.FontInflate(UnityBridge.ReadSkinBytes(font.packed_index_file))
            font._packedCoverage=UnityBridge.ReadSkinBytes(font.packed_coverage_file)
            if font.packed_block_format==3 then font._rasterOrigins={} end
        else
            font._packedIndex=UnityBridge.FontInflate(CS.System.Convert.FromBase64String(font.packed_index))
            font._packedCoverage=CS.System.Convert.FromBase64String(font.packed_coverage)
        end
        assert(type(font._packedIndex)=='string' and type(font._packedCoverage)=='string',
            'Ma Skin Bridge: unsupported packed-font byte-array bridge')
        assert(#font._packedIndex==65536*font.packed_record_size,'Ma Skin Bridge: invalid packed-font index')
        font.packed_index=nil;font.packed_coverage=nil
    end
    if font.packed_block_format==2 or font.packed_block_format==3 then
        local offset,length,start,count,w,h,ox,oy,advance,left,top
        if font.packed_block_format==3 then
            offset,length,start,count,w,h,ox,oy,advance,left,top=string.unpack('<I4I4I4I4I2I2i2fi2i2i2',font._packedIndex,code*font.packed_record_size+1)
        else
            offset,length,start,count,w,h,ox,oy,advance=string.unpack('<I4I4I4I4I2I2i2fi2',font._packedIndex,code*font.packed_record_size+1)
        end
        font.glyphs[code]={0,0,0,w,h,ox,oy,advance}
        assert(offset+length<=#font._packedCoverage,'Ma Skin Bridge: invalid packed font block bounds')
        if count>0 then
            if font._blockOffset~=offset then
                font._block=UnityBridge.FontInflate(font._packedCoverage:sub(offset+1,offset+length))
                font._blockOffset=offset
            end
            assert(start+count<=#font._block and count==w*h,'Ma Skin Bridge: invalid glyph block span')
            -- PrepareBitmapFont expects per-glyph GZip in the old format;
            -- block coverage is already raw and byte-identical here.
            font.coverage[code]=font._block:sub(start+1,start+count)
        elseif font.packed_block_format==3 and w>0 and h>0 then
            font._rasterOrigins[code]={left,top}
        end
        return
    end
    local offset,count,w,h,ox,oy,advance=string.unpack('<I4I4I2I2i2fi2',font._packedIndex,code*font.packed_record_size+1)
    assert(offset+count<=#font._packedCoverage,'Ma Skin Bridge: invalid packed glyph bounds')
    font.glyphs[code]={0,0,0,w,h,ox,oy,advance}
    if count>0 then font.coverage[code]=font._packedCoverage:sub(offset+1,offset+count) end
end
function UnityBridge.PrepareBitmapFont(font,text)
    if not font.runtime_cache then return font.glyphs,font.pages end
    local cache=font._cache
    if not cache then cache={glyphs={},pages={},x=0,y=0,page=0,tall=0};font._cache=cache end
    local fresh={}
    for _,code in ipairs(UnityBridge.FontCodes(font,text)) do
        if not font.glyphs[code] and font.packed_record_size then UnityBridge.LoadPackedGlyph(font,code) end
        -- Original Label records an all-zero definition for unsupported
        -- UTF-16 units, including both halves of an unsupported emoji.
        -- Keep those entries in atlas allocation order (one blank column).
        if not font.glyphs[code] and font.missing_glyphs_are_zero then font.glyphs[code]={0,0,0,0,0,0,0,0} end
        assert(font.glyphs[code],string.format('Ma Skin Bridge: font bank has no U+%04X',code))
        if not cache.glyphs[code] then fresh[#fresh+1]=code end
    end
    if font.native_outline_file then UnityBridge.PrepareOutlineCoverage(font,fresh) end
    if font.hybrid_os_fallback then UnityBridge.PrepareHybridCoverage(font,fresh) end
    local dirty={}
    for _,code in ipairs(UnityBridge.FontAllocationOrder(fresh)) do
        local source=font.glyphs[code];local w,h=source[4],source[5]
        local page,x,y=0,0,0
        if w>0 and h>0 then
            if h>cache.tall then cache.tall=math.floor(h)+3 end
            if cache.x+w>512 then
                cache.y=cache.y+cache.tall;cache.tall=0;cache.x=0
                if cache.y+font.line_height>=512 then cache.y=0;cache.page=cache.page+1 end
            end
            page=cache.page;x=cache.x;y=cache.y+1;cache.x=cache.x+w+1
            local destination=cache.pages[page]
            if not destination then destination=blankPage(font,page);cache.pages[page]=destination end
            local coverage=assert(font.coverage[code],'Ma Skin Bridge: native glyph coverage missing')
            if not font.coverage_binary then coverage=CS.System.Convert.FromBase64String(coverage) end
            if font.coverage_encoding=='gzip' and font.packed_block_format~=2 and font.packed_block_format~=3 then
                -- xLua's reflection wrapper supplies 0 for this optional C#
                -- parameter instead of Stream's 81920 default. Pass it explicitly.
                coverage=UnityBridge.FontInflate(coverage)
            end
            -- xLua marshals System.Byte[] results as binary Lua strings in
            -- the shipped player; keep the managed-array case explicit too.
            local binary=type(coverage)=='string'
            assert((binary and #coverage or coverage.Length)==w*h,'Ma Skin Bridge: corrupt native glyph coverage')
            -- Stored bytes are top-down. Native atlas V rows increase in the
            -- same direction; the output PNG orientation is handled once.
            for row=0,h-1 do
                local alpha
                if binary then alpha=coverage:sub(row*w+1,(row+1)*w)
                else
                    local bytes={}
                    for column=0,w-1 do bytes[column+1]=string.char(coverage[row*w+column]) end
                    alpha=table.concat(bytes)
                end
                local rgba=alpha:gsub('.',fontPixelBytes)
                local old=destination.rows[y+row+1]
                assert(old and x+w<=512,'Ma Skin Bridge: native font glyph exceeds atlas bounds')
                destination.rows[y+row+1]=old:sub(1,x*4)..rgba..old:sub((x+w)*4+1)
            end
            dirty[page]=true
        else cache.x=cache.x+1 end
        cache.glyphs[code]={page,x,y,w,h,source[6],source[7],source[8]}
    end
    for page in pairs(dirty) do
        local destination=cache.pages[page]
        -- One byte-array bridge per changed atlas page replaces two managed
        -- calls per glyph pixel. RGB stays white even at zero alpha; cached
        -- glyphs, margins, row direction and Apply timing stay unchanged.
        destination.texture:LoadRawTextureData(table.concat(destination.rows))
        destination.texture:Apply(false,false)
    end
    return cache.glyphs,cache.pages
end
