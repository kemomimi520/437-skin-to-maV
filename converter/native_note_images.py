"""Texture-only native Key adaptation; no per-frame rendering or game state."""
from fractions import Fraction
import math

from PIL import Image


def hold_body_slice_edges(image):
    """Keep native atlas-edge filtering out of the stretched body interior.

    A two-row source stretched over a long LN magnifies its half-texel atlas
    boundary over hundreds of screen pixels. Add identical outer rows and
    mark only those rows as unscaled native nine-slice caps. The original
    image, including its RGBA edges, remains byte-identical in the centre.
    """
    if image.height+2>16384:
        raise ValueError('条身边缘适配会超出已验证的纹理尺寸')
    result=Image.new('RGBA',(image.width,image.height+2))
    result.paste(image,(0,1))
    result.paste(image.crop((0,0,image.width,1)),(0,0))
    result.paste(image.crop((0,image.height-1,image.width,image.height)),(0,image.height+1))
    return result


def hold_body_canvas(image, *, width, lane_width, anchor_x, return_info=False):
    """Encode the old quad width inside maV's fixed lane-width rectangle.

    Rounding a 2-pixel body to a 2-pixel padded canvas silently turns a
    90-unit body into 100 units. Keep the original pixels whenever that
    quantization is subpixel; otherwise solve the required rational extent
    before resampling once. Geometry is checked again after integer padding.
    """
    original_width=image.width

    def geometry(canvas_width, body_width):
        left=round(canvas_width/2-anchor_x*body_width)
        actual_width=body_width/canvas_width*lane_width
        actual_centre=((left+body_width/2)/canvas_width-.5)*lane_width
        expected_centre=(.5-anchor_x)*width
        return left,max(abs(actual_width-width),abs(actual_centre-expected_centre))

    body_width=original_width
    canvas_width=max(1,round(body_width*lane_width/width))
    left,delta=geometry(canvas_width,body_width)
    if delta>.25:
        solved=False
        for k in range(2,17):
            cand_body=original_width*k
            base_canvas=max(1,round(cand_body*lane_width/width))
            for cand_canvas in (base_canvas,base_canvas-1,base_canvas+1):
                if cand_canvas<1 or cand_canvas>16384:continue
                if anchor_x==.5 and (cand_canvas-cand_body)%2:continue
                cand_left,cand_delta=geometry(cand_canvas,cand_body)
                if cand_delta<=.25 and cand_left>=0 and cand_left+cand_body<=cand_canvas:
                    body_width,canvas_width,left,delta=cand_body,cand_canvas,cand_left,cand_delta
                    solved=True
                    break
            if solved:break
        if not solved:
            fraction=Fraction(width/lane_width).limit_denominator(256)
            if fraction.numerator<=0:
                raise ValueError('条身宽度不足以用原生纹理边界可靠表达')
            body_width=math.lcm(original_width,fraction.numerator)
            canvas_width=body_width*fraction.denominator//fraction.numerator
            if anchor_x==.5 and (canvas_width-body_width)%2:
                body_width*=2;canvas_width*=2
            if max(canvas_width,image.height)>16384:
                step=fraction.numerator
                mul=max(1,math.ceil(original_width/step))
                body_width=step*mul
                canvas_width=fraction.denominator*mul
                if anchor_x==.5 and (canvas_width-body_width)%2:
                    body_width*=2;canvas_width*=2
            left,delta=geometry(canvas_width,body_width)
    # A low-resolution transparent border is stretched together with the
    # body. One texel could then become a 5-pixel alpha fringe. Sampling at
    # native 1080-unit density bounds that fringe without a shader or loop.
    factor=max(1,math.ceil(width*1.5/body_width))
    if factor>1:
        body_width*=factor;canvas_width*=factor
        left,delta=geometry(canvas_width,body_width)
    if left<0 or left+body_width>canvas_width:
        raise ValueError('原条身超出普通 Key 的固定轨道矩形')
    if delta>.25:
        raise ValueError('整数纹理边界无法将条身几何误差控制在四分之一逻辑像素内')
    if max(canvas_width,image.height)>16384:
        raise ValueError('条身边界适配会超出已验证的纹理尺寸')
    if body_width!=original_width:
        # ShapeSprite samples straight RGBA channels independently. Pillow's
        # default RGBA resize premultiplies first, changing transparent edges.
        image=Image.merge('RGBA',[channel.resize((body_width,image.height),Image.Resampling.BILINEAR)
                                  for channel in image.split()])
    result=Image.new('RGBA',(canvas_width,image.height))
    result.paste(image,(left,0))
    if return_info:
        return result,{'left':left,'top':0,'width':body_width,'height':image.height,
                       'canvas_width':canvas_width,'canvas_height':image.height}
    return result
