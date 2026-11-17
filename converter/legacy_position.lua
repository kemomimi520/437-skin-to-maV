-- Original 0x50b6b0 scans decimal digits right-to-left, rounding every SSE
-- operation to float32. Parsing as a double then scaling changes roundf edges.
local LegacyPosition={}
function LegacyPosition.Expression(text,extent,scale,width)
    local f=UnityBridge.Float
    local variables
    if type(text)=='table' then
        variables=text.variables
        scale=f((PROFILE.ui_rounding_height or 720)/(text.unit or 720))
        text=text.text
    end
    local result,value,place,mode=0,0,1,0
    local variable=''
    for i=#text,1,-1 do
        local c=text:sub(i,i);local digit=string.byte(c)-48
        if c=='{' then
            value=variables and variables[variable] or value
            variable='';place=10;mode=5
        elseif mode==4 then variable=c..variable
        elseif digit>=0 and digit<=9 then value=f(f(value/10)+digit);place=place*10
        elseif c=='.' then place=1
        elseif c=='%' then mode=1
        elseif c=='x' then mode=2
        elseif c=='w' then mode=3
        elseif c=='}' then mode=4 end
        if mode~=4 and (i==1 or c=='+' or c=='-') then
            local term=f(math.floor(place/10)*value)
            if mode==1 then term=f(f(term*extent)/100)
            elseif mode==0 then term=f(term*scale)
            elseif mode==3 then term=f(f(term*(width or extent))/1280) end
            if c=='-' then term=-term end
            result=f(result+term);value=0;place=1;mode=0
        end
    end
    return result
end
function LegacyPosition.Rounded(entry,width,height)
    local scale=(PROFILE.ui_rounding_height or 720)/720
    local cached=entry._nativePosition
    if cached and cached.width==width and cached.height==height then return cached.x,cached.y end
    local extents={UnityBridge.Float(width*scale),UnityBridge.Float(height*scale)}
    local values={}
    for i,program in ipairs(entry.native_pos_program) do
        local value=0
        for _,text in ipairs(program) do
            value=UnityBridge.Float(value+LegacyPosition.Expression(text,extents[i],UnityBridge.Float(scale),extents[1]))
        end
        values[i]=(value<0 and math.ceil(value-0.5) or math.floor(value+0.5))/scale
    end
    entry._nativePosition={width=width,height=height,x=values[1],y=values[2]}
    return values[1],values[2]
end
function UnityBridge.ResolveNoteDimensions(entry,width,height)
    local cached=entry._nativeNoteDimensions
    if cached and cached.width==width and cached.height==height then
        return cached.w,cached.h,cached.ew,cached.eh,cached.enabled
    end
    local f=UnityBridge.Float;local scale=(PROFILE.ui_rounding_height or 720)/720
    local extents={f(width*scale),f(height*scale)}
    local function values(program,affine)
        local result={}
        for axis=1,2 do
            if program then
                local value=0
                for _,text in ipairs(program[axis]) do
                    value=f(value+LegacyPosition.Expression(text,extents[axis],f(scale),extents[1]))
                end
                result[axis]=value
            else result[axis]=f((affine[axis][1]*(axis==1 and width or height)+affine[axis][2])*scale) end
        end
        return result
    end
    local first=values(entry.native_size_program,entry.size)
    local last=values(entry.native_size2_program,entry.size2)
    local ew,eh=last[1],last[2]
    -- Original CreateNoteSprite 0x4f318b..0x4f31ca. This surprising width
    -- sentinel also disables HEIGHT-only size2 changes; do not replace it
    -- with an intuitive two-axis interpolation or an equality shortcut.
    local enabled=ew>0 and not (math.abs(f(ew-first[1]))<.0001 and math.abs(f(eh-first[2]))~=0)
    if not enabled then ew,eh=first[1],first[2] end
    cached={width=width,height=height,w=first[1]/scale,h=first[2]/scale,
        ew=ew/scale,eh=eh/scale,enabled=enabled};entry._nativeNoteDimensions=cached
    return cached.w,cached.h,cached.ew,cached.eh,enabled
end
