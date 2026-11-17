"""437 KeyUIS units recovered from its installed update and context ctor.

0x5ac1b0 uses a DOUBLE 632.5 display window numerator (0x7cc438),
a FLOAT 720 size divisor (0x7cc5a8), and a separate DOUBLE 1000
retirement distance (0x7cc460). They are not interchangeable.
"""
import math

from .native_numeric import float32 as f

MOVE_WINDOW_NUMERATOR=632.5
MUI_SIZE_DIVISOR=720.
RETIRE_DISPLAY_DISTANCE=1000.
LEGACY_KEYUIS_BASE_SCALE=0.7


def display_window(speed, speed_scale):
    """Return the original KeyUIS prefetch reach with its float32 product."""
    speed,scale=map(f,(speed,speed_scale))
    if not all(math.isfinite(v) and v>0 for v in (speed,scale)):
        raise ValueError('Original KeyUIS needs finite positive speed inputs')
    return MOVE_WINDOW_NUMERATOR/f(speed*scale)


def keyuis_units(field_height,speed,speed_scale):
    """Actual update arithmetic; field_height is cached visible viewport H.

    Layer base Init 0x59b220 copies Director::getVisibleSize into +0x31c;
    ContextCtor 0x50aff0 takes the SAME visible H for its H/720 unit scale.
    No game window or user setting is changed by this calculation.
    """
    height,speed,scale=map(f,(field_height,speed,speed_scale))
    if not all(math.isfinite(v) and v>0 for v in (height,speed,scale)):
        raise ValueError('Original KeyUIS needs finite positive viewport and speed inputs')
    return {'display_window':display_window(speed,scale),
            'height_per_display_unit':f(f(f(height*scale)*speed)/MUI_SIZE_DIVISOR),
            'mui_unit_scale':f(height/MUI_SIZE_DIVISOR),
            'retire_display_distance':RETIRE_DISPLAY_DISTANCE}


def admission_to_motion_ratio(field_height,travel):
    """Default whole-image length / head-to-tail motion length.

    The coefficient is viewportH*s*scale/720, while the note's movement
    denominator is 632.5/(s*scale). Their ratio retains 632.5/720.
    A clipped maV range still cannot supply the original motion length.
    """
    if not all(math.isfinite(v) and v>0 for v in (field_height,travel)):
        raise ValueError('Original viewport and lane travel must be finite and positive')
    return f((field_height/travel)*(MOVE_WINDOW_NUMERATOR/MUI_SIZE_DIVISOR))
