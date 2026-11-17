"""Original KeyUIS play-plane construction, before perspective projection.

Recovered from 4.3.7 virtual_192 (0x5a9a00), not maV track-angle metadata.
The matrix is column-major. Projection and logical viewport are explicit.
"""
import math
import re
import struct


def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]


def build_plane(angle, projection, logical_height):
    if type(angle) is not int or not 1<=angle<90:
        raise ValueError('Legacy 3D requires an explicit integer @angle from 1 to 89; zero uses an external old game setting')
    if len(projection)!=16 or projection[15]<=0 or projection[11]!=-1:
        raise ValueError('Legacy 3D requires the original perspective projection')
    alpha=math.atan(f32(logical_height*.5)/projection[15])
    denominator=math.cos(-alpha-math.radians(angle))
    if denominator<=0:raise ValueError('Legacy 3D plane crosses the verified camera hemisphere')
    scale=f32(math.cos(alpha)/denominator)
    # Cocos constructs its float quaternion first. Direct cos(angle) loses
    # the rounding seen in the actual native Node world-transform readback.
    radians=f32(f32(-angle)*f32(math.pi/180));half=f32(radians*f32(.5))
    x,w=f32(math.sin(half)),f32(math.cos(half))
    cosine=f32(1-f32(f32(2*x)*x));sine=f32(f32(2*x)*w)
    matrix=[1,0,0,0,0,f32(scale*cosine),f32(scale*sine),0,
        0,-sine,cosine,0,0,0,0,1]
    # The old perspective matrix includes its camera translation. Solve its
    # homogeneous depth inequalities, rather than treating Z/W as screen XY.
    a=-projection[10];b=projection[10]*projection[15]+projection[14]
    near_w,far_w=-b/(a+1),-b/(a-1)
    slope=-projection[5]*matrix[5]/matrix[6]
    intercept=projection[13]-slope*projection[15]
    visible_w_min=-intercept/(slope+1)
    if not (0<near_w<visible_w_min and near_w<far_w and slope>0 and intercept<0):
        raise ValueError('Legacy play-plane clipping context is not verified')
    return {'angle':angle,'matrix':matrix,
        'clip_depth':{'near_w':near_w,'far_w':far_w,'visible_w_min':visible_w_min},
        'scroll_scale':f32(.7),
        'source_projection':list(projection),'logical_height':logical_height,
        'whole_scene_verified':False}


def project_point(point, plane, width, height):
    """Project canonical MUI units through the original whole play plane."""
    scale=plane['logical_height']/720
    vector=[point[0]*scale,point[1]*scale,0,1]
    t=plane['matrix'];p=plane['source_projection']
    world=[sum(t[c*4+r]*vector[c] for c in range(4)) for r in range(4)]
    clip=[sum(p[c*4+r]*world[c] for c in range(4)) for r in range(4)]
    if clip[3]<=0:raise ValueError('Legacy point is behind the original camera')
    return [(clip[0]/clip[3]+1)*width/2,(1-clip[1]/clip[3])*height/2]


def from_document(doc, projection):
    if '3d' not in doc.features:return None
    if not projection:raise ValueError('Legacy 3D requires an explicit original projection context')
    value=doc.directives.get('angle','')
    if not re.fullmatch(r'[+]?[0-9]+',value):
        raise ValueError('Legacy 3D requires an explicit integer @angle; old external settings are unavailable')
    return build_plane(int(value),projection['matrix'],projection['logical_height'])
