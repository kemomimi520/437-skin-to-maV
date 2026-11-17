"""Verified 4.3.7 x86 glyph allocation, independent of captured atlas UVs."""

def _bucket(code,mask):
    h=2166136261
    h=((h^(code&255))*16777619)&0xffffffff
    return (((h^(code>>8))*16777619)&0xffffffff)&mask

def allocation_order(text):
    groups={};known=set();capacity=8
    for char in text:
        code=ord(char)
        if code>65535 or 0xd800<=code<=0xdfff:raise ValueError('Native font cache model supports verified BMP characters only')
        if code in known:continue
        known.add(code);groups.setdefault(_bucket(code,capacity-1),[]).insert(0,code)
        # This executable inserts before growing. Reversing that order moves
        # colliding glyphs and changes filtered pixels despite equal masks.
        if len(known)>capacity:
            capacity*=8 if capacity<512 else 2
            previous=[c for group in groups.values() for c in group];groups={}
            for c in previous:groups.setdefault(_bucket(c,capacity-1),[]).insert(0,c)
    return [c for group in groups.values() for c in group]

def pack_atlas(text_batches,glyphs,line_height):
    result={};x=y=page=tall=0
    for text in text_batches:
        fresh=''.join(c for c in text if ord(c) not in result)
        for code in allocation_order(fresh):
            if code not in glyphs:raise ValueError(f'Native font bank has no U+{code:04X}')
            width,height=glyphs[code][3:5]
            if width and height:
                if height>tall:tall=int(height)+3
                if x+width>512:
                    y+=tall;x=tall=0
                    if y+line_height>=512:y=0;page+=1
                result[code]=[page,x,y+1];x+=width+1
            else:result[code]=[0,0,0];x+=1
    return result
