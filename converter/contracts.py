"""Conservative coupled-feature audit. Native evidence, not name similarity, is authoritative."""
import re
from .mui import Issue,linear,native_integer,is_scene_custom,is_key_scene_definition
from .animation import canonical, rejected_options, normalize_record


def audit(doc):
    results=[]
    def block(code,message,source=''):
        doc.issues.append(Issue('error',code,message,source))
    first_note=next((e for name,e in doc.elements.items() if name.startswith('note-')),None)
    if first_note is not None:
        block('scene-draw-order',
            'Legacy Key sorts parent groups, stable child arrival and pooled note attachments. Flat per-element zindex and global body/head/tail bands change occlusion; the parent-traversal candidate requires native overlap, pool/retry and whole-scene RGBA acceptance',
            next(iter(first_note.origins.values()),first_note.name))
        block('native-key-judge',
            'Custom Free rendering selects JudgeLogicFree, which does not perform Key judgement. The shipped Key-judge adapter remains version-specific and requires native input, hold, score and retry acceptance',
            next(iter(first_note.origins.values()),first_note.name))
        block('chart-time-quantization',
            'Native 4.3.7 truncates note milliseconds while maV rounds ScriptNote times; old/new real-chart evidence differs by 1 ms on 145 of 312 heads. Chords, event clocks and progress require an independently verified timing bridge',
            next(iter(first_note.origins.values()),first_note.name))
    if 'soundend' in doc.features:
        block('sound-clock','@apply soundend adds one held-tail sound; real engine callback ordering and pause behavior need verification',doc.directive_origins.get('apply',''))
    if '3d' in doc.features:
        block('play-plane-runtime','@apply 3d uses original whole-plane projection, Y compensation, UI attachment and 0.7 scroll scale; cross-engine geometry, texture and complete scene acceptance remain pending',doc.directive_origins.get('apply',''))
    for name,item in doc.elements.items():
        if not is_key_scene_definition(item):continue
        def n(attr,default=0):
            try:
                if attr.startswith('type'):return native_integer(item.attrs[attr])
                p,u=linear(item.attrs[attr]);return p*100+u
            except KeyError:return default
            except ValueError:return None
        if n('anchor',4) not in range(9):
            doc.issues.append(Issue('warning','native-custom-anchor',f'{name}: bare custom anchor uses native zero-initialized point (0,0)',item.origins.get('anchor','')))
        if n('fix') not in (0,None):
            if name.startswith(('note-','score-')):block('fixed-layout',f'{name}: half-texel fixed UV is not implemented for notes or HUD glyph/fill surfaces',item.origins.get('fix',''))
            else:block('fixed-uv-runtime',f'{name}: native half-texel UV inset is emitted through RawImage; engine sampling and binding need verification',item.origins.get('fix',''))
        if n('toggle') not in (0,None):block('note-lifecycle',f'{name}: toggle bits drive completion visibility and held-head scroll offset; pause, SV discontinuities and pooled note lifecycle need engine verification',item.origins.get('toggle',''))
        if name.startswith('note-'):
            if 'flip' in item.attrs:
                doc.issues.append(Issue('warning','native-ignored-note-flip',f'{name}: native note factory loads frames directly and ignores ApplyTexture flip',item.origins['flip']))
            if n('type',2)!=2:block('note-type',f'{name}: note type {item.attrs.get("type")} is not verified by the free-note backend',item.origins.get('type',''))
            if n('type2') not in (0,1,2):block('body-axis',f'{name}: unsupported body edge axis type2={item.attrs.get("type2")}',item.origins.get('type2',''))
            if n('blend')!=0:block('note-blend',f'{name}: additive free-note material has not been mapped',item.origins.get('blend',''))
            if 'motion' in item.attrs:block('note-animation',f'{name}: note motion and trajectory composition is not implemented',item.origins['motion'])
            if any(a.startswith('frame') for a in item.attrs):block('note-frames',f'{name}: animated note states are not implemented',next(v for a,v in item.origins.items() if a.startswith('frame')))
            if 'tex4' in item.attrs:block('chord-runtime',f'{name}: native equal-integer-ms chord classification and recycled head texture reset are implemented; engine chart timing still needs verification',item.origins['tex4'])
        if name=='score-hp':
            if n('type')!=0:block('hp-type',f'{name}: only native ProgressBarLine (type=0) is implemented',item.origins.get('type',''))
            else:block('hp-clock',f'{name}: fill direction, 2500 ms full-range slew and motion are implemented; pause/speed clock parity needs engine verification',next(iter(item.origins.values()),''))
            if n('type')==0 and ('color' in item.attrs or n('opacity',100)!=100):
                doc.issues.append(Issue('warning','native-hp-child-color','Native ProgressBarLine fill child keeps white/255; parent tint/opacity are not transferred to that child',item.origins.get('color',item.origins.get('opacity',''))))
        if name.startswith('score-') and name!='score-hp':
            block('number-value-lifecycle',f'{name}: bitmap layout, 42 ms stepping, 160 ms combo pulse and 800 ms milestone color are implemented; engine clock and callback ordering need verification',next(iter(item.origins.values()),''))
        if name=='bar':block('bar-travel','Native fractional bar carriers, public layer progress and pos2 travel are emitted; old bar generation, 1000-unit retirement, sprite alpha/filtering and pause/SV/retry parity still require native verification',item.origins.get('pos2',''))
        if name=='touch':block('touch-runtime','Rectangle/polygon coordinates are emitted to native TouchAreaPolygon; camera projection, edge ownership and slide lifecycle need engine verification',next(iter(item.origins.values()),''))
        if name.startswith(('press-','hit-')) and n('type',1) not in (0,1,3):
            doc.issues.append(Issue('warning','native-ignored-event-type',f'{name}: native EventFactory ignores type={item.attrs.get("type")}; frame banks control its behavior',item.origins.get('type','')))
        if name.startswith(('key-','judge-')) and n('type',1) not in (0,1,3):
            block('event-type',f'{name}: event type {item.attrs.get("type")} has no verified trigger/lifetime mapping',item.origins.get('type',''))
        if re.fullmatch(r'judge-\d+',name) and n('type',1)==1 and 'motion' in item.attrs:
            doc.issues.append(Issue('warning','native-static-judge-motion-reset',
                f'{name}: first native static-judge hit removes this node\'s attached MUI tracks, retaining its current position/rotation/skew/content size; retry restores source attachments',item.origins['motion']))
        if n('type2') not in (0,None) and not name.startswith('note-') and name!='score-hp' and not (is_scene_custom(item) and n('type')==4):
            block('secondary-type',f'{name}: type2 behavior is not implemented',item.origins.get('type2',''))
    attached=[]
    for item in doc.elements.values():
        if not is_key_scene_definition(item):continue
        kind=native_integer(item.attrs.get('type'))
        if item.name=='touch' or is_scene_custom(item) and (
            kind==0 and 'tex' not in item.attrs or kind==1 and 'text' not in item.attrs or kind==2 and 'color' not in item.attrs or kind==4 and not {'part','tex'}.issubset(item.attrs)):continue
        binding=item.motion_bindings.get('motion')
        if binding:attached.append((item.name,binding['records']))
    for name,records in attached:
        item=doc.elements[name]
        kind=native_integer(item.attrs.get('type'))
        frame_size_motion=any(canonical(normalize_record(r).get('name')) in ('w','h','size')
            and not rejected_options(normalize_record(r)) for r in records)
        for record in records:
            record=normalize_record(record)
            if rejected_options(record):continue # original rejects the complete record
            if canonical(record.get('name')) in ('s','sx','sy'):
                if not (is_scene_custom(item) and (kind in (0,2,4) or kind==3 and not frame_size_motion)):
                    block('scale-animation',f'{name}: factory-relative scale composition on this node type still requires native frame/HUD verification',record['source'])
    return {
        'release_gate':'not_accepted',
        'evidence_root':'analysis',
        'contracts':[
            {'group':'layout × anchors × units × resizing','status':'cpu_subset_only','evidence':['malody-v/render-evidence/functions/180321130_Malody_Scene_Play_Skin_SkinRuntime__set_ParentSize.c','malody-v/native-extra/functions/180595de0_Malody_Composer_fky__ApplyBasicParam.c'],'pending':['camera/canvas dimensions','old defaults/inheritance','3D projection']},
            {'group':'trajectory × size interpolation × hold mesh','status':'cpu_subset_only','evidence':['malody-4.3.7/render-native/functions/004f29f0_Legacy_CreateNoteSprite.c','malody-4.3.7/render-native/functions/004f1580_NoteSpritePart3_virtual_5.c','malody-v/native-extra/functions/18034cf50_Malody_Scene_Play_Note_PlayNoteFreeSubGrid__SetVertex.c'],'pending':['body UVs and type=3 tiling','toggle event/scroll coupling','BPM/SV/timing and segmented holds','game lifecycle']},
            {'group':'animation × events × frame banks','status':'pending_native_lifecycle','evidence':['malody-4.3.7/native/functions/0050be70_FUN_0050be70.c','malody-4.3.7/render-native/functions/006c2b90_cocos2d__AnimationBase_virtual_1.c','malody-4.3.7/render-native/functions/006c2260_Legacy_AnimationInterpolate.c'],'pending':['event restart/release rules','absolute scale vs content size','pause/retry clock coupling']},
            {'group':'atlas × rotation × trimming × flip × color','status':'partial_native_fixture_only','evidence':['../output/legacy-native-mui-r5/report.json','../output/cross-native-mui-20261016-r2/report.json'],'pending':['strict GPU sampling/material parity','all original skin factories and complete scene']},
            {'group':'HUD × font metrics × variables × clipping','status':'blocked','pending':['bitmap advances','font face/rasterization','HP fill']},
            {'group':'sound × hold end × judge × retry','status':'pending_native_lifecycle','pending':['soundend and duplicate triggers']},
            {'group':'touch regions × key indexing','status':'blocked','pending':['rectangle/polygon touch handling']}
        ]}
