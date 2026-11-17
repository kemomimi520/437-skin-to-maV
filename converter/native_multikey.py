"""Native Key package branches and ordinary-script visual dispatch.

This is independent of the retained Free combiner. The native Key chooser
still selects and renders native note modules. Its branch gate is a source
NoteX condition on our own modules, not a replacement chooser or judge.
The original processor selects note types before ordinary Init. New research
packages therefore keep stable native factory modules; Init only binds their
public visual parameters to the selected source modules, never the carriers
or the native chooser/caches. Render/online acceptance remains a hard gate.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

from .common import lua, skin_class, skin_info_payload

BRANCH_FIELD = 'native_multikey_branches'
FACTORY_FIELD = 'native_multikey_factories'
DEFAULTS_FIELD = 'native_multikey_defaults'
NOTE_GATE = -2147483647
CALLBACKS = ('Init', 'Update', 'OnRetry', 'OnInput', 'OnHit', 'OnVarChange', 'ReportCustomInfo')
SELECTION_ISSUE = {'severity': 'warning', 'code': 'native-multikey-selection-unverified',
    'message': '原生多键数旧 NoteX gate 已证实晚于工厂选择而失效；稳定原生工厂的源视觉绑定尚未完成原生及上传验收，不能交付。'}


def note_identity(module, platform, *, gated=False):
    """Only the emitted ordinary tap/hold pair has a shared factory meaning."""
    if platform not in ('windows','android'):raise ValueError('Invalid native multi-Key factory platform')
    lanes = [c.valint for c in module.scenes if c.source == 1 and c.flag == 0 and c.valint != NOTE_GATE]
    expected = len(lanes) + 1 + int(gated)
    if (module.usage != 1 or module.type not in (6,7) or len(lanes) != 1 or lanes[0] < 1 or
            len(module.scenes) != expected or
            sum(c.source == 6 and c.flag == 0 and c.valint == {'windows':1,'android':3}[platform]
                for c in module.scenes) != 1 or
            sum(c.source == 1 and c.flag == 0 and c.valint == NOTE_GATE for c in module.scenes) != int(gated) or
            len(module.note.images) != {7:2,6:5}[module.type]):
        raise ValueError('Native multi-Key stable factories require exactly one ordinary tap7/hold6 per lane and no extra note conditions')
    return lanes[0],module.type


def validate_branches(data):
    branches = data.get(BRANCH_FIELD)
    if not isinstance(branches, list) or not branches:
        raise ValueError('Native multi-Key branch manifest is missing')
    identities = set(); handles = set()
    for branch in branches:
        keys = branch.get('keys'); platform = branch.get('platform')
        if type(keys) is not int or not 1 <= keys <= 64 or platform not in ('windows', 'android'):
            raise ValueError('Invalid native multi-Key branch identity')
        aspect_tag = branch.get('aspect_tag', '')
        if not isinstance(aspect_tag, str):
            raise ValueError('Invalid native multi-Key aspect identity')
        identity = (keys, platform, aspect_tag)
        if identity in identities:raise ValueError('Duplicate native multi-Key branch')
        identities.add(identity)
        runtime = branch.get('data')
        if not isinstance(runtime, dict) or not isinstance(runtime.get('entries'), list) or BRANCH_FIELD in runtime:
            raise ValueError('Invalid nested native multi-Key runtime')
        names = branch.get('handles'); notes = branch.get('note_handles')
        if not isinstance(names, list) or not names or not isinstance(notes, list) or not notes:
            raise ValueError('Native multi-Key branch requires native modules')
        if any(not isinstance(name, str) or not name for name in names) or len(set(names)) != len(names):
            raise ValueError('Invalid native multi-Key handles')
        if handles.intersection(names) or not set(notes).issubset(names) or branch.get('marker') not in names:
            raise ValueError('Ambiguous native multi-Key handles')
        handles.update(names)
        if set(branch.get('alpha', {})) != set(names):raise ValueError('Missing native multi-Key appearance')
    keys = {key for key, _, _ in identities}
    platforms = {(key, platform) for key, platform, _ in identities}
    if len(keys)<2 or platforms != {(key,platform) for key in keys for platform in ('windows','android')}:
        raise ValueError('Native multi-Key manifest must retain every Key/platform branch')
    defaults=data.get(DEFAULTS_FIELD,[])
    if not isinstance(defaults,list) or len(defaults)>1:
        raise ValueError('Invalid native multi-Key default component overrides')
    if defaults:
        row=defaults[0]
        if (not isinstance(row,dict) or set(row)!={'type','definition_sha256'} or row['type']!=18 or
                not isinstance(row['definition_sha256'],str) or len(row['definition_sha256'])!=64 or
                any(c not in '0123456789abcdef' for c in row['definition_sha256'])):
            raise ValueError('Unsupported native multi-Key default component override')
        selections=[]
        for branch in branches:
            disabled=branch.get('disabled_defaults')
            if disabled not in ([],[18]):raise ValueError('Invalid native multi-Key default selection')
            absent=branch.get('absent_default_defs')
            if absent not in ([],[18]) or absent and not disabled:
                raise ValueError('Invalid native multi-Key default definition selection')
            selections.append(bool(disabled))
        if not any(selections) or all(selections):
            raise ValueError('Native multi-Key default selection must vary between branches')
    elif any('disabled_defaults' in branch or 'absent_default_defs' in branch for branch in branches):
        raise ValueError('Native multi-Key default selection has no override')
    return branches


def validate_package(skin, data):
    branches = validate_branches(data)
    if skin.meta.key.keys != 0:raise ValueError('Native multi-Key package requires wildcard metadata')
    if data.get(DEFAULTS_FIELD):
        definitions=[d for d in skin.defs if d.type==18]
        if (18 in skin.disabled or len(definitions)!=1 or
                hashlib.sha256(definitions[0].SerializeToString(deterministic=True)).hexdigest()!=data[DEFAULTS_FIELD][0]['definition_sha256']):
            raise ValueError('Native multi-Key shared musicbar definition differs')
    modules = {module.meta.desc: module for module in skin.modules}
    if len(modules) != len(skin.modules):raise ValueError('Duplicate native module handles')
    claimed = set();factories=data.get(FACTORY_FIELD)
    factory_names=set()
    if factories is not None:
        if not isinstance(factories,list) or not factories:raise ValueError('Native multi-Key stable factories missing')
        identities=set()
        for row in factories:
            name=row['handle'];platform=row['platform'];identity=(platform,row['lane'],row['type'])
            if name in factory_names or identity in identities or name not in modules:
                raise ValueError('Ambiguous native multi-Key stable factory')
            factory_names.add(name);identities.add(identity);claimed.add(name)
            if note_identity(modules[name],platform)!=(row['lane'],row['type']):
                raise ValueError('Native multi-Key stable factory identity differs')
        expected={(platform,lane,kind) for platform in ('windows','android')
                  for lane in range(1,max(b['keys'] for b in branches)+1) for kind in (6,7)}
        if identities!=expected:raise ValueError('Native multi-Key stable factory coverage differs')
    for branch in branches:
        branch_modules = []
        for name in branch['handles']:
            if name not in modules:raise ValueError('Native multi-Key module missing: '+name)
            module = modules[name]; claimed.add(name);branch_modules.append(module)
            if not any(c.source == 6 and c.flag == 0 and c.valint == {'windows':1,'android':3}[branch['platform']]
                       for c in module.scenes):raise ValueError('Native multi-Key platform condition missing')
        notes = {module.meta.desc for module in branch_modules if module.usage == 1}
        if notes != set(branch['note_handles']):raise ValueError('Native multi-Key note manifest differs')
        types = {module.type for module in branch_modules if module.usage == 1}
        if not types.intersection((1,2,7)) or not types.intersection((3,4,5,6)):
            raise ValueError('Native multi-Key branch lacks native tap/hold modules')
        for name in notes:
            if sum(c.source == 1 and c.flag == 0 and c.valint == NOTE_GATE for c in modules[name].scenes) != 1:
                raise ValueError('Native multi-Key note selection gate missing')
        if factories is not None:
            bindings=branch.get('factory_bindings',[])
            expected={(lane,kind) for lane in range(1,branch['keys']+1) for kind in (6,7)}
            actual={note_identity(modules[name],branch['platform'],gated=True) for name in notes}
            if actual!=expected or len(notes)!=len(expected):raise ValueError('Native multi-Key source tap/hold coverage differs')
            if len(bindings)!=len(notes) or {b['source'] for b in bindings}!=notes:
                raise ValueError('Native multi-Key source visual bindings differ')
            for binding in bindings:
                if binding['target'] not in factory_names or note_identity(modules[binding['target']],branch['platform'])!=note_identity(modules[binding['source']],branch['platform'],gated=True):
                    raise ValueError('Native multi-Key source visual factory differs')
    if claimed != set(modules):raise ValueError('Native multi-Key contains unclaimed modules')
    return branches


def basic_script(data):
    from .native_key import basic_script as branch_script
    branches = validate_branches(data)
    factories = []; definitions = []; implementations = {}
    for index, branch in enumerate(branches, 1):
        script = branch_script(branch['data']).decode('utf-8')
        header, body = script.split('\n', 1)
        constructor = implementations.get(body)
        if constructor is None:
            constructor = 'buildNativeBranch'+str(len(implementations)+1)
            implementations[body] = constructor
            definitions.append('local function '+constructor+'(DATA)\nlocal '+','.join(CALLBACKS)+
                '\n'+body+'\nreturn {'+','.join(name+'='+name for name in CALLBACKS)+'}\nend\n')
        factories.append('builders['+str(index)+']=function()\n'+header+'\nreturn '+constructor+'(DATA)\nend\n')
    stable_factories = FACTORY_FIELD in data
    dispatcher = r'''
local selected,active
local function findNativeModule(name)
    local module=Module:Find(name)
    if not module then return nil end
    local tp=module.GetType and module:GetType()
    if tp and tp.FullName=='Malody.Scene.Play.Skin.Module.SkinRuntimeDummy' then return nil end
    return module
end
local function selectNativeBranch()
    if selected then return selected end
    local keys=tonumber(Game:ChartInfo('Key'))
    assert(keys and keys%1==0,'Native multi-Key requires original chart Key metadata')
    for index,branch in ipairs(BRANCHES) do
        if branch.keys==keys and findNativeModule(branch.marker) then
            assert(not selected,'Ambiguous native multi-Key platform branch')
            selected=index
        end
    end
    assert(selected,'No source-defined native Key/platform entry for this chart')
    return selected
end
local function selectNativeVisuals(index)
    xlua.load_assembly('Assembly-CSharp');xlua.load_assembly('UnityEngine.CoreModule')
    local runtimes=CS.UnityEngine.Object.FindObjectsOfType(typeof(CS.Malody.Scene.Play.Skin.SkinRuntime),false)
    assert(runtimes.Length==1,'Native multi-Key requires one original skin runtime')
    local runtime=runtimes[0]
    local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public')
    local methods=runtime:GetType():GetMethods(flags)
    local getter
    for i=0,methods.Length-1 do
        local method=methods[i]
        if method.Name=='get_AllModules' and method:GetParameters().Length==0 then
            assert(not getter,'Ambiguous original visual module list');getter=method
        end
    end
    assert(getter,'Original visual module list is unavailable')
    local empty=CS.System.Array.CreateInstance(typeof(CS.System.Object),0)
    local modules=getter:Invoke(runtime,CS.System.Reflection.BindingFlags.Default,nil,empty,nil)
    local wanted={};local found={}
    for _,name in ipairs(BRANCHES[index].note_handles) do wanted[name]=true end
    -- Only our emitted impossible NoteX gate is removed. Native lane/type/
    -- beat/hold conditions, factories and all gameplay objects remain native.
    for i=0,modules.Count-1 do
        local module=modules[i];local name=module.Meta.Desc
        if wanted[name] then
            found[name]=true
            local conditions=module.Scenes
            for j=conditions.Count-1,0,-1 do
                local condition=conditions[j]
                -- Protobuf ModuleCondFlag is a C# enum userdata in xLua;
                -- comparing it with Lua's numeric zero is always false.
                if condition.Source==1 and CS.System.Convert.ToInt32(condition.Flag)==0 and condition.Valint==NOTE_GATE then
                    conditions:RemoveAt(j)
                end
            end
        end
    end
    for name in pairs(wanted) do assert(found[name],'Selected native note module missing '..name) end
    for branchIndex,branch in ipairs(BRANCHES) do
        for _,name in ipairs(branch.handles) do
            local module=findNativeModule(name)
            if module then
                if branchIndex==index then module.Alpha=branch.alpha[name]
                else module.gameObject:SetActive(false) end
            end
        end
    end
end
function Init()
    local index=selectNativeBranch()
    selectNativeVisuals(index)
    active=builders[index]()
    if active.Init then return active.Init() end
end
'''
    if stable_factories:
        begin=dispatcher.index('    local wanted={};local found={}')
        end=dispatcher.index('    for branchIndex,branch in ipairs(BRANCHES) do',begin)
        dispatcher=dispatcher[:begin]+r'''
    local byName={}
    for i=0,modules.Count-1 do
        local module=modules[i];local name=module.Meta.Desc
        assert(not byName[name],'Duplicate original visual module handle');byName[name]=module
    end
    for _,binding in ipairs(BRANCHES[index].factory_bindings) do
        local target=assert(byName[binding.target],'Stable native factory missing')
        local source=assert(byName[binding.source],'Selected source visual missing')
        assert(target.Usage==1 and source.Usage==1 and target.Type==source.Type,
            'Stable native factory and source subtype differ')
        -- The processor already cached THIS emitted Module object. Bind only
        -- its public protobuf visual parameters; keep its identity, native
        -- lane/type conditions, carriers, ObjectType and chooser untouched.
        target.Param=source.Param
        target.Note=source.Note
    end
'''+dispatcher[end:]
    if data.get(DEFAULTS_FIELD):
        marker='    local byName={}' if stable_factories else '    local wanted={};local found={}'
        index=dispatcher.index(marker)
        dispatcher=dispatcher[:index]+r'''
    -- Runtime IsEnable/GetDefModule read this same SkinFile live. Select only
    -- the source branch's musicbar data before any default widget has awoken.
    -- No Key metadata, chooser, judge, score, replay or other default changes.
    local defaults=CS.UnityEngine.Object.FindObjectsOfType(
        typeof(CS.Malody.Scene.Play.Skin.SkinRuntimeDef),true)
    for i=0,defaults.Length-1 do
        assert(CS.System.Convert.ToInt32(defaults[i].type)~=18,
            'Native musicbar default was created before branch selection')
    end
    local privateFlags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, NonPublic')
    local fields=runtime:GetType():GetFields(privateFlags);local skinField
    for i=0,fields.Length-1 do
        if fields[i].FieldType.FullName=='Malody.DB.SkinFile' then
            assert(not skinField,'Ambiguous native runtime skin data');skinField=fields[i]
        end
    end
    assert(skinField,'Native runtime skin data missing')
    local skin=assert(skinField:GetValue(runtime),'Native runtime skin data is null')
    local getMeta,isEnabled,getDefinition
    for i=0,methods.Length-1 do
        local method=methods[i];local parameters=method:GetParameters()
        if method.Name=='get_Meta' and parameters.Length==0 then
            assert(not getMeta,'Ambiguous native skin metadata getter');getMeta=method
        elseif (method.Name=='IsEnable' or method.Name=='GetDefModule') and parameters.Length==1 and
                parameters[0].ParameterType.FullName=='Malody.Composer.DefaultSkinModule' then
            if method.Name=='IsEnable' then assert(not isEnabled,'Ambiguous native default enable getter');isEnabled=method
            else assert(not getDefinition,'Ambiguous native default definition getter');getDefinition=method end
        end
    end
    assert(getMeta and isEnabled and getDefinition,'Native default data getters are unavailable')
    assert(CS.System.Object.ReferenceEquals(skin.Meta,
        getMeta:Invoke(runtime,CS.System.Reflection.BindingFlags.Default,nil,empty,nil)),
        'Native runtime skin data identity differs')
    local arg=CS.System.Array.CreateInstance(typeof(CS.System.Object),1)
    arg[0]=CS.System.Enum.ToObject(typeof(CS.Malody.Composer.DefaultSkinModule),18)
    local disabled=skin.Disabled;local defs=skin.Defs;local count=0;local position,definition
    for i=0,disabled.Count-1 do if disabled[i]==18 then count=count+1 end end
    assert(count<=1,'Duplicate native musicbar disabled entry')
    for i=0,defs.Count-1 do
        if defs[i].Type==18 then
            assert(not definition,'Duplicate native musicbar definition');position=i;definition=defs[i]
        end
    end
    local before=getDefinition:Invoke(runtime,CS.System.Reflection.BindingFlags.Default,nil,arg,nil)
    assert((not definition and not before) or
        (definition and CS.System.Object.ReferenceEquals(definition,before)),
        'Native musicbar definition identity differs')
    local wantDisabled=#BRANCHES[index].disabled_defaults>0
    local wantAbsent=#BRANCHES[index].absent_default_defs>0
    assert(count==0 or wantDisabled,'Unexpected native musicbar disabled entry')
    assert(definition or wantAbsent and count==1,'Native musicbar definition missing before branch selection')
    if wantDisabled and count==0 then disabled:Add(18) end
    if wantAbsent and definition then defs:RemoveAt(position) end
    local actualEnabled=isEnabled:Invoke(runtime,CS.System.Reflection.BindingFlags.Default,nil,arg,nil)
    assert(actualEnabled==not wantDisabled,'Native musicbar enabled state differs from selected branch')
    local actualDefinition=getDefinition:Invoke(runtime,CS.System.Reflection.BindingFlags.Default,nil,arg,nil)
    assert((wantAbsent and not actualDefinition) or
        (not wantAbsent and definition and CS.System.Object.ReferenceEquals(definition,actualDefinition)),
        'Native musicbar definition differs from selected branch')
'''+dispatcher[index:]
    for name in CALLBACKS[1:]:
        dispatcher += '\nfunction '+name+'(...) if active and active.'+name+' then return active.'+name+'(...) end end\n'
    # Store data only in the constructors. Selector metadata cannot mutate a
    # different branch's queues, animation state or source visual pool.
    metadata = [{key:copy.deepcopy(value) for key,value in branch.items() if key != 'data'} for branch in branches]
    return ('local BRANCHES='+lua(metadata)+'\nlocal NOTE_GATE='+str(NOTE_GATE)+'\nlocal builders={}\n'+
            '\n'.join(definitions)+'\n'+'\n'.join(factories)+dispatcher).encode('utf-8')


def assemble_native_branches(compiled, package, *, input_name, input_sha256):
    """Shared assembly for ordinary compiler and bounded research tools.

    Callers retain semantic acceptance checks. This function never changes
    an input report's warnings or claims native/online acceptance.
    """
    from .msz import merge_native_resources, rewrite_message, rewrite_native_ui_resources
    package = Path(package);package.mkdir()
    combined = skin_class()();branches = [];reports = [];default_rows = []
    candidates={}
    common3d = None
    for row in compiled:
        if len(row) == 4:
            keys, platform, folder, report = row
            aspect_conds, aspect_tag = (), ''
        elif len(row) == 6:
            keys, platform, aspect_conds, aspect_tag, folder, report = row
        else:
            raise ValueError('Invalid native multi-Key branch tuple')
        folder = Path(folder);entry = type(combined).FromString((folder/'info.asm').read_bytes())
        if entry.meta.free or entry.meta.mode != 0 or entry.meta.key.keys != keys:
            raise ValueError('Native branch metadata differs from its source entry')
        if any(issue['severity']=='error' for issue in report['issues']):
            raise ValueError(f'{platform} {keys}K has unmapped native source definitions')
        definitions = {d.type:d.SerializeToString(deterministic=True) for d in entry.defs}
        if len(definitions)!=len(entry.defs):raise ValueError('Duplicate native default component definitions')
        default_rows.append((definitions,set(entry.disabled)))
        if len(default_rows)==1:
            combined.meta.CopyFrom(entry.meta)
            common3d = entry.meta.key.use3_d
        if entry.meta.key.use3_d != common3d:
            raise ValueError('原生多入口使用不同 3D 轨道模式，尚未映射')
        renames = merge_native_resources(entry,folder,package)
        if len(default_rows)==1 and combined.meta.cover:
            combined.meta.cover = renames.get(combined.meta.cover, combined.meta.cover)
        elif not combined.meta.cover and entry.meta.cover:
            combined.meta.cover = renames.get(entry.meta.cover, entry.meta.cover)
        rewrite_message(entry,renames)
        prefix = f'k{keys}_{platform}_{aspect_tag}_' if aspect_tag else f'k{keys}_{platform}_'
        handle_renames = {m.meta.desc:prefix+m.meta.desc for m in entry.modules}
        if len(handle_renames) != len(entry.modules):raise ValueError('Native branch contains duplicate handles')
        rewrite_message(entry,handle_renames)
        handles = [];notes = [];alpha = {}
        for module in entry.modules:
            module.scenes.add(source=6,flag=0,valint={'windows':1,'android':3}[platform])
            if module.usage != 1:
                for op, boundary in aspect_conds:
                    module.scenes.add(source=5,flag=2 if op=='large' else 3,valdbl=boundary)
            name = module.meta.desc;handles.append(name);alpha[name] = module.param.alpha
            if module.usage == 1:
                identity=note_identity(module,platform)
                if identity[0]>keys:raise ValueError('Native source note lane exceeds entry Key count')
                candidate=type(module)();candidate.CopyFrom(module)
                candidates[(platform,*identity)]=candidate
                module.scenes.add(source=1,flag=0,valint=NOTE_GATE);notes.append(name)
            else:module.param.alpha = 0
            combined.modules.add().CopyFrom(module)
        marker = combined.modules.add(usage=99,type=5004);marker.meta.desc=prefix+'configuration'
        marker.param.alpha=0;marker.param.layer=4;marker.image.color='#FFFFFF';marker.image.width=marker.image.height=1
        marker.scenes.add(source=6,flag=0,valint={'windows':1,'android':3}[platform])
        for op, boundary in aspect_conds:
            marker.scenes.add(source=5,flag=2 if op=='large' else 3,valdbl=boundary)
        handles.append(marker.meta.desc);alpha[marker.meta.desc]=0
        runtime = {'entries':[],'configs':[]}
        if (folder/'native_ui.json').is_file():
            runtime = rewrite_native_ui_resources(json.loads((folder/'native_ui.json').read_text('utf-8')),renames)
            runtime = rewrite_native_ui_resources(runtime,handle_renames)
        runtime.setdefault('configs',[]).append({'marker':marker.meta.desc,'scale':entry.meta.key.scale,
            'judge':entry.meta.key.judge_pos,'angle':entry.meta.key.angle})
        branch = {'keys':keys,'platform':platform,'marker':marker.meta.desc,'handles':handles,
                  'note_handles':notes,'alpha':alpha,'data':runtime}
        if aspect_tag:
            branch['aspect_tag'] = aspect_tag
        branches.append(branch)
        branch_report = copy.deepcopy(report);branch_report['keys']=keys;branch_report['source_platform']=platform
        if aspect_tag:
            branch_report['aspect_tag'] = aspect_tag
        reports.append(branch_report)
    if not branches:raise ValueError('No native source branches to assemble')
    # Default modules lack scene conditions. The only mapped difference is
    # the source musicbar being absent in some branches, with one identical
    # native definition across every enabled branch. Everything else fails.
    all_types=set().union(*(set(defs)|disabled for defs,disabled in default_rows))
    definitions,disabled=default_rows[0];disabled=set(disabled)
    selected_defs=dict(definitions);default_overrides=[]
    differing=[];disabled_difference=[]
    for kind in sorted(all_types):
        values={defs.get(kind) for defs,_ in default_rows}
        states={kind in off for _,off in default_rows}
        if len(values)==1 and len(states)==1:continue
        if kind==18 and len(states)==2:
            enabled={defs.get(kind) for defs,off in default_rows if kind not in off}
            if len(enabled)==1 and None not in enabled and values.issubset(enabled|{None}):
                selected_defs[kind]=next(iter(enabled));disabled.discard(kind)
                default_overrides.append({'type':kind,'definition_sha256':hashlib.sha256(selected_defs[kind]).hexdigest()})
                for branch,(branch_defs,off) in zip(branches,default_rows):
                    branch['disabled_defaults']=[kind] if kind in off else []
                    branch['absent_default_defs']=[kind] if kind not in branch_defs else []
                continue
        if len(values)>1:differing.append(kind)
        if len(states)>1:disabled_difference.append(kind)
    if differing or disabled_difference:
        raise ValueError('原生默认组件的键数/平台定义不一致，不能静默合并：'
            f'default_types={differing}; disabled_difference={disabled_difference}')
    for kind in sorted(selected_defs):combined.defs.add().ParseFromString(selected_defs[kind])
    combined.disabled.extend(sorted(disabled))
    combined.meta.title=Path(input_name).stem;combined.meta.key.keys=0
    combined.meta.key.lock_scale=False;combined.meta.key.lock3_d=False;combined.meta.script='native_ui.lua'
    factories=[];factory_names={}
    for (platform,lane,kind),candidate in sorted(candidates.items()):
        handle=f'native-multikey-factory-{platform}-{lane}-{kind}'
        candidate.meta.desc=handle;combined.modules.add().CopyFrom(candidate)
        factories.append({'platform':platform,'lane':lane,'type':kind,'handle':handle})
        factory_names[(platform,lane,kind)]=handle
    for branch in branches:
        branch['factory_bindings']=[]
        for name in branch['note_handles']:
            source=next(m for m in combined.modules if m.meta.desc==name)
            lane,kind=note_identity(source,branch['platform'],gated=True)
            branch['factory_bindings'].append({'source':name,'target':factory_names[(branch['platform'],lane,kind)]})
    data={'entries':[],BRANCH_FIELD:branches,FACTORY_FIELD:factories}
    if default_overrides:data[DEFAULTS_FIELD]=default_overrides
    validate_package(combined,data)
    (package/'native_ui.json').write_text(json.dumps(data,ensure_ascii=False,allow_nan=False),encoding='utf-8')
    (package/'native_ui.lua').write_bytes(basic_script(data))
    binary=combined.SerializeToString(deterministic=True);(package/'info.asm').write_bytes(binary)
    (package/'info.json').write_text(json.dumps(skin_info_payload(combined.meta,0),ensure_ascii=False),encoding='utf-8')
    receipt={'input_name':input_name,'input_sha256':input_sha256,'keys':sorted({b['keys'] for b in branches}),
        'platform_keys':{p:sorted({b['keys'] for b in branches if b['platform']==p}) for p in ('windows','android')},
        'render_backend':'native_key','free':False,'custom_judge':False,'custom_note_clock':False,
        'score_eligibility_modified':False,'one_to_one_verified':False,'full_acceptance':False,
        'chart_source_read_by_skin':any(report.get('chart_source_read_by_skin',False) for report in reports),
        'private_visual_fields_used':any(report.get('private_visual_fields_used',False) for report in reports),
        'native_render_verified_for_this_package':False,'skin_upload_verified':False,
        'normal_score_submission_verified':False,'issues':[copy.deepcopy(SELECTION_ISSUE)],'entries':reports,
        'info_sha256':hashlib.sha256(binary).hexdigest()}
    (package/'conversion-report.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    return package
