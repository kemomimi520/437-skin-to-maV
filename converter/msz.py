"""MSZ in, one MSP beside it. Intermediate extraction is always temporary."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import stat
import sys
import tempfile
import zipfile

from .common import ROOT, font_bank, lua, skin_class, skin_info_payload
from .mui import parse,is_key_scene_definition
from .contracts import audit as audit_contracts
from .output_contract import require_native_key_backend, validate_native_key_package

CALLBACKS = ('CanPlay', 'OnProcessNote', 'Init', 'Update', 'OnRetry', 'OnInput',
             'OnHit', 'OnDrawNote', 'OnNoteMove', 'ReportCustomInfo')

# These have an emitted implementation but still lack full equivalence proof.
# Everything else is a conversion failure, including future unknown errors.
# In particular parser/include/directive errors must never become a partial MSP.
ACCEPTANCE_GATES = frozenset({
    'lifetime-research-only','scene-draw-order','native-key-judge',
    'chart-time-quantization','note-lifecycle','number-value-lifecycle',
    'hp-clock','touch-runtime','font-face','text-player-semantics',
    'sound-clock','bar-travel','fixed-uv-runtime','chord-runtime',
    'musicbar-lifecycle','text-variable-semantics','play-plane-runtime',
})


def check_output(path):
    """Check before creating even an intermediate beside the input."""
    destination = path.resolve()
    # Local configured boundaries also apply if an executable moved.
    protected = []
    settings = ROOT / 'project.local.json'
    if not settings.is_file() and ROOT.parent.name == 'dist':
        settings = ROOT.parent.parent / 'project.local.json'
    if settings.is_file():
        paths = json.loads(settings.read_text(encoding='utf-8'))
        protected.extend(Path(paths[k]) for k in ('legacy', 'mav') if paths.get(k))
    if any(destination == p.resolve() or destination.is_relative_to(p.resolve()) for p in protected):
        raise ValueError('MSZ 位于原游戏安装目录内，不能在此生成文件；请把 MSZ 放到普通文件夹后拖入')
    for parent in destination.parents:
        if (parent / 'malody.exe').is_file() or ((parent / 'Malody V.exe').is_file() and (parent / 'GameAssembly.dll').is_file()):
            raise ValueError('不能在原游戏安装目录内生成文件，请把 MSZ 放到普通文件夹后拖入')


def extract_skin(source, destination):
    with zipfile.ZipFile(source) as archive:
        seen = {}
        entries = []
        total = 0
        for info in archive.infolist():
            name = info.filename.replace('\\', '/')
            if not info.flag_bits & 0x800:
                # Old exporters sometimes wrote UTF-8/GBK without the ZIP UTF-8 flag.
                raw = name.encode('cp437')
                for encoding in ('utf-8', 'gb18030'):
                    try:
                        name = raw.decode(encoding)
                        break
                    except UnicodeError:
                        continue
            parts = PurePosixPath(name).parts
            if (not parts or name.startswith('/') or PureWindowsPath(name).drive or
                    any(p in ('.', '..') or any(c in '<>:"|?*' or ord(c)<32 for c in p) or p.endswith((' ', '.')) or
                        re.fullmatch(r'(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?', p)
                        for p in parts)):
                raise ValueError(f'MSZ 内含非法路径：{name}')
            if stat.S_ISLNK(info.external_attr >> 16) or info.flag_bits & 1:
                raise ValueError(f'MSZ 内含链接或加密文件，无法读取：{name}')
            identity = '/'.join(parts).casefold()
            previous=seen.get(identity)
            if previous is not None and previous[1]!=info.is_dir():
                raise ValueError(f'MSZ 内含文件与目录冲突：{name}')
            target=previous[0] if previous is not None else destination.joinpath(*parts)
            seen[identity]=(target,info.is_dir())
            total += info.file_size
            if total > 2 * 1024**3 or len(entries) >= 50000:
                raise ValueError('MSZ 解包超过 2 GiB 或 50000 文件，已停止')
            entries.append((info, target))
        if shutil.disk_usage(destination).free < total + 256 * 1024**2:
            raise ValueError('工作磁盘可用空间不足，未开始解包')
        written=set()
        for info, target in entries:
            if not target.resolve().is_relative_to(destination.resolve()):
                raise ValueError('MSZ 解包路径越界')
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                # Original 0x6124cd..0x612510 opens each entry with "wb";
                # later archive entries replace earlier files. Only overwrite
                # files created in THIS extraction; preexisting files retain
                # the original exclusive-create protection.
                with archive.open(info) as incoming, target.open('wb' if target in written else 'xb') as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
                written.add(target)
    roots = {p.parent for p in destination.rglob('*') if re.fullmatch(r'script-key-\d+K\.mui', p.name, re.I)}
    if len(roots) != 1:
        raise ValueError('MSZ 中未找到 Key 皮肤入口' if not roots else 'MSZ 包含多个皮肤目录，无法确定要转换的皮肤')
    root = roots.pop()
    counts = sorted({int(p.name.rsplit('-', 1)[1][:-5]) for p in root.iterdir()
                     if re.fullmatch(r'script-key-\d+K\.mui', p.name, re.I)})
    if not counts:
        raise ValueError('未找到 script-key-*K.mui 入口')
    return root, counts


def rewrite_message(message, replacements):
    for field, value in message.ListFields():
        if field.type == field.TYPE_MESSAGE:
            for item in value if field.is_repeated else (value,):
                rewrite_message(item, replacements)
        elif field.type == field.TYPE_STRING:
            if field.is_repeated:
                for i, item in enumerate(value):
                    value[i] = replacements.get(item, item)
            else:
                setattr(message, field.name, replacements.get(value, value))


def combine(compiled, target, title, platform_entries=None):
    """One native SkinFile; separate handles/resources and a per-chart dispatcher."""
    target.mkdir()
    SkinFile = skin_class()
    merged = SkinFile()
    runtimes = []
    runtime_factories = {}
    runtime_definitions = []
    all_handles = []
    platform_handles = {'windows': [], 'android': []}
    shared_resources = {}
    for keys, folder, report in compiled:
        entry_platforms = [p for p, entries in (platform_entries or {}).items() if keys in entries.values()]
        skin = SkinFile.FromString((folder / 'info.asm').read_bytes())
        if not runtimes:
            merged.CopyFrom(skin)
            del merged.modules[:]
        prefix = f'k{keys}_'
        excluded = {'info.asm', 'info.json', 'info.decoded.json', 'legacy.lua',
                    'legacy-ir.json', 'conversion-report.json', '测试说明.txt'}
        omitted=set(report.get('omitted_package_resources',[]))
        replacements = {}
        for resource in folder.rglob('*'):
            if not resource.is_file() or resource.name in excluded:
                continue
            relative = resource.relative_to(folder).as_posix()
            if relative in omitted:continue
            # Equal bytes with equal extensions are interchangeable resources.
            # Keep handles separate, but share font banks, PNGs and audio across
            # Key entries instead of multiplying them by the number of modes.
            identity = (resource.suffix.lower(), hashlib.sha256(resource.read_bytes()).digest())
            renamed = shared_resources.get(identity, prefix + relative)
            replacements[relative] = renamed
            if identity in shared_resources:
                continue
            shared_resources[identity] = renamed
            output = target / renamed
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(resource), output)
        for module in skin.modules:
            replacements[module.meta.desc] = prefix + module.meta.desc
        rewrite_message(skin, replacements)
        for module in skin.modules:
            # Only the selected Key entry's Init/Update may make visuals visible.
            module.param.alpha = 0
            # Hidden native value/fill helpers are instantiated components
            # too. Leaving them active keeps other Key/platform branches
            # running even though their visible graphics are disabled.
            all_handles.append(module.meta.desc)
            for platform in entry_platforms:
                platform_handles[platform].append(module.meta.desc)
            if len(entry_platforms) == 1:
                # SkinRuntime.Prepare filters scene Platform before factories,
                # watchers and canvases are created. Hiding another platform's
                # GameObjects in Init is too late to avoid that native work.
                module.scenes.add(source=6, flag=0, valint={'windows': 1, 'android': 3}[entry_platforms[0]])
            merged.modules.add().CopyFrom(module)
        header, original = (folder / 'legacy.lua').read_text(encoding='utf-8').split('\n', 1)
        # Retain the emitted Lua's numeric keys (notes/glyphs) and string keys
        # (texture states). A JSON round trip would turn both into strings.
        literals = {lua(k): lua(v) for k, v in replacements.items()}
        header = re.sub(r'"(?:\\.|[^"\\])*"', lambda m: literals.get(m[0], m[0]), header)
        if not runtimes:
            merged.meta.cover = replacements.get(merged.meta.cover, merged.meta.cover)
        # Every entry needs its own mutable state, not another copy of the
        # same program. Share only byte-identical runtime code; PROFILE and
        # callback locals are created afresh inside each constructor call.
        # Runtime variants (e.g. bar/musicbar) remain separate constructors.
        constructor = runtime_factories.get(original)
        if constructor is None:
            constructor = f'buildRuntime{len(runtime_factories) + 1}'
            runtime_factories[original] = constructor
            runtime_definitions.append('local function ' + constructor + '(PROFILE)\nlocal ' +
                ','.join(CALLBACKS) + '\n' + original + '\nreturn {' +
                ','.join(f'{name}={name}' for name in CALLBACKS) + '}\nend\n')
        factory = (f'builders[{lua(keys)}]=function()\n' + header +
                   '\nreturn ' + constructor + '(PROFILE)\nend\n')
        runtimes.append(factory)
    merged.meta.title = title + ' · Key 移植'
    # Native SupportPlayMode treats key=0 as a wildcard. Do not mislabel 4K as 6K.
    merged.meta.key.keys = 0
    merged.meta.script = 'legacy.lua'
    (target / 'info.asm').write_bytes(merged.SerializeToString(deterministic=True))
    (target / 'info.json').write_text(json.dumps({'title': merged.meta.title, 'desc': merged.meta.desc,
        'creator': merged.meta.creator, 'version': merged.meta.minver, 'mode': 0, 'key': 0,
        'feature': 3, 'cover': merged.meta.cover, 'skinid': 0, 'updatedTime': 0, 'special': None}, ensure_ascii=False), encoding='utf-8')
    dispatcher = (Path(__file__).parent / 'multi_key.lua').read_text(encoding='utf-8')
    (target / 'legacy.lua').write_text('local builders={}\nlocal platformEntries='+lua(platform_entries)+'\nlocal platformHandles='+lua(platform_handles if platform_entries else None)+'\nlocal handles=' + lua(all_handles) + '\n' +
        '\n'.join(runtime_definitions) + '\n' + '\n'.join(runtimes) + '\n' + dispatcher, encoding='utf-8')


def compile_package(skin, counts, base, *, input_name, input_sha256, progress=lambda message: None, runtime_phase_profile=False, native_musicbar_camera_local_candidate=False,native_ui_atlas_candidate=False,native_packed_mesh_candidate=False,native_canvas_text_candidate=False,native_numeric_float_candidate=False,native_combined_position_candidate=False,native_frame_mesh_candidate=False,native_dynamic_mesh_candidate=False,native_carrier_window_candidate=False,native_instruction_profile_candidate=False,native_ui_schedule_candidate=False,native_note_layout_candidate=False,native_math_module=None,native_transform_submit_candidate=False,native_vertex_upload_candidate=False,native_text_read_candidate=False,native_ui_submit_candidate=False,native_retained_text_candidate=False,native_stable_text_basis_candidate=False,native_plane_text_candidate=False,native_font_outline_candidate=False):
    """One post-extraction compiler for the MSZ app and immutable corpus probes."""
    compiled = []
    declared_counts=list(counts);omitted=[];plans=[]
    platform_entries={'windows':{},'android':{}};windows_documents={};entry_metadata={}
    for platform in platform_entries:
        for keys in counts:
            document=parse(skin,keys,1024/600,logical_height=600,platform=platform)
            if platform=='windows':windows_documents[keys]=document
            if not any(is_key_scene_definition(e) for e in document.elements.values()) and not any(i.severity=='error' for i in document.issues):
                omitted.append({'keys':keys,'platform':platform,'reason':f'no-active-{platform}-elements','files':document.files,
                    'issues':[vars(i) for i in document.issues],
                    'message':f'{keys}K 在 {platform} 分支没有皮肤元素，未生成该入口'})
                progress('提示：'+omitted[-1]['message'])
                continue
            if platform=='android' and document==windows_documents[keys] and keys in platform_entries['windows']:
                platform_entries[platform][keys]=keys
                continue
            entry_id=keys if platform=='windows' else f'android_{keys}'
            platform_entries[platform][keys]=entry_id
            entry_metadata[entry_id]=(keys,platform)
            plans.append((entry_id,platform,keys,document))
    # Audit every platform before compiling font banks or image resources.
    for _,platform,keys,document in plans:
        audit_contracts(document)
        fatal=[i for i in document.issues if i.severity=='error' and i.code not in ACCEPTANCE_GATES]
        if fatal:raise ValueError(f'{platform} {keys}K 无法转换：'+'\n'.join(i.message for i in fatal))
    font_build_context=None
    if not native_font_outline_candidate:
        from .font_storage import plan_font_storage
        font_build_context=plan_font_storage([row[3] for row in plans],font_bank(),base/'font-storage-plan',progress=progress)
    for entry_id,platform,keys,document in plans:
        from .preview import compile_preview
        progress(f'正在转换 {platform} {keys}K…')
        folder = base / f'key-{entry_id}'
        report = compile_preview(skin, folder, keys, archive_input=True, runtime_phase_profile=runtime_phase_profile,native_musicbar_camera_local_candidate=native_musicbar_camera_local_candidate,native_ui_atlas_candidate=native_ui_atlas_candidate,native_packed_mesh_candidate=native_packed_mesh_candidate,native_canvas_text_candidate=native_canvas_text_candidate,native_numeric_float_candidate=native_numeric_float_candidate,native_combined_position_candidate=native_combined_position_candidate,native_frame_mesh_candidate=native_frame_mesh_candidate,native_dynamic_mesh_candidate=native_dynamic_mesh_candidate,native_carrier_window_candidate=native_carrier_window_candidate,native_instruction_profile_candidate=native_instruction_profile_candidate,native_ui_schedule_candidate=native_ui_schedule_candidate,native_note_layout_candidate=native_note_layout_candidate,native_math_module=native_math_module,native_transform_submit_candidate=native_transform_submit_candidate,native_vertex_upload_candidate=native_vertex_upload_candidate,native_text_read_candidate=native_text_read_candidate,native_ui_submit_candidate=native_ui_submit_candidate,native_retained_text_candidate=native_retained_text_candidate,native_stable_text_basis_candidate=native_stable_text_basis_candidate,native_plane_text_candidate=native_plane_text_candidate,source_platform=platform,native_font_outline_candidate=native_font_outline_candidate,font_build_context=font_build_context,progress=progress)
        # Structural/resource failures must not be packaged as a usable skin.
        fatal = [issue for issue in report['issues']
                 if issue['severity'] == 'error' and issue['code'] not in ACCEPTANCE_GATES]
        if fatal:
            raise ValueError(f'{platform} {keys}K 无法转换：' + '\n'.join(i['message'] for i in fatal))
        compiled.append((entry_id, folder, report))
    if not compiled:
        raise ValueError('此 MSZ 的 Windows / Android 分支没有任何可用 Key 皮肤入口')
    counts=sorted({entry_metadata[entry_id][0] for entry_id,_,_ in compiled})
    platform_dispatch=platform_entries['windows']!=platform_entries['android']
    package = base / 'package'
    if len(compiled) == 1 and not platform_dispatch:
        package = compiled[0][1]
        metadata = skin_class().FromString((package / 'info.asm').read_bytes())
        if not (skin / 'preview.json').is_file():
            metadata.meta.title = Path(input_name).stem + f' · {counts[0]}K 移植'
            (package / 'info.asm').write_bytes(metadata.SerializeToString(deterministic=True))
            info = json.loads((package / 'info.json').read_text(encoding='utf-8'))
            info['title'] = metadata.meta.title
            (package / 'info.json').write_text(json.dumps(info, ensure_ascii=False), encoding='utf-8')
    else:
        combine(compiled, package, Path(input_name).stem, platform_entries if platform_dispatch else None)
    entries = []
    for entry_id, _, report in compiled:
        keys,platform=entry_metadata[entry_id]
        entry = {k: v for k, v in report.items() if k not in ('archive', 'source', 'files')}
        entry['source'] = input_name + f'!/script-key-{keys}K.mui'
        entry['platforms']=[p for p,m in platform_entries.items() if m.get(keys)==entry_id]
        entries.append(entry)
    receipt = {'input_name': input_name, 'input_sha256':input_sha256, 'keys': counts, 'one_to_one_verified': False,
               'declared_source_keys':declared_counts,'omitted_source_entries':omitted,
               'platform_keys':{p:sorted(m) for p,m in platform_entries.items()},
               'info_sha256': hashlib.sha256((package / 'info.asm').read_bytes()).hexdigest(),
               'diagnostic_phase_profiling':bool(runtime_phase_profile or native_instruction_profile_candidate),
               'native_render_verified_for_this_package': False,
               'limitations': '当前兼容层仍有 MC/mania OSU、16384 音符排序范围等限制，MSP 后缀不代表渲染验收通过',
               'entries': entries,
               'font_storage_plan':font_build_context['report'] if font_build_context else None}
    (package / 'conversion-report.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
    return package


def merge_native_ui_branch(data, branch, platform, expected_config=None):
    """Keep the runtime configuration as well as the platform UI entries.

    Source queues and LN hit handlers are selected by these top-level keys.
    Dropping them emits event code without its required native adapter. Refuse
    different platform configurations instead of silently choosing one.
    """
    if not isinstance(data,dict) or not isinstance(branch,dict):
        raise ValueError('Native UI merge requires mapping data and branch')
    config={key:value for key,value in branch.items() if key not in ('entries','configs')}
    if expected_config is not None and config!=expected_config:
        raise ValueError('Windows/Android 原生 UI 配置不一致，不能静默丢弃')
    data.update(copy.deepcopy(config))
    prefix=platform+'_'
    entries=data.setdefault('entries',[])
    for row in branch.get('entries',[]):
        clone=copy.deepcopy(row)
        clone['handle']=prefix+clone['handle']
        entries.append(clone)
    return copy.deepcopy(config)


def _aspect_intervals(thresholds):
    points=sorted({round(float(t),6) for _,t in thresholds if t>0})
    if not points:
        return [((),1024/600,'')]
    boundaries=[p+1e-4 for p in points]
    canonical=(4/3,16/10,1024/600,16/9,19.5/9)
    def pick_sample(low,high):
        for candidate in (1024/600,16/9,4/3,16/10,19.5/9):
            if (low is None or candidate>low+1e-6) and (high is None or candidate<=high):
                return candidate
        if low is None:return max(0.75,high*0.9)
        if high is None:return low+0.15
        return (low+high)*0.5
    rows=[]
    for idx in range(len(points)+1):
        low=None if idx==0 else points[idx-1]
        high=None if idx==len(points) else points[idx]
        conds=[]
        if idx>0:conds.append(('large',boundaries[idx-1]))
        if idx<len(points):conds.append(('less',boundaries[idx]))
        rows.append((tuple(conds),pick_sample(low,high),f'a{idx}'))
    return rows


def _tag_package_title(package, input_name, label):
    combined=skin_class()()
    combined.ParseFromString((package/'info.asm').read_bytes())
    combined.meta.title=f'{Path(input_name).stem} ({label})'
    binary=combined.SerializeToString(deterministic=True)
    (package/'info.asm').write_bytes(binary)
    info=json.loads((package/'info.json').read_text(encoding='utf-8'))
    info['title']=combined.meta.title
    (package/'info.json').write_text(json.dumps(info,ensure_ascii=False),encoding='utf-8')
    receipt=json.loads((package/'conversion-report.json').read_text(encoding='utf-8'))
    receipt['info_sha256']=hashlib.sha256(binary).hexdigest()
    (package/'conversion-report.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')


def _assemble_single_key_package(branch_entries, package, keys, input_name, input_sha256, *, basic_script, title_suffix=''):
    package.mkdir(parents=True,exist_ok=True)
    combined=type(branch_entries[0][6])();data={'entries':[],'configs':[]};reports=[];configurations=[]
    ui_branches=[]
    for index,(platform,platform_id,aspect_conds,aspect_tag,folder,report,entry) in enumerate(branch_entries):
        if index==0:combined.meta.CopyFrom(entry.meta)
        elif entry.meta.key.use3_d!=combined.meta.key.use3_d:
            raise ValueError('Windows/Android 使用不同 3D 轨道模式，原生平台映射尚未完成')
        renames=merge_native_resources(entry,folder,package)
        if index==0 and combined.meta.cover:
            combined.meta.cover=renames.get(combined.meta.cover,combined.meta.cover)
        elif not combined.meta.cover and entry.meta.cover:
            combined.meta.cover=renames.get(entry.meta.cover,entry.meta.cover)
        prefix=f'{platform}_{aspect_tag}_' if aspect_tag else f'{platform}_'
        for module in entry.modules:
            clone=combined.modules.add();clone.CopyFrom(module);rewrite_message(clone,renames)
            clone.meta.desc=prefix+clone.meta.desc
            clone.scenes.add(source=6,valint=platform_id)
            for op,boundary in aspect_conds:
                clone.scenes.add(source=5,flag=2 if op=='large' else 3,valdbl=boundary)
        for definition in entry.defs:
            prior=next((d for d in combined.defs if d.type==definition.type),None)
            if prior is None:combined.defs.add().CopyFrom(definition)
            elif prior.SerializeToString()!=definition.SerializeToString():
                raise ValueError('原生默认组件的平台定义不一致，不能静默丢弃：'+str(definition.type))
        for value in entry.disabled:
            if value not in combined.disabled:combined.disabled.append(value)
        branch_cfg=None
        if (folder/'native_ui.json').is_file():
            branch=rewrite_native_ui_resources(json.loads((folder/'native_ui.json').read_text(encoding='utf-8')),renames)
            branch_cfg={key:value for key,value in branch.items() if key not in ('entries','configs')}
            for row in branch.get('entries',[]):
                clone_row=copy.deepcopy(row)
                clone_row['handle']=prefix+clone_row['handle']
                data['entries'].append(clone_row)
            ui_branches.append(index)
        configurations.append((platform,platform_id,aspect_conds,prefix,entry.meta.key,branch_cfg))
        reports.append(report)
    if ui_branches and len(ui_branches)!=len(branch_entries):
        raise ValueError('Windows/Android 原生 UI 分支缺失，不能静默合并')
    if ui_branches:
        first_cfg=configurations[0][5]
        data.update(copy.deepcopy(first_cfg))
        configs_differ=any(c[5]!=first_cfg for c in configurations)
    else:
        configs_differ=False
    combined.meta.title=Path(input_name).stem+title_suffix
    meta_differs=len({meta.SerializeToString() for _,_,_,_,meta,_ in configurations})>1
    if meta_differs or configs_differ:
        if meta_differs:
            combined.meta.key.lock_scale=False;combined.meta.key.lock3_d=False
        for platform,platform_id,aspect_conds,prefix,meta,branch_cfg in configurations:
            marker=combined.modules.add(usage=99,type=5004);marker.meta.desc=prefix+'configuration'
            marker.param.alpha=0;marker.param.layer=4;marker.image.color='#FFFFFF';marker.image.width=marker.image.height=1
            marker.scenes.add(source=6,valint=platform_id)
            for op,boundary in aspect_conds:
                marker.scenes.add(source=5,flag=2 if op=='large' else 3,valdbl=boundary)
            cfg_row={'marker':marker.meta.desc,'scale':meta.scale,'judge':meta.judge_pos,'angle':meta.angle}
            if configs_differ and branch_cfg is not None:
                cfg_row['branch_config']=branch_cfg
            data['configs'].append(cfg_row)
    combined.meta.ClearField('script')
    if data['entries'] or data['configs'] or any(key not in ('entries','configs') for key in data):
        combined.meta.script='native_ui.lua'
        (package/'native_ui.json').write_text(json.dumps(data,ensure_ascii=False,allow_nan=False),encoding='utf-8')
        (package/'native_ui.lua').write_bytes(basic_script(data))
    (package/'info.asm').write_bytes(combined.SerializeToString(deterministic=True))
    (package/'info.json').write_text(json.dumps(skin_info_payload(combined.meta,keys),ensure_ascii=False),encoding='utf-8')
    receipt={'input_name':input_name,'input_sha256':input_sha256,'keys':[keys],
             'render_backend':'native_key','free':False,'script':'ordinary UI only',
             'chart_source_read_by_skin':False,'custom_note_clock':False,'custom_judge':False,
             'one_to_one_verified':False,'native_render_verified_for_this_package':False,
             'skin_upload_verified':False,'normal_score_submission_verified':False,
             'entries':reports,'info_sha256':hashlib.sha256((package/'info.asm').read_bytes()).hexdigest()}
    (package/'conversion-report.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    return package


def compile_normal_packages(skin, counts, base, *, input_name, input_sha256, progress=lambda message: None):
    """Compile into one MSP package or split straight/tilted packages when both 2D and 3D exist."""
    from .native_key import compile_native_key_skin, basic_script
    base=Path(base);base.mkdir(parents=True,exist_ok=True)
    if len(counts)!=1:
        from .native_multikey import assemble_native_branches
        skin_type=skin_class()
        def compile_multikey_branch(keys,folder,ratio,platform):
            kwargs={'source_platform':platform,'progress':progress,'font_build_context':font_context}
            if platform=='android':kwargs['phone_predicate']=True
            report=compile_native_key_skin(skin,folder,keys,ratio,**kwargs)
            issues=native_export_issues(report)
            if issues:raise ValueError('; '.join(i['message'] for i in issues))
            return report
        compiled={};errors={};font_context={}
        for keys in counts:
            for platform in ('windows','android'):
                folder=base/f'native-{keys}-{platform}'
                try:
                    report=compile_multikey_branch(keys,folder,1024/600,platform)
                    compiled[(keys,platform)]=(platform,folder,report)
                except (ValueError,FileNotFoundError) as error:
                    errors[(keys,platform)]=('missing_note1' if '原定义缺少 note-1' in str(error) else 'other',str(error))
                    continue
        for (keys,platform),(kind,_) in list(errors.items()):
            other='android' if platform=='windows' else 'windows'
            if kind=='missing_note1' and (keys,other) in compiled:
                src_platform,src_folder,src_report=compiled[(keys,other)]
                fb=base/f'native-{keys}-{platform}-fallback'
                shutil.copytree(src_folder,fb,dirs_exist_ok=True)
                compiled[(keys,platform)]=(src_platform,fb,copy.deepcopy(src_report))
                del errors[(keys,platform)]
        if errors:
            raise ValueError('原生多入口转换未完成：'+'\n'.join(f'{p} {k}K: {msg}' for (k,p),(_,msg) in sorted(errors.items())))
        rows=[]
        for keys in counts:
            for platform in ('windows','android'):
                src_platform,default_folder,default_report=compiled[(keys,platform)]
                intervals=_aspect_intervals(default_report.get('aspect_thresholds',()))
                for aspect_conds,sample_ratio,aspect_tag in intervals:
                    if not aspect_tag or abs(sample_ratio-1024/600)<=1e-9:
                        folder,report=default_folder,default_report
                    else:
                        folder=base/f'native-{keys}-{platform}-{aspect_tag}'
                        try:
                            report=compile_multikey_branch(keys,folder,sample_ratio,src_platform)
                        except (ValueError,FileNotFoundError) as error:
                            if '原定义缺少 note-1' not in str(error):raise
                            fb_folder=base/f'native-{keys}-{platform}-{aspect_tag}-fallback'
                            shutil.copytree(default_folder,fb_folder,dirs_exist_ok=True)
                            folder,report=fb_folder,copy.deepcopy(default_report)
                    entry_obj=skin_type();entry_obj.ParseFromString((folder/'info.asm').read_bytes())
                    rows.append((keys,platform,aspect_conds,aspect_tag,folder,report,entry_obj,entry_obj.meta.key.use3_d))
        modes={r[7] for r in rows}
        if len(modes)>1:
            # Cancel _直轨 export: retain only tilted (use3_d=True) branches across both platforms.
            kept=[]
            part_keys=sorted({r[0] for r in rows if r[7]})
            for k in part_keys:
                matched_k=[r for r in rows if r[0]==k and r[7]]
                for p in ('windows','android'):
                    matched_kp=[r for r in matched_k if r[1]==p]
                    if matched_kp:
                        kept.extend(matched_kp)
                    else:
                        other='android' if p=='windows' else 'windows'
                        for _,__,aspect_conds,aspect_tag,src_f,src_r,src_entry,u3d in [r for r in matched_k if r[1]==other]:
                            f=base/f'tilted-{k}-{p}-{aspect_tag or "base"}'
                            shutil.copytree(src_f,f,dirs_exist_ok=True)
                            clone_entry=skin_type();clone_entry.CopyFrom(src_entry)
                            kept.append((k,p,aspect_conds,aspect_tag,f,copy.deepcopy(src_r),clone_entry,u3d))
            rows=kept
        pkg=assemble_native_branches([(k,p,conds,tag,f,r) for k,p,conds,tag,f,r,_,_ in rows],base/'native-package',
            input_name=input_name,input_sha256=input_sha256)
        return [('',pkg)]
    keys=counts[0]
    font_context={}
    def run_compile(folder,ratio,platform):
        kwargs={'source_platform':platform,'progress':progress,'font_build_context':font_context}
        if platform=='android':kwargs['phone_predicate']=True
        report=compile_native_key_skin(skin,folder,keys,ratio,**kwargs)
        fatal=native_export_issues(report)
        if fatal:raise ValueError(f'{platform} {keys}K 原生转换未完成：'+'\n'.join(issue['message'] for issue in fatal))
        return report
    skin_type=skin_class()
    by_platform={};platform_errors={}
    for platform,platform_id in (('windows',1),('android',3)):
        try:
            default_folder=base/('native-'+platform)
            default_report=run_compile(default_folder,1024/600,platform)
            intervals=_aspect_intervals(default_report.get('aspect_thresholds',()))
            entries=[]
            for aspect_conds,sample_ratio,aspect_tag in intervals:
                if not aspect_tag or abs(sample_ratio-1024/600)<=1e-9:
                    folder,report=default_folder,default_report
                else:
                    folder=base/f'native-{platform}-{aspect_tag}'
                    try:
                        report=run_compile(folder,sample_ratio,platform)
                    except ValueError as err:
                        if '原定义缺少 note-1' not in str(err):raise
                        fb_folder=base/f'native-{platform}-{aspect_tag}-fallback'
                        shutil.copytree(default_folder,fb_folder,dirs_exist_ok=True)
                        folder,report=fb_folder,copy.deepcopy(default_report)
                entry=skin_type();entry.ParseFromString((folder/'info.asm').read_bytes())
                entries.append((platform,platform_id,aspect_conds,aspect_tag,folder,report,entry))
            by_platform[platform]=entries
        except ValueError as err:
            platform_errors[platform]=err
    for platform,platform_id in (('windows',1),('android',3)):
        other='android' if platform=='windows' else 'windows'
        if platform in platform_errors and '原定义缺少 note-1' in str(platform_errors[platform]) and other in by_platform:
            mirrored=[]
            for _,__,aspect_conds,aspect_tag,folder,report,entry in by_platform[other]:
                fb=base/f'native-{platform}-fallback-{aspect_tag or "base"}'
                shutil.copytree(folder,fb,dirs_exist_ok=True)
                clone_entry=skin_type();clone_entry.CopyFrom(entry)
                mirrored.append((platform,platform_id,aspect_conds,aspect_tag,fb,copy.deepcopy(report),clone_entry))
            by_platform[platform]=mirrored
            del platform_errors[platform]
    if platform_errors:
        raise next(iter(platform_errors.values()))
    branch_entries=by_platform['windows']+by_platform['android']
    modes={row[6].meta.key.use3_d for row in branch_entries}
    if len(modes)>1:
        # Cancel _直轨 export: retain only tilted (use3_d=True) branches across both platforms.
        filtered=[row for row in branch_entries if row[6].meta.key.use3_d]
        present_platforms={row[0] for row in filtered}
        full=list(filtered)
        if present_platforms=={'windows'}:
            for _,__,aspect_conds,aspect_tag,folder,report,entry in filtered:
                fb=base/f'tilted-android-{aspect_tag or "base"}'
                shutil.copytree(folder,fb,dirs_exist_ok=True)
                clone_entry=skin_type();clone_entry.CopyFrom(entry)
                full.append(('android',3,aspect_conds,aspect_tag,fb,copy.deepcopy(report),clone_entry))
        elif present_platforms=={'android'}:
            for _,__,aspect_conds,aspect_tag,folder,report,entry in filtered:
                fb=base/f'tilted-windows-{aspect_tag or "base"}'
                shutil.copytree(folder,fb,dirs_exist_ok=True)
                clone_entry=skin_type();clone_entry.CopyFrom(entry)
                full.append(('windows',1,aspect_conds,aspect_tag,fb,copy.deepcopy(report),clone_entry))
        branch_entries=full
    pkg=_assemble_single_key_package(branch_entries,base/'native-package',keys,input_name,input_sha256,basic_script=basic_script)
    return [('',pkg)]


def compile_normal_package(skin, counts, base, *, input_name, input_sha256, progress=lambda message: None):
    """The ordinary drag/drop compiler, returning one MSP package directory."""
    packages=compile_normal_packages(skin,counts,base,input_name=input_name,input_sha256=input_sha256,progress=progress)
    if len(packages)!=1:
        raise ValueError('该皮肤同时包含直轨与斜轨两套模式，请使用 convert_msz / compile_normal_packages 分别导出直轨与斜轨 .msp')
    return packages[0][1]


_DEFAULT_COMPILE_NORMAL_PACKAGE = compile_normal_package


def native_export_issues(report):
    """One acceptance boundary shared by single- and multi-Key compilation."""
    blocked={'native-chord-appearance','native-key-projection','native-ui-motion',
        'native-touch-regions','native-musicbar','native-progress-style',
        'native-hold-hit-effect','native-blend-difference'}
    return [issue for issue in report['issues'] if issue['severity']=='error' or issue['code'] in blocked]


def rewrite_native_ui_resources(value, replacements):
    """Rename exact resource values, including runtime-only font/frame files."""
    if isinstance(value,str):return replacements.get(value,value)
    if isinstance(value,list):return [rewrite_native_ui_resources(item,replacements) for item in value]
    if isinstance(value,dict):return {key:rewrite_native_ui_resources(item,replacements) for key,item in value.items()}
    return value


def merge_native_resources(skin, source, destination):
    """Keep referenced resources once, including content-identical frame banks.

    Renaming a frame's file without its filebase breaks the native provider.
    Bank identity includes the numeric suffix, so sparse number fonts retain
    the game's glyph indices. No original source or game files are changed.
    """
    replacements={};wanted=set()
    if skin.meta.cover:wanted.add(skin.meta.cover)
    for module in skin.modules:
        images=[*module.note.images,*module.images.items]
        if module.HasField('image'):images.append(module.image)
        if module.HasField('number'):images.append(module.number)
        for image in images:
            if image.file:wanted.add(image.file)
            if image.filebase:
                prefix=image.filebase
                members=sorted((p for p in source.iterdir() if p.is_file() and
                    re.fullmatch(re.escape(prefix)+r'\d+\.png',p.name)),key=lambda p:p.name)
                if not members:raise ValueError('原生序列资源为空：'+prefix)
                digest=hashlib.sha256()
                for path in members:
                    digest.update(path.name[len(prefix):].encode('utf-8')+b'\0')
                    digest.update(hashlib.sha256(path.read_bytes()).digest())
                canonical='bank-'+digest.hexdigest()[:24]+'-'
                replacements[prefix]=canonical
                for path in members:
                    replacements[path.name]=canonical+path.name[len(prefix):]
                    wanted.add(path.name)
        if module.HasField('sound') and module.sound.file:wanted.add(module.sound.file)
    ui_path=source/'native_ui.json'
    if ui_path.is_file():
        ordinary=json.loads(ui_path.read_text(encoding='utf-8'))
        for entry in ordinary.get('entries',[]):
            for frame in entry.get('source_frames',{}).get('frames',[]):
                # Subsequent StateAnimator frames are selected on one native
                # Image, so they have no extra declarative module reference.
                wanted.add(frame['file'])
            for frame in entry.get('source_meter',{}).get('frames',[]):
                wanted.add(frame['file'])
            for bank in entry.get('source_events',{}).get('banks',[]):
                for frame in bank['frames']:wanted.add(frame['file'])
            font=entry.get('source_text',{}).get('font',{})
            for field in ('packed_index_file','packed_coverage_file'):
                if font.get(field):wanted.add(font[field])
    for name in sorted(wanted):
        path=source/name
        blob=path.read_bytes()
        target=replacements.setdefault(name,hashlib.sha256(blob).hexdigest()[:24]+path.suffix.lower())
        output=destination/target
        if output.exists():
            if output.read_bytes()!=blob:raise ValueError('原生资源标识冲突：'+target)
        else:output.write_bytes(blob)
    return replacements


def write_package(package, destination):
    """Identical archive contents for the app and corpus validation."""
    validate_native_key_package(skin_class().FromString((package/'info.asm').read_bytes()),
                                (p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()),
                                {name:(package/name).read_bytes() for name in ('native_ui.lua','native_ui.json') if (package/name).is_file()})
    receipt=json.loads((package/'conversion-report.json').read_text(encoding='utf-8'))
    # A combined package already excluded each entry's superseded copies.
    # Only a single entry still points at the compiler's original directory.
    omitted=set(receipt['entries'][0].get('omitted_package_resources',[])) if len(receipt['entries'])==1 else set()
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(package.rglob('*')):
            if file.is_file() and file.name not in {'legacy-ir.json', 'info.decoded.json', '测试说明.txt'} and file.relative_to(package).as_posix() not in omitted:
                archive.write(file, file.relative_to(package).as_posix())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError('MSP 压缩校验失败')


def convert_msz(source, progress=lambda message: None):
    source = Path(source).resolve(strict=True)
    if source.suffix.lower() != '.msz' or not source.is_file():
        raise ValueError('请拖入旧版 .msz 皮肤文件')
    # maV ImportFromFile calculates the Setup path from the MSP basename,
    # while UnzipFileWithName replaces ASCII spaces and a final dot. Both
    # paths must match; preserve the source archive and normalize the output.
    stem=source.stem.replace(' ','_')
    if stem.endswith('.'):stem=stem[:-1]+'_'
    input_sha256=hashlib.sha256(source.read_bytes()).hexdigest()
    work = ROOT / 'output'
    work.mkdir(exist_ok=True)
    progress('正在读取 MSZ…')
    outputs=[]
    with tempfile.TemporaryDirectory(prefix='msz-', dir=work) as temporary:
        base = Path(temporary)
        extracted = base / 'input'
        extracted.mkdir()
        skin, counts = extract_skin(source, extracted)
        if compile_normal_package is not _DEFAULT_COMPILE_NORMAL_PACKAGE:
            packages=[('',compile_normal_package(skin,counts,base,input_name=source.name,
                                                input_sha256=input_sha256,progress=progress))]
        else:
            packages = compile_normal_packages(skin, counts, base, input_name=source.name,
                                               input_sha256=input_sha256, progress=progress)
        targets=[]
        for suffix, package in packages:
            output = source.with_name(f'{stem}{suffix}.msp')
            check_output(output)
            targets.append((output, package))
        progress('正在生成 MSP…')
        for output, package in targets:
            # Stage beside the final path for an atomic replacement; never leave a half MSP.
            descriptor, staged = tempfile.mkstemp(prefix='.' + output.stem + '-', suffix='.tmp', dir=output.parent)
            os.close(descriptor)
            try:
                write_package(package, staged)
                if hashlib.sha256(source.read_bytes()).hexdigest()!=input_sha256:
                    raise ValueError('转换期间 MSZ 内容发生变化，未替换已有 MSP')
                os.replace(staged, output)
            finally:
                Path(staged).unlink(missing_ok=True)
            outputs.append(output)
    return outputs[0] if len(outputs)==1 else outputs


def main(argv=None):
    parser = argparse.ArgumentParser(description='将 MSZ 转为同目录 MSP；文件名空格替换为 _ 以兼容原生导入')
    parser.add_argument('files', nargs='+', type=Path)
    args = parser.parse_args(argv)
    failed = False
    for source in args.files:
        try:
            result=convert_msz(source, print)
            for path in (result if isinstance(result,(list,tuple)) else [result]):
                print(path)
        except Exception as error:
            failed = True
            print(f'{source.name}：{error}', file=sys.stderr)
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
