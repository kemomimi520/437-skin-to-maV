-- EventFactory truncates interval to integer milliseconds (default 10),
-- whereas SkinFile.Image.Fps is an integer.  The game's actual UIFrameImage
-- exposes a float FPS; set it before any trigger clones the prototype.
-- No replacement frame loop, clock, judgement or input provider is installed.
local NativeUiFrameRate={}
function NativeUiFrameRate.Bind(module,entry)
    local interval=entry.source_frame_interval
    assert(interval and interval>0,'Unmapped original event frame interval')
    local players={}
    local function visit(transform)
        local player=transform.gameObject:GetComponent(typeof(CS.Malody.UI.UIFrameImage))
        if player then players[#players+1]=player end
        for i=0,transform.childCount-1 do visit(transform:GetChild(i)) end
    end
    visit(module.transform)
    assert(#players==1,'Original event interval requires one native UIFrameImage')
    players[1].FPS=1000/interval
end
