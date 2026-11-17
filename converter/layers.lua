-- Flatten the verified old parent traversal into distinct native renderer /
-- canvas orders. SortingGroup setters are stripped from this maV player.
-- Retain the acceptance gate: admission and retirement can still differ.
-- The opt-in pool candidate maps physical reuse onto legacy logical slots.
LegacyLayers={}
local layerRows,layerSeen={},{}
LegacyLayers.rows=layerRows
local layerSerial,layerDirty=0,false
local layerNotes={}
local deferNotes=0
local function layerRegister(identity,key,draw,noteId)
    if layerSeen[identity] then return end
    local row={identity=identity,key=key,draw=draw,note_id=noteId};layerSeen[identity]=row
    layerRows[#layerRows+1]=row;layerDirty=true
end
local function layerKey(e,serial,part)
    local k=e.scene_key
    return {k[1],k[2],k[3],k[4],serial or 0,part or 0}
end
function LegacyLayers.Flush()
    -- Owned lifetime groups never enter maV's resetting note-module pool.
    -- With an unchanged registry their renderer orders remain valid. Keep
    -- rechecking the native-carrier route, where checkout really resets Order.
    if not layerDirty and PROFILE and PROFILE.native_lifetime_candidate then return end
    assert(#layerRows<32760,'Ma Skin Bridge: legacy draw queue exceeds native sorting range')
    if layerDirty then table.sort(layerRows,function(a,b)
        if a==b then return false end
        for i=1,6 do if a.key[i]~=b.key[i] then return a.key[i]<b.key[i] end end
        error('Ma Skin Bridge: ambiguous legacy draw order '..a.identity..' / '..b.identity)
    end) end
    -- Native pool checkout / repeated OnDrawNote can reset child Order.
    -- A stable registry does not mean the native component values stayed set.
    for i,row in ipairs(layerRows) do
        if PROFILE and PROFILE.native_lifetime_candidate then
            -- These draws never enter the game's resetting checkout pool.
            -- An insertion only changes ranks after its insertion point.
            if row.order~=i then row.draw.sortingOrder=i end
        elseif row.draw.sortingOrder~=i then row.draw.sortingOrder=i end
        row.order=i
    end
    layerDirty=false
end
function LegacyLayers.BeginNotes() deferNotes=deferNotes+1 end
function LegacyLayers.EndNotes()
    assert(deferNotes>0,'Ma Skin Bridge: unmatched layer registration batch')
    deferNotes=deferNotes-1
    if deferNotes==0 then LegacyLayers.Flush() end
end
function LegacyLayers.UI(canvas,e)
    layerRegister('canvas:'..canvas:GetInstanceID(),layerKey(e),canvas)
end
function LegacyLayers.Mesh(draw,e,part)
    layerRegister('mesh:'..draw:GetInstanceID(),layerKey(e,0,part),draw)
    LegacyLayers.Flush()
end
local function layerRenderer(obj)
    return obj:GetComponent(typeof(CS.UnityEngine.SpriteRenderer)) or obj:GetComponent(typeof(CS.UnityEngine.MeshRenderer))
end
function LegacyLayers.Bar(obj,e,index)
    local draw=assert(layerRenderer(obj),'Ma Skin Bridge: bar renderer missing')
    draw.sortingLayerName='Notes'
    layerRegister('bar:'..draw:GetInstanceID(),layerKey(e,index),draw)
    LegacyLayers.Flush()
end
function LegacyLayers.BeforeCheckout(typeName)
    local ids=UnityBridge.NotePoolIdle(typeName);local selected;local minimum=math.huge
    local present={}
    for _,id in ipairs(ids) do
        local rank=assert(layerNotes[id],'Ma Skin Bridge: unknown module in native idle pool')
        present[id]=true
        if rank<minimum then minimum=rank;selected=id end
    end
    return {first=selected,present=present}
end
function LegacyLayers.AfterCheckout(mod,plan)
    if not plan.first then return end
    local id=mod:GetInstanceID()
    assert(plan.present[id],'Ma Skin Bridge: native checkout did not use observed idle list')
    if id==plan.first then return end
    local first=plan.first
    layerNotes[id],layerNotes[first]=layerNotes[first],layerNotes[id]
    -- Swap both logical labels before sorting. The native idle objects,
    -- their list, carrier bindings and judgement state remain untouched.
    for _,row in ipairs(layerRows) do
        if row.note_id==id or row.note_id==first then row.key[5]=layerNotes[row.note_id] end
    end
    layerDirty=true
end
function LegacyLayers.Note(mod,e)
    local identity=mod:GetInstanceID()
    local serial=layerNotes[identity]
    if not serial then layerSerial=layerSerial+1;serial=layerSerial;layerNotes[identity]=serial end
    local parts={}
    local body=mod:GetChild('body')
    if body then parts[#parts+1]={body,0} else
        local texture=e.states['2'] and e.states['2'][1]
        for i in ipairs(texture and texture.tiles or {}) do parts[#parts+1]={mod:GetChild('body-'..i),i/10000} end
    end
    parts[#parts+1]={mod:GetChild('head'),1};parts[#parts+1]={mod:GetChild('tail'),2}
    for _,part in ipairs(parts) do if part[1] then
        local draw=assert(layerRenderer(part[1]),'Ma Skin Bridge: note renderer missing')
        draw.sortingLayerName='Notes'
        layerRegister('note:'..draw:GetInstanceID(),layerKey(e,serial,part[2]),draw,identity)
    end end
    if deferNotes==0 then LegacyLayers.Flush() end
end
