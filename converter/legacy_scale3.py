"""Recovered vertical Scale3Sprite geometry, not Unity border compression.

437 uses THREE ordinary Sprites. Its centre may have a negative scale when
the requested height is shorter than the two fixed caps. Unity's Sliced
renderer compresses borders instead, so these contracts cannot be equated.
Source: Scale3Sprite_RebuildParts 0x4fb0b0 and layout 0x4fbc60.
"""
import math

from .native_numeric import float32


def admission_content_height(scale_y,saved_scaled_height,display_interval,distance_per_display_unit):
    """Recover KeyUIS 0x5ac1b0's ONE-TIME default-LN content height.

    saved_scaled_height comes from the factory's GetScaledSize, not the raw
    texture rectangle. The original applies scale_y again here. The caller
    must supply the actual display-axis interval and the KeyUIS coefficient;
    maV's current head-to-tail length is not automatically either input.
    """
    sy,saved,coefficient=map(float32,(scale_y,saved_scaled_height,distance_per_display_unit))
    if not all(math.isfinite(v) for v in (sy,saved,coefficient,display_interval)) or sy==0:
        raise ValueError('Scale3 admission requires finite original geometry and nonzero scale')
    physical=float32(float32(sy*saved)+float32(display_interval*coefficient))
    return float32(physical/sy)


def vertical_parts(texture_size,content_size,part=None):
    """Return the original top/bottom/centre order, pixels and local geometry.

    Source Rect Y increases down the texture; local node Y increases upwards.
    Cocos compares both slice boundaries to zero before falling back to
    WIDTH thirds, even for a vertical sprite. The note-factory default is
    separately (0,1), not thirds. A zero centre interval is not certified.
    """
    w,h=map(float32,texture_size);cw,ch=map(float32,content_size)
    if not all(math.isfinite(v) for v in (w,h,cw,ch)) or min(w,h)<=0:
        raise ValueError('Scale3Sprite requires finite geometry and a positive source rectangle')
    first,last=map(float32,(0,1) if part is None else part)
    # Original Vec2::equals 0x6cc090 uses STRICT FLT_EPSILON on both
    # components, not exact equality and not the usual gameplay .0001.
    if abs(first)<2**-23 and abs(last)<2**-23:
        first=float32(w/3);last=float32(float32(w+w)/3)
    if not all(math.isfinite(v) for v in (first,last)) or not 0<=first<last<=h:
        raise ValueError('Scale3Sprite intervals outside the verified texture rectangle need an atlas-neighbour mapping')
    bottom=float32(h-last);centre=float32(last-first)
    height=float32(float32(ch-first)-bottom)
    scale=float32(height/centre)
    actual=float32(centre*scale)
    # RebuildParts keeps each sub-Sprite's original width. Parent scale
    # supplies width changes; setting the content width alone does not.
    return [
        {'source_rect':[0,0,w,first],'position':[0,float32(actual+bottom)],'scale':[1,1]},
        {'source_rect':[0,last,w,bottom],'position':[0,0],'scale':[1,1]},
        {'source_rect':[0,first,w,centre],'position':[0,bottom],'scale':[1,scale]},
    ]
