"""437 Director projection for the original 600-unit UI viewport."""

import math

from .context import UI_PROJECTION_1024_600
from .native_numeric import float32


def director_projection(logical_height, ratio):
    """Reproduce the captured Director's float32 aspect construction.

    The independent original constructor sweep is retained in
    tests/data/legacy-director-aspects.json. Other logical heights need their
    own camera-depth construction and are not silently approximated here.
    """
    if logical_height != 600:
        raise ValueError('Type=2 UI requires a captured Director projection at this logical height')
    height=float32(logical_height)
    width=float32(height*ratio)
    if not math.isfinite(width) or width<=0:
        raise ValueError('Invalid original UI viewport width')
    projection=list(UI_PROJECTION_1024_600)
    projection[0]=float32(float32(1/float32(width/height))*projection[5])
    projection[12]=float32(-float32(width*.5)*projection[0])
    return {'matrix':projection,'logical_height':height}
