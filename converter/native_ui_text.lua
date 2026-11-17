-- Original Label glyph metrics and alpha coverage on ordinary UI children.
-- SkinRuntimeText still resolves its own live metadata; its TMP raster is
-- hidden, not substituted for source glyphs. No gameplay values are written.
local NativeUiText={items={},fonts={}}
function NativeUiText.ResolveVersion(text,config)
    local marker=config.version_marker
    if not marker then return text end
    local version=Game:ChartInfo('Version')
    assert(type(version)=='string','Original Label version is unavailable')
    local parts={};local start,count=1,0
    while true do
        local first,last=text:find(marker,start,true)
        if not first then parts[#parts+1]=text:sub(start);break end
        parts[#parts+1]=text:sub(start,first-1);parts[#parts+1]=version
        count=count+1;start=last+1
    end
    -- Do not silently replace a matching sequence supplied by a different
    -- metadata value; every marker must come from the original template.
    assert(count==config.version_count,'Original Label version marker differs from template')
    return table.concat(parts)
end
function NativeUiText.SkinAssetPath(file)
    assert(type(file)=='string' and not file:find('[/\\]') and not file:find('..',1,true),
        'Invalid original font resource filename')
    return scale3Getter(CS.Malody.Scene.Play.Skin.SkinRuntime.instance,'get_BaseDir')..'/'..file
end
function NativeUiText.ReadSkinBytes(file)
    local data=CS.System.IO.File.ReadAllBytes(NativeUiText.SkinAssetPath(file))
    assert(type(data)=='string','Unsupported original font byte bridge')
    return data
end
function NativeUiText.Plan(font,text)
    local definitions,pages=NativeUiText.PrepareBitmapFont(font,text)
    local codes=NativeUiText.FontCodes(font,text);local lines=1
    for _,code in ipairs(codes) do if code==10 then lines=lines+1 end end
    local pen,width,line,lineWidth=0,0,0,0;local glyphs={}
    for _,code in ipairs(codes) do
        local g=assert(definitions[code],'Original Label definition missing')
        if code==10 then width=math.max(width,lineWidth);lineWidth=0;pen=0;line=line+1
        elseif g[4]>0 and g[5]>0 then
            local x,top=pen+g[6],(lines-line)*font.line_height-g[7]
            glyphs[#glyphs+1]={code=code,page=g[1],x=x,top=top,width=g[4],height=g[5],u=g[2],v=g[3]}
            lineWidth=x+g[4]
        end
        if code~=10 then pen=pen+g[8] end
    end
    return glyphs,math.max(width,lineWidth),text~='' and lines*font.line_height or 0,pages
end
function NativeUiText.Bind(module,entry)
    xlua.load_assembly('Unity.TextMeshPro');xlua.load_assembly('UnityEngine.UI')
    local U=CS.UnityEngine;local provider
    local function visit(transform)
        local text=transform.gameObject:GetComponent(typeof(CS.TMPro.TMP_Text))
        if text then assert(not provider,'Ambiguous native Text provider');provider=text end
        for i=0,transform.childCount-1 do visit(transform:GetChild(i)) end
    end
    visit(module.transform);assert(provider,'Native Text provider missing')
    local config=entry.source_text;local font=config.font
    local identity=font.packed_index_file or tostring(font)
    if NativeUiText.fonts[identity] then font=NativeUiText.fonts[identity]
    else
        -- JSON platform branches turn numeric keys into strings. The old
        -- cache identifies glyphs/pages by numeric UTF-16 code units.
        for _,name in ipairs({'glyphs','coverage','pages'}) do
            local numeric={};for k,v in pairs(font[name]) do numeric[tonumber(k)]=v end;font[name]=numeric
        end
        NativeUiText.fonts[identity]=font
    end
    provider.enabled=false
    -- The native TMP prefab's fitter may run in Canvas layout AFTER the
    -- Key LateUpdate. A disabled TMP has no preferred width, so that pass
    -- collapses its rect and moves every centre/right anchored source glyph.
    -- Source Label owns its content bounds; retain the native text resolver
    -- but stop this unrelated TMP preferred-size writer on its provider.
    local fitter=provider.gameObject:GetComponent(typeof(U.UI.ContentSizeFitter))
    local fitterWasEnabled=fitter and fitter.enabled or false
    if fitter then fitter.enabled=false end
    NativeUiText.items[#NativeUiText.items+1]={module=module,provider=provider,
        rect=provider.gameObject:GetComponent(typeof(U.RectTransform)),font=font,config=config,graphics={},
        name=entry.handle,fitter_was_enabled=fitterWasEnabled,fitter_present=fitter~=nil}
end
local function glyphImage(item,index)
    if item.graphics[index] then return item.graphics[index] end
    local U=CS.UnityEngine
    local object=U.GameObject('original-label-glyph-'..index,typeof(U.RectTransform))
    object.layer=item.provider.gameObject.layer
    object.transform:SetParent(item.provider.transform,false)
    local image=object:AddComponent(typeof(U.UI.RawImage));image.raycastTarget=false
    local rect=image.rectTransform
    rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(0,0);rect.pivot=U.Vector2(0,0)
    item.graphics[index]=image
    return image
end
function NativeUiText.Update()
    local U=CS.UnityEngine
    local time=U.Time;local fc=time and time.frameCount
    for idx,item in ipairs(NativeUiText.items) do
        local skipText=false
        if fc~=nil and item._prev_fc~=nil and fc~=item._prev_fc and item.drawn and item.raw_text~='' and (item._polls or 0)>4 and ((fc+idx)%120)~=0 then
            skipText=true
        end
        local provider=item.provider
        local changedText=false
        if not skipText then
            item._polls=(item._polls or 0)+1
            local raw=provider.text or ''
            if item.raw_text~=raw or item.config.version_marker then
                item.raw_text=raw
                local text=NativeUiText.ResolveVersion(raw,item.config)
                if item.text~=text then
                    local rows,width,height,pages=NativeUiText.Plan(item.font,text)
                    item.rows=rows;item.pages=pages;item.width=width;item.height=height;item.text=text
                    changedText=true
                end
            end
        end
        local color=provider.color
        local changedColor=(not item.has_color) or item.cr~=color.r or item.cg~=color.g or item.cb~=color.b or item.ca~=color.a
        if changedText or not item.drawn then
            local factor=item.config.units_per_pixel
            item.rect.sizeDelta=U.Vector2(item.width*factor,item.height*factor)
            for index,row in ipairs(item.rows) do
                local image=glyphImage(item,index);local page=item.pages[row.page]
                image.enabled=true;image.texture=page.texture
                -- Original GL cache rows start at the glyph TOP; Unity's usual
                -- RawImage V direction is opposite. Preserve the source rows.
                image.uvRect=U.Rect(row.u/page.width,(row.v+row.height)/page.height,
                    row.width/page.width,-row.height/page.height)
                image.rectTransform.anchoredPosition=U.Vector2(row.x*factor,(row.top-row.height)*factor)
                image.rectTransform.sizeDelta=U.Vector2(row.width*factor,row.height*factor)
                image.color=color
            end
            for index=#item.rows+1,#item.graphics do item.graphics[index].enabled=false end
            item.drawn=true
            item.cr=color.r;item.cg=color.g;item.cb=color.b;item.ca=color.a;item.has_color=true
        elseif changedColor then
            for index=1,#item.rows do item.graphics[index].color=color end
            item.cr=color.r;item.cg=color.g;item.cb=color.b;item.ca=color.a;item.has_color=true
        end
        if not skipText and provider.enabled~=false then provider.enabled=false end
        if fc~=nil then item._prev_fc=fc end
    end
end
