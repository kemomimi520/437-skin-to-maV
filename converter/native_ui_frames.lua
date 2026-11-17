-- GenericElementFactory type=3 starts StateAnimator bank zero and forces it
-- to repeat forever. Its clock accumulates float(dt*1000) into a double;
-- changing frames retains the factory's scale rather than its pixel size.
-- This adapts one ordinary Image; gameplay and its native carrier are separate.
local NativeUiFrames={items={}}
local function frameFloat(value) return string.unpack('f',string.pack('f',value)) end
local function selectFrame(item,index)
    local before=item.config.frames[item.index]
    local after=item.config.frames[index]
    item.module.Width=item.module.Width*after.width/before.width
    item.module.Height=item.module.Height*after.height/before.height
    item.image.sprite=NativeUiSampling.Sprite(after.file)
    item.index=index
end
function NativeUiFrames.Bind(module,entry)
    local config=entry.source_frames
    assert(config.interval>0 and #config.frames>0,'Invalid original StateAnimator bank')
    local item={module=module,config=config,image=NativeUiSampling.Image(module),
        elapsed=0,index=1,width=module.Width,height=module.Height}
    item.image.sprite=NativeUiSampling.Sprite(config.frames[1].file)
    entry.frame_state=item
    NativeUiFrames.items[#NativeUiFrames.items+1]=item
end
function NativeUiFrames.Ratio(item,axis)
    if not item then return 1 end
    if item.reference then return item.drawn[axis]/item.reference[axis] end
    return item.config.frames[item.index][axis]/item.config.frames[1][axis]
end
function NativeUiFrames.Reset()
    NativeUiFrames.last_frame=nil
    for _,item in ipairs(NativeUiFrames.items) do
        item.elapsed=0;item.index=1
        item.module.Width=item.width;item.module.Height=item.height
        item.image.sprite=NativeUiSampling.Sprite(item.config.frames[1].file)
    end
end
function NativeUiFrames.Advance(dt)
    local delta=frameFloat(frameFloat(dt)*1000)
    for _,item in ipairs(NativeUiFrames.items) do
        if item.config.enabled~=false then
            item.elapsed=item.elapsed+delta
            local index=math.floor(item.elapsed/item.config.interval)%#item.config.frames+1
            if item.index~=index then selectFrame(item,index) end
        end
    end
end
function NativeUiFrames.Update()
    local time=CS.UnityEngine.Time
    if NativeUiFrames.last_frame==time.frameCount then return end
    NativeUiFrames.last_frame=time.frameCount
    NativeUiFrames.Advance(time.deltaTime)
end
