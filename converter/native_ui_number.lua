-- The ORIGINAL UIDynamicNumber still resolves and owns score/combo/accuracy.
-- Restore only its existing Image children's 437 NumberSprite layout.
-- No replacement values, judgement, score, replay, or Free callbacks.
local NativeUiNumber={items={},by_handle={}}
local function numberFloat(v) return string.unpack('f',string.pack('f',v)) end
local numberGlyphs={['%']=10,['.']=11,['-']=12,['+']=13,['x']=14,[':']=15}
local numberChars={[0]='0','1','2','3','4','5','6','7','8','9',[10]='%',[11]='.'}
function NativeUiNumber.Plan(config,text)
    local zero=config.glyphs['0']
    local scale=zero and numberFloat(config.height/zero.frame_height) or 1
    local advance=numberFloat((zero and zero.width or 0)*scale)
    local pen,last,rows,slots=0,advance,{},0
    for i=1,math.min(30,#text) do
        local c=text:sub(i,i);local id=tonumber(c) or numberGlyphs[c]
        -- UIDynamicNumber's native HUD formatter emits digits, '%' and '.'.
        -- These all have provider slots, including transparent placeholders
        -- for glyphs absent from a permissive old NumberSprite bank.
        if id and id<=11 then slots=slots+1 end
        local glyph=id and config.glyphs[tostring(id)]
        if glyph then
            if config.proportional then advance=numberFloat(glyph.width*scale) end
            rows[#rows+1]={glyph=id,slot=slots,left=pen,
                width=numberFloat(glyph.width*scale),height=numberFloat(glyph.height*scale)}
            pen=numberFloat(numberFloat(config.spacing*advance)+pen);last=advance
        end
    end
    local width=numberFloat(numberFloat(numberFloat(1-config.spacing)*last)+pen)
    return {width=width,height=config.height,scale=scale,rows=rows,slots=slots}
end
function NativeUiNumber.Bind(module,entry)
    xlua.load_assembly('Assembly-CSharp');xlua.load_assembly('UnityEngine.UI')
    local U=CS.UnityEngine;local number
    local function visit(transform)
        local candidate=transform.gameObject:GetComponent(typeof(CS.Malody.UI.UIDynamicNumber))
        if candidate then assert(not number,'Ambiguous original Number provider');number=candidate end
        for i=0,transform.childCount-1 do visit(transform:GetChild(i)) end
    end
    visit(module.transform)
    assert(number,'Original native Number provider missing')
    local rect=number.gameObject:GetComponent(typeof(U.RectTransform))
    assert(rect,'Original Number RectTransform missing')
    local item={module=module,handle=entry.handle,number=number,transform=number.transform,rect=rect,
        config=assert(entry.source_number,'Original Number provider config missing'),
        -- JudgeFactory type=2 writes Text from its own per-grade counter. The
        -- native provider refreshes its child pool on a later Unity pass, so
        -- inferring text from the pool can observe stale glyphs.
        managed_by_judge=entry.managed_by_judge==true,text='0'}
    NativeUiNumber.items[#NativeUiNumber.items+1]=item
    NativeUiNumber.by_handle[item.handle]=item
end
function NativeUiNumber.SetManagedText(handle,text)
    local item=NativeUiNumber.by_handle[handle]
    if item then
        local s=tostring(text)
        if item.text~=s then item.text=s;NativeUiNumber._dirty=4 end
    end
end
function NativeUiNumber.Update()
    local U=CS.UnityEngine
    local time=U.Time;local fc=time and time.frameCount
    local dirty=NativeUiNumber._dirty or 0
    if dirty>0 then NativeUiNumber._dirty=dirty-1 end
    if fc~=nil and dirty<=0 and (fc%8)~=0 then return end
    for _,item in ipairs(NativeUiNumber.items) do
        local parentTransform=item.transform or item.number.transform
        local childCount=parentTransform.childCount
        if not (item.managed_by_judge and item.pool_count==childCount and item.last_key and item.last_managed_text==item.text) then
        if item.pool_count~=childCount then
            local pool={};local spriteIds=item.sprite_ids or {};item.sprite_ids=spriteIds
            for i=0,childCount-1 do
                local go=parentTransform:GetChild(i).gameObject
                local image=go:GetComponent(typeof(U.UI.Image))
                if image then pool[#pool+1]={go=go,image=image,rect=image.rectTransform} end
            end
            item.pool=pool;item.pool_count=childCount;item.last_key=nil
        end
        local images=item.images_buf;if not images then images={};item.images_buf=images end
        local chars=item.chars_buf;if not chars then chars={};item.chars_buf=chars end
        local prevIds=item.prev_ids;if not prevIds then prevIds={};item.prev_ids=prevIds end
        local count=0
        local spriteIds=item.sprite_ids
        local activeMask=0
        local changed=item.managed_by_judge or item.last_key==nil
        for idx,slot in ipairs(item.pool) do
            local image=slot.image
            if item.managed_by_judge then
                count=count+1;images[count]=slot
            elseif image.enabled and (not slot.go or slot.go.activeSelf~=false) and image.color.a>0 then
                local sprite=image.sprite
                local id
                if sprite and sprite==slot.last_sprite then
                    id=slot.last_id
                else
                    local sname=sprite and sprite.name
                    id=sname and spriteIds[sname]
                    if id==nil and sname then
                        id=tonumber(sname:match('%-(%d+)%.png$')) or false
                        spriteIds[sname]=id
                    end
                    slot.last_sprite=sprite;slot.last_id=id
                end
                assert(id and id<=11,'Original Number selected Sprite has no glyph identity')
                count=count+1;images[count]=slot
                local ch=numberChars[id];chars[count]=ch
                if prevIds[count]~=ch then prevIds[count]=ch;changed=true end
                activeMask=activeMask+(1<<(idx-1))
            end
        end
        for i=count+1,#images do images[i]=nil;chars[i]=nil;prevIds[i]=nil end
        assert(count<=30,'Original Number text exceeds source layout bound')
        if changed or count~=item.last_count or activeMask~=item.last_mask then
            local rendered=item.managed_by_judge and item.text or table.concat(chars,'',1,count)
            local key=rendered..'|'..count..'|'..activeMask
            if item.last_key~=key then
                local plan=NativeUiNumber.Plan(item.config,rendered)
                if item.managed_by_judge then
                    assert(count>=plan.slots,'Original judge Number glyph pool incomplete')
                else
                    assert(count==plan.slots,'Original Number glyph pool incomplete')
                end
                local factor=item.config.units_per_pixel
                item.rect.sizeDelta=U.Vector2(plan.width*factor,plan.height*factor)
                local rows={};for _,row in ipairs(plan.rows) do rows[row.slot]=row end
                local zero=U.Vector2(0,0)
                for i=1,count do
                    local slot=images[i];local rect=slot.rect;local row=rows[i]
                    if not slot.anchored then
                        rect.anchorMin=zero;rect.anchorMax=zero;rect.pivot=zero
                        slot.anchored=true
                    end
                    if row then
                        if item.managed_by_judge then slot.image.enabled=true end
                        rect.anchoredPosition=U.Vector2(row.left*factor,0)
                        rect.sizeDelta=U.Vector2(row.width*factor,row.height*factor)
                    else
                        if item.managed_by_judge then slot.image.enabled=false end
                        rect.anchoredPosition=zero
                        rect.sizeDelta=zero
                    end
                end
                item.last_key=key
            end
            item.last_count=count;item.last_mask=activeMask
        end
        if item.managed_by_judge then item.last_managed_text=item.text end
        end
    end
end
