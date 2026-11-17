"""Lossless optional UI atlas; source definitions and painter order stay intact."""
import hashlib
import io
from pathlib import Path

from PIL import Image


def atlas_storage(profile, skin):
    """Bind native UI factories to pages; omit only superseded UI-only PNGs.

    A logical source name remains in the Lua atlas map. Notes, bars, procedural
    meshes, font data and the cover keep their independent source resources.
    No generated file is deleted: the package writer omits the proved copies.
    """
    atlas=profile.get('ui_atlas',{})
    protected={skin.meta.cover}
    def resources(value):
        if isinstance(value,str):protected.add(value)
        elif isinstance(value,dict):
            for item in value.values():resources(item)
        elif isinstance(value,list):
            for item in value:resources(item)
    resources(profile.get('notes',{}))
    resources(profile.get('fonts',{}))
    handles=set()
    for entry in profile['entries']:
        if entry['name']=='bar' or entry.get('musicbar') or entry.get('bitmap_font'):
            resources(entry)
            continue
        for bank in entry.get('handles',{}).values():handles.update(bank)
        if entry.get('value_handle'):handles.add(entry['value_handle'])
    bindings=[]
    for module in skin.modules:
        source=module.image.file
        if source in atlas and module.meta.desc in handles and module.type in (5000,4900):
            module.image.file=atlas[source]['file']
            bindings.append({'handle':module.meta.desc,'source':source,'page':module.image.file})
        else:
            protected.add(source)
    return sorted(set(atlas)-protected),bindings


def build_ui_atlas(entries, directory, *, limit=2048, gutter=2):
    directory=Path(directory)
    excluded={t['file'] for e in entries if e.get('musicbar')
              for t in [*e['musicbar']['textures'],e['musicbar']['body_texture']]}
    for entry in entries:
        for frames in entry.get('states',{}).values():
            for texture in frames:
                if texture.get('sample_rect') or texture.get('tiles'):excluded.add(texture['file'])
    files=set()
    for entry in entries:
        if entry.get('musicbar') or entry.get('bitmap_font') or entry.get('name')=='bar':continue
        textures=list(entry.get('number',{}).get('glyphs',{}).values())
        textures += [t for frames in entry.get('states',{}).values() for t in frames]
        for texture in textures:
            if (texture['file'] not in excluded and not texture.get('tiles') and
                not texture.get('sample_rect') and texture.get('alpha_encoding')=='cocos-premultiplied-rgb'):
                files.add(texture['file'])
    sizes={}
    for name in sorted(files):
        with Image.open(directory/name) as image:
            if max(image.size)+2*gutter<=limit:sizes[name]=image.size
    if len(sizes)<2:return {},[]
    # Deterministic shelf allocation; no rotation, scaling, trimming or sorting
    # of drawables. Files too large for a page retain standalone textures.
    pages=[]
    for name in sorted(sizes,key=lambda name:(-sizes[name][1],-sizes[name][0],name)):
        iw,ih=sizes[name];w,h=iw+2*gutter,ih+2*gutter
        for page in pages:
            if page['x']+w>limit:
                x,y,row=0,page['y']+page['row'],0
            else:x,y,row=page['x'],page['y'],page['row']
            if y+h<=limit:break
        else:
            page={'x':0,'y':0,'row':0,'width':0,'height':0,'items':[]};pages.append(page)
            x,y,row=0,0,0
        page['items'].append((name,x+gutter,y+gutter))
        page.update(x=x+w,y=y,row=max(row,h),width=max(page['width'],x+w),height=max(page['height'],y+h))
    mapping={};receipts=[]
    power=lambda value:1<<(value-1).bit_length()
    for page in pages:
        if len(page['items'])<2:continue
        width,height=power(page['width']),power(page['height'])
        atlas=Image.new('RGBA',(width,height))
        for name,x,y in page['items']:
            with Image.open(directory/name) as original:image=original.convert('RGBA')
            w,h=image.size
            atlas.paste(image,(x,y))
            # Extrude each edge/corner byte for byte. This retains the direct
            # PNG's clamp samples without introducing a neighbouring sprite.
            atlas.paste(image.crop((0,0,1,h)).resize((gutter,h),Image.Resampling.NEAREST),(x-gutter,y))
            atlas.paste(image.crop((w-1,0,w,h)).resize((gutter,h),Image.Resampling.NEAREST),(x+w,y))
            atlas.paste(image.crop((0,0,w,1)).resize((w,gutter),Image.Resampling.NEAREST),(x,y-gutter))
            atlas.paste(image.crop((0,h-1,w,h)).resize((w,gutter),Image.Resampling.NEAREST),(x,y+h))
            for dx,sx in ((-gutter,0),(w,w-1)):
                for dy,sy in ((-gutter,0),(h,h-1)):
                    atlas.paste(image.getpixel((sx,sy)),(x+dx,y+dy,x+dx+gutter,y+dy+gutter))
        encoded=io.BytesIO();atlas.save(encoded,format='PNG');blob=encoded.getvalue()
        digest=hashlib.sha256(blob).hexdigest();file='ui-atlas-'+digest[:24]+'.png'
        (directory/file).write_bytes(blob)
        for name,x,y in page['items']:
            w,h=sizes[name]
            mapping[name]={'file':file,'rect':[x,height-y-h,w,h]}
        receipts.append({'file':file,'sha256':digest,'width':width,'height':height,
            'frames':len(page['items']),'gutter':gutter,'rescaled':False})
    return mapping,receipts
