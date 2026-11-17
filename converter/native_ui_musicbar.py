"""437 MusicBarFactory resources for ordinary native Key UI.

This module emits visual data only.  The six widget functions, factory and
KeyUIS callbacks were recovered into output/native-musicbar-20261114-r1/core.
Gameplay chart parsing, input, judgement, score and Replay are not replaced.
"""
from __future__ import annotations

import hashlib
import io
import math
import re

from PIL import Image

from .mui import native_integer
from .native_numeric import float32


WIDGET_TEXTURES = ('g-white.png', 'play-start.png', 'play-end.png', 'play-seek.png')


def widget_texture(assets, name):
    """Retain the source atlas neighbourhood without resampling its pixels.

    RawImage uses the ordinary UI material, so retain straight PNG RGB.  The
    retained Free mesh exporter premultiplies PNG RGB for its own material;
    reusing those encoded images here would multiply their alpha twice.
    """
    key=name.replace('\\','/').casefold()
    if key in assets.direct:
        result=dict(assets.texture(name))
        result['sample_rect']=[0,0,result['width'],result['height']]
        if key=='g-white.png':
            result['sample_rect']=[.5,.5,result['width']-1,result['height']-1]
        return result
    if key not in assets.frames:
        raise FileNotFoundError(f'Texture not found: {name}')
    atlas,frame=assets.frames[key]
    canvas=assets.image(name)
    if assets.trim(name,canvas.size)!=[0,0,*canvas.size]:
        raise ValueError(f'Musicbar trimmed widget frame is not mapped: {name}')
    x,y,w,h=map(int,re.findall(r'-?\d+',str(frame.get('frame',frame.get('textureRect')))))
    rotated=frame.get('rotated',frame.get('textureRotated',False))
    with Image.open(atlas) as original:
        image=original.convert('RGBA');atlas_width=image.width
        if rotated:image=image.transpose(Image.Transpose.ROTATE_90)
        if max(image.size)>16384:raise ValueError('Musicbar source atlas exceeds texture bound')
        left,top=(y,atlas_width-x-h) if rotated else (x,y)
        stream=io.BytesIO();image.save(stream,format='PNG');blob=stream.getvalue()
        digest=hashlib.sha256(blob).hexdigest();filename=digest[:24]+'.png'
        target=assets.output/filename
        if not target.exists():target.write_bytes(blob)
        result={'file':filename,'width':canvas.width,'height':canvas.height,
                'sample_rect':[left,image.height-top-canvas.height,canvas.width,canvas.height],
                'texture_extent':list(image.size),'trim':[0,0,*canvas.size],
                'alpha_encoding':'straight','source_atlas_sha256':hashlib.sha256(atlas.read_bytes()).hexdigest()}
    # The background alone calls Sprite::setRectFixed(true): its UVs are
    # inset by half a source texel. Markers and cursor keep the full frame.
    if key=='g-white.png':
        r=result['sample_rect'];result['sample_rect']=[r[0]+.5,r[1]+.5,r[2]-1,r[3]-1]
    assets.records.append({'source':name,'sha256':digest,
                           'sampling':'original-widget-atlas-straight',**result})
    return result


def compile_musicbar(item, width, height, assets, *, logical_height=600):
    """Return source_musicbar data; missing size/count is the NULL factory.

    Width/height are the caller's already evaluated 720-unit dimensions.
    Position, anchor, painter order and rotation stay on the ordinary module.
    The current target has static geometry. Dynamic size/alpha bindings need
    their own original-node semantics; reject them rather than approximate.
    """
    if not {'size','count'}.issubset(item.attrs):return None
    count=native_integer(item.attrs['count'])
    if not 1<=count<=4096:raise ValueError('Musicbar count exceeds verified 1..4096 visual bound')
    if item.motion_bindings:
        raise ValueError('Musicbar source motion requires original compound-node mapping')
    if not all(math.isfinite(v) and v>0 for v in (width,height,logical_height)):
        raise ValueError('Musicbar requires positive finite source geometry')
    size=[float32(v*logical_height/720) for v in (width,height)]
    textures=[widget_texture(assets,name) for name in WIDGET_TEXTURES]
    # Reject a constructor that cannot fit its actual source markers.
    from .musicbar import geometry
    geometry(*size,count,textures[1]['width'],textures[1]['height'],
             textures[2]['width'],textures[2]['height'])
    return {'count':count,'size':size,'textures':textures,
            'units_per_pixel':1080/logical_height,
            'visible':native_integer(item.attrs.get('show'),1)!=0,
            'density_ceiling':10,'density_saturation':100,
            'scope':'legacy-musicbar-static-v1'}
