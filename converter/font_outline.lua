-- Original layout metrics with on-demand public TextCore rasterization.
-- Raster edge coverage differs from FreeType 2.5 CFF stem darkening.
function UnityBridge.LoadOutlineGlyph(font,code)
    if not font._packedIndex then
        font._packedIndex=UnityBridge.FontInflate(UnityBridge.ReadSkinBytes(font.packed_index_file))
        assert(#font._packedIndex==65536*font.packed_record_size,'Ma Skin Bridge: invalid outline metrics index')
        font._rasterOrigins={}
    end
    local w,h,ox,oy,advance,left,top=string.unpack('<I2I2i2fi2i2i2',font._packedIndex,code*font.packed_record_size+1)
    font.glyphs[code]={0,0,0,w,h,ox,oy,advance}
    font._rasterOrigins[code]={left,top}
end
function UnityBridge.OutlineGlyphCoverage(raw,textureWidth,rect,metrics,source,origin)
    -- Public Alpha8 texture bytes increase bottom-up. The exact old cache
    -- consumes top-down rows, with one transparent pixel at each X edge.
    local w,h=source[4],source[5]
    local dx=math.floor(metrics[3]-origin[1]+.5)+1
    local dy=origin[2]-math.floor(metrics[4]+.5)
    local rows={};local blank=string.rep('\0',w)
    local first=math.max(0,-dx);local last=math.min(rect[3],w-dx)
    for row=0,h-1 do
        local nativeRow=row-dy
        if nativeRow>=0 and nativeRow<rect[4] and last>first then
            local start=((rect[2]+rect[4]-1-nativeRow)*textureWidth+rect[1]+first)+1
            rows[row+1]=string.rep('\0',dx+first)..raw:sub(start,start+last-first-1)..string.rep('\0',w-dx-last)
        else rows[row+1]=blank end
    end
    return table.concat(rows)
end
function UnityBridge.PrepareOutlineCoverage(font,codes)
    local requested={}
    for _,code in ipairs(codes) do
        local source=font.glyphs[code]
        if source[4]>0 and source[5]>0 then requested[#requested+1]=utf8.char(code) end
    end
    if #requested==0 then return end
    if not font._outlineAsset then
        xlua.load_assembly('UnityEngine.TextCoreFontEngineModule')
        xlua.load_assembly('UnityEngine.TextCoreTextEngineModule')
        local side=1024
        while side<font.pixel_size*2+8 do side=side*2 end
        assert(side<=4096,'Ma Skin Bridge: outline atlas exceeds supported size')
        font._outlineAsset=assert(CS.UnityEngine.TextCore.Text.FontAsset.CreateFontAsset(
            UnityBridge.SkinAssetPath(font.native_outline_file),0,font.pixel_size,2,
            CS.UnityEngine.TextCore.LowLevel.GlyphRenderMode.SMOOTH_HINTED,side,side),
            'Ma Skin Bridge: native outline font loading unavailable')
        font._outlineAsset.isMultiAtlasTexturesEnabled=true
    end
    local asset=font._outlineAsset
    assert(asset:TryAddCharacters(table.concat(requested),false),
        'Ma Skin Bridge: native outline rasterizer omitted an original font character')
    local lookup={}
    for i=0,asset.characterTable.Count-1 do
        local character=asset.characterTable[i];lookup[character.unicode]=character.glyph
    end
    local rawPages={}
    for _,code in ipairs(codes) do
        local source=font.glyphs[code]
        if source[4]>0 and source[5]>0 then
            local glyph=assert(lookup[code],'Ma Skin Bridge: requested outline glyph not in atlas')
            local page=glyph.atlasIndex;local texture=asset.atlasTextures[page]
            local raw=rawPages[page]
            if not raw then
                assert(texture.format==CS.UnityEngine.TextureFormat.Alpha8,'Ma Skin Bridge: outline atlas is not Alpha8')
                raw=texture:GetRawTextureData();rawPages[page]=raw
                assert(type(raw)=='string' and #raw==texture.width*texture.height,
                    'Ma Skin Bridge: outline atlas byte layout unavailable')
            end
            local r,m=glyph.glyphRect,glyph.metrics
            font.coverage[code]=UnityBridge.OutlineGlyphCoverage(raw,texture.width,
                {r.x,r.y,r.width,r.height},{m.width,m.height,m.horizontalBearingX,m.horizontalBearingY,m.horizontalAdvance},
                source,font._rasterOrigins[code])
        end
    end
end
function UnityBridge.PrepareHybridCoverage(font,codes)
    local needed={}
    for _,code in ipairs(codes) do
        local source=font.glyphs[code]
        if source and source[4]>0 and source[5]>0 and not font.coverage[code] then
            if code<0xD800 or code>0xDFFF then needed[#needed+1]=code end
        end
    end
    if #needed==0 then return end
    if not font._hybridCandidates then
        local dirs,seenDirs={},{}
        local function addDir(d)
            if type(d)=='string' and d~='' then
                local norm=d:gsub('[/\\]+$','')
                if norm~='' and not seenDirs[norm:lower()] then
                    seenDirs[norm:lower()]=true;dirs[#dirs+1]=norm
                end
            end
        end
        pcall(function() addDir(CS.System.Environment.GetFolderPath(CS.System.Environment.SpecialFolder.Fonts)) end)
        local winRoot=CS.System.Environment.GetEnvironmentVariable('SystemRoot') or CS.System.Environment.GetEnvironmentVariable('WINDIR')
        if type(winRoot)=='string' and winRoot~='' then addDir(winRoot..'\\Fonts') end
        addDir('C:\\Windows\\Fonts')
        local localApp=CS.System.Environment.GetEnvironmentVariable('LOCALAPPDATA')
        if type(localApp)=='string' and localApp~='' then addDir(localApp..'\\Microsoft\\Windows\\Fonts') end
        local names={'msyh.ttc','msyh.ttf','simhei.ttf','simsun.ttc','msgothic.ttc','meiryo.ttc','YuGothM.ttc','malgun.ttf','seguisym.ttf','segoeui.ttf','arial.ttf'}
        local paths={}
        for _,dir in ipairs(dirs) do
            for _,name in ipairs(names) do
                local candidate=dir..'\\'..name
                if CS.System.IO.File.Exists(candidate) then paths[#paths+1]=candidate end
            end
        end
        font._hybridCandidates=paths
        font._hybridAssets={}
    end
    local assets,paths=font._hybridAssets,font._hybridCandidates
    local remaining=needed
    local side=1024
    while side<font.pixel_size*2+8 do side=side*2 end
    for idx=1,#paths do
        if #remaining==0 then break end
        local asset=assets[idx]
        if asset==nil then
            xlua.load_assembly('UnityEngine.TextCoreFontEngineModule')
            xlua.load_assembly('UnityEngine.TextCoreTextEngineModule')
            local ok,created=pcall(function()
                local a=CS.UnityEngine.TextCore.Text.FontAsset.CreateFontAsset(
                    paths[idx],0,font.pixel_size,2,
                    CS.UnityEngine.TextCore.LowLevel.GlyphRenderMode.SMOOTH_HINTED,side,side)
                if a then a.isMultiAtlasTexturesEnabled=true end
                return a
            end)
            asset=(ok and created) or false
            assets[idx]=asset
        end
        if asset then
            local req={}
            for i=1,#remaining do req[i]=utf8.char(remaining[i]) end
            pcall(function() asset:TryAddCharacters(table.concat(req),false) end)
            local lookup={}
            for i=0,asset.characterTable.Count-1 do
                local ch=asset.characterTable[i];lookup[ch.unicode]=ch.glyph
            end
            local rawPages={};local nextRemaining={}
            for _,code in ipairs(remaining) do
                local glyph=lookup[code]
                if glyph then
                    local page=glyph.atlasIndex;local texture=asset.atlasTextures[page]
                    local raw=rawPages[page]
                    if not raw and texture and texture.format==CS.UnityEngine.TextureFormat.Alpha8 then
                        raw=texture:GetRawTextureData();rawPages[page]=raw
                    end
                    if type(raw)=='string' and #raw==texture.width*texture.height then
                        local r,m=glyph.glyphRect,glyph.metrics
                        font.coverage[code]=UnityBridge.OutlineGlyphCoverage(raw,texture.width,
                            {r.x,r.y,r.width,r.height},
                            {m.width,m.height,m.horizontalBearingX,m.horizontalBearingY,m.horizontalAdvance},
                            font.glyphs[code],font._rasterOrigins[code])
                    else nextRemaining[#nextRemaining+1]=code end
                else nextRemaining[#nextRemaining+1]=code end
            end
            remaining=nextRemaining
        end
    end
    for _,code in ipairs(remaining) do
        local source=font.glyphs[code]
        font.coverage[code]=string.rep('\0',source[4]*source[5])
    end
end
