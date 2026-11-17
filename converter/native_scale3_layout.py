"""Factory-specific affine layout on a calibrated native Key motion range.

The original 437 source field height and per-lane travel are independent.
This plans geometry only. It does not prove that a game's processed motion
range, judgement-line centre or object lifetime already matches 437.
"""
import math

from .native_numeric import float32 as f
from .legacy_note_space import admission_to_motion_ratio


def range_layout(factory,texture_size,declared_size,*,head_size=None,tail_size=None,
                 anchor=4,logical_height,field_height_720,travel_720,
                 units_per_720,judge_offset_720=0):
    """Return RectTransform parameters; no chart clock or per-note raster.

    Sizes/travel use normalized 720 coordinates. units_per_720 belongs to
    the ACTUAL native range's parent coordinate space, not Sprite.size or
    the SpriteRenderer's PPU-scaled transform. The caller must calibrate it.
    """
    w,h=map(f,texture_size);dw,dh=map(f,declared_size)
    values=(w,h,dw,dh,logical_height,field_height_720,travel_720,units_per_720,judge_offset_720)
    if not all(math.isfinite(v) for v in values) or min(w,h,dw,dh,logical_height,travel_720,units_per_720)<=0:
        raise ValueError('Native Scale3 layout requires finite, positive source sizes, travel and native units')
    if anchor not in range(9):raise ValueError('Resolve the original anchor before creating a Scale3 layout')
    ax,ay=(anchor%3)*.5,1-(anchor//3)*.5
    if factory=='scale3':
        pixel_x,pixel_y=f(dw/w),f(dh/h)
        old_scale=f(f(f(dh*logical_height)/720)/h)
        # Saved GetScaledSize is multiplied by ScaleY once more at admission;
        # dividing by ScaleY leaves this already-scaled height as content base.
        base=f(h*old_scale)
        ratio=admission_to_motion_ratio(field_height_720,travel_720)
        pivot=[ax,ay];offset=[0,-judge_offset_720]
    elif factory=='scale3part3':
        if head_size is None or tail_size is None:raise ValueError('Scale3Part3 needs both original sprite bounds')
        hw,hh=map(f,head_size);tw,th=map(f,tail_size)
        if min(hw,hh,tw,th)<=0 or not all(math.isfinite(v) for v in (hw,hh,tw,th)):
            raise ValueError('Scale3Part3 requires finite, positive head and tail bounds')
        if abs(hw-tw)>1e-4:raise ValueError('Different head/tail widths require the original edge-axis geometry')
        # 0x4f1c10 scales this body UNIFORMLY from head width, unlike the
        # default factory's independently declared width/height scaling.
        pixel_x=pixel_y=f(hw/w)
        base=f(f(f(hh*.5)+f(th*.5))/pixel_y)
        ratio=1
        pivot=[.5,0];offset=[f((.5-ax)*hw),f(-hh*.5)]
    else:raise ValueError('Not an original Scale3Sprite factory: '+str(factory))
    sx,sy=f(pixel_x*units_per_720),f(pixel_y*units_per_720)
    coefficient=f(ratio/sy)
    return {'factory':factory,'anchor_y':[f(-pivot[1]*coefficient),f((1-pivot[1])*coefficient)],
        'pivot':pivot,'size_delta':[w,base],'scale':[sx,sy],
        'offset':[f(v*units_per_720) for v in offset],
        'source_motion_height_ratio':ratio,'native_motion_calibration_required':True,
        'requires_unclipped_motion_range':True,
        'fixed_at_admission':factory=='scale3',
        'required_native_head_policy':'None' if factory=='scale3' else 'source-toggle',
        'actual_ln_lifetime_verified':False}
