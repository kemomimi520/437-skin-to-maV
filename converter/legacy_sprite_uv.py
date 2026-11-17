"""Original Sprite_UpdateTextureCoords (437 VA 0x6d1500), not Unity UVs.

Scale3Sprite_RebuildParts enables SetRectFixed(1) for all three children.
That changes sampling, including a ZERO UV span for a one-texel strip.
It does not change the child's geometric texture rectangle or content size.
"""
import math

from .native_numeric import float32 as f


def sprite_uv(rect,texture_size,*,rect_fixed=True,rotated=False,flip_x=False,flip_y=False,content_scale=1):
    x,y,w,h=map(f,rect);tw,th=map(f,texture_size);scale=f(content_scale)
    if not all(math.isfinite(v) for v in (x,y,w,h,tw,th,scale)) or min(tw,th,scale)<=0:
        raise ValueError('Original sprite UVs require finite inputs and positive texture dimensions/scale')
    x,y,w,h=(f(v*scale) for v in (x,y,w,h))
    uw,vh=(h,w) if rotated else (w,h)
    if rect_fixed:
        left=f(f(f(x*2)+1)/f(tw*2));top=f(f(f(y*2)+1)/f(th*2))
        right=f(f(f(f(uw*2)-2)/f(tw*2))+left)
        bottom=f(f(f(f(vh*2)-2)/f(th*2))+top)
    else:
        left,right=f(x/tw),f(f(x+uw)/tw)
        top,bottom=f(y/th),f(f(y+vh)/th)
    if rotated:
        if flip_x:top,bottom=bottom,top
        if flip_y:left,right=right,left
        return [[right,top],[left,top],[right,bottom],[left,bottom]]
    if flip_x:left,right=right,left
    if flip_y:top,bottom=bottom,top
    return [[left,top],[left,bottom],[right,top],[right,bottom]]
