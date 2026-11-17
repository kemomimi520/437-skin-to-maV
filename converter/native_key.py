"""Compile source-defined native Key modules; never a Free compatibility skin.

The retained MUI/atlas readers are shared. Original Key still owns gameplay.
Source-whole visual bindings may read native carriers and the retained source
display queue, without a replacement clock/judge or a Free draw callback.
Unexpressed definitions are reported; this is not a 1:1 acceptance certificate.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import shutil
from PIL import Image
import io

from .assets import Assets, frame_spec
from .common import ROOT, DATA, font_bank, lua, skin_class, skin_info_payload
from .mui import (parse, pair, numeric_pair_program, split_values, native_scalar, native_dimension, native_integer,
                  native_float, native_toggle, is_key_scene_definition, is_scene_custom, touch_coordinates)
from .native_numeric import expression, float32
from .native_ui_motion import compile_ui_motion
from .native_ui_projection import director_projection
from .native_ui_musicbar import compile_musicbar
from .native_note_images import hold_body_canvas, hold_body_slice_edges
from .native_note_factory import require_mapped_hold_factories
from .native_scale3_layout import range_layout
from .legacy_note_space import LEGACY_KEYUIS_BASE_SCALE,display_window
from .context import UI_PROJECTION_1024_600
from .legacy_plane import from_document
from .layers import scene_key


def basic_script(data):
    if 'native_multikey_branches' in data:
        from .native_multikey import basic_script as multikey_script
        return multikey_script(data)
    # Reconstructible from JSON for byte-exact audit before import/export.
    json.dumps(data, allow_nan=False)
    adapter=''
    if data.get('native_frame_driver'):
        if not data.get('admission_policy'):raise ValueError('Native frame driver requires original Key admission')
        adapter+=Path(__file__).with_name('native_frame_driver.lua').read_text(encoding='utf-8')+'\n'
    # Define the painter callbacks BEFORE Scale3's closure captures them.
    # Lua locals declared later in the chunk are not forward-visible.
    if data.get('native_painter'):
        if not data.get('scale3_recipes') or not data.get('admission_policy'):
            raise ValueError('Native painter is restricted to the controlled Scale3 admission candidate')
        for filename in ('native_painter_slots.lua','native_painter.lua'):
            adapter+=Path(__file__).with_name(filename).read_text(encoding='utf-8')+'\n'
    if data.get('scale3_recipes'):
        for filename in ('native_scale3_sprite.lua','native_scale3_rect.lua','native_scale3_admission.lua'):
            adapter+=Path(__file__).with_name(filename).read_text(encoding='utf-8')+'\n'
    if data.get('source_visual_pool'):
        if not data.get('scale3_recipes') or not data.get('native_frame_driver') or data.get('native_painter'):
            raise ValueError('Source FIFO visuals require the post-native driver and their own source sorting')
        adapter+='local UnityBridge={Float=scale3float}\n'
        for filename in ('native_bindings.lua','legacy_clock.lua','legacy_note_identity.lua','legacy_note_sort.lua'):
            adapter+=Path(__file__).with_name(filename).read_text(encoding='utf-8')+'\n'
        order=Path(__file__).with_name('native_source_order.lua').read_text(encoding='utf-8')
        body=Path(__file__).with_name('legacy_source_order.lua').read_text(encoding='utf-8')
        adapter+=order.replace('-- SOURCE_ORDER_BODY',body)+'\n'
        # The pure retained OSU reader precedes its old Free bridge entry.
        # Include only that parser, never the Chart/Note Free API wrapper.
        osu=Path(__file__).with_name('legacy_osu.lua').read_text(encoding='utf-8')
        adapter+=osu.split('\nfunction UnityBridge.LegacyOsuInput(',1)[0]+'\n'
        for filename in ('legacy_scroll.lua','legacy_lifetime.lua','native_source_input.lua','native_source_part3.lua','native_source_geometry.lua','native_source_factory.lua','native_source_part3_mesh.lua','native_source_motion.lua','native_source_motion_groups.lua','native_source_pool.lua'):
            adapter+=Path(__file__).with_name(filename).read_text(encoding='utf-8')+'\n'
    if data.get('hold_policy') or data.get('hold_policies'):
        adapter+=Path(__file__).with_name('native_hold_visual.lua').read_text(encoding='utf-8')+'\n'
    if data.get('admission_policy'):
        adapter+=Path(__file__).with_name('native_note_admission.lua').read_text(encoding='utf-8')+'\n'
    has_musicbar=any(e.get('source_musicbar') for e in data.get('entries',[]))
    if has_musicbar and not (data.get('source_visual_pool') and data.get('native_frame_driver')):
        raise ValueError('Source musicbar requires the original source visual context and post-native frame driver')
    def scoped_module(symbol, filename):
        code=Path(__file__).with_name(filename).read_text(encoding='utf-8')
        return f'{symbol}=(function()\n{code}\nreturn {symbol}\nend)()\n'
    parts=[]
    if data.get('source_bar') or any(e.get('source_texture') or e.get('source_frames') or e.get('source_meter') or e.get('source_strip') or e.get('source_events') or e.get('source_judge_counter') or e.get('source_musicbar') for e in data.get('entries',[])):
        parts.append(('NativeUiSampling',scoped_module('NativeUiSampling','native_ui_sampling.lua')))
    if data.get('source_bar') or data.get('suppress_native_bar'):
        parts.append(('NativeSourceBars',scoped_module('NativeSourceBars','native_source_bar.lua')))
    if any(e.get('source_frames') or e.get('source_events') for e in data.get('entries',[])):
        parts.append(('NativeUiFrames',scoped_module('NativeUiFrames','native_ui_frames.lua')))
    if any(e.get('source_events') for e in data.get('entries',[])):
        parts.append(('NativeUiEvents',scoped_module('NativeUiEvents','native_ui_events.lua')))
    if data.get('touches'):
        parts.append(('NativeUiTouch',scoped_module('NativeUiTouch','native_ui_touch.lua')))
    if any(e.get('source_frame_interval') for e in data.get('entries',[])):
        parts.append(('NativeUiFrameRate',scoped_module('NativeUiFrameRate','native_ui_frame_rate.lua')))
    if any(e.get('source_number') or e.get('source_judge_counter_number') for e in data.get('entries',[])):
        parts.append(('NativeUiNumber',scoped_module('NativeUiNumber','native_ui_number.lua')))
    if has_musicbar or any(e.get('source_judge_counter_number') or e.get('source_projection') for e in data.get('entries',[])):
        parts.append(('NativeUiProjection',scoped_module('NativeUiProjection','native_ui_projection.lua')))
    if any(e.get('source_judge_counter_number') for e in data.get('entries',[])):
        parts.append(('NativeUiJudge',scoped_module('NativeUiJudge','native_ui_judge.lua')))
    if has_musicbar:
        parts.append(('NativeUiMusicbar',scoped_module('NativeUiMusicbar','native_ui_musicbar.lua')))
    if any(e.get('source_text') for e in data.get('entries',[])):
        font_scripts=Path(__file__).with_name('font_cache.lua').read_text(encoding='utf8')
        if any(e['source_text'].get('font',{}).get('hybrid_os_fallback') or e['source_text'].get('font',{}).get('native_outline_file') for e in data.get('entries',[]) if e.get('source_text')):
            font_scripts=Path(__file__).with_name('font_outline.lua').read_text(encoding='utf8')+'\n'+font_scripts
        parts.append(('NativeUiText',scoped_module('NativeUiText','native_ui_text.lua')+
            'do local UnityBridge=NativeUiText\n'+font_scripts+'\nend\n'))
    if any(e.get('source_meter') for e in data.get('entries',[])):
        parts.append(('NativeUiMeter',scoped_module('NativeUiMeter','native_ui_meter.lua')))
    if any(e.get('source_strip') for e in data.get('entries',[])):
        parts.append(('LegacyStrip',scoped_module('LegacyStrip','strip_geometry.lua')))
        parts.append(('NativeUiStrip',scoped_module('NativeUiStrip','native_ui_strip.lua')))
    if any(e.get('source_blend') for e in data.get('entries',[])):
        parts.append(('NativeUiBlend',scoped_module('NativeUiBlend','native_ui_blend.lua')))
    if any(e.get('source_motion') for e in data.get('entries',[])):
        parts.append(('NativeUiMotion',scoped_module('NativeUiMotion','native_ui_source_motion.lua')))
    if any(e.get('source_plane_ui') for e in data.get('entries',[])):
        parts.append(('NativeSourcePlaneUI',scoped_module('NativeSourcePlaneUI','native_source_plane_ui.lua')))
    if parts:
        adapter+='local '+','.join(sym for sym,_ in parts)+'\n'+''.join(code for _,code in parts)
    script='local DATA = '+lua(data)+'\n'+adapter+(Path(__file__).with_name('native_ui.lua')).read_text(encoding='utf-8')
    if has_musicbar:
        script+='\n'+Path(__file__).with_name('native_ui_musicbar_hooks.lua').read_text(encoding='utf-8')+'\n'
    if data.get('touches'):
        script+='\nlocal nativeTouchOriginalInit=Init;local nativeTouchOriginalUpdate=Update\nfunction Init() nativeTouchOriginalInit();NativeUiTouch.Bind(DATA) end\nfunction Update() if nativeTouchOriginalUpdate then nativeTouchOriginalUpdate() end;NativeUiTouch.Update() end\n'
    if data.get('scale3_recipes'):
        script+='\nlocal scale3OriginalInit=Init\nfunction Init() if nativePrepareRuntimeData then nativePrepareRuntimeData(DATA) end;initScale3Admission(DATA);scale3OriginalInit() end\n'
    return script.encode('utf-8')


def validate_basic_script(script, data_bytes):
    data = json.loads(data_bytes)
    if not isinstance(data, dict) or not isinstance(data.get('entries'), list):
        raise ValueError('Invalid ordinary UI data')
    if script != basic_script(data):
        raise ValueError('Ordinary UI script differs from audited compiler template')


_COVER_SUFFIXES = frozenset({'.png', '.jpg', '.jpeg', '.bmp', '.webp'})
_FALLBACK_COVERS = ('cover.png', 'cover.jpg', 'cover.jpeg',
                    'preview.png', 'preview.jpg', 'preview.jpeg',
                    'skin_cover.png', 'skin_cover.jpg', 'skin_cover.jpeg')


def _copy_skin_cover(source: Path, preview_info: dict, destination: Path) -> str:
    """Resolve explicit or conventional skin cover bytes inside source and stage them."""
    root = source.resolve()
    files = {}
    for path in sorted(root.rglob('*')):
        if path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root):
            files.setdefault(path.relative_to(root).as_posix().casefold(), path)
    candidates = []
    raw_cover = preview_info.get('cover')
    if isinstance(raw_cover, str) and raw_cover.strip():
        candidates.append(raw_cover.strip().replace('\\', '/').lstrip('/'))
    candidates.extend(_FALLBACK_COVERS)
    for candidate in candidates:
        match = files.get(candidate.casefold())
        if match is None or match.suffix.lower() not in _COVER_SUFFIXES:
            continue
        try:
            with Image.open(match) as probe:
                probe.verify()
        except Exception:
            continue
        blob = match.read_bytes()
        target = hashlib.sha256(blob).hexdigest()[:24] + match.suffix.lower()
        dest = destination / target
        if not dest.exists():
            dest.write_bytes(blob)
        elif dest.read_bytes() != blob:
            raise ValueError('原生封面资源标识冲突：' + target)
        return target
    return ''


def compile_native_key_skin(source, destination, keys, ratio=1024/600, *, source_platform='windows', phone_predicate: bool | None = None, progress=lambda value:None, font_build_context=None):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if destination == source or destination.is_relative_to(source):
        raise ValueError('Native output must be outside source skin')
    if destination.exists():
        raise FileExistsError(destination)
    # The recovered desktop Director uses a 600-high logical viewport. Pair
    # expressions normalize design units to 720, but x / w units, captured
    # variables and intrinsic Sprite pixels still depend on this context.
    doc = parse(source, keys, ratio, logical_height=600, platform=source_platform, phone_predicate=phone_predicate)
    parse_errors = [issue for issue in doc.issues if issue.severity == 'error']
    if parse_errors:
        raise ValueError('\n'.join(issue.message for issue in parse_errors))
    # Dispatch before destination creation, asset resolution or image work.
    # An unused tex5/tex3 must not mask a different native factory contract.
    note_factories=require_mapped_hold_factories({name:item for name,item in doc.elements.items()
                                               if name in {f'note-{lane}' for lane in range(1,keys+1)}})
    factory_names={plan.name for plan in note_factories.values()}
    # Keep every original note factory on its lane.  Part3 owns a projected
    # source mesh; Scale3Part3 and Tile3 use their own native segment/tile
    # contracts in the source queue.  They must never be relabelled as the
    # default whole-image Scale3 branch.
    part3_factories={'part3'}
    source_factories={'part3','scale3part3','tile3'}
    supported_factories={'scale3',*source_factories}
    source_supported=bool(note_factories) and factory_names.issubset(supported_factories)
    source_whole=source_supported and factory_names=={'scale3'}
    source_part3=source_supported and factory_names.issubset(source_factories) and bool(factory_names)
    source_mixed=source_supported and len(factory_names)>1
    destination.mkdir(parents=True)
    defaults = DATA/'legacy'
    if not defaults.is_dir(): defaults=ROOT/'analysis/malody-4.3.7/resources'
    assets = Assets(source, defaults, destination, doc.packs)
    font_context=font_build_context if font_build_context is not None else {}
    font_groups={}
    for item in doc.elements.values():
        if not (is_scene_custom(item) and native_integer(item.attrs.get('type'))==1 and 'text' in item.attrs):continue
        requested=math.trunc(native_dimension(doc,item,'fsize',24))
        pixels=math.floor(float32(requested*1.5)+.5)
        if re.search(r'\{[^{}]+\}',item.attrs['text']):font_groups[pixels]=None
        elif pixels not in font_groups or font_groups[pixels] is not None:
            font_groups.setdefault(pixels,{32}).update(ord(c) for c in item.attrs['text'])
    skin = skin_class()()
    skin.meta.title = source.name+f' {keys}K'
    skin.meta.creator = 'Original skin authors; converted by Ma Skin Bridge'
    info = {}
    preview = source/'preview.json'
    if preview.is_file():
        try:
            loaded = json.loads(preview.read_text(encoding='utf-8-sig'))
            if isinstance(loaded, dict):
                info = loaded
        except (ValueError, UnicodeError):
            pass
    if info:
        skin.meta.title = str(info.get('title') or source.name) + f' {keys}K'
        skin.meta.desc = str(info.get('desc') or '')
        creator = str(info.get('creator') or info.get('author') or '').strip()
        if creator:
            skin.meta.creator = creator
    cover = _copy_skin_cover(source, info, destination)
    if cover:
        skin.meta.cover = cover
    skin.meta.mode=0;skin.meta.feature=1;skin.meta.minver=328450
    skin.meta.key.keys=keys;skin.meta.key.locked=True
    skin.meta.key.lock3_d=True;skin.meta.key.lock_scale=True
    skin.meta.key.scale=.5
    ui={'entries':[],'touches':[]};issues=[];resolved={};disabled=set(range(1,21))-{1,15};serial=0
    musicbar_resource_holder=None
    painter_keys={name:scene_key(name,int(native_scalar(item,'zindex')) if 'zindex' in item.attrs else None,index)
                  for index,(name,item) in enumerate(doc.elements.items())}
    painter_order={name:index for index,name in enumerate(sorted(painter_keys,key=painter_keys.get))}
    def warning(code, message):issues.append({'severity':'warning','code':code,'message':message})
    def error(code, message):issues.append({'severity':'error','code':code,'message':message})
    legacy_plane=None
    if '3d' in doc.features:
        if doc.ui_rounding_height!=600:
            error('native-legacy-projection-context','旧版 3D 投影只在已核实的 600 高 KeyUIS 视口上有原生矩阵；当前高度不能声称 1:1')
        else:
            try:
                legacy_plane=from_document(doc,director_projection(doc.ui_rounding_height,ratio))
            except ValueError as exc:
                error('native-legacy-projection-context',str(exc))
    elif doc.ui_rounding_height==600:
        # The old KeyUIS camera is perspective even for an ordinary 2D
        # definition.  In that path the plane transform is the identity, but
        # Sprite/ShapeSprite commands still go through the verified Director
        # projection.  Treating these notes as maV's orthographic Rect plane
        # changes the lane pitch and causes a growing x error across lanes.
        legacy_plane={'angle':0,'matrix':[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
            'clip_depth':{},'scroll_scale':1.0,
            'source_projection':director_projection(600,ratio)['matrix'],
            'logical_height':600,'whole_scene_verified':False,
            'default_2d':True}
    legacy_scale=legacy_plane['scroll_scale'] if legacy_plane else 1.0
    def dimensions(item, attr='size', default='0,0'):
        return [value[0]*extent+value[1] for value,extent in zip(pair(doc,item,attr,default), (ratio*720,720))]
    def _source_ui_position_raw(item, aspect_ratio=None):
        # ApplyAttributes rounds the original parser's float32 result before
        # the captured Director projection. Preserve assignment-time variables,
        # selector increments and reference-addition boundaries.
        program=numeric_pair_program(doc,item,'pos')
        if program is None:raise ValueError('Original UI position exceeds the verified numeric scanner bound')
        height=float32(doc.ui_rounding_height);width=float32(height*(ratio if aspect_ratio is None else aspect_ratio))
        result=[];raw=[]
        for terms,extent in zip(program,(width,height)):
            value=0.0
            for term in terms:
                context=term if isinstance(term,dict) else {}
                text=context.get('text',term)
                scale=float32(height/context.get('unit',720))
                value=float32(value+expression(text,extent,scale,width,context.get('variables')))
            raw.append(value)
            result.append(math.ceil(value-.5) if value<0 else math.floor(value+.5))
        return result,raw
    def source_ui_position(item):return _source_ui_position_raw(item)[0]
    def source_ui_x_pct(item):
        _,base_raw=_source_ui_position_raw(item,ratio)
        _,shifted_raw=_source_ui_position_raw(item,ratio+1.0)
        return float((shifted_raw[0]-base_raw[0])/doc.ui_rounding_height)
    def valid_hex_color(value):return value if value and re.fullmatch(r'#[0-9a-fA-F]{6}',value) else '#FFFFFF'
    def opacity(item):return max(0,min(100,round(native_scalar(item,'opacity',100))))
    _missing_blank=None
    def _missing_blank_texture():
        nonlocal _missing_blank
        if _missing_blank is None:
            buf=io.BytesIO();Image.new('RGBA',(1,1),(0,0,0,0)).save(buf,format='PNG')
            blob=buf.getvalue();rel=hashlib.sha256(blob).hexdigest()[:24]+'.png'
            path=destination/rel
            if not path.exists():path.write_bytes(blob)
            _missing_blank={'file':rel,'width':1,'height':1,'frame_height':1,'trim':[0,0,1,1],'source_texture_clamp':False,'missing':True}
        return dict(_missing_blank)
    def resource(item, suffix='', *, note=False):
        attr='tex'+suffix if 'tex'+suffix in item.attrs else 'frame'+suffix
        if note or item.name=='bar' or item.name.startswith('key-') or is_scene_custom(item) and native_integer(item.attrs.get('type'))==0:
            attr='tex'+suffix
        if is_scene_custom(item) and native_integer(item.attrs.get('type'))==3:
            attr='frame'+suffix  # StateAnimator never uses a competing tex.
        if re.fullmatch(r'(press|hit)-\d+',item.name):attr='frame'+suffix
        if attr not in item.attrs:return []
        strip=is_scene_custom(item) and native_integer(item.attrs.get('type'))==4
        flip=0 if note or item.name=='bar' or strip else {0:1,1:2,2:3}.get(native_integer(item.attrs.get('flip'),-1),0)
        # 437's ShapeSprite body samples an already Cocos-premultiplied
        # texture but still uses SRC_ALPHA. The observed native body uses
        # Sprites/Default (shader premultiplication + ONE blend). Preserve
        # the old texture encoding here so that last multiplication matches;
        # ordinary Sprite heads/tails have a different old blend contract.
        generic_additive=(is_scene_custom(item) and native_integer(item.attrs.get('type'))==0 and
                          native_integer(item.attrs.get('blend'),-1) in (1,2))
        body_factory=note_factories.get(item.name) if note and suffix=='2' else None
        try:
            textures=assets.sequence(item.attrs[attr],flip=flip,
                                     trim_canvas=bool(strip or body_factory and body_factory.trim_body_canvas),
                                     premultiplied=bool(body_factory and body_factory.premultiplied_body or generic_additive))
        except FileNotFoundError as exc:
            if not note:raise
            warning('native-missing-texture',f'{item.name}: {exc}')
            return [_missing_blank_texture()]
        return textures[:1] if attr.startswith('tex') else textures
    def sprite_dimensions(size, texture, explicit_zero=False):
        width,height=size
        if not all(math.isfinite(v) for v in (width,height)):
            raise ValueError('原定义生成了非正尺寸，普通原生 Key 尚未表达该翻转几何')
        if width==0 and height==0:
            if explicit_zero:return 0.0,0.0
            return texture['width']*720/doc.ui_rounding_height,texture['height']*720/doc.ui_rounding_height
        # 437 Legacy_ApplyVisualParams (00508430:59-80) uses DAT_007cbed0=1e-6:
        # a non-positive axis triggers aspect lock against the positive axis,
        # or preserves intrinsic texture size if neither axis is positive.
        pos_w=width>=1e-6;pos_h=height>=1e-6
        if not pos_w and not pos_h:
            return texture['width']*720/doc.ui_rounding_height,texture['height']*720/doc.ui_rounding_height
        if not pos_w:width=height*texture['width']/texture['height']
        if not pos_h:height=width*texture['height']/texture['width']
        return width,height
    def native_image(target, item, textures, width, height, *, frames=False, allow_native_pct=True, row=None):
        target.file=textures[0]['file']
        target.width=width*1.5;target.height=height*1.5;target.wu=target.hu=1
        if row is not None and any(m['method'] in ('DoSkew','DoSkewX','DoSkewY') for m in row.get('motions',())):
            row['source_tex_size']=[textures[0]['width'],textures[0]['height']]
            if row not in ui['entries']:ui['entries'].append(row)
        raw_w,raw_h=dimensions(item)
        sx,_=pair(doc,item,'size')
        if raw_w>=1e-6 and abs(sx[0])>1e-6:
            auto_h=(raw_h<1e-6)
            if allow_native_pct and abs(sx[1])<1e-6 and abs(sx[0]*100)>=0.5 and (not frames or not auto_h):
                target.width=float32(sx[0]*100);target.wu=0
                if auto_h:target.height=0;target.hu=1
            elif row is not None:
                row['source_size']={'w_pct':float32(sx[0]*1080),'w_px':float32(sx[1]*1.5),
                    'auto_h':auto_h,'aspect':float(textures[0]['height']/textures[0]['width'])}
                if row not in ui['entries']:ui['entries'].append(row)
        if frames:
            nonlocal serial
            serial+=1;prefix=f'frame-{serial}-'
            for index,texture in enumerate(textures):
                shutil.copyfile(destination/texture['file'],destination/f'{prefix}{index}.png')
            target.file=f'{prefix}0.png';target.filebase=prefix;target.filestart=0
            target.frames=len(textures);target.fps=max(1,round(1000/max(1,native_float(item.attrs.get('interval'),60))))
        if 'blend' in item.attrs and not (is_scene_custom(item) and native_integer(item.attrs.get('type'))==4):
            blend=native_integer(item.attrs['blend'])
            if blend in (0,1):target.blend=1
            elif blend==2:
                if row is not None and is_scene_custom(item) and native_integer(item.attrs.get('type'))==0:
                    row['source_blend']=2
                    if row not in ui['entries']:ui['entries'].append(row)
                else:
                    warning('native-blend-difference',f'{item.name}: destination-color blending is not represented by native images')
    def apply_solid_size(module, row, item):
        sx,_=pair(doc,item,'size')
        width_i,height_i=dimensions(item)
        module.image.color=valid_hex_color(item.attrs.get('color'))
        if abs(sx[0])>1e-6 and abs(sx[1])<1e-6 and abs(sx[0]*100)>=0.5 and not row.get('source_motion'):
            module.image.width=float32(sx[0]*100);module.image.wu=0
        else:
            module.image.width=width_i*1.5;module.image.wu=1
            if abs(sx[0])>1e-6:
                row['source_size']={'w_pct':float32(sx[0]*1080),'w_px':float32(sx[1]*1.5),'auto_h':False,'aspect':1.0}
                if row not in ui['entries']:ui['entries'].append(row)
        module.image.height=height_i*1.5;module.image.hu=1
    def event_interval(item,row):
        # 0050a210 stores int(interval), 005029c0 replaces only negatives
        # with 10. Do not reinterpret a source zero as a 1 ms animation.
        interval=native_integer(item.attrs.get('interval'),10)
        if interval<0:interval=10
        if interval==0:raise ValueError('Original EventFactory zero interval is not mapped')
        row['source_frame_interval']=interval
        if row not in ui['entries']:ui['entries'].append(row)
    note_scene_key=scene_key('note-1',None)
    def plane_ui_eligible(item):
        if '3d' not in doc.features or not legacy_plane or not source_supported:return False
        name=item.name
        if name in ('bar','touch','musicbar','progress','score-hp') or name.startswith('note-'):return False
        if painter_keys[name][0]!=1:return False
        indexed=re.fullmatch(r'(key|hit|press|judge)-(\d+)',name)
        if indexed and indexed[1]=='judge' and native_integer(item.attrs.get('type'))==2:return False
        if not indexed and is_scene_custom(item) and native_integer(item.attrs.get('type'))==1:return False
        return True
    def attach_plane_ui(item, module, row, *, solid=False, number=False):
        if not plane_ui_eligible(item):return False
        item_key=painter_keys[item.name]
        order=(-20000+painter_order[item.name]) if item_key<note_scene_key else (31000+painter_order[item.name])
        blend_mode=native_integer(item.attrs.get('blend'),-1)
        row['source_plane_ui']={'order':order,'solid':bool(solid),'additive':blend_mode==1,
            'blend':blend_mode if blend_mode in (1,2) else 0}
        if number:row['source_plane_ui']['number']=True
        if row not in ui['entries']:ui['entries'].append(row)
        return True
    def _mascot_key_pair():
        for mascot in ('_neko','_meow'):
            mitem=doc.elements.get(mascot)
            k1=doc.elements.get('key-1')
            if mitem and k1 and painter_keys.get(mascot,(-1,))>=note_scene_key and k1.attrs.get('pos')==mitem.attrs.get('pos'):
                return True
        return False
    mascot_keys=_mascot_key_pair()
    def playfield_above_notes_sort(item):
        name=item.name
        if name in ('bar','touch','musicbar','progress','score-hp','hit-fast','hit-slow') or name.startswith('note-'):
            return False
        if painter_keys[name]<note_scene_key or plane_ui_eligible(item):
            return False
        if re.fullmatch(r'(hit|press)-(\d+)',name):
            return True
        if re.fullmatch(r'key-(\d+)',name):
            return not mascot_keys
        return bool(re.fullmatch(r'_(?:button.*|bottom.*|buttom|bgb|bg2|bk2|bg|line-\d+|upline-\d+|judgeline\d*)',name))
    def base(item, module, name=None, alpha=None, tint=True):
        module.meta.desc=name or item.name
        anchor=native_integer(item.attrs.get('anchor'),4)
        module.param.pivot=anchor if anchor in range(9) else 6
        module.param.rotate=-int(native_scalar(item,'rotate'))
        module.param.alpha=opacity(item) if alpha is None else alpha
        module.param.layer=1 if painter_keys[item.name]<note_scene_key else 4
        module.param.order=painter_order[item.name]
        positions=pair(doc,item,'pos')
        module.param.x=positions[0][0]*100;module.param.y=positions[1][0]*100
        module.param.dx=positions[0][1]*1.5;module.param.dy=positions[1][1]*1.5
        module.param.dxu=module.param.dyu=1
        # ApplyAttributes rounds percentage coordinates in the original
        # Director canvas before the native module receives them. Preserve
        # that boundary for ordinary UI nodes; forwarding the raw percentage
        # leaves a stable fractional-pixel drift at the right/top edges.
        raw_position=item.attrs.get('pos','')
        if not plane_ui_eligible(item) and ',' in raw_position and '%' in raw_position:
            rounded=source_ui_position(item)
            terms=split_values(raw_position)
            canvas_width=float32(doc.ui_rounding_height*ratio)
            if len(terms)==2:
                if '%' in terms[0] and abs(positions[0][1])<1e-6:
                    module.param.x=float32(rounded[0]/canvas_width*100);module.param.dx=0
                if '%' in terms[1] and abs(positions[1][1])<1e-6:
                    module.param.y=float32(rounded[1]/doc.ui_rounding_height*100);module.param.dy=0
        if is_scene_custom(item) and native_integer(item.attrs.get('show'),1)==0:module.param.alpha=0
        row={'handle':module.meta.desc,'motions':[]}
        color=item.attrs.get('color') if tint else None
        if color and re.fullmatch(r'#[0-9a-fA-F]{6}',color):row['color']=[int(color[i:i+2],16) for i in (1,3,5)]
        binding=item.motion_bindings.get('motion')
        if is_scene_custom(item) and native_integer(item.attrs.get('show'),1)==0:binding=None
        if binding:
            def motion_issue(severity,code,message):
                issues.append({'severity':severity,'code':code,'message':item.name+': '+message})
            row['motions']=compile_ui_motion(binding,ratio=ratio,logical_height=doc.ui_rounding_height,
                issue=motion_issue,position_anchor=(positions[0][0],positions[1][0]))
            if any(m['method'] in ('DoSkew','DoSkewX','DoSkewY') for m in row['motions']):
                row['source_anchor']=module.param.pivot
            if row['motions'] and (is_scene_custom(item) or any(
                    m.get('clock')=='system' or m['method'] in ('DoSkew','DoSkewX','DoSkewY')
                    for m in row['motions'])):
                row['source_motion']=True
        if (is_scene_custom(item) and native_integer(item.attrs.get('type'))==0 and
                native_integer(item.attrs.get('blend'),-1) in (1,2)):
            # Old explicit blend=1 is PMA texture + PMA vertex colour with
            # SRC_ALPHA/ONE, whereas native additive UI has straight vertex
            # colour. Track base RGB when DoAlpha runs so vertex RGB scales
            # identically with vertex alpha at every frame.
            base_rgb=list(row.get('color',[255,255,255]))
            vertex_alpha=max(0,min(255,math.trunc(float32(native_scalar(item,'opacity',100)*float32(2.55)))))
            row['color']=[math.trunc(c*vertex_alpha/255) for c in base_rgb]
            if any(motion['method']=='DoAlpha' for motion in row['motions']):
                row['pma_rgb']=base_rgb
                row['source_motion']=True
        if row.get('color') or row['motions']:ui['entries'].append(row)
        if playfield_above_notes_sort(item):
            row['source_sorting']={'layer':'Above Notes','order':-10000+painter_order[item.name]}
            if row not in ui['entries']:ui['entries'].append(row)
        return row
    def source_sprite_projection(item,row):
        # 437 Sprite vertices pass through the Director even when the native
        # Image uses an orthographic UI camera. Only bind known, fixed source
        # positions: motion and parent/skew composition need separate proof.
        raw_anchor=item.attrs.get('anchor','4')
        anchor=native_integer(raw_anchor)
        if ',' not in raw_anchor and (anchor in range(9) or anchor==99) and not any(
                attr in item.attrs for attr in ('parent','skew')):
            # The 437 anchor=99 fallback yields (0,0) in the actual source
            # readback; the standard enum fallback 6 has the same pivot.
            pivot=anchor if anchor in range(9) else 6
            row['source_projection']={'projection':director_projection(doc.ui_rounding_height,ratio),
                'source_position':source_ui_position(item),
                'source_anchor':[(pivot%3)*.5,1-(pivot//3)*.5],
                'compiled_ratio':ratio,
                'source_pct_x':source_ui_x_pct(item)}
            if row not in ui['entries']:ui['entries'].append(row)
        else:
            warning('native-ui-projection-unmapped',f'{item.name}: original Sprite anchor/parent/skew projection is not yet mapped')
    notes=[];judge_modules=[];judge_events=[]
    for lane in range(1,keys+1):
        item=doc.elements.get(f'note-{lane}')
        if item is None:raise ValueError(f'原定义缺少 note-{lane}')
        head=resource(item,note=True)
        if not head:raise ValueError(f'note-{lane} 缺少原生头部资源')
        pos=dimensions(item,'pos');end=dimensions(item,'pos2');size=dimensions(item)
        factory=note_factories[item.name]
        # The whole-image factory never opens tex3/tex5. The native carrier
        # can use the tap bounds for its field origin, but emits no LN art
        # from that placeholder; tex2 alone supplies the actual whole LN.
        hold_head=head if factory.name=='scale3' else resource(item,factory.head_suffix,note=True)
        body=resource(item,'2',note=True)
        tail=head if factory.name=='scale3' else resource(item,factory.tail_suffix,note=True)
        notes.append((item,head,pos,end,size,hold_head,body,tail))
        if abs(pos[0]-end[0])>1:
            warning('native-key-path-candidate',f'note-{lane}: 使用原生拥有 Mesh Part3 路径候选；仍需实际场景逐帧验收')
    centers=[row[3][0] for row in notes]
    spacing=(centers[-1]-centers[0])/(keys-1) if keys>1 else max(notes[0][4][0],100)
    width=spacing*keys
    if width<=0:raise ValueError('Native Key track width must be positive')
    if any(abs(x-(centers[0]+i*spacing))>1 for i,x in enumerate(centers)):
        (warning if source_supported and not source_whole else error)('native-key-spacing' if not source_supported else 'native-key-nonuniform-lanes',
            'Original lane centres are not equally spaced; whole-image Scale3 cannot map per-lane x with one field translation' if source_whole else
            'Original lane centres are not equally spaced; source-owned Part3 geometry keeps per-lane x coordinates' if source_supported
            else 'Original lane centres are not equally spaced')
    hold_centres=[];judge_offsets={}
    for item,head,pos,end,size,hold_head,body,tail in notes:
        head_w,head_h=sprite_dimensions(size,hold_head[0])
        tail_w,tail_h=sprite_dimensions(size,tail[0])
        anchor=native_integer(item.attrs.get('anchor'),4)
        if anchor not in range(9):anchor=6
        ax=(anchor%3)*.5;ay=1-(anchor//3)*.5
        hold_centres.append(end[1]+(.5-ay)*head_h)
        if abs((.5-ay)*(head_h-tail_h))>1:
            error('native-hold-end-centres',f'{item.name}: 原头尾锚点造成不同的条身端点偏移，普通 Key 条身尚未映射')
    judge_line=hold_centres[0]
    if any(abs(value-judge_line)>1 for value in hold_centres):
        (warning if source_supported and not source_whole else error)('native-key-judge-line' if not source_supported else 'native-key-nonuniform-judge',
            'Original hold image centres do not share a straight native judgement line; whole-image Scale3 cannot map per-lane y with one judgement line' if source_whole else
            'Original hold image centres do not share a straight native judgement line; source-owned Part3 geometry keeps per-lane y coordinates' if source_supported
            else 'Original hold image centres do not share a straight native judgement line')
    for item,head,pos,end,size,hold_head,body,tail in notes:
        judge_offsets[item.name]=judge_line-end[1]
        if not source_supported and (pos[1]<=end[1] or abs((pos[1]-end[1])-(notes[0][2][1]-notes[0][3][1]))>1):
            error('native-key-travel',f'{item.name}: 原各轨道的纵向行程/方向不同，普通 Key 尚未映射')
    # The shipped Key prefab projects to 1680 units on a 1080-unit viewport.
    # The measured native centre spacing confirms this independent of images.
    skin.meta.key.scale=width/(720*14/9)
    # Carry a legacy whole-field x translation on the owned source-visual
    # root; maV has no Key metadata field for this old origin.
    field_offset_x=(centers[0]+centers[-1])*.5-ratio*360
    # Part3 lanes may intentionally have independent or even zero-length
    # MUI trajectories (for example a radial 9K layout).  The source FIFO
    # keeps the per-lane start/end values in each recipe; its global motion
    # contract only needs a finite validation span.
    source_travel=max((abs(row[2][1]-row[3][1]) for row in notes),default=0.0)
    source_travel=max(float32(source_travel),1.0)
    # The positive span above validates the common display window, not motion.
    # Every lane, including reversed/zero travel, retains its signed trajectory.
    lane_travels=[float32(row[2][1]-row[3][1]) for row in notes]
    uniform_travel=not lane_travels or max(lane_travels)-min(lane_travels)<=1e-6
    # Judge is an anchored offset INSIDE the scaled native field, whose
    # prefab has a 160-unit bottom inset. It is not a screen-space Y value.
    # Native body geometry joins the *image centres*, whereas 437 first
    # converts each declared anchor to its Sprite bounding-box centre.
    # Align the native field to that common LN centre, and compensate the
    # per-sprite canvas by the same offset. Moving only the head leaves the
    # native body visibly detached for bottom/top anchors.
    skin.meta.key.judge_pos=round(judge_line*1.5/skin.meta.key.scale-160)
    angle=native_integer(doc.directives.get('angle'))
    applied3d='3d' in doc.features
    skin.meta.key.angle=angle;skin.meta.key.use3_d=applied3d
    if applied3d and not legacy_plane:warning('native-key-projection','旧版 3D 投影上下文缺失；新版原生角度保留但此场景不具备 1:1 证明')
    if source_supported:
        centers_affine=[pair(doc,row[0],'pos2')[0] for row in notes]
        note1_size_x=pair(doc,notes[0][0],'size')[0]
        ui.update(admission_policy=[0]*keys,native_frame_driver=True,scale3_recipes=[],
            source_visual_pool={'scope':'legacy-source-fifo-v1','distance':display_window(1,legacy_scale),'judge_ahead':160,'base':32,'capacity':6000,
                'field_offset_x':float32(field_offset_x*1.5/skin.meta.key.scale),
                'motion':{'scope':('legacy-mixed-v1' if source_mixed else
                                   'legacy-linear-whole-scale3-v1' if source_whole else
                                   'legacy-linear-part3-v1'),'logical_height':doc.ui_rounding_height,
                    'travel_720':source_travel,'speed':1,'scale':legacy_scale,
                    'legacy_play_plane':legacy_plane,
                    'speed_source':'native-layer','affine_groups':True}})
        if any(abs(c[0])>1e-6 for c in centers_affine) or (keys==1 and abs(note1_size_x[0])>1e-6):
            ui['source_visual_pool']['x_affine']={
                'lane_centers_x':[[float32(p[0]*720),float32(p[1])] for p in centers_affine],
                'note1_size_x':[float32(note1_size_x[0]*720),float32(note1_size_x[1])],
                'keys':keys,'base_scale':skin.meta.key.scale,'judge_line_720':float32(judge_line)}
        if not uniform_travel:
            ui['source_visual_pool']['motion']['lane_travel_720']=lane_travels
        if source_mixed:
            warning('native-source-mixed-unverified','混合 Scale3/Part3 已按原工厂分轨接入源视觉队列；完整生命周期、平台、Mods 和上传验收尚未完成，不能作为通用成品交付')
        else:
            warning('native-source-whole-unverified' if source_whole else 'native-source-part3-unverified',
                ('整图 Scale3' if source_whole else 'Part3')+' 已接入源视觉队列；完整界面、平台、Mods 和上传验收尚未完成，不能作为通用成品交付')
    blank=Image.new('RGBA',(2,2));buffer=io.BytesIO();blank.save(buffer,format='PNG')
    blank_name=hashlib.sha256(buffer.getvalue()).hexdigest()[:24]+'.png'
    (destination/blank_name).write_bytes(buffer.getvalue())
    def _bleed_transparent_rgb(img):
        from PIL import ImageChops
        rgba=img.convert('RGBA')
        a=rgba.getchannel('A')
        ext=a.getextrema()
        if ext[1]==0:
            return Image.new('RGBA',rgba.size,(0,0,0,0))
        if ext[0]>0:
            return rgba
        valid=a.point(lambda v:255 if v>0 else 0)
        cur_rgb=Image.composite(rgba.convert('RGB'),Image.new('RGB',rgba.size,(0,0,0)),valid)
        cur_mask=valid
        w,h=rgba.size
        for _ in range(3):
            next_rgb=cur_rgb;next_mask=cur_mask
            for dx,dy in ((-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)):
                shifted_mask=ImageChops.offset(cur_mask,dx,dy)
                if dx>0:shifted_mask.paste(0,(0,0,dx,h))
                elif dx<0:shifted_mask.paste(0,(w+dx,0,w,h))
                if dy>0:shifted_mask.paste(0,(0,0,w,dy))
                elif dy<0:shifted_mask.paste(0,(0,h+dy,w,h))
                need=ImageChops.subtract(shifted_mask,next_mask)
                if need.getbbox():
                    shifted_rgb=ImageChops.offset(cur_rgb,dx,dy)
                    next_rgb=Image.composite(shifted_rgb,next_rgb,need)
                    next_mask=ImageChops.lighter(next_mask,need)
            if next_mask is cur_mask:break
            cur_rgb,cur_mask=next_rgb,next_mask
        cr,cg,cb=cur_rgb.split()
        return Image.merge('RGBA',(cr,cg,cb,a))
    def overlap_image(target,item,texture,size):
        # The native overlap is a SpriteRenderer owned by PlayNoteKeySkin.
        # It keeps intrinsic sprite dimensions, unlike the fixed lane-width
        # sliced head. Encode the original anchor in the transparent canvas;
        # maV still owns movement, holding, retirement and sprite submission.
        with Image.open(destination/texture['file']) as original:image=_bleed_transparent_rgb(original)
        width,height=sprite_dimensions(size,texture)
        # Preserve BOTH source axes. Resizing only the height to an integer
        # at the width's original density changed e.g. a 90x60 note into
        # 90x63. Tiny padded sprites also acquire multi-pixel transparent
        # fringes under native bilinear sampling. Keep source detail and at
        # least one sample per native 1080-unit screen pixel.
        density=max(image.width/width,image.height/height,1.5)
        target_size=(max(1,round(width*density)),max(1,round(height*density)))
        if max(target_size)>16384:raise ValueError(f'{item.name}: 原音符的比例适配超出已验证纹理尺寸')
        if image.size!=target_size:
            image=_bleed_transparent_rgb(Image.merge('RGBA',[channel.resize(target_size,Image.Resampling.BILINEAR) for channel in image.split()]))
        anchor=native_integer(item.attrs.get('anchor'),4)
        if anchor not in range(9):anchor=6
        ax=(anchor%3)*.5;ay=1-(anchor//3)*.5
        left=-ax*image.width
        top=-(1-ay)*image.height+judge_offsets[item.name]*density
        extent=max(1,math.ceil(2*max(abs(left),abs(left+image.width),abs(top),abs(top+image.height))))
        if extent>16384:raise ValueError(f'{item.name}: 原音符锚点适配超出已验证纹理尺寸')
        # UIOffsetScale normalizes the overlap rectangle independently on X
        # and Y. A square canvas preserves the original sprite aspect ratio.
        canvas=Image.new('RGBA',(extent,extent))
        paste_x=round(canvas.width/2+left);paste_y=round(canvas.height/2+top)
        canvas.paste(image,(paste_x,paste_y))
        encoded=io.BytesIO();canvas.save(encoded,format='PNG');blob=encoded.getvalue()
        filename=hashlib.sha256(blob).hexdigest()[:24]+'.png';(destination/filename).write_bytes(blob)
        target.file=filename;target.height=(extent/density)*.015/skin.meta.key.scale
        # Projected Part3 mesh draws the source Sprite rectangle, not the padded
        # square used by the native overlap Renderer. Only atlas frames packed in
        # a plist carry SpriteFrame trim/offset; loose PNGs keep their full bounds
        # in 4.3.7 (no alpha-bbox crop).
        # Sample outer texel centres (+-0.5px) so maV's packed 2048x2048 atlas
        # never bleeds adjacent gutter pixels into opaque head/tail borders.
        tw,th=texture.get('width',image.width),texture.get('height',image.height)
        tex_trim=texture.get('trim')
        if tex_trim and tw>0 and th>0 and list(tex_trim)!=[0,0,tw,th]:
            tl,tt,tcw,tch=tex_trim
            u0,v0,u1,v1=tl/tw,1-(tt+tch)/th,(tl+tcw)/tw,1-tt/th
            bx0,by0,bx1,by1=u0*image.width,(tt/th)*image.height,u1*image.width,((tt+tch)/th)*image.height
            hx=min(0.5,(bx1-bx0)*.5);hy=min(0.5,(by1-by0)*.5)
            uv=[(paste_x+bx0+hx)/extent,1-(paste_y+by1-hy)/extent,(paste_x+bx1-hx)/extent,1-(paste_y+by0+hy)/extent]
            return uv,[u0,v0,u1,v1]
        hx=min(0.5,image.width*.5);hy=min(0.5,image.height*.5)
        return [(paste_x+hx)/extent,1-(paste_y+image.height-hy)/extent,
                (paste_x+image.width-hx)/extent,1-(paste_y+hy)/extent],None
    for lane,(item,head,pos,end,size,hold_head,body,tail) in enumerate(notes,1):
        part3_body_uv=None
        tap_head_uv=None;hold_head_uv=None;tail_uv=None;chord_head_uv=None
        tap_head_trim=None;hold_head_trim=None;tail_trim=None;chord_head_trim=None
        tap_head_file=None;hold_head_file=None;tail_file=None;body_file=None
        # CreateNoteSprite (437 0x4f29f0) dispatches the LN factory BEFORE
        # choosing images. tex5 is the optional LN head, tex3 falls back to
        # that head, and tex2 is REQUIRED. tex4 is the alternate chord image.
        # A Scale3 body cannot be relabelled as Part3.  The selected factory
        # remains attached to the source recipe below, including sliced and
        # tiled bodies.
        lane_factory=note_factories[item.name].name
        if lane_factory in source_factories and native_integer(item.attrs.get('type2'))==2:
            warning('native-hold-axis-candidate',f'{item.name}: 使用原生拥有 Mesh Part3 固定轴候选；仍需实际场景逐帧验收')
        # Part3 owns the old head/body/tail quads, so the note's rotation and
        # tint can be carried into that mesh.  Validate the source colour here
        # instead of silently dropping it; the runtime applies the same RGBA
        # to every source-owned part after InitObject.
        note_color=item.attrs.get('color','#FFFFFF').upper()
        if not re.fullmatch(r'#[0-9A-F]{6}',note_color):
            error('native-note-color',f'{item.name}: 原音符颜色不是六位十六进制，不能静默替换')
        note_alpha=max(0,min(100,round(native_scalar(item,'opacity',100))))
        if not body:raise ValueError(f'{item.name}: 437 长条工厂需要 tex2，不能用头图补造条身')
        chord=resource(item,'4',note=True)
        head_width,_=sprite_dimensions(size,hold_head[0])
        final=dimensions(item,'size2',item.attrs.get('size','0,0')) if 'size2' in item.attrs else size
        width_end=final[0] if final[0]>0 and abs(float32(final[0]-size[0]))>=.0001 else size[0]
        tail_width,_=sprite_dimensions((width_end,final[1] if width_end!=size[0] else size[1]),tail[0])
        if abs(head_width-tail_width)>.0001 and lane_factory not in source_factories:
            error('native-hold-taper',f'{item.name}: 原长条头尾实际宽度不同，默认原生 Scale3 尚未表达梯形条身')
        part_values=None
        effective_part_values=None
        if lane_factory=='scale3part3':
            from .mui import split_values as _split_values
            values=_split_values(item.attrs.get('part',''))
            if len(values)!=2:raise ValueError(f'{item.name}: Scale3Part3 needs two part boundaries')
            part_values=[native_float(values[0]),native_float(values[1])]
            effective_part_values=part_values
            if all(abs(v)<2**-23 for v in part_values):
                # 437 Scale3Sprite_RebuildParts (0x4fb0b0) substitutes
                # WIDTH thirds for the all-zero sentinel, not height thirds.
                effective_part_values=[float32(body[0]['width']/3),
                                       float32(float32(body[0]['width']*2)/3)]
            if not 0<=effective_part_values[0]<effective_part_values[1]<=body[0]['height']:
                raise ValueError(f'{item.name}: Scale3Part3 part boundaries exceed tex2')
        for kind in (7,6):
            module=skin.modules.add(usage=1,type=kind);module.meta.desc=f'native-{item.name}-{kind}'
            module.param.pivot=4;module.param.alpha=100;module.param.layer=4
            module.scenes.add(source=1,valint=lane)
            # type=7 image[0] feeds the ordinary head and its common image[1]
            # binding feeds overlap. Keep the ordinary head transparent so
            # legacy Key art uses the same explicit overlap layer as 4.3.7.
            # type=6 instead reserves image[3]/[4] for overlap/rear-overlap.
            for slot,textures in enumerate(([[],head] if kind==7 else [[],body,[],[] if lane_factory=='scale3' else hold_head,[] if lane_factory=='scale3' else tail])):
                image=module.note.images.add()
                if slot==0:
                    if chord and (kind==7 or lane_factory in source_factories):
                        chord_head_uv,chord_head_trim=overlap_image(image,item,chord[0],size)
                    else:
                        image.file=blank_name;image.height=1
                elif kind==6 and (slot==2 or lane_factory=='scale3' and slot in (3,4)):
                    image.file=blank_name;image.height=1
                elif textures:
                    if kind==7 or slot in (3,4):
                        crop,trim=overlap_image(image,item,textures[0],size)
                        if kind==7:
                            tap_head_uv=crop;tap_head_trim=trim;tap_head_file=image.file
                        elif slot==3:
                            hold_head_uv=crop;hold_head_trim=trim;hold_head_file=image.file
                        else:
                            tail_uv=crop;tail_trim=trim;tail_file=image.file
                    elif lane_factory=='scale3':
                        image.file=textures[0]['file'];image.height=1
                    elif lane_factory=='scale3part3':
                        image.file=textures[0]['file'];image.height=1
                        # SkinFile's slice is [left,right,top,bottom] in
                        # source pixels.  437's part=(first,last) describes
                        # the middle interval, so the fixed caps are the
                        # first rows and the rows after last.
                        image.slice.extend([0,body[0]['width'],
                            int(round(effective_part_values[0])),
                            int(round(body[0]['height']-effective_part_values[1]))])
                    elif lane_factory=='tile3':
                        # Tile3 repeats the raw body texture; no nine-slice
                        # boundaries may be injected into its source.
                        image.file=textures[0]['file'];image.height=1
                    else:
                        with Image.open(destination/textures[0]['file']) as original:body_image=original.convert('RGBA')
                        anchor=native_integer(item.attrs.get('anchor'),4)
                        if anchor not in range(9):anchor=6
                        try:
                            canvas,canvas_info=hold_body_canvas(body_image,width=head_width,
                                lane_width=spacing,anchor_x=(anchor%3)*.5,return_info=True)
                            padded=hold_body_slice_edges(canvas)
                            if lane_factory=='part3':
                                part3_body_uv=[canvas_info['left']/canvas_info['canvas_width'],
                                    1/padded.height,
                                    (canvas_info['left']+canvas_info['width'])/canvas_info['canvas_width'],
                                    (1+canvas_info['height'])/padded.height]
                        except ValueError as exc:
                            error('native-body-width',f'{item.name}: {exc}')
                        else:
                            encoded=io.BytesIO();padded.save(encoded,format='PNG');blob=encoded.getvalue()
                            filename=hashlib.sha256(blob).hexdigest()[:24]+'.png';(destination/filename).write_bytes(blob)
                            image.file=filename
                        image.slice.extend([0,1,0,1])
                    if kind==6 and slot==1:body_file=image.file
        resolved[item.name]='native_key_note'
        if lane_factory in source_factories:
            anchor=native_integer(item.attrs.get('anchor'),4)
            if anchor not in range(9):anchor=6
            final=dimensions(item,'size2',item.attrs.get('size','0,0')) if 'size2' in item.attrs else size
            width_end=final[0] if final[0]>0 and abs(float32(final[0]-size[0]))>=.0001 else size[0]
            tail_size=sprite_dimensions((width_end,final[1] if width_end!=size[0] else size[1]),tail[0])
            head_size=sprite_dimensions(size,hold_head[0])
            tap_head_size=sprite_dimensions(size,head[0])
            # 0x4f29f0 initializes size2.x to -1. Move only calls SetSize
            # when that field is positive; absence of size2 therefore keeps
            # each Sprite's already resolved MUI size. Intrinsic texture size
            # is NOT an implicit near endpoint. The final factory check also
            # disables a height-only change with an unchanged width.
            size2_active=('size2' in item.attrs and final[0]>0 and not
                (abs(float32(final[0]-size[0]))<.0001 and abs(float32(final[1]-size[1]))!=0))
            legacy_size_end=list(map(float32,size)) if size2_active else None
            legacy_size_start=list(map(float32,final)) if size2_active else None
            tile_width=float32(final[0] if 'size2' in item.attrs else size[0])
            tile_gap=float32(-dimensions(item,'size3')[0]*doc.ui_rounding_height/720) if 'size3' in item.attrs else 0
            if lane_factory=='tile3' and (tile_width<=0 or body[0]['height']+tile_gap<=0):
                raise ValueError(f'{item.name}: Tile3 原定义产生非正宽度或重复步长，不能生成无效条身')
            recipe_row={'factory':lane_factory,'scope':'legacy-source-native-v1',
                'toggle':native_toggle(item.attrs.get('toggle'))&3,'lane_width_720':spacing,
                'start_x':pos[0],'end_x':end[0],'start_y':pos[1],'end_y':end[1],
                'tap_head_size':list(map(float32,tap_head_size)),
                'head_size':list(map(float32,head_size)),'tail_size':list(map(float32,tail_size)),
                'legacy_size_end':legacy_size_end,'legacy_size_start':legacy_size_start,
                'tap_head_uv':tap_head_uv or [0,0,1,1],
                'head_uv':hold_head_uv or [0,0,1,1],
                'tail_uv':tail_uv or [0,0,1,1],
                'tap_head_trim':tap_head_trim,
                'head_trim':hold_head_trim,
                'tail_trim':tail_trim,
                'chord_head_trim':chord_head_trim,
                'tap_head_file':tap_head_file or head[0]['file'],
                'head_file':hold_head_file or hold_head[0]['file'],
                'body_file':body_file,
                'tail_file':tail_file or tail[0]['file'],
                'chord_head_uv':chord_head_uv,
                'anchor':anchor,'rotate':int(native_scalar(item,'rotate')),
                'body_axis':native_integer(item.attrs.get('type2'),0),
                'part':part_values,
                'body_texture_height':body[0]['height'],
                'body_texture_width':body[0]['width'],
                'body_trim':body[0]['trim'],
                'tile_width':tile_width,'tile_gap':tile_gap,
                'body_uv':part3_body_uv or [0,0,1,1],
                'note_color':note_color,
                'note_opacity':note_alpha,
                'legacy_projected':bool(legacy_plane)}
            px_pair=pair(doc,item,'pos')[0];ex_pair=pair(doc,item,'pos2')[0]
            sx_pair,sy_pair=pair(doc,item,'size')
            s2_pair=pair(doc,item,'size2')[0] if 'size2' in item.attrs else [0.0,0.0]
            if any(abs(v[0])>1e-6 for v in (px_pair,ex_pair,sx_pair,s2_pair)):
                recipe_row['x_affine']={
                    'start_x':[float32(px_pair[0]*720),float32(px_pair[1])],
                    'end_x':[float32(ex_pair[0]*720),float32(ex_pair[1])],
                    'size_x':[float32(sx_pair[0]*720),float32(sx_pair[1])],
                    'size2_x':[float32(s2_pair[0]*720),float32(s2_pair[1])] if 'size2' in item.attrs else None,
                    'size2_active':bool(size2_active),
                    'size_auto_h':bool(sy_pair[0]==0 and sy_pair[1]==0),
                    'tap_aspect':float(head[0]['height']/head[0]['width']),
                    'head_aspect':float(hold_head[0]['height']/hold_head[0]['width']),
                    'tail_aspect':float(tail[0]['height']/tail[0]['width'])}
            ui['scale3_recipes'].append(recipe_row)
        if lane_factory=='scale3':
            body_size=sprite_dimensions(size,body[0])
            anchor=native_integer(item.attrs.get('anchor'),4)
            if anchor not in range(9):anchor=6
            part=None
            if 'part' in item.attrs:
                from .mui import split_values as _split_values
                values=_split_values(item.attrs['part'])
                if len(values)!=2:raise ValueError(f'{item.name}: original Scale3 part needs two values')
                part=list(map(native_float,values))
            scale3_recipe={'factory':'scale3','scope':'legacy-source-native-v1',
                'toggle':native_toggle(item.attrs.get('toggle'))&3,'part':part,
                'motion_range_source':'source-whole-scale3','lane_width_720':spacing,
                'source_texture_size':[body[0]['width'],body[0]['height']],
                'note_color':note_color,
                'note_opacity':note_alpha,
                'rotate':int(native_scalar(item,'rotate')),
                'layout':range_layout('scale3',(body[0]['width'],body[0]['height']),body_size,
                    anchor=anchor,logical_height=doc.ui_rounding_height,field_height_720=720,
                    travel_720=pos[1]-end[1],units_per_720=1,judge_offset_720=judge_offsets[item.name])}
            sx_pair=pair(doc,item,'size')[0]
            if abs(sx_pair[0])>1e-6:
                scale3_recipe['x_affine']={'size_x':[float32(sx_pair[0]*720),float32(sx_pair[1])]}
            ui['scale3_recipes'].append(scale3_recipe)
        if lane_factory not in supported_factories and native_toggle(item.attrs.get('toggle'))&2:
            if native_toggle(item.attrs.get('toggle'))&1:
                if 'hold_policy' not in ui:ui['hold_policy']=[0]*keys
                ui['hold_policy'][lane-1]=1
                warning('native-hold-visual-unverified',f'{item.name}: toggle 位 2 已接入原生锁头状态候选；逐状态、Android 及上传验证尚未完成，不能交付')
            else:
                error('native-hold-state',f'{item.name}: toggle 位 2 不隐藏完成条，原生 Key 的退场规则尚未映射')
        if item.motion_bindings.get('motion'):
            error('native-note-motion',f'{item.name}: attached note motion still requires an ordinary native appearance mapping')
        if 'size2' in item.attrs:
            final=dimensions(item,'size2')
            active=final[0]>0 and not (abs(float32(final[0]-size[0]))<.0001 and abs(float32(final[1]-size[1]))!=0)
            if active and lane_factory not in source_factories and any(abs(a-b)>.0001 for a,b in zip(size,final)):
                error('native-key-size2',f'{item.name}: 437 的有效双端尺寸变化尚未映射到普通原生 Key')
        if len(head)>1 or len(body)>1 or len(tail)>1:error('native-note-frames',f'{item.name}: note frame banks require a native appearance mapping')
        if 'tex4' in item.attrs:
            warning('native-chord-appearance',f'{item.name}: source chord-specific appearance has no verified ordinary native condition yet')
    for name,item in doc.elements.items():
        if name.startswith('note-') or not is_key_scene_definition(item):continue
        indexed=re.fullmatch(r'(key|hit|press|judge)-(\d+)',name)
        if indexed and not 1<=int(indexed[2])<=keys:continue
        progress('正在生成原生组件：'+name)
        try:
            if indexed and indexed[1]=='judge':
                kind=native_integer(item.attrs['type']) if 'type' in item.attrs else None
                spec=frame_spec(item.attrs.get('frame',''))
                if kind not in (1,2,3) or 'size' not in item.attrs or not spec:
                    resolved[name]='original_factory_no_visual';continue
                if kind==3:
                    specs=[frame_spec(item.attrs.get('frame'+suffix,'')) for suffix in ('','2','3','4')]
                    if not all(specs):resolved[name]='original_factory_no_visual';continue
                    banks=[]
                    for prefix,first,last,_ in specs:
                        # JudgeFactory owns four FrameGroups. EventFactory's
                        # keep/repeat suffixes are not copied into these groups.
                        # 0050a78e..0050a7af truncates to int, then compares
                        # signed low bytes and sign-extends the first index.
                        first,last=((v+128)%256-128 for v in (first,last))
                        if first>last or last-first+1==256:
                            raise ValueError('Original animated judge has an empty or overflowing signed-byte frame range')
                        frames=[assets.texture(f'{prefix}-{i}.png') for i in range(first,last+1)]
                        banks.append({'frames':[{k:f[k] for k in ('file','width','height')} for f in frames],
                                      'repeat_count':0,'keep_last':False})
                    module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                    size=sprite_dimensions(dimensions(item),banks[0]['frames'][0])
                    native_image(module.image,item,banks[0]['frames'][:1],*size,allow_native_pct=False,row=row)
                    if not attach_plane_ui(item,module,row) and not row['motions']:source_sprite_projection(item,row)
                    event_interval(item,row);interval=row.pop('source_frame_interval')
                    row['source_events']={'kind':'judge','lane':int(indexed[2]),'interval':interval,'banks':banks}
                    if row['motions']:row['source_motion']=True
                    if row not in ui['entries']:ui['entries'].append(row)
                    judge_events.append(row);judge_modules.append((int(indexed[2]),module))
                    resolved[name]='native_judge_state_animator';disabled.add(8);continue
                if kind==2:
                    numberspec=frame_spec(item.attrs.get('frame2',''))
                    if not numberspec:resolved[name]='original_factory_no_visual';continue
                    ui_projection=director_projection(doc.ui_rounding_height,ratio)
                    if 'skew' in item.attrs or 'parent' in item.attrs:
                        raise ValueError('Type=2 source skew/parent transform is not yet mapped to its actual original node hierarchy')
                    textures=[assets.texture(f'{spec[0]}-{i}.png') for i in range(4)]
                    number_glyphs={};number_prefix=f'number-judge-{int(indexed[2])}-'
                    for i in range(16):
                        try:
                            glyph=assets.texture(f'{numberspec[0]}-{i}.png')
                        except FileNotFoundError:
                            continue
                        number_glyphs[i]={k:glyph[k] for k in ('width','height','frame_height')}
                        shutil.copyfile(destination/glyph['file'],destination/f'{number_prefix}{i}.png')
                    if 0 not in number_glyphs:
                        raise ValueError('Original type=2 judge DynamicNumber zero glyph is missing')
                    # maV loads consecutive slots and otherwise stops at the
                    # first absent file. 437 skips missing individual glyphs;
                    # the transparent slots only keep the native provider
                    # available, while number_config retains the real bank.
                    for i in range(12):
                        glyph_path=destination/f'{number_prefix}{i}.png'
                        if not glyph_path.exists():Image.new('RGBA',(1,1)).save(glyph_path)
                    module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                    if row['motions']:
                        raise ValueError('Original type=2 judge stops parent actions on hit; source motion composition is not yet mapped')
                    size=sprite_dimensions(dimensions(item),textures[0])
                    raw_anchor=item.attrs.get('anchor','4')
                    if ',' in raw_anchor:
                        # Legacy_ApplyAnchor divides the two stored absolute
                        # components by the factory node's initial content
                        # size, then keeps that normalized anchor as the
                        # compound width changes on each Hit.
                        components=split_values(raw_anchor)
                        if len(components)!=2:raise ValueError('Original type=2 absolute anchor requires two components')
                        source_size=[float32(v*doc.ui_rounding_height/720) for v in size]
                        if min(source_size)<=0:raise ValueError('Original type=2 absolute anchor has no initial content size')
                        anchor_xy=[float32(native_float(value)/extent) for value,extent in zip(components,source_size)]
                    else:
                        anchor=native_integer(raw_anchor)
                        if anchor not in range(9):raise ValueError('Original type=2 numeric anchor outside 0..8 is not mapped')
                        anchor_xy=[(anchor%3)*.5,1-(anchor//3)*.5]
                    native_image(module.image,item,textures[:1],*size,allow_native_pct=False,row=row)
                    banks=[{'frames':[{k:t[k] for k in ('file','width','height')}],
                            'repeat_count':0,'keep_last':True} for t in textures]
                    number_name=f'{name}__number'
                    number_module=skin.modules.add(usage=99,type=5003)
                    number_row=base(item,number_module,name=number_name,tint=False)
                    number_module.param.alpha=0
                    number_module.number.file=f'{number_prefix}0.png'
                    number_module.number.filebase=number_prefix
                    # A source grade counter is not the chart combo. fjg()
                    # binds tokens to native WatchForInt callbacks at Setup;
                    # a {combo} placeholder keeps overwriting our per-grade
                    # value after every judgement (including LN tails).
                    number_module.number.text='0'
                    number_module.number.height=size[1]/doc.ui_rounding_height*100
                    number_module.number.padding=0
                    # JudgeFactory's type=2 DynamicNumber is a child of the
                    # same 437 parent as the grade image.  The native image
                    # adapter already applies the 1.5 source-to-Module unit
                    # conversion (see native_image above); using the generic
                    # 1080/UI-height factor here enlarged every counter glyph
                    # by 20% and made the number overlap the grade image.
                    # Keep the DynamicNumber in that same parent unit domain.
                    number_config={'glyphs':{str(k):v for k,v in number_glyphs.items()},
                                   'height':size[1],
                                   # JudgeFactory 0050a570 copies attribute
                                   # 0x29 (size2.x) into DynamicNumber+0x33c.
                                   # This is the parser's logical float, not
                                   # a pixel gap and not pos2. Preserve even
                                   # zero/negative factors; missing means 1.
                                   'spacing':float32(dimensions(item,'size2')[0]*doc.ui_rounding_height/720) if 'size2' in item.attrs else 1,
                                   'proportional':False,
                                   'units_per_pixel':1.5}
                    # The judge callback is the authoritative source of this
                    # per-grade counter.  Do not let the generic number
                    # reader infer text from a stale native glyph pool.
                    number_row['managed_by_judge']=True
                    number_row['source_judge_counter_number']=number_config
                    if number_row not in ui['entries']:ui['entries'].append(number_row)
                    row['source_judge_counter']={'kind':'judge_counter','lane':int(indexed[2]),
                        'all_lanes':False,'number_handle':number_name,'number':number_config,
                        'anchor_x':anchor_xy[0], 'anchor_y':anchor_xy[1],
                        'source_position':source_ui_position(item),
                        'projection':ui_projection,
                        'compiled_ratio':ratio,
                        'source_pct_x':source_ui_x_pct(item),
                        'axis_rotation':-module.param.rotate,
                        'banks':banks}
                    if row not in ui['entries']:ui['entries'].append(row)
                    judge_events.append(row);judge_modules.append((int(indexed[2]),module))
                    resolved[name]='native_judge_counter';disabled.add(8);continue
                if kind==1:
                    textures=[assets.texture(f'{spec[0]}-{i}.png') for i in range(4)]
                    module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                    if row['motions']:row['source_motion']=True
                    size=sprite_dimensions(dimensions(item),textures[0])
                    native_image(module.image,item,textures[:1],*size,allow_native_pct=False,row=row)
                    if not attach_plane_ui(item,module,row):source_sprite_projection(item,row)
                    row['source_events']={'kind':'judge','lane':int(indexed[2]),'interval':1,
                        'static_effect':True,'banks':[{'frames':[{k:t[k] for k in ('file','width','height')}],
                            'repeat_count':0,'keep_last':True} for t in textures]}
                    if row not in ui['entries']:ui['entries'].append(row)
                    judge_events.append(row);judge_modules.append((int(indexed[2]),module))
                    resolved[name]='native_judge_static_source_actions';disabled.add(8);continue
            if name in ('score-hp','progress'):
                # KeyUIS selects HpFactory, not GenericElementFactory, for
                # both widgets. A missing type is a NULL factory, not type=0.
                kind=native_integer(item.attrs['type']) if 'type' in item.attrs else None
                spec=frame_spec(item.attrs.get('frame','')) if kind==1 else None
                if (kind not in (0,1) or kind==0 and 'tex' not in item.attrs or
                        kind==1 and ('count' not in item.attrs or not spec or spec[2]-spec[1]+1<2)):
                    resolved[name]='original_factory_no_visual';continue
                count=native_integer(item.attrs['count']) if kind==1 else 1
                if not 0<=count<=4096:raise ValueError('Original meter child count exceeds verified bounded allocation')
                # Dot factory always opens <prefix>-0/1, even when the
                # declared frame range starts at another index. flip, tex
                # and interval do not select or animate its frame bank.
                names=[item.attrs['tex']] if kind==0 else [f'{spec[0]}-{i}.png' for i in (0,1)]
                textures=[]
                for filename in names:
                    texture=dict(assets.texture(filename))
                    key=filename.lstrip('"').replace('\\','/').casefold()
                    frame=assets.frames.get(key) if key not in assets.direct else None
                    offset=frame[1].get('offset',frame[1].get('spriteOffset','{0,0}')) if frame else '{0,0}'
                    texture['offset']=[float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',str(offset))][:2]
                    textures.append(texture)
                module=skin.modules.add(usage=4 if name=='score-hp' else 5,type=4900)
                row=base(item,module,tint=False);width_i,height_i=dimensions(item)
                module.image.file=textures[0]['file']
                module.image.width=width_i*1.5;module.image.height=height_i*1.5
                module.image.wu=module.image.hu=1
                module.image.valint=100
                meter_cfg={'kind':'line' if kind==0 else 'dots','count':count,
                    'visible':native_integer(item.attrs.get('show'),1)!=0,
                    'size':[float32(v*doc.ui_rounding_height/720) for v in (width_i,height_i)],
                    'reverse':native_integer(item.attrs.get('type2'))==1,
                    'spacing':float32(dimensions(item,'pos2')[0]*doc.ui_rounding_height/720) if 'pos2' in item.attrs else None,
                    'frames':[{k:t[k] for k in ('file','width','height','trim','offset')} for t in textures],
                    'units_per_pixel':1080/doc.ui_rounding_height}
                msx,_=pair(doc,item,'size')
                if abs(msx[0])>1e-6:
                    meter_cfg['size_pct_x']=float32(msx[0]*doc.ui_rounding_height)
                    meter_cfg['size_px_x']=float32(msx[1]*doc.ui_rounding_height/720)
                    row['source_size']={'w_pct':float32(msx[0]*1080),'w_px':float32(msx[1]*1.5),'auto_h':False,'aspect':1.0}
                if 'pos2' in item.attrs:
                    mp2x,_=pair(doc,item,'pos2')
                    if abs(mp2x[0])>1e-6:
                        meter_cfg['spacing_pct_x']=float32(mp2x[0]*doc.ui_rounding_height)
                        meter_cfg['spacing_px_x']=float32(mp2x[1]*doc.ui_rounding_height/720)
                row['source_meter']=meter_cfg
                if row not in ui['entries']:ui['entries'].append(row)
                disabled.add(2 if name=='score-hp' else 10)
                resolved[name]='native_source_meter';continue
            # Dispatch exactly the selected old factory BEFORE resolving any
            # resources. Unused attributes cannot create a sprite or reject a
            # skin because a file that 437 never opens happens to be absent.
            if is_scene_custom(item):
                kind=native_integer(item.attrs.get('type'))
                absent=(kind==0 and 'tex' not in item.attrs or kind==1 and 'text' not in item.attrs or
                        kind==3 and 'frame' not in item.attrs or
                        kind==2 and 'color' not in item.attrs or kind==4 and not {'part','tex'}.issubset(item.attrs))
                if absent:
                    resolved[name]='original_factory_no_visual';continue
                if kind==3:
                    if not frame_spec(item.attrs['frame']):
                        raise ValueError('Original StateAnimator requires a parsed frame range')
                    textures=resource(item)
                    # ParseFile stores atof in this scalar slot; EventFactory
                    # casts that float to int. Scientific notation is valid.
                    interval=math.trunc(native_scalar(item,'interval',10))
                    # StateAnimator::AddBank (005029c0) resets a strictly
                    # negative interval to 10 after the factory's int cast.
                    if interval<0:interval=10
                    if interval==0:raise ValueError('Original StateAnimator zero interval is not mapped')
                    width_i,height_i=sprite_dimensions(dimensions(item),textures[0],explicit_zero=('size' in item.attrs))
                    module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                    native_image(module.image,item,textures[:1],width_i,height_i,allow_native_pct=False,row=row)
                    zero_static=width_i==0 and height_i==0 and not any(m['method'] in ('DoResize','DoWidth','DoHeight') for m in row['motions'])
                    if zero_static:module.param.alpha=0
                    elif not attach_plane_ui(item,module,row) and not row['motions']:source_sprite_projection(item,row)
                    row['source_frames']={'interval':interval,'frames':[
                        {key:texture[key] for key in ('file','width','height')} for texture in textures],
                        'enabled':native_integer(item.attrs.get('show'),1)!=0}
                    if any(m['method'] in ('DoWidth','DoHeight','DoResize') for m in row['motions']):
                        # NativeUiMotion applies the size record first and
                        # NativeUiFrames then applies the SpriteFrame ratio;
                        # this preserves the old frame-size coupling instead
                        # of rejecting otherwise valid 437 StateAnimator UI.
                        warning('native-ui-frame-size-motion',f'{name}: StateAnimator 换帧与尺寸动画按原顺序组合，仍需原生逐帧验收')
                    if row not in ui['entries']:ui['entries'].append(row)
                    resolved[name]='native_state_animator';continue
                if kind not in (0,1,2,4):
                    if kind in (5,6,101,102,103,104,105,106,107,108,109):
                        raise ValueError(f'Original generic factory type={kind} has no verified native UI mapping')
                    # Default switch branch returns without constructing an
                    # image. A stray tex cannot select the plain Sprite path.
                    resolved[name]='original_factory_no_visual';continue
                if kind==2:
                    module=skin.modules.add(usage=99,type=5004);row=base(item,module,tint=False)
                    apply_solid_size(module,row,item);attach_plane_ui(item,module,row,solid=True)
                    resolved[name]='native_solid';continue
                if kind==4:
                    textures=resource(item)
                    if not textures:raise ValueError(f'{name}: original strip texture missing')
                    from .mui import split_values as _split_values
                    parts=_split_values(item.attrs['part'])
                    if len(parts)!=2:raise ValueError('Original strip requires two part boundaries')
                    first,last=map(native_float,parts);strip_kind=native_integer(item.attrs.get('type2'))
                    if strip_kind not in (0,1,2,3):raise ValueError('Original strip orientation outside verified factory branches')
                    texture=textures[0];tw,th=texture['width'],texture['height']
                    # The source sentinel uses WIDTH thirds, also vertically.
                    if first==last==0:first,last=float32(tw/3),float32(tw*2/3)
                    axis=th if strip_kind in (1,3) else tw
                    if not 0<=first<last<=axis or strip_kind in (2,3) and (first==0 or last==axis):
                        raise ValueError('Original strip outside/singular texture segments are not mapped')
                    width_i,height_i=sprite_dimensions(dimensions(item),texture)
                    secondary=None
                    if 'size2' in item.attrs:
                        secondary=float32(dimensions(item,'size2')[strip_kind%2]*doc.ui_rounding_height/720)
                        if secondary<=0:raise ValueError('Original strip nonpositive secondary content extent is not mapped')
                    module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                    native_image(module.image,item,textures[:1],width_i,height_i,allow_native_pct=False,row=row)
                    strip_cfg={'file':texture['file'],'width':tw,'height':th,
                        'kind':strip_kind,'first':first,'last':last,
                        'size':[float32(v*doc.ui_rounding_height/720) for v in (width_i,height_i)],
                        'secondary':secondary}
                    ssx,ssy=pair(doc,item,'size')
                    if abs(ssx[0])>1e-6:
                        strip_cfg['size_pct_x']=float32(ssx[0]*doc.ui_rounding_height)
                        strip_cfg['size_px_x']=float32(ssx[1]*doc.ui_rounding_height/720)
                        strip_cfg['size_auto_h']=(ssy[0]==0 and ssy[1]==0)
                    if 'size2' in item.attrs and strip_kind%2==0:
                        s2x,_=pair(doc,item,'size2')
                        if abs(s2x[0])>1e-6:
                            strip_cfg['secondary_pct_x']=float32(s2x[0]*doc.ui_rounding_height)
                            strip_cfg['secondary_px_x']=float32(s2x[1]*doc.ui_rounding_height/720)
                    row['source_strip']=strip_cfg
                    attach_plane_ui(item,module,row)
                    if row not in ui['entries']:ui['entries'].append(row)
                    resolved[name]='native_strip';continue
            if name=='touch':
                shape=native_integer(item.attrs.get('type'),1)
                if shape not in (1,3):raise ValueError(f'Touch shape {shape} is not mapped')
                prefix='rect' if shape==1 else 'array'
                for lane in range(1,keys+1):
                    attr=prefix+('' if lane==1 else str(lane))
                    values=touch_coordinates(doc,item,attr) if attr in item.attrs else [[0,0] for _ in range(4)]
                    if shape==1:
                        if len(values)!=4:raise ValueError('Touch rectangle must have x,y,width,height')
                        x,y,w,h=values
                        width_extent=float32(720*doc.ratio);height_extent=float32(720)
                        axis=lambda value,extent:float32(value[0]*extent+value[1])
                        px,py,pw,ph=axis(x,width_extent),axis(y,height_extent),axis(w,width_extent),axis(h,height_extent)
                        points=[[px,py],[px+pw,py],[px+pw,py+ph],[px,py+ph]]
                        affine_x=[[x[0]*720,x[1]],[(x[0]+w[0])*720,x[1]+w[1]],
                                  [(x[0]+w[0])*720,x[1]+w[1]],[x[0]*720,x[1]]]
                    else:
                        if len(values)<6 or len(values)%2:raise ValueError('Touch polygon needs at least three coordinate pairs')
                        width_extent=float32(720*doc.ratio);height_extent=float32(720)
                        axis=lambda value,extent:float32(value[0]*extent+value[1])
                        points=[[axis(values[i],width_extent),axis(values[i+1],height_extent)] for i in range(0,len(values),2)]
                        affine_x=[[values[i][0]*720,values[i][1]] for i in range(0,len(values),2)]
                    touch_row={'lane':lane,'points':points,'handle':f'legacy_touch_{lane}'}
                    if any(abs(p[0])>1e-6 for p in affine_x):
                        touch_row['points_pct']=[p[0] for p in affine_x]
                        touch_row['points_px']=[p[1] for p in affine_x]
                    ui['touches'].append(touch_row)
                warning('native-touch-regions-unverified','Original TouchAreaPolygon regions are emitted; physical touch/slide acceptance remains pending')
                resolved[name]='native_touch_regions';continue
            if name=='musicbar':
                width_i,height_i=dimensions(item)
                config=compile_musicbar(item,width_i,height_i,assets,logical_height=doc.ui_rounding_height)
                if config is None:
                    resolved[name]='original_factory_no_visual';continue
                if not (ui.get('source_visual_pool') and ui.get('native_frame_driver')):
                    raise ValueError('Original musicbar requires the recovered source visual context')
                raw_anchor=item.attrs.get('anchor','4')
                if ',' in raw_anchor:raise ValueError('Original musicbar absolute anchor is not yet mapped')
                anchor=native_integer(raw_anchor)
                if anchor not in range(9):raise ValueError('Original musicbar anchor outside 0..8 is not mapped')
                config.update(projection=director_projection(doc.ui_rounding_height,ratio),
                    source_position=source_ui_position(item),
                    source_anchor=[(anchor%3)*.5,1-(anchor//3)*.5],
                    compiled_ratio=ratio,
                    source_pct_x=source_ui_x_pct(item))
                mbsx,_=pair(doc,item,'size')
                module=skin.modules.add(usage=99,type=5000);row=base(item,module,alpha=100,tint=False)
                if abs(mbsx[0])>1e-6:
                    config['size_pct_x']=float32(mbsx[0]*doc.ui_rounding_height)
                    config['size_px_x']=float32(mbsx[1]*doc.ui_rounding_height/720)
                    row['source_size']={'w_pct':float32(mbsx[0]*1080),'w_px':float32(mbsx[1]*1.5),'auto_h':False,'aspect':1.0}
                module.image.file=config['textures'][0]['file']
                module.image.width=width_i*1.5;module.image.height=height_i*1.5
                module.image.wu=module.image.hu=1
                # SkinRuntime.GetTexture only exposes resources declared by
                # the imported module.  Declare every procedural widget
                # image on this owner while keeping the visible provider as
                # the original background image.
                if musicbar_resource_holder is None:
                    musicbar_resource_holder=skin.modules.add(usage=99,type=5000)
                    musicbar_resource_holder.meta.desc='native-musicbar-resources'
                for texture in config['textures']:
                    if not any(existing.file==texture['file'] for existing in musicbar_resource_holder.images.items):
                        musicbar_resource_holder.images.items.add(file=texture['file'],width=texture['width'],height=texture['height'])
                row['source_musicbar']=config
                if row not in ui['entries']:ui['entries'].append(row)
                disabled.add(18)
                warning('native-source-musicbar-unverified','Original musicbar resources, bins and result state require paired native visual verification')
                resolved[name]='native_source_musicbar';continue
            width_i,height_i=dimensions(item)
            if name.startswith('score-') and name!='score-hp':
                token={'score-score':'score','score-combo':'combo','score-maxcombo':'maxcombo','score-acc':'acc'}[name]
                spec=frame_spec(item.attrs.get('frame',''))
                if not spec:raise ValueError('Original NumberSprite glyph bank missing')
                prefix=f'number-{token}-'
                glyphs={}
                for index in range(16):
                    try:texture=assets.texture(f'{spec[0]}-{index}.png')
                    except FileNotFoundError:continue
                    glyphs[index]={key:texture[key] for key in ('width','height','frame_height')}
                    shutil.copyfile(destination/texture['file'],destination/f'{prefix}{index}.png')
                if 0 not in glyphs:raise ValueError('Original NumberSprite zero glyph is missing; its null-frame layout is not mapped')
                # maV's provider requires consecutive digits and stops at the
                # first absent file. 437 allows sparse banks and skips absent
                # glyphs. Keep native values intact and supply transparent
                # provider slots; the layout adapter hides/skips those slots.
                for index in range(12):
                    target=destination/f'{prefix}{index}.png'
                    if not target.exists():Image.new('RGBA',(1,1)).save(target)
                source_height=math.trunc(native_dimension(doc,item,'fsize',20))
                if source_height<=0:raise ValueError('Original NumberSprite nonpositive height is not mapped')
                module=skin.modules.add(usage=99,type=5003);row=base(item,module)
                module.number.file=prefix+'0.png';module.number.filebase=prefix
                module.number.text='{'+token+'}';module.number.height=source_height/doc.ui_rounding_height*100
                module.number.padding=0
                row['source_number']={'glyphs':{str(k):v for k,v in glyphs.items()},'height':source_height,
                    'spacing':float32(dimensions(item,'pos2')[0]*doc.ui_rounding_height/720) if 'pos2' in item.attrs else 1,
                    'proportional':native_integer(item.attrs.get('type2'))!=0,
                    'units_per_pixel':1080/doc.ui_rounding_height}
                attach_plane_ui(item,module,row,number=True)
                if row not in ui['entries']:ui['entries'].append(row)
                disabled.add({'score':3,'combo':4,'acc':5,'maxcombo':4}[token]);resolved[name]='native_number';continue
            if ('text' in item.attrs and native_integer(item.attrs.get('type'))==1 and
                    not (indexed and indexed[1] in ('key','press','hit'))):
                # 0060e920: integer logical size -> roundf(size*1.5),
                # Label scale=1/1.5. Keep old coverage and glyph metrics.
                requested=math.trunc(native_dimension(doc,item,'fsize',24))
                pixels=math.floor(float32(requested*1.5)+.5)
                if not 1<=pixels<=1024:raise ValueError('Original Label font size is outside the mapped raster range')
                from .font_generator import FontGenerator
                if 'generator' not in font_context:
                    reference=json.loads((font_bank()/'font-bank.json').read_text(encoding='utf8'))
                    font_context['generator']=FontGenerator(DATA,ROOT,reference)
                generator=font_context['generator']
                font=generator.export_external_size(pixels,font_groups.get(pixels),destination,progress=progress,hybrid=True)
                module=skin.modules.add(usage=99,type=5001);row=base(item,module,tint=False)
                from .text_variables import translate_native_key
                module.text.text,_,unresolved,version=translate_native_key(item.attrs['text'])
                if unresolved:error('native-text-template',f'{name}: 原文本的嵌套占位符尚未映射：'+', '.join(sorted(unresolved)))
                module.text.font=1;module.text.size=native_dimension(doc,item,'fsize',24)/doc.ui_rounding_height*100
                module.text.color=valid_hex_color(item.attrs.get('color'));disabled.add(14)
                row['source_text']={'font':font,'units_per_pixel':1080/doc.ui_rounding_height/1.5}
                if version:row['source_text'].update(version)
                if not row['motions']:source_sprite_projection(item,row)
                if row not in ui['entries']:ui['entries'].append(row)
                if row['motions'] and any(m['method'] in ('DoWidth','DoHeight','DoResize') for m in row['motions']):
                    error('native-label-size-motion',f'{name}: Label 直接尺寸动画与字形内容尺寸耦合尚未映射')
                warning('native-font',f'{name}: original coverage and metrics emitted; native Label placement/lifecycle acceptance remains pending')
                resolved[name]='native_source_label';continue
            if indexed and indexed[1] in ('press','hit') and 'frame' not in item.attrs:
                resolved[name]='original_factory_no_visual';continue
            if indexed and indexed[1]=='key' and 'tex' not in item.attrs:
                resolved[name]='original_factory_no_visual';continue
            if name=='bar' and 'tex' not in item.attrs:
                # CreateNoteSprite(kind=0) returns NULL before opening any
                # resource unless tex exists. A frame bank is not a fallback.
                resolved[name]='original_factory_no_visual';continue
            if indexed and indexed[1]=='hit':
                # BuildUI stores a NULL slot unless EventFactory constructed
                # EXACTLY three consecutive frame banks. Unused tex/text or
                # an extra fourth bank must not synthesize a hit effect.
                count=0
                for bank_index in range(9):
                    suffix='' if bank_index==0 else str(bank_index+1)
                    if not frame_spec(item.attrs.get('frame'+suffix,'')):break
                    count+=1
                if count!=3:
                    resolved[name]='original_factory_no_visual';continue
            textures=resource(item)
            if name=='bar':
                if not textures:raise ValueError('Original bar texture missing')
                if not source_supported or not legacy_plane:
                    raise ValueError('Original bar Sprite geometry requires the source Key visual plane')
                module=skin.modules.add(usage=9,type=4600);bar_row=base(item,module)
                native_image(module.image,item,textures,width_i,height_i);disabled.add(17)
                start_size=sprite_dimensions((width_i,height_i),textures[0])
                end_size=dimensions(item,'size2',default='-1,0')
                resize=end_size[0]>0 and not (abs(float32(end_size[0]-width_i))<.0001 and
                                               abs(float32(end_size[1]-height_i))!=0)
                anchor=native_integer(item.attrs.get('anchor'),4)
                bar_cfg={'file':textures[0]['file'],
                    'start':dimensions(item,'pos'),'finish':dimensions(item,'pos2'),
                    'size':list(start_size),'end_size':list(sprite_dimensions(end_size,textures[0])) if resize else None,
                    'anchor':anchor if anchor in range(9) else 6,
                    'rotate':int(native_scalar(item,'rotate')),
                    'before_notes':painter_keys[name]<scene_key('note-1',None)}
                bpx=pair(doc,item,'pos')[0];bp2x=pair(doc,item,'pos2')[0]
                bsx,bsy=pair(doc,item,'size')
                bs2x=pair(doc,item,'size2')[0] if 'size2' in item.attrs else [0.0,0.0]
                if any(abs(v[0])>1e-6 for v in (bpx,bp2x,bsx,bs2x)):
                    bar_cfg['x_affine']={
                        'start':[float32(bpx[0]*720),float32(bpx[1])],
                        'finish':[float32(bp2x[0]*720),float32(bp2x[1])],
                        'size':[float32(bsx[0]*720),float32(bsx[1])],
                        'end_size':[float32(bs2x[0]*720),float32(bs2x[1])] if resize else None,
                        'auto_h':(bsy[0]==0 and bsy[1]==0),
                        'aspect':float(textures[0]['height']/textures[0]['width'])}
                ui['source_bar']=bar_cfg
                if bar_row.get('color'):ui['source_bar']['color']=bar_row['color']
                # Keep the native image solely as an importer/resource provider.
                # PlayBarKey ignores source height, path and painter metadata;
                # the ordinary script owns only its source Sprite appearance.
                resolved[name]='native_source_bar';continue
            if not textures and is_scene_custom(item) and native_integer(item.attrs.get('type'))==2:
                module=skin.modules.add(usage=99,type=5004);row=base(item,module)
                apply_solid_size(module,row,item);attach_plane_ui(item,module,row,solid=True)
                resolved[name]='native_solid';continue
            if not textures:
                # An unselected generic factory has no visible resource in 437.
                if is_scene_custom(item) and native_integer(item.attrs.get('type'))==0:
                    resolved[name]='original_factory_no_sprite';continue
                raise ValueError('Original visible resource has no native mapping')
            width_i,height_i=sprite_dimensions((width_i,height_i),textures[0],explicit_zero=('size' in item.attrs))
            if indexed and indexed[1]=='key':
                second=resource(item,'2')
                if second:
                    # Original ResponseFrame replaces the SpriteFrame of the
                    # SAME Sprite. Its factory scale, opacity and animations
                    # survive even when the alternate canvas differs.
                    module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                    native_image(module.image,item,textures[:1],width_i,height_i,allow_native_pct=False,row=row)
                    if not attach_plane_ui(item,module,row) and not row['motions']:source_sprite_projection(item,row)
                    row['source_events']={'kind':'key','lane':int(indexed[2]),'interval':10,
                        'banks':[{'frames':[{k:f[k] for k in ('file','width','height')}],
                                  'keep_last':True,'repeat_count':0} for f in (textures[0],second[0])]}
                    if row['motions']:row['source_motion']=True
                    if any(m['method'] in ('DoWidth','DoHeight','DoResize') for m in row['motions']):
                        warning('native-event-frame-size-motion',f'{name}: ResponseFrame 切图与尺寸动画按原顺序组合，仍需原生逐帧验收')
                    if row not in ui['entries']:ui['entries'].append(row)
                    resolved[name]='native_key_response_frame';continue
            if indexed and indexed[1] in ('press','hit'):
                # KeyUIS owns one StateAnimator, not independent down/up
                # Images. Bank zero keeps its last submitted frame; release
                # selects bank one only from bank zero. Animated opacity is
                # separate from the node's visible flag.
                event_kind=indexed[1];banks=[]
                for bank_index in range(9):
                    suffix='' if bank_index==0 else str(bank_index+1)
                    spec=frame_spec(item.attrs.get('frame'+suffix,''))
                    if not spec:break
                    frames=resource(item,suffix)
                    if not frames:raise ValueError('Original event bank has no source frames')
                    banks.append({'frames':[{k:f[k] for k in ('file','width','height')} for f in frames],
                        'repeat_count':-1 if spec[3]=='+' or event_kind=='hit' and bank_index==1 else 0,
                        'keep_last':event_kind=='press' and bank_index==0 or spec[3]=='~'})
                module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                native_image(module.image,item,textures[:1],width_i,height_i,allow_native_pct=False,row=row)
                if not attach_plane_ui(item,module,row) and not row['motions']:source_sprite_projection(item,row)
                event_interval(item,row);interval=row.pop('source_frame_interval')
                row['source_events']={'kind':event_kind,'lane':int(indexed[2]),'interval':interval,'banks':banks}
                if row['motions']:
                    row['source_motion']=True
                    if any(m['method'] in ('DoWidth','DoHeight','DoResize') for m in row['motions']):
                        warning('native-event-frame-size-motion',f'{name}: StateAnimator 换帧与尺寸动画按原顺序组合，仍需原生逐帧验收')
                disabled.add(13 if event_kind=='press' else 12)
                resolved[name]='native_'+event_kind+'_state_animator';continue
            if name in ('hit-fast','hit-slow'):
                spec=frame_spec(item.attrs.get('frame',''))
                if not spec:resolved[name]='original_factory_no_visual';continue
                module=skin.modules.add(usage=99,type=5000);row=base(item,module)
                native_image(module.image,item,textures[:1],width_i,height_i,allow_native_pct=False,row=row)
                if not attach_plane_ui(item,module,row) and not row['motions']:source_sprite_projection(item,row)
                event_interval(item,row);interval=row.pop('source_frame_interval')
                row['source_events']={'kind':'timing','fast':name=='hit-fast','interval':interval,
                    'banks':[{'frames':[{k:f[k] for k in ('file','width','height')} for f in textures],
                              'repeat_count':-1 if spec[3]=='+' else 0,'keep_last':spec[3]=='~'}]}
                if row['motions']:
                    row['source_motion']=True
                    if any(m['method'] in ('DoWidth','DoHeight','DoResize') for m in row['motions']):
                        warning('native-event-frame-size-motion',f'{name}: StateAnimator 换帧与尺寸动画按原顺序组合，仍需原生逐帧验收')
                disabled.add(9)
                resolved[name]='native_timing_state_animator';continue
            module=skin.modules.add(usage=2 if name=='pause' else 99,type=5002 if len(textures)>1 else 5000)
            row=base(item,module)
            native_image(module.image,item,textures,width_i,height_i,frames=module.type==5002,
                allow_native_pct=not (row.get('source_motion') or textures[0].get('source_texture_clamp')),row=row)
            zero_static=width_i==0 and height_i==0 and not any(m['method'] in ('DoResize','DoWidth','DoHeight') for m in row['motions'])
            if zero_static:
                module.param.alpha=0
                row.pop('source_size',None)
            else:
                plane_bound=attach_plane_ui(item,module,row)
                if (not plane_bound and is_scene_custom(item) and native_integer(item.attrs.get('type'))==0 and
                        module.type==5000 and not row['motions']):
                    source_sprite_projection(item,row)
            if module.type==5000 and textures[0].get('source_texture_clamp'):
                # Old standalone textures clamp at the image edge. Native UI
                # atlas UV edges instead interpolate adjacent packed pixels.
                # Bind the game's own original-file texture loader for this
                # static Image; do not inset UVs and shrink its source art.
                row['source_texture']=textures[0]['file']
                if row not in ui['entries']:ui['entries'].append(row)
            if module.type==5002:setattr(module.image,'repeat',1)
            if name=='pause':disabled.add(1)
            resolved[name]='native_ui'
        except (ValueError,KeyError,IndexError,FileNotFoundError) as exc:
            error('native-component',f'{name}: {exc}');resolved[name]='unmapped'
    global_judge=len(judge_modules)==1 and judge_modules[0][0]==1
    for row in judge_events:
        if row.get('source_events') is not None: row['source_events']['all_lanes']=global_judge
        if row.get('source_judge_counter') is not None: row['source_judge_counter']['all_lanes']=global_judge
    if not global_judge:
        for lane,module in judge_modules:
            if lane==1 and module.type==4800:module.scenes.add(source=1,valint=lane)
    if 'pause' not in resolved and 'ui-play-pause.png' in assets.source_names:
        pause_tex=assets.texture('ui-play-pause.png')
        pause_mod=skin.modules.add(usage=2,type=5000)
        pause_mod.meta.desc='native-source-pause'
        pause_mod.param.pivot=0
        pause_mod.param.alpha=100
        pause_mod.param.layer=4
        pause_mod.param.order=max(painter_order.values(),default=-1)+1
        pause_mod.param.x=0;pause_mod.param.y=100
        pause_mod.param.dx=0;pause_mod.param.dy=-15
        pause_mod.param.dxu=pause_mod.param.dyu=1
        pause_mod.image.file=pause_tex['file']
        pause_h=150.0
        pause_w=pause_h*pause_tex['width']/pause_tex['height'] if pause_tex['height']>0 else pause_h
        pause_mod.image.width=float32(pause_w);pause_mod.image.height=float32(pause_h)
        pause_mod.image.wu=pause_mod.image.hu=1
        disabled.add(1)
        resolved['pause']='native_source_pause_fallback'
    hitsounds=[]
    for grade,trigger in (('best',11),('cool',12),('good',13)):
        sound=doc.directives.get(grade)
        if not sound:continue
        target=assets.direct.get(sound.replace('\\','/').casefold())
        if not target: error('native-sound',f'{grade}: sound resource missing: {sound}');continue
        blob=target.read_bytes();filename=hashlib.sha256(blob).hexdigest()[:24]+target.suffix.lower()
        (destination/filename).write_bytes(blob)
        module=skin.modules.add(usage=99,type=5006);module.meta.desc='native-sound-'+grade
        module.param.alpha=100;module.param.layer=4;module.triggers.add(source=trigger,flag=4)
        module.sound.file=filename;module.sound.volume=100;module.sound.hitsound=True
        hitsounds.append({'handle':module.meta.desc,'volume':100})
    if hitsounds:
        ui['hitsounds']=hitsounds
    skin.disabled.extend(sorted(disabled))
    if ui.get('source_visual_pool') and not ui.get('source_bar'):
        ui['suppress_native_bar']=True
    if ui['entries'] or ui.get('hold_policy') or ui.get('source_visual_pool') or ui.get('suppress_native_bar') or ui.get('hitsounds'):
        skin.meta.script='native_ui.lua'
        (destination/'native_ui.json').write_text(json.dumps(ui,ensure_ascii=False,allow_nan=False),encoding='utf-8')
        (destination/'native_ui.lua').write_bytes(basic_script(ui))
    errors=sum(issue['severity']=='error' for issue in issues)
    report={'keys':keys,'source_platform':source_platform,'errors':errors,'issues':issues,
            'original_note_factories':{name:factory.record() for name,factory in note_factories.items()},
            'module_count':len(skin.modules),'element_resolution':resolved,
            'render_backend':'native_key','native_declarative':not skin.meta.script,
            'native_hold_visual_candidate':bool(ui.get('hold_policy')),
            'private_visual_fields_used':bool(ui.get('hold_policy') or source_supported),
            'native_source_whole_backend':source_whole,
            'native_source_part3_backend':source_part3,
            'native_source_mixed_backend':source_mixed,
            'native_key_renderer':True,'free':False,'chart_source_read_by_skin':source_supported,
            'custom_note_clock':False,'custom_judge':False,'score_eligibility_modified':False,
            'ui_rounding_height':doc.ui_rounding_height,'aspect_thresholds':sorted(doc.aspect_thresholds),
            'one_to_one_verified':False,'full_acceptance':False,
            'native_render_verified_for_this_package':False,'skin_upload_verified':False,
            'normal_score_submission_verified':False}
    binary=skin.SerializeToString(deterministic=True)
    (destination/'info.asm').write_bytes(binary)
    (destination/'info.json').write_text(json.dumps(skin_info_payload(skin.meta,keys),ensure_ascii=False),encoding='utf-8')
    (destination/'conversion-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return report
