"""Affine form of the old numeric scanner for geometry compilation.

Native per-operation float32 and reference-addition boundaries are retained
separately in the emitted position program; this form is used for trajectories.
"""
from .native_numeric import tokens


def coordinate(text, index=0, *, ratio=16/9, logical_height=720, unit=720, variables=None):
    if isinstance(text,dict):
        unit=text.get('unit',720);variables=text.get('variables');text=text['text']
    text=text.strip()
    # NumericExpression scans recognised bytes and ignores all other bytes.
    # In particular a full-width percent sign is ignored, NOT a percent unit.
    # Do not impose a second expression grammar on skins the old loader reads.
    if '$' in text:
        start,step=text.split('$',1)
        a,b=coordinate(start,ratio=ratio,logical_height=logical_height,unit=unit,variables=variables)
        c,d=coordinate(step,ratio=ratio,logical_height=logical_height,unit=unit,variables=variables)
        return a+c*index,b+d*index
    fraction,units=0.,0.
    for sign,value,mode in tokens(text,variables):
        number=sign*value
        if mode==1:fraction+=number/100
        elif mode in (2,5):units+=number*720/logical_height
        elif mode==3:units+=number*ratio*720/1280
        elif mode==0:units+=number*720/unit
    return fraction,units
