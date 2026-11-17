"""Recovered MusicBarSprite state; kept separate from generic sprite translation.

Evidence: original 4effd0 / 4ef990 / 4efa40 / 4efad0 / 4efdf0 / 4f0550.
The custom MUI factory creates a fresh body with density ceiling 10. It does
not inherit the duration-dependent ceiling assigned to the discarded base HUD.
"""
from __future__ import annotations
import math
import struct


def f32(value):
    return struct.unpack('<f',struct.pack('<f',value))[0]


def geometry(width,height,count,start_width,start_height,end_width,end_height):
    if not 1<=count<=4096 or min(width,height,start_height,end_height)<=0:
        raise ValueError('Invalid native musicbar geometry')
    marker_height=f32(float(height)*.6)
    left=f32(start_width*f32(marker_height/start_height))
    right=f32(end_width*f32(marker_height/end_height))
    available=f32(f32(f32(width-left)-right)-40)
    if available<=0:raise ValueError('Musicbar is too narrow for its native markers and margins')
    return {'width':width,'height':height,'count':count,'start_width':left,'end_width':right,
            'marker_height':marker_height,'available_width':available,
            'body_height':marker_height,'cursor_width':f32(available/100),
            'body_x':f32(f32(width-available)*.5),'body_y':f32(height*.2)}


def cursor_x(layout,time,start,end):
    if start==end:end=start+1
    time=max(start,min(end,time))
    return f32(f32(f32(f32(layout['available_width']-layout['cursor_width'])*f32(time-start))/f32(end-start))+layout['body_x'])


def segment_rect(layout,index,total,ceiling=10):
    # Original DrawNode expands the filled rectangle by half a logical pixel.
    step=f32(layout['available_width']/layout['count'])
    height=f32(layout['body_height']*f32(min(total,ceiling)/ceiling))
    x0=f32(f32(f32(step*.15)+f32(step*index))-.5)
    x1=f32(f32(f32(step*.85)+f32(step*index))+.5)
    return (x0,-.5,x1,f32(height+.5))


def committed_color(flags):
    # Flags are legacy judge bits, not maV's 1..4 enum values.
    if flags&16:return (102,102,102,255)
    if flags&8:return (47,186,141,255)
    if flags&4:return (244,208,85,255)
    return (238,102,102,255)


class State:
    def __init__(self,count,start,end,density):
        self.count,self.start,self.end=count,start,max(start+1,end)
        self.step=f32((self.end-start)/count)
        self.totals=list(density)
        if len(self.totals)!=count:raise ValueError('Density count mismatch')
        self.judged=[0]*count;self.flags=[0]*count
        self.colors=[(102,102,102,255)]*count
        self.commits=[]

    def judge(self,time,flags):
        index=math.floor(f32(f32(time-self.start)/self.step))
        if not 0<=index<self.count:return
        bit=next((bit for mask,bit in ((2,2),(4,4),(8,8),(1,16)) if flags&mask),0)
        if not bit:return
        self.flags[index]|=bit
        self.judged[index]=(self.judged[index]+1)&255
        if self.judged[index]==self.totals[index]:
            self.colors[index]=committed_color(self.flags[index])
            if self.totals[index]>0:self.commits.append(index)
