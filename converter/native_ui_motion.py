"""Lower recovered 437 ParseAni records to ordinary maV module animations.

This is a UI adapter. It never creates a note callback or reads a chart.
The option aliases, named Bezier controls, native numeric prefixes and
attachment-terminal branch are shared with the retained 437 reader evidence.
"""
from __future__ import annotations

import math

from .animation import NATIVE_EASES, NATIVE_KINDS, canonical, normalize_record, rejected_options
from .mui import native_float, native_integer, split_values
from .native_numeric import expression, float32

METHODS = {'m':'DoMove','mx':'DoMoveX','my':'DoMoveY','w':'DoWidth','h':'DoHeight',
           'size':'DoResize','r':'DoRotate','f':'DoAlpha','s':'DoScale',
           'sx':'DoScaleX','sy':'DoScaleY','skew':'DoSkew','skewx':'DoSkewX','skewy':'DoSkewY'}


def compile_ui_motion(binding, *, ratio, logical_height, issue, position_anchor=(0,0)):
    motions=[]
    for raw in binding['records']:
        record=normalize_record(raw)
        rejected=rejected_options(record)
        if rejected or record.get('name') not in NATIVE_KINDS:
            issue('warning','native-rejected-animation-record',
                  '437 ParseAni 拒绝此记录，未生成替代动画：'+str(record.get('source','')))
            continue
        kind=canonical(record['name'])
        if kind in ('hide','show'):
            continue  # Both attached 437 AnimationManager queues skip 10/11.
        if kind not in METHODS:
            issue('error','native-ui-motion',f'437 的 {kind} 动画尚未映射普通原生组件')
            continue
        try:
            controls=None
            transition=record.get('trans','')
            if transition in NATIVE_EASES:
                controls=NATIVE_EASES[transition]
            elif transition.startswith('('):
                controls=[float(v) for v in split_values(transition.strip('()'))]
                if len(controls)!=4 or not all(math.isfinite(v) for v in controls):
                    issue('warning','native-rejected-animation-record',
                          '437 ParseAni 拒绝不含四个有限控制值的 trans 元组，整条动画未附加')
                    continue
                controls=[float32(v) for v in controls]
            raw_times=split_values(record.get('_time_value','0').strip('()'))
            times=[native_integer(v) for v in raw_times]
            if len(times)==1:times=[0,times[0]]
            elif len(times)==2:
                if raw_times[1].startswith('+'):times[1]+=times[0]
            else:raise ValueError('动画时间需要一个值或一对值')
            times=[v+binding['delay'] for v in times]
            repeat=split_values(record.get('repeat','0').strip('()'))
            reverse=repeat[0].startswith('r')
            count=native_integer(repeat[0][1:] if reverse else repeat[0])
            delay=native_integer(repeat[1]) if len(repeat)>1 else 0
            context=record.get('_numeric',{})

            def endpoint(field):
                value=record.get(field,'0,0' if kind in ('m','size','skew') else '0').strip('()')
                if value=='fill':
                    raise ValueError('437 from-current 的附加时刻取值尚未映射，不能替换为零')
                parts=split_values(value)
                pcts=None
                if kind in ('r','f','skewx','skewy'):
                    values=[native_float(v) for v in parts]
                    # maV's public Rotate setter already negates the value
                    # before writing Unity Euler Z. Both APIs expose the old
                    # clockwise convention; a second negation reverses art.
                    if kind=='f':values=[max(0,min(100,v)) for v in values]
                elif kind=='s' and len(parts)==1:
                    # Scalar uniform scale is atof, NOT NumericExpression.
                    values=[native_float(parts[0])]*2
                elif kind=='size' and len(parts)==1:
                    # 0050be70:651-656: 'size' constructs AnimationVec2 (kind 0x12). A single-scalar
                    # endpoint cannot cast to AnimationFloat/Int and aborts ParseAni, discarding the record.
                    raise ValueError('__rejected_single_scalar_size__')
                else:
                    def eval_part(part, horizontal, test_ratio):
                        extent=logical_height*(test_ratio if horizontal else 1)
                        number=expression(part,extent,float32(logical_height/context.get('unit',720)),
                                          float32(logical_height*test_ratio),context.get('variables'))
                        val=number if kind in ('s','sx','sy','skew') else number*1080/logical_height
                        if kind in ('m','mx','my'):
                            # SkinModuleBase.X/Y and DoMove write anchoredPosition3D,
                            # not an absolute coordinate from the parent's lower
                            # left. Static MUI pos already installed these anchors.
                            # Keeping the percentage again displaces the motion by
                            # that fraction of the whole UI extent (often half a
                            # screen). The old animation writes absolute Node pos.
                            axis=0 if horizontal else 1
                            val-=position_anchor[axis]*1080*(test_ratio if horizontal else 1)
                        return val
                    values=[];pct_list=[];px_list=[]
                    for index,part in enumerate(parts):
                        horizontal=kind in ('mx','w','sx') or kind in ('m','size','s','skew') and index==0
                        val=eval_part(part,horizontal,ratio)
                        values.append(val)
                        if horizontal:
                            v1=eval_part(part,True,1.0);v2=eval_part(part,True,2.0)
                            slope=v2-v1
                            if abs(slope)>1e-4:
                                pct_list.append(slope);px_list.append(val-slope*ratio)
                            else:
                                pct_list.append(0.0);px_list.append(val)
                        else:
                            pct_list.append(0.0);px_list.append(val)
                    if any(abs(p)>1e-4 for p in pct_list):
                        pcts=(pct_list,px_list)
                wanted=2 if kind in ('m','size','s','skew') else 1
                if len(values)!=wanted:raise ValueError(f'{kind} 端点需要 {wanted} 个分量')
                if not all(math.isfinite(v) for v in values):raise ValueError('动画端点不是有限值')
                return values,pcts

            from_vals,from_affine=endpoint('from')
            to_vals,to_affine=endpoint('to')
            motion={'method':METHODS[kind],'start':times[0],'finish':times[1],
                    'from':from_vals,'to':to_vals,'repeats':count,
                    'repeatType':2 if reverse else 1,'delay':delay}
            if from_affine:motion['from_pct'],motion['from_px']=from_affine
            if to_affine:motion['to_pct'],motion['to_px']=to_affine
            if controls:motion['custom']=dict(zip(('p1','p2','p3','p4'),controls))
            if 'atime' not in record:
                if max(times)<=0 and count==0:
                    # Original attachment immediately applies the final value;
                    # waiting until audio time zero changes the intro state.
                    motion['instant']=True
                else:
                    motion['clock']='system'
            motions.append(motion)
        except (ValueError,IndexError,OverflowError) as exc:
            if str(exc)=='__rejected_single_scalar_size__':
                issue('warning','native-rejected-animation-record',
                      '437 ParseAni 拒绝单标量 size 记录，未生成替代动画：'+str(record.get('source','')))
            else:
                issue('error','native-ui-motion',str(exc))
    motions.sort(key=lambda m:(0 if m.get('instant') else 1,m['start']))
    return motions
