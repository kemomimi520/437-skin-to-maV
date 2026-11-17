from __future__ import annotations
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import time
import zipfile
from google.protobuf import descriptor_pool, message_factory, json_format
from .assets import Assets, frame_spec
from .common import ROOT, DATA, skin_class, lua, uses_scene_text
from .mui import Issue, Element, parse, pair, numeric_pair_program, linear, split_values, position_program, native_integer, native_float, native_scalar, native_dimension, native_toggle, is_scene_custom, is_key_scene_definition, touch_coordinates
from .contracts import audit
from .animation import canonical, rejected_options, normalize_record, NATIVE_KINDS, NATIVE_EASES
from .output_contract import require_native_key_backend


def retained_text_plane_eligible(entry, motions):
    """Only source semantics proved by the owned-plane font implementation."""
    if not entry.get('bitmap_font'):
        return False
    if any(name in entry.get('attrs',{}) for name in ('parent','skew','skewx','skewy')):
        return False
    # Translation, rotation and alpha are represented by the old Widget MVP.
    # Size/scale/shear and unknown future motion kinds need their own proof.
    return all(motion['kind'] in ('m','mx','my','r','f','fade')
               for motion in motions.get(entry.get('motion'),[]))


def compile_skin(source: Path, destination: Path, keys: int, ratio=16/9, draft=False, *, ui_rounding_height=None, native_font_bank=None, native_font_runtime_cache=False, native_clock_candidate=False, native_scroll_candidate=False, native_atlas_precision_candidate=False, native_musicbar_geometry_candidate=False, native_musicbar_clip_w_candidate=False, native_key_judge_candidate=False, native_bar_source_candidate=False, native_layer_order_candidate=False, native_note_pool_candidate=False, native_lifetime_candidate=False, native_prelude_candidate=False, candidate_projection=None, native_font_generator=False, runtime_phase_profile=False, native_musicbar_camera_local_candidate=False, native_ui_atlas_candidate=False,native_packed_mesh_candidate=False,native_canvas_text_candidate=False,native_numeric_float_candidate=False,native_combined_position_candidate=False,native_frame_mesh_candidate=False,native_dynamic_mesh_candidate=False,native_carrier_window_candidate=False,native_instruction_profile_candidate=False,native_ui_schedule_candidate=False,native_note_layout_candidate=False,native_math_module=None,native_transform_submit_candidate=False,native_vertex_upload_candidate=False,native_text_read_candidate=False,native_ui_submit_candidate=False,native_retained_text_candidate=False,native_stable_text_basis_candidate=False,native_plane_text_candidate=False,source_platform='windows',native_font_outline_candidate=False,font_build_context=None,progress=lambda message:None):
    require_native_key_backend()
    if native_prelude_candidate and not native_lifetime_candidate:raise ValueError('Prelude research candidate requires the bounded visual lifetime candidate')
    if native_lifetime_candidate and (not native_scroll_candidate or not native_layer_order_candidate or native_note_pool_candidate):raise ValueError('Visual lifetime candidate requires scroll/layer candidates and replaces idle-pool mapping')
    if native_note_pool_candidate and not native_layer_order_candidate:raise ValueError('Native idle-pool mapping requires legacy layer ordering')
    if native_musicbar_clip_w_candidate:native_musicbar_geometry_candidate=True
    if native_scroll_candidate and not native_clock_candidate:raise ValueError('Legacy scroll reconstruction requires the legacy clock candidate')
    source=Path(source).resolve();destination=Path(destination).resolve()
    if destination==source or destination.is_relative_to(source): raise ValueError('Output must be outside the input skin')
    if destination.exists(): raise FileExistsError('Output already exists; choose a new output directory')
    if not 1<=keys<=64: raise ValueError('Key count must be between 1 and 64')
    if not 0<ratio<=10:raise ValueError('Target ratio must be finite and between 0 and 10')
    if native_font_runtime_cache and native_font_bank is None:raise ValueError('Runtime native font cache requires a verified native font bank')
    if native_font_outline_candidate and not (native_font_generator and native_font_bank):raise ValueError('Outline font research requires original font generator and metrics reference')
    from .context import ui_rounding_context
    rounding_context=ui_rounding_context(source,ui_rounding_height)
    ui_rounding_height=rounding_context['height']
    doc=parse(source,keys,ratio,logical_height=ui_rounding_height,platform=source_platform)
    doc.ui_rounding_height=ui_rounding_height
    uses_text=uses_scene_text
    if native_lifetime_candidate:
        doc.issues.append(Issue('error','lifetime-research-only',
            'Visual lifetime research candidate is bounded to 16384 MC/mania OSU notes, normalized beat fractions, old speed/scale 1 and judge ahead 160; full old/new scene pixels and all styles remain unverified'))
    if rounding_context['method']=='canonical-fallback':
        doc.issues.append(Issue('warning','ui-rounding-context','Original logical viewport is unverified; static UI positions use the 720 reference grid'))
    contracts=audit(doc)
    destination.mkdir(parents=True)
    defaults=DATA/'legacy'
    if not defaults.exists(): defaults=ROOT/'analysis/malody-4.3.7/resources'
    assets=Assets(source,defaults,destination,doc.packs)
    for pack in assets.missing_packs:
        doc.issues.append(Issue('warning','native-missing-pack-declaration',
            f'@texpack {pack}: no local plist; preserve native fallback and validate each consumed resource'))
    font_candidate=None;font_generator=None;font_groups={};fonts={}
    if native_font_bank is not None:
        from .fonts import NativeFontBank
        font_candidate=NativeFontBank(native_font_bank)
        if font_candidate.data['legacy_logical_height']!=ui_rounding_height:
            raise ValueError('Native font bank belongs to a different old logical viewport')
        if not font_candidate.data.get('native_ui_projection'):
            raise ValueError('Native font bank lacks verified projection context; use a context-bearing bank')
        projection=font_candidate.data['native_ui_projection']
        if native_font_generator and any(uses_text(e) for e in doc.elements.values()):
            from .font_generator import FontGenerator
            font_generator=font_build_context['generator'] if font_build_context else FontGenerator(DATA,ROOT,font_candidate.data)
            if font_generator.reference!=font_candidate.data:raise ValueError('Shared font generator metrics reference mismatch')
            for item in doc.elements.values():
                if not uses_text(item):continue
                requested_size=int(native_dimension(doc,item,'fsize',24))
                pixels=int(math.floor(requested_size*font_candidate.data['legacy_render_scale']+.5))
                if re.search(r'\{[^{}]+\}',item.attrs['text']):font_groups[pixels]=None
                elif pixels not in font_groups or font_groups[pixels] is not None:
                    font_groups.setdefault(pixels,{32}).update(ord(c) for c in item.attrs['text'])
        if any(uses_text(e) for e in doc.elements.values()) and not math.isclose(ratio,projection['logical_width']/projection['logical_height'],rel_tol=0,abs_tol=1e-10):
            raise ValueError(f'Native font candidate requires its verified projection aspect ratio; this bank covers {projection["logical_width"]:g}:{projection["logical_height"]:g}, other aspect ratios remain unverified')
    literal_font_texts=[e.attrs['text'] for e in doc.elements.values() if uses_text(e)]
    cold_font_texts=literal_font_texts if len(literal_font_texts)==1 and not any(c in literal_font_texts[0] for c in '{}') else None
    if native_font_runtime_cache:cold_font_texts=None
    skin=skin_class()();title=source.name;description=''
    preview=source/'preview.json'
    if preview.is_file():
        try:
            info=json.loads(preview.read_text(encoding='utf-8-sig'));title=info.get('title',title);description=info.get('desc','')
        except (ValueError,UnicodeError): doc.issues.append(Issue('warning','metadata','preview.json is not valid UTF-8 JSON'))
    skin.meta.title=f'{title} · {keys}K 移植';skin.meta.desc=description
    skin.meta.creator='Original skin authors; converted with Ma Skin Bridge'
    skin.meta.key.keys=keys;skin.meta.key.locked=True;skin.meta.key.lock3_d=True;skin.meta.key.lock_scale=True;skin.meta.key.scale=1
    skin.meta.free=True;skin.meta.feature=3;skin.meta.script='legacy.lua';skin.meta.minver=328450
    skin.disabled.extend(range(1,21))
    settings=skin.settings;settings.hide_def=True
    entries=[];notes={};motions={};touches=[];counter=0;element_resolution={}
    supported={'type','type2','size','size2','pos','pos2','anchor','zindex','tex','tex2','tex3','tex4','tex5','frame','frame2','frame3','frame4','interval','motion','opacity','rotate','flip','blend','color','fsize','toggle','text','fix','count'}

    def number(raw,default=0):
        if raw is None:return default
        p,u=linear(raw)
        return p*100+u

    def module(item,name,texture,size,alpha=100):
        nonlocal counter
        counter+=1
        m=skin.modules.add(usage=99,type=5000)
        m.meta.desc=name;m.param.pivot=int(number(item.attrs.get('anchor'),4));m.param.alpha=int(alpha)
        m.param.layer=4;m.param.order=native_scalar(item,'zindex',10)
        m.param.rotate=-native_scalar(item,'rotate')
        m.image.file=texture['file'];m.image.width=texture['width']*1.5;m.image.height=texture['height']*1.5
        m.image.wu=m.image.hu=1
        if native_integer(item.attrs.get('blend'))==1:m.image.blend=1
        # maV Image.Color selects a SOLID-COLOR image resource; it is not tint.
        # Keep the file-backed resource and apply legacy RGB through SetColor.
        return name

    def sequence(item,spec,body=False):
        # Legacy ApplyTexture: explicit 0 = X, 1 = Y, 2 = both; absence = neither.
        flip={0:1,1:2,2:3}.get(native_integer(item.attrs.get('flip'),-1),0)
        # Note factory loads SpriteFrames directly and never calls ApplyTexture's
        # flip branch. ShapeSprite UVs use the atlas rectangle without padding.
        strip=is_scene_custom(item) and native_integer(item.attrs.get('type'))==4
        if item.name.startswith('note-') or item.name=='bar' or strip:flip=0
        shape=body and item.name.startswith('note-') or strip
        return assets.sequence(spec,flip,shape,premultiplied=True)

    motion_specs={};bound_motion_names={};used_motion_names=set()
    for item in doc.elements.values():
        if not is_key_scene_definition(item):continue
        binding=item.motion_bindings.get('motion')
        if not binding:continue
        kind=native_integer(item.attrs.get('type'))
        if item.name=='touch' or is_scene_custom(item) and (
            kind==0 and 'tex' not in item.attrs or kind==1 and 'text' not in item.attrs or kind==2 and 'color' not in item.attrs):continue
        original=binding['name']
        if original is not None:used_motion_names.add(original)
        if original is not None and binding['delay']==0 and binding['records']==doc.animations.get(original):motion_name=original
        else:
            motion_name='@bound:'+item.name
            while motion_name in doc.animations or motion_name in motion_specs:motion_name+=':'
        bound_motion_names[item.name]=motion_name
        motion_specs[motion_name]=(binding['records'],binding['delay'])
    # ParseAni still reads unused definitions. Keep its rejection diagnostics,
    # while an unconsumed, valid native feature needs no runtime implementation.
    for name,records in doc.animations.items():
        if name in used_motion_names:continue
        motions[name]=[]
        for record in records:
            rejected=rejected_options(record)
            if rejected:doc.issues.append(Issue('warning','native-rejected-animation-record',
                f'Original ParseAni rejects the entire record containing {sorted(rejected)}; no replacement animation is attached',record['source']))
    for name,(records,binding_delay) in motion_specs.items():
        motions[name]=[]
        for record in records:
            record=normalize_record(record)
            rejected=rejected_options(record)
            if rejected:
                # ParseAni can allocate a scalar object before it rejects the
                # unknown token. A constructor capture is not attachment proof.
                # Actual KeyUIS animation queues omit this ENTIRE record.
                doc.issues.append(Issue('warning','native-rejected-animation-record',
                    f'Original ParseAni rejects the entire record containing {sorted(rejected)}; no replacement animation is attached',record['source']))
                continue
            native_kind=NATIVE_KINDS.get(record.get('name'))
            if native_kind is None:
                doc.issues.append(Issue('warning','native-rejected-animation-name',
                    f'Original ParseAni rejects animation name {record.get("name")}; no track is attached',record['source']))
                continue
            kind=canonical(record['name'])
            if kind in ('hide','show'):
                # AdvanceAnimations (0x6c3030) deliberately skips types 10/11
                # in BOTH queues. Their direct virtual can change visibility,
                # but ordinary attached MUI tracks never call it. Do not
                # invent the effect suggested by the animation's name.
                doc.issues.append(Issue('warning','native-manager-noop',
                    f'Original AnimationManager skips attached {kind} tracks; preserve the unchanged visibility',record['source']))
                continue
            if kind not in ['m','mx','my','r','f','fade','w','h','size','s','sx','sy','skew','skewx','skewy']:
                doc.issues.append(Issue('error','animation-kind',f'Accepted native animation {kind} has no implemented rendering behavior',record['source']));continue
            default='0,0' if kind in ('m','size','skew') else '0'
            from_value=record.get('from',default).strip('()');to_value=record.get('to',default).strip('()')
            try:
                raw_times=split_values(record.get('_time_value','0').strip('()'))
                times=[native_integer(x) for x in raw_times]
                if len(times)==1:times=[0,times[0]]
                elif len(times)==2:
                    if raw_times[1].startswith('+'):times[1]+=times[0]
                else:raise ValueError('Animation time requires a scalar or pair')
                times=[t+binding_delay for t in times]
                rep=split_values(record.get('repeat','0').strip('()'))
                reverse=rep[0].startswith('r')
                repeat_count=native_integer(rep[0][1:] if reverse else rep[0])
                repeat_delay=native_integer(rep[1]) if len(rep)>1 else 0
                system_terminal='atime' not in record and max(times)<=0 and repeat_count==0
                def endpoint(value):
                    if value=='fill':raise ValueError('Native from-current attachment capture is not implemented')
                    values=split_values(value)
                    if kind in ('r','f','fade','skewx','skewy') or kind=='s' and len(values)==1:
                        return [[0,native_float(x)] for x in values]
                    from .position import coordinate
                    return [list(coordinate(dict(record.get('_numeric',{}),text=x),ratio=ratio,logical_height=ui_rounding_height)) for x in values]
                frm=endpoint(from_value);to=endpoint(to_value)
                if kind in ('s','sx','sy'):
                    # ParseAni uses NumericExpression for axis/pair scale
                    # factors, but atof for a scalar uniform scale. Preserve
                    # its native-pixel factor before attachment-time capture.
                    def scale_endpoint(values):
                        if kind=='s' and len(values)==1:return values
                        factor=ui_rounding_height/720
                        return [[0,native_float((p*(ratio*720 if kind=='sx' or kind=='s' and i==0 else 720)+u)*factor)] for i,(p,u) in enumerate(values)]
                    frm=scale_endpoint(frm);to=scale_endpoint(to)
                # 4.3.7 ParseAni clamps opacity endpoints *before* interpolation.
                if kind in ('f','fade'):
                    frm=[[0,max(0,min(100,p*100+u))] for p,u in frm]
                    to=[[0,max(0,min(100,p*100+u))] for p,u in to]
                motion={'kind':kind,'start':times[0],'finish':times[1],
                    'from':frm,'to':to,
                    'repeats':repeat_count,'delay':repeat_delay}
                if system_terminal:motion['clock']='attachment_terminal'
                elif 'atime' not in record:motion['clock']='system'
                if reverse:motion['reverse_repeat']=True
                if 'trans' in record:
                    transition=record['trans']
                    if transition in NATIVE_EASES:motion['bezier']=list(NATIVE_EASES[transition])
                    elif transition.startswith('('):
                        control=[float(x) for x in split_values(transition.strip('()'))]
                        if len(control)!=4 or not all(math.isfinite(x) for x in control):
                            doc.issues.append(Issue('warning','native-rejected-animation-record','Original ParseAni rejects a trans tuple without four finite controls',record['source']));continue
                        motion['bezier']=[struct.unpack('<f',struct.pack('<f',x))[0] for x in control]
                    else:
                        doc.issues.append(Issue('warning','native-ignored-transition',f'Original ParseAni leaves unknown scalar transition {transition} linear',record['source']))
                motions[name].append(motion)
            except (ValueError,IndexError) as error:doc.issues.append(Issue('error','animation',str(error),record['source']))
        # Original AnimationManager inserts by start time, retaining arrival
        # order for equal starts. Reopened blocks/includes append definitions.
        motions[name].sort(key=lambda motion:(0 if motion.get('clock') in ('system','attachment_terminal') else 1,motion['start']))

    for element_index,(name,item) in enumerate(doc.elements.items(),1):
        progress(f'正在处理组件 {element_index}/{len(doc.elements)}：{name}')
        resolution={'status':'unresolved','source':next(iter(item.origins.values()),name)}
        element_resolution[name]=resolution
        try:
            if not is_key_scene_definition(item):
                resolution.update(status='native_unselected_group',reason=f'Original KeyUIS selects __def_group; group {item.group!r} is not instantiated')
                continue
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==2 and 'color' not in item.attrs:
                doc.issues.append(Issue('warning','native-null-element',
                    f'{name}: original rectangle factory requires color and creates no node without it',item.origins.get('type','')))
                resolution.update(status='native_null_factory',reason='Rectangle has no color; original creates no node')
                continue
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==4 and not {'part','tex'}.issubset(item.attrs):
                doc.issues.append(Issue('warning','native-null-element',f'{name}: original strip factory requires part and tex; no node is created',next(iter(item.origins.values()),name)))
                resolution.update(status='native_null_factory',reason='Strip has no part or primary texture')
                continue
            if name=='touch':
                shape=native_integer(item.attrs.get('type'),1)
                if shape not in (1,3):raise ValueError(f'Touch shape {shape} is not implemented')
                prefix='rect' if shape==1 else 'array'
                for lane in range(1,keys+1):
                    attr=prefix+('' if lane==1 else str(lane))
                    if attr not in item.attrs:
                        if shape!=1:raise ValueError(f'Missing touch region for column {lane}')
                        # Original KeyUIS BuildUI (0x5ab0e8..0x5ab13b) submits
                        # Rect::ZERO at 0x82e3c4 for an absent rectangle. Keep
                        # that empty region; never borrow a neighbour's area.
                        values=[[0,0] for _ in range(4)]
                        doc.issues.append(Issue('warning','native-empty-touch-region',
                            f'{name}: column {lane} has no rectangle; original uses a zero rectangle',next(iter(item.origins.values()),'')))
                    else:values=touch_coordinates(doc,item,attr)
                    if shape==1:
                        if len(values)!=4:raise ValueError('Touch rectangle must have x,y,width,height')
                        x,y,w,h=values
                        add=lambda a,b:[a[0]+b[0],a[1]+b[1]]
                        points=[[x,y],[add(x,w),y],[add(x,w),add(y,h)],[x,add(y,h)]]
                    else:
                        if len(values)<6 or len(values)%2:raise ValueError('Touch polygon needs at least three coordinate pairs')
                        points=[[values[i],values[i+1]] for i in range(0,len(values),2)]
                    touches.append({'lane':lane,'points':points,'handle':f'legacy_touch_{lane}'})
                resolution['status']='input_regions'
                continue
            indexed=re.fullmatch(r'(key|hit|press|judge)-(\d+)',name)
            if indexed and not 1<=int(indexed[2])<=keys:
                doc.issues.append(Issue('warning','native-unused-key-lane',
                    f'{name}: original KeyUIS builds only lanes 1..{keys}; this definition is not instantiated',next(iter(item.origins.values()),name)))
                resolution.update(status='native_unused_lane',reason=f'Outside original 1..{keys} lane construction')
                continue
            for attr in item.attrs:
                if attr=='show' and is_scene_custom(item):
                    continue # GenericFactory calls ApplyAttributes -> setVisible(false) for zero.
                elif attr=='part' and is_scene_custom(item) and native_integer(item.attrs.get('type'))==4:
                    continue # Consumed by the original three-sprite factory below.
                elif attr=='part' and re.fullmatch(r'judge-\d+',name):
                    # Original parser stores part as attribute 180 (0xb4).
                    # JudgeFactory 0x50a570 and its ApplyAttributes 0x508430
                    # never consume it. Other factories DO use this attribute;
                    # this exception is scoped to the original judge element.
                    doc.issues.append(Issue('warning','native-unused-judge-part',
                        f'{name}.part: original JudgeFactory does not consume this parsed attribute',item.origins[attr]))
                elif attr=='part' and name=='bar':
                    # BarFactoryCreate calls CreateNoteSprite(0), whose tap
                    # branch never reads attribute 180. Unlike a hold body or
                    # GenericElementFactory type 4, this is one plain Sprite.
                    doc.issues.append(Issue('warning','native-unused-bar-part',
                        'bar.part: original BarFactory uses the plain Sprite branch and does not consume part',item.origins[attr]))
                elif attr not in supported:doc.issues.append(Issue('error','attribute',f'Unsupported {name}.{attr}',item.origins[attr]))
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==1 and 'text' not in item.attrs:
                doc.issues.append(Issue('warning','native-empty-label',
                    f'{name}: original text factory has no text; unused texture definitions cannot create a Sprite',next(iter(item.origins.values()),name)))
                resolution.update(status='native_empty_label',reason='Text factory without text; no visible glyphs')
                continue
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==0 and 'tex' not in item.attrs:
                # 0x5092d0 fallback searches attribute 1 (tex), then creates a
                # plain Node if absent. frame/text do not turn it into a Sprite
                # or Label. Its parse-time coordinates still serve references.
                # True parent/action bindings remain separately blocked above.
                doc.issues.append(Issue('warning','native-nonvisual-node',
                    f'{name}: original generic factory creates a nonvisual Node; retain parsed references without inventing an image or loading unused frame resources',next(iter(item.origins.values()),name)))
                resolution.update(status='native_nonvisual_node',reason='Original plain Node; coordinates retained for parse-time references. Parent/action semantics have separate blockers')
                continue
            position=pair(doc,item,'pos');size=pair(doc,item,'size')
            anchor=int(number(item.attrs.get('anchor'),4))
            # A bare non-enum anchor keeps the parameter's zero-initialized vector.
            if anchor not in range(9):anchor=6
            entry={'name':name,'pos':position,'size':size,'anchor':anchor,
                   'opacity':native_scalar(item,'opacity',100),'rotate':native_scalar(item,'rotate'),
                   'order':native_scalar(item,'zindex',10),'motion':bound_motion_names.get(name,''),
                   'interval':native_scalar(item,'interval',10),'states':{},'handles':{},'attrs':item.attrs,
                   'frame_modes':{}}
            entry['attrs']=dict(item.attrs)
            if is_scene_custom(item) and native_integer(item.attrs.get('show'),1)==0:
                entry['visible']=False
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==3:
                entry['autoplay_frames']=True
            judge_match=re.fullmatch(r'judge-(\d+)',name)
            if judge_match:entry['judge_lane']=int(judge_match[1])
            for attr in item.attrs:
                if re.fullmatch(r'type[2-9]?',attr):entry['attrs'][attr]=str(native_integer(item.attrs[attr]))
                elif attr in ('blend','flip'):entry['attrs'][attr]=str(native_integer(item.attrs[attr]))
            entry['fixed_uv']=bool(number(item.attrs.get('fix')))
            if not name.startswith('note-') and name!='bar':
                entry['native_pos_program']=position_program(doc,item)
                if entry['native_pos_program'] is None:
                    doc.issues.append(Issue('error','native-position-expression',
                        f'{name}: exact native position evaluation for range/arithmetic/variable expressions remains unverified',item.origins.get('pos','')))
            if 'blend' in item.attrs and not name.startswith(('note-','score-')) and name!='bar' and 'text' not in item.attrs:
                # Presence matters. Native GetBlend: 0=ONE+ONE,
                # 1=SRC_ALPHA+ONE, 2=ONE_MINUS_DST_COLOR+ONE (GL 0x0307).
                entry['legacy_blend']=native_integer(item.attrs['blend'])
                if entry['legacy_blend']==2:
                    doc.issues.append(Issue('error','destination-color-blend',f'{name}: native blend=2 depends on the complete destination color/order chain; full-scene parity is not verified',item.origins['blend']))
            if name=='bar':
                entry['pos2']=pair(doc,item,'pos2')
                entry['size2']=pair(doc,item,'size2',item.attrs.get('size','0,0'))
            for suffix in ['', '2','3','4','5']:
                if judge_match and native_integer(item.attrs.get('type'),1)==1 and suffix:
                    continue # Static JudgeFactory consumes only its four-grade frame bank.
                if is_scene_custom(item):
                    kind=native_integer(item.attrs.get('type'))
                    consumed=kind not in (1,2) and (kind!=0 or suffix in ('','2')) and (kind!=4 or suffix=='')
                    if not consumed:
                        for stem in ('tex','frame'):
                            attr=stem+suffix
                            if attr in item.attrs:doc.issues.append(Issue('warning','native-unused-custom-resource',
                                f'{name}.{attr}: original generic factory type={kind} does not consume this image definition',item.origins[attr]))
                        continue
                if name.startswith('key-') and suffix in ('3','4','5'):
                    ignored=[a+suffix for a in ('tex','frame') if a+suffix in item.attrs]
                    for attr in ignored:
                        # KeyUIS::BuildUI (0x5a9ea0..0x5a9fd5) only queries
                        # texture attributes 1 and 2 for key sprites/actions.
                        # Resolving an unused key.tex3 can reject a valid skin.
                        doc.issues.append(Issue('warning','native-unused-key-texture',
                            f'{name}.{attr}: original KeyUIS reads only tex/tex2; this unused definition is not loaded',item.origins[attr]))
                    continue
                if 'tex'+suffix in item.attrs: entry['states'][suffix or '1']=[sequence(item,item.attrs['tex'+suffix],suffix=='2')[0]]
                elif 'frame'+suffix in item.attrs and not (is_scene_custom(item) and native_integer(item.attrs.get('type'))==0):
                    spec=item.attrs['frame'+suffix]
                    parsed_frame=frame_spec(spec)
                    if parsed_frame is None:raise ValueError(f'Original parser rejects frame definition: {spec}')
                    entry['states'][suffix or '1']=sequence(item,spec,suffix=='2')
                    entry['frame_modes'][suffix or '1']=parsed_frame[3]
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==2:
                # GenericElementFactory case 2 uses the shipped g-white.png,
                # SetRectFixed(true), then the declared color and dimensions.
                texture=assets.texture('g-white.png',premultiplied=True)
                entry['states']={'1':[texture]}
                entry['fixed_uv']=True
            if is_scene_custom(item) and native_integer(item.attrs.get('type'))==4:
                parts=split_values(item.attrs['part'])
                if len(parts)!=2:raise ValueError('Native strip part requires two numeric prefixes')
                first,last=map(native_float,parts)
                kind=native_integer(item.attrs.get('type2'))
                if kind not in (1,2,3):kind=0
                texture=entry['states']['1'][0]
                axis=texture['height'] if kind in (1,3) else texture['width']
                if not 0<=first<last<=axis:raise ValueError('Native strip texture boundaries are outside the verified frame extent')
                entry['strip']={'kind':kind,'first':first,'last':last}
                if 'size2' in item.attrs:entry['strip']['secondary']=pair(doc,item,'size2')
                entry['fixed_uv']=False # Each strip has its own native half-texel inset.
            if name.startswith('note-'):
                lane=int(name[5:]);entry['end']=pair(doc,item,'pos2');entry['size2']=pair(doc,item,'size2',item.attrs.get('size','0,0'))
                entry['native_size_program']=numeric_pair_program(doc,item,'size')
                entry['native_size2_program']=numeric_pair_program(doc,item,'size2') if 'size2' in item.attrs else None
                notes[lane]=entry
                # Factory 0x4f29f0: type=3 selects Tile3. For type=2,
                # type2=1/2 instead chooses the body edge axis (0x4f1580).
                entry['body_axis']=native_integer(item.attrs.get('type2'))
                entry['toggle']=native_toggle(item.attrs.get('toggle'))
                if native_integer(item.attrs.get('type'))==2 and (entry['opacity']!=100 or item.attrs.get('color','#FFFFFF').upper()!='#FFFFFF'):
                    doc.issues.append(Issue('warning','native-part3-body-color',f'{name}: original ShapeSprite body ignores inherited Node tint/opacity; preserve white opaque vertex RGBA separately from head/tail',item.origins.get('opacity',item.origins.get('color',''))))
                resolution['status']='note_definition'
                continue
            if name.startswith('score-') and name not in ('score-hp',):
                # KeyUIS GetElement(0x7c) builds a separate NumberSprite.
                # maV SkinTextVar.MaxCombo=3 resolves the actual {maxcombo}
                # token; it must not follow the current combo after a miss.
                var={'score-score':'score','score-combo':'combo','score-maxcombo':'maxcombo','score-acc':'acc'}.get(name)
                if var is None:raise ValueError(f'Unknown score variable {name}')
                match=re.fullmatch(r'(.+)/\d+-\d+(?:\.png)?',item.attrs.get('frame',''))
                if not match:raise ValueError(f'No bitmap font prefix for {name}')
                glyphs={}
                # Native NumberSprite loads indices 0..15, independently of frame's range.
                for i in range(16):
                    try:glyphs[i]=assets.texture(f'{match[1]}-{i}.png',premultiplied=True)
                    except FileNotFoundError:pass
                if 0 not in glyphs:raise ValueError(f'Missing required zero glyph for {name}')
                entry['number']={'glyphs':glyphs,'height':native_dimension(doc,item,'fsize',20)*720/ui_rounding_height,
                    'spacing':pair(doc,item,'pos2','1,0')[0],
                    'proportional':bool(native_integer(item.attrs.get('type2'))),'variable':var,
                    'duration':int(number(item.attrs.get('interval'),1))}
                entry['handles']={'glyphs':[]}
                for i in range(30):
                    handle=f'legacy_{name}_glyph_{i}'
                    module(item,handle,glyphs[0],size,0)
                    skin.modules[-1].param.pivot=4
                    entry['handles']['glyphs'].append(handle)
                m=skin.modules.add(usage=99,type=5001);m.meta.desc=f'legacy_{name}_value'
                m.param.alpha=0;m.param.layer=4;m.param.order=entry['order'];m.text.text='{'+var+'}';m.text.size=1;m.text.font=1;m.text.color='#FFFFFF'
                entry['value_handle']=m.meta.desc
            elif name=='musicbar':
                count=int(number(item.attrs.get('count'),100))
                if not 1<=count<=4096:raise ValueError('Musicbar count must be between 1 and 4096')
                textures=[assets.atlas_neighbour_texture(n,preserve_extent=native_atlas_precision_candidate,native_uv=native_musicbar_geometry_candidate) for n in ('g-white.png','play-start.png','play-end.png','play-seek.png')]
                body_texture=assets.procedural_white_texture()
                entry['musicbar']={'count':count,'textures':textures,'body_texture':body_texture}
                entry['handles']['musicbar']=[]
                for i,texture in enumerate(textures+[body_texture]*count):
                    handle=f'legacy_musicbar_part_{i}'
                    module(item,handle,texture,size,0)
                    skin.modules[-1].param.pivot=4;skin.modules[-1].param.rotate=0
                    entry['handles']['musicbar'].append(handle)
                doc.issues.append(Issue('error','musicbar-lifecycle',
                    'Recovered procedural density, cursor and judge-commit candidate; old chart range, hold counting, duplicate Key callbacks, touch seeking and strict cross-engine pixels still require native acceptance',next(iter(item.origins.values()),name)))
            elif uses_text(item):
                m=skin.modules.add(usage=99,type=5001);m.meta.desc='legacy_'+name
                m.param.pivot=entry['anchor'];m.param.alpha=int(entry['opacity']);m.param.layer=4;m.param.order=entry['order']
                # maV TextVarHolder (0x587fa0) uses {art}/{ver}; copying the
                # legacy spellings renders the braces literally in the player.
                from .text_variables import translate
                text,empty_tokens,unresolved_tokens=translate(item.attrs['text'])
                tokens=set(re.findall(r'\{([^{}]+)\}',item.attrs['text']))
                # Native resolver 0x5a8e00 / paired maV Setup evidence:
                # current player names and unsupported tokens are not aliases.
                # Keep a hard block until their surrounding lifecycle is mapped.
                if 'player' in tokens:
                    doc.issues.append(Issue('error','text-player-semantics','Legacy Auto resolves to Auto; the maV synthetic Marlo play type resolves to Marlo. Player/replay/account semantics are not certified',item.origins.get('text','')))
                if empty_tokens:
                    doc.issues.append(Issue('warning','native-empty-text-token','Original metadata resolver returns empty for: '+', '.join(sorted(empty_tokens)),item.origins.get('text','')))
                if unresolved_tokens:
                    doc.issues.append(Issue('error','text-variable-semantics','Nested/escaped/formatted old placeholder parsing still requires verification: '+', '.join(sorted(unresolved_tokens)),item.origins.get('text','')))
                # Native SkinRuntimeText.Setup uses Size * cached parent
                # height / 100. It is a screen-height percentage, unlike
                # image dimensions; legacy fsize is measured in 720 units.
                m.text.text=text;m.text.size=native_dimension(doc,item,'fsize',24)*100/ui_rounding_height;m.text.color=item.attrs.get('color','#FFFFFF');m.text.font=1
                if text!=item.attrs['text'] and any('{'+token+'}' in item.attrs['text'] for token in ('artist','version')):
                    doc.issues.append(Issue('warning','text-variable-alias','Native artist/version tokens emitted; metadata formatting and legacy font parity still require acceptance',item.origins.get('text','')))
                entry['handles']['1']=['legacy_'+name]
                if font_candidate is not None:
                    old_size=int(native_dimension(doc,item,'fsize',24))
                    pixel_size=int(math.floor(old_size*font_candidate.data['legacy_render_scale']+.5))
                    if font_generator:
                        font_key=f'sourcehan-{pixel_size}'
                        if font_key not in fonts:
                            if native_font_outline_candidate or font_build_context and pixel_size in font_build_context['outline_sizes']:
                                fonts[font_key]=font_generator.export_outline_metrics(pixel_size,destination)
                            else:
                                fonts[font_key]=font_generator.export_external_size(pixel_size,font_groups[pixel_size],destination,progress=progress)
                        entry['bitmap_font']=font_key
                    else:
                        if pixel_size!=font_candidate.data['pixel_size']:raise ValueError(f'{name}: native font bank size does not match original integer font size')
                        if 'sourcehan' not in fonts:fonts['sourcehan']=font_candidate.export(destination,cold_font_texts)
                        entry['bitmap_font']='sourcehan'
                    doc.issues.append(Issue('warning','native-font-candidate','Exact old coverage/metrics emitted with public non-snapping bitmap rendering; full text acceptance remains blocked',item.origins.get('text','')))
                doc.issues.append(Issue('error','font-face',
                    'Native bitmap candidate does not yet certify prior shared glyph-cache state, other font sizes or full dynamic text lifecycle' if font_candidate is not None
                    else 'Legacy vector font rasterization has not been matched',item.origins.get('text','')))
            else:
                # A Cocos frame animation changes one Sprite's display frame.
                # Keep one native image per state, rather than instantiating
                # every texture as a separate always-active UI module.
                entry['reuse_frames']=not entry.get('fixed_uv',False) and not entry.get('strip')
                for state,textures in entry['states'].items():
                    entry['handles'][state]=[]
                    for i,texture in enumerate(textures[:1] if entry['reuse_frames'] else textures):
                        handle=f'legacy_{name}_{state}_{i}'
                        module(item,handle,texture,size,0)
                        skin.modules[-1].param.pivot=entry['anchor']
                        entry['handles'][state].append(handle)
            if name=='score-hp' and native_integer(item.attrs.get('type'),0)==0 and entry['states'].get('1'):
                entry['fill']={'reverse':native_integer(item.attrs.get('type2'))==1}
                m=skin.modules.add(usage=4,type=4900);m.meta.desc='legacy_score-hp_value';m.param.alpha=0;m.param.layer=4
                m.image.file=entry['states']['1'][0]['file'];m.image.width=m.image.height=1;m.image.wu=m.image.hu=1
                entry['value_handle']=m.meta.desc
            if not entry['handles'] and name=='bar':
                doc.issues.append(Issue('warning','bar','Bar graphic is empty'))
            elif not entry['handles']:raise ValueError(f'No visual resource for {name}')
            if (entry.get('musicbar') or entry.get('bitmap_font')) and any(
                motion['kind'] in ('skew','skewx','skewy') for motion in motions.get(entry['motion'],[])):
                doc.issues.append(Issue('error','animation-surface',
                    f'{name}: skew on bitmap text or procedural musicbar meshes has not been verified; refusing to silently omit the transform',item.origins.get('motion','')))
            if entry.get('bitmap_font'):
                entry['retained_text_plane']=bool(native_retained_text_candidate and
                    native_layer_order_candidate and retained_text_plane_eligible(entry,motions))
            entries.append(entry)
            resolution['status']='generated_visual_entry'
        except (ValueError,OSError) as error:
            resolution.update(status='error',reason=str(error))
            doc.issues.append(Issue('error','element',f'{name}: {error}',next(iter(item.origins.values()),name)))
    for lane in range(1,keys+1):
        if lane not in notes or not notes[lane]['states'].get('1'):
            doc.issues.append(Issue('error','missing-note',f'No resolved note texture/trajectory for column {lane}'))
    for region in touches:
        texture=next((e['states']['1'][0] for e in notes.values() if e['states'].get('1')),None)
        if texture is None:break
        m=skin.modules.add(usage=99,type=4500);m.meta.desc=region['handle'];m.param.alpha=0;m.param.pivot=4;m.param.layer=4
        m.image.file=texture['file'];m.image.width=m.image.height=1;m.image.wu=m.image.hu=1
    sounds={}
    for grade in ['best','cool','good','miss']:
        if grade in doc.directives:
            try:sounds[grade]=assets.audio(doc.directives[grade])
            except OSError as error:doc.issues.append(Issue('error','audio',str(error)))
    cover=None
    for name in ['preview.png','preview.jpg']:
        if (source/name).is_file():
            cover=assets.texture(name)['file'];break
    if cover:skin.meta.cover=cover
    from .context import native_ui_projection
    projection=(native_ui_projection(source,ui_rounding_height,ratio) or candidate_projection) if any(e.get('musicbar') for e in entries) else None
    if native_musicbar_geometry_candidate and not projection:raise ValueError('Musicbar geometry candidate requires the verified native projection context')
    profile={'native_stable_text_basis_candidate':native_stable_text_basis_candidate,'native_retained_text_candidate':native_retained_text_candidate,'keys':keys,'ratio':ratio,'ui_rounding_height':ui_rounding_height,'native_ui_projection':projection,'native_clock_candidate':native_clock_candidate,'native_scroll_candidate':native_scroll_candidate,'native_musicbar_geometry_candidate':native_musicbar_geometry_candidate,'native_musicbar_clip_w_candidate':native_musicbar_clip_w_candidate,'fonts':fonts,'entries':entries,'notes':notes,'motions':motions,'sounds':sounds,'touches':touches,
             'sound_end':'soundend' in doc.features}
    profile['native_key_judge_candidate']=native_key_judge_candidate
    judge_lanes=[e['judge_lane'] for e in entries if e.get('judge_lane')]
    profile['global_judge']=judge_lanes==[1]
    profile['has_autoplay_frames']=any(e.get('autoplay_frames') for e in entries)
    profile['has_system_motions']=any(a.get('clock')=='system' for e in entries for a in motions.get(e['motion'],[]))
    profile['native_bar_source_candidate']=native_bar_source_candidate
    profile['native_layer_order_candidate']=native_layer_order_candidate
    profile['native_note_pool_candidate']=native_note_pool_candidate
    profile['native_note_projection']=(native_ui_projection(source,ui_rounding_height,ratio) or candidate_projection) if native_lifetime_candidate else None
    profile['legacy_play_plane']=None
    if '3d' in doc.features:
        from .legacy_plane import from_document
        try:
            if not native_lifetime_candidate:raise ValueError('Legacy 3D requires the original lifetime/scroll and projection backend')
            profile['legacy_play_plane']=from_document(doc,profile['native_note_projection'])
        except ValueError as error:doc.issues.append(Issue('error','legacy-play-plane',str(error),doc.directive_origins.get('apply','')))
    profile['runtime_phase_profile']=bool(runtime_phase_profile or native_instruction_profile_candidate)
    profile['native_instruction_profile_candidate']=bool(native_instruction_profile_candidate)
    profile['native_ui_schedule_candidate']=bool(native_ui_schedule_candidate)
    profile['native_plane_text_candidate']=bool(native_plane_text_candidate)
    profile['native_note_layout_candidate']=bool(native_note_layout_candidate)
    profile['native_musicbar_camera_local_candidate']=bool(native_musicbar_camera_local_candidate)
    profile['native_packed_mesh_candidate']=bool(native_packed_mesh_candidate)
    profile['native_canvas_text_candidate']=bool(native_canvas_text_candidate)
    profile['native_numeric_float_candidate']=bool(native_numeric_float_candidate)
    profile['native_transform_submit_candidate']=bool(native_transform_submit_candidate)
    profile['native_vertex_upload_candidate']=bool(native_vertex_upload_candidate)
    profile['native_text_read_candidate']=bool(native_text_read_candidate)
    profile['native_ui_submit_candidate']=bool(native_ui_submit_candidate)
    profile['native_math_module']=None
    if (native_transform_submit_candidate or native_vertex_upload_candidate or native_text_read_candidate or native_ui_submit_candidate) and native_math_module is None:
        raise ValueError('Owned native Transform candidate requires a verified native module')
    if native_math_module is not None:
        module=Path(native_math_module).resolve(strict=True)
        receipt=json.loads((module.parent/'build-receipt.json').read_text(encoding='utf-8'))
        digest=hashlib.sha256(module.read_bytes()).hexdigest()
        if receipt.get('binary_sha256')!=digest or receipt.get('target')!='x86_64-windows' or receipt.get('source_sha256')!=hashlib.sha256((ROOT/'tools/native_skin_math.c').read_bytes()).hexdigest():
            raise ValueError('Unverified/stale native arithmetic candidate')
        filename='skinbridge_math_'+digest[:16]+'.dll'
        shutil.copyfile(module,destination/filename)
        import ctypes
        profile['native_math_module']={'file':filename,'sha256':digest,'abi':'Lua 5.3 Windows x64',
                                      'windows_codepage':ctypes.windll.kernel32.GetACP()}

    profile['native_combined_position_candidate']=bool(native_combined_position_candidate)
    profile['native_frame_mesh_candidate']=bool(native_frame_mesh_candidate)
    profile['native_dynamic_mesh_candidate']=bool(native_dynamic_mesh_candidate)
    profile['native_carrier_window_candidate']=bool(native_carrier_window_candidate)
    profile['ui_atlas']={}
    profile['ui_atlas_pages']=[]
    if native_ui_atlas_candidate:
        from .ui_atlas import build_ui_atlas
        profile['ui_atlas'],profile['ui_atlas_pages']=build_ui_atlas(entries,destination)
    from .ui_atlas import atlas_storage
    omitted_resources,atlas_bindings=atlas_storage(profile,skin)
    profile['native_lifetime_candidate']=native_lifetime_candidate
    profile['native_prelude_candidate']=native_prelude_candidate
    profile['legacy_prelude_needed']=any(a['start']<0 for e in entries for a in motions.get(e.get('motion'),[]))
    from .layers import plan,canvas_batches
    profile['layer_plan']=plan(entries,notes)
    profile['layer_plan']['canvas_batches']=canvas_batches(entries,notes,motions,canvas_text=native_canvas_text_candidate) if native_layer_order_candidate else []
    (destination/'legacy-ir.json').write_text(json.dumps(profile,ensure_ascii=False,indent=2),encoding='utf-8')
    runtime_files=['native_bindings.lua','unity.lua','legacy_position.lua','legacy_clock.lua','legacy_scroll.lua']
    if native_clock_candidate or native_lifetime_candidate:runtime_files+=['legacy_note_identity.lua']
    if native_lifetime_candidate:runtime_files+=['legacy_note_sort.lua','legacy_lifetime.lua','legacy_source_order.lua']
    elif native_clock_candidate:runtime_files+=['legacy_note_sort.lua']
    if native_clock_candidate:runtime_files+=['legacy_osu.lua']
    if native_prelude_candidate:runtime_files+=['native_prelude.lua']
    if native_note_pool_candidate:runtime_files+=['native_note_pool.lua']
    if native_layer_order_candidate:runtime_files+=['layers.lua']
    if native_key_judge_candidate:runtime_files+=['native_key_judge.lua']
    if native_bar_source_candidate:runtime_files+=['native_bar_source.lua']
    if native_musicbar_geometry_candidate:runtime_files+=['musicbar_geometry.lua','musicbar_mesh.lua']
    runtime_files+=['strip_geometry.lua','font_cache.lua']
    if any(font.get('native_outline_file') for font in fonts.values()):runtime_files+=['font_outline.lua']
    runtime_files+=['bitmap_text.lua','instruction_profile.lua','runtime.lua']
    runtime='\n'.join((Path(__file__).parent/name).read_text(encoding='utf-8') for name in runtime_files)
    (destination/'legacy.lua').write_text('local PROFILE = '+lua(profile)+'\n'+runtime,encoding='utf-8')
    binary=skin.SerializeToString(deterministic=True)
    checked=skin_class().FromString(binary);checked.DiscardUnknownFields()
    if checked.SerializeToString(deterministic=True)!=binary:raise RuntimeError('Generated schema has unknown fields')
    (destination/'info.asm').write_bytes(binary)
    (destination/'info.json').write_text(json.dumps({'title':skin.meta.title,'desc':description,'creator':skin.meta.creator,'cover':cover or '',
        'version':skin.meta.minver,'mode':0,'key':keys,'feature':3,'skinid':0,'updatedTime':0,'special':None},ensure_ascii=False,indent=2),encoding='utf-8')
    (destination/'info.decoded.json').write_text(json_format.MessageToJson(skin,ensure_ascii=False),encoding='utf-8')
    for texture in assets.records:
        if texture.get('tiles'):
            doc.issues.append(Issue('error','body-tiles-runtime',
                f"{texture['source']}: lossless body subdivision is emitted; Unity mesh binding, filtering and seam coverage need engine verification",texture['source']))
        elif max(texture['width'],texture['height'])>16384:
            doc.issues.append(Issue('error','texture-dimension',
                f"{texture['source']}: {texture['width']}x{texture['height']} exceeds D3D11's 16384 dimension limit; lossless subdivision is required",
                texture['source']))
    errors=sum(x.severity=='error' for x in doc.issues)
    report={'status':'blocked' if errors else 'generated_needs_runtime_validation','one_to_one_verified':False,
            'unused_animation_definitions':[name for name in doc.animations if name not in used_motion_names],
            'element_resolution':element_resolution,
            'diagnostic_phase_profiling':bool(runtime_phase_profile),
            'legacy_play_plane':profile['legacy_play_plane'],
            'note_body_lanes':[lane for lane,e in notes.items() if e['states'].get('2')],
            'legacy_prelude_needed':profile['legacy_prelude_needed'],
            'source':str(source),'keys':keys,'ratio':ratio,'ui_rounding_height':ui_rounding_height,'ui_rounding_context':rounding_context,'files':doc.files,'module_count':len(skin.modules),
            'asset_count':len(assets.records),'errors':errors,'issues':[asdict(x) for x in doc.issues],
            'omitted_package_resources':omitted_resources,'atlas_factory_bindings':atlas_bindings,
            'schema_roundtrip':True,'info_sha256':hashlib.sha256(binary).hexdigest(),
            'runtime_acceptance':{'imported':False,'visual':False,'animation':False,'hold':False},'assets':assets.records}
    report['compatibility_contracts']=contracts
    if any(font.get('native_outline_file') for font in fonts.values()):
        report['font_storage_research']={'backend':'native-outline-with-original-layout',
            'exact_legacy_coverage':False,'ordinary_drag_drop_enabled':bool(font_build_context),
            'native_import_verified':False,'android_verified':False}
    report['required_render_api']={'backend':'public Unity Graphic/SpriteRenderer/Mesh.colors32 through xLua CS','native_metadata_checked':True,'engine_binding_executed':False}
    if native_key_judge_candidate:
        report['required_render_api']['judge_adapter']='Version-specific reflection of ChartPlayer.judgeLogic; original JudgeLogicKey computes all judgements'
    if native_bar_source_candidate:
        report['required_render_api']['bar_source_adapter']='Version-specific native bar builder; retains original loaded time/note queues'
    if native_note_pool_candidate:
        report['required_render_api']['note_pool_adapter']='Version-specific read-only reflection of idle modules; swaps logical draw slots without changing the native pool'
    (destination/'conversion-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    if not errors or draft:
        archive=Path(str(destination)+('.draft.msp' if errors else '.msp'))
        if archive.exists():raise FileExistsError(f'Refusing to replace {archive}')
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as out:
            for p in sorted(destination.rglob('*')):
                if p.is_file() and p.name not in ['legacy-ir.json','conversion-report.json','info.decoded.json'] and p.relative_to(destination).as_posix() not in omitted_resources:
                    out.write(p,p.relative_to(destination).as_posix())
        report['archive']=str(archive)
        (destination/'conversion-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return report
