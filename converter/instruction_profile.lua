-- Diagnostic sampling only. Never enable this in a delivered converter package:
-- count hooks perturb execution, and samples are not exclusive CPU timings.
local InstructionProfile={}
function InstructionProfile.Begin(state)
    if not PROFILE.native_instruction_profile_candidate or not state then return end
    assert(debug and debug.sethook and debug.getinfo and debug.gethook,
        'Ma Skin Bridge: instruction sampling is unavailable')
    assert(not debug.gethook(),'Ma Skin Bridge: refusing to replace an existing Lua hook')
    local stats=state.update_profile.instructions
    if not stats then
        stats={period=10000,rows={},lookup={}}
        state.update_profile.instructions=stats
    end
    local previous=CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    debug.sethook(function()
        local now=CS.UnityEngine.Time.realtimeSinceStartupAsDouble
        local info=debug.getinfo(2,'Sln')
        local key=info.source..':'..info.currentline
        local row=stats.lookup[key]
        if not row then
            row={source=info.short_src,line=info.currentline,defined=info.linedefined,
                name=info.name or '',samples=0,elapsed_ms=0}
            stats.lookup[key]=row;stats.rows[#stats.rows+1]=row
        end
        row.samples=row.samples+1;row.elapsed_ms=row.elapsed_ms+(now-previous)*1000
        previous=CS.UnityEngine.Time.realtimeSinceStartupAsDouble
    end,'',stats.period)
end
function InstructionProfile.End()
    if PROFILE.native_instruction_profile_candidate then debug.sethook() end
end
