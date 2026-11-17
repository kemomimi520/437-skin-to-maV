"""Resolve direct/default textures and Cocos atlases, preserving original sprite canvases."""
from __future__ import annotations
import hashlib
import io
import json
from pathlib import Path
import plistlib
import re
from PIL import Image


def frame_spec(spec):
    """ParseFile's frame regex, including its immediate repeat suffix.

    0x50d735 uses regex_search, not fullmatch. '/~' after the range does
    not set '~': the recognized suffix is '0-2~', with no second slash.
    """
    match=re.search(r'(.+)/(\d+)-(\d+)([~+]?)',spec)
    if match is None:return None
    prefix,first,last,mode=match.groups()
    # The leading quote is a native resource marker, not paired quotation.
    # ParseFile removes exactly its first character; a closing quote survives.
    if prefix.startswith('"'):prefix=prefix[1:]
    first,last=int(first),int(last)
    if not 0<=last-first<=1024:raise ValueError('Invalid frame range')
    return prefix,first,last,mode


def cocos_premultiplied(image):
    """4.3.7 Image::premultiplyAlpha (0x6cef90), before GPU filtering.

    The native integer operation is c * (alpha + 1) >> 8, not round(c*a/255).
    ShapeSprite still uses SRC_ALPHA blending with these texture bytes.
    """
    data=bytearray(image.convert('RGBA').tobytes())
    for i in range(0,len(data),4):
        alpha=data[i+3]+1
        data[i]=data[i]*alpha>>8;data[i+1]=data[i+1]*alpha>>8;data[i+2]=data[i+2]*alpha>>8
    return Image.frombytes('RGBA',image.size,bytes(data))


class Assets:
    def __init__(self, source: Path, defaults: Path, output: Path, packs=()):
        self.source, self.output = source, output
        self.direct = {}; self.frames = {}; self.source_names = set(); self.cache = {}; self.atlas_cache = {}; self.records = []; self.missing_packs=[]
        self.defaults = defaults
        if defaults.is_dir():
            for p in defaults.iterdir():
                if p.is_file(): self.direct[p.name.casefold()] = p
        for p in source.rglob('*'):
            if p.is_file() and not p.is_symlink():
                rel_name = p.relative_to(source).as_posix().casefold()
                self.direct[rel_name] = p
                self.source_names.add(rel_name)
        plists = list(defaults.glob('*.plist')) if defaults.is_dir() else []
        # 4.3.7 ScanSkinAssets (0x4ff550) enumerates every root plist. @texpack
        # does not restrict that scan. In the native A/B proof, a frame from an
        # unlisted pack resolves and the later pack replaces an earlier alias.
        source_plists=list(source.glob('*.plist'))
        for pack in packs:
            p=(source/(pack+'.plist')).resolve()
            if not p.is_relative_to(source.resolve()):raise ValueError('Atlas path escapes skin root')
            if not p.is_file():
                # Native @texpack also attempts built-in packs and tolerates
                # an absent declaration when actual sprites resolve elsewhere.
                # Never substitute blank resources: image() still checks each
                # texture the selected native factory really consumes.
                self.missing_packs.append(pack)
                continue
            if p not in source_plists:source_plists.append(p)
        plists += source_plists
        for p in dict.fromkeys(plists):
            if not p.is_file(): continue
            data = plistlib.loads(p.read_bytes())
            # Original ScanSkinAssets / LoadTexturePack explicitly supplies
            # <pack>.png to SpriteFrameCache, including automatic root packs.
            # A metadata.textureFileName override is not used by that overload.
            if p in source_plists:
                atlas = p.with_suffix('.png').resolve()
            else:
                # Extracted built-ins use container hash filenames for plists;
                # their logical resource filename is retained in the metadata.
                texture=data.get('metadata',{}).get('textureFileName',p.stem+'.png')
                atlas=(p.parent/texture).resolve()
            if not atlas.is_relative_to(p.parent.resolve()):raise ValueError(f'Atlas texture escapes its directory: {p.name}')
            if not atlas.is_file(): continue
            is_source_plist = p in source_plists
            for name, frame in data.get('frames',{}).items():
                key = name.casefold()
                self.frames[key] = (atlas, frame)
                if is_source_plist:
                    self.source_names.add(key)

    def image(self, name: str):
        if name.startswith('"'):name=name[1:]
        key = name.replace('\\','/').casefold()
        if key in self.direct:
            with Image.open(self.direct[key]) as image: return image.convert('RGBA')
        if key not in self.frames: raise FileNotFoundError(f"Texture not found: {name}")
        atlas, frame = self.frames[key]
        rect = frame.get('frame', frame.get('textureRect'))
        x,y,w,h = [int(v) for v in re.findall(r'-?\d+',str(rect))]
        rotated = frame.get('rotated', frame.get('textureRotated',False))
        texture=self.atlas_cache.get(atlas)
        if texture is None:
            with Image.open(atlas) as raw:
                texture=raw.convert('RGBA');texture.load()
            self.atlas_cache[atlas]=texture
        if min(w,h)<=0:
            raise ValueError(f'Atlas frame outside texture bounds: {name}')
        sprite = texture.crop((x,y,x+(h if rotated else w),y+(w if rotated else h)))
        if rotated: sprite = sprite.transpose(Image.Transpose.ROTATE_90)
        size = frame.get('sourceSize',frame.get('spriteSourceSize',f'{{{w},{h}}}'))
        ow,oh = [int(v) for v in re.findall(r'-?\d+',str(size))][:2]
        offset = frame.get('offset',frame.get('spriteOffset','{0,0}'))
        ox,oy = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',str(offset))][:2]
        if min(ow,oh)<=0 or max(ow,oh)>16384:raise ValueError(f'Invalid source canvas: {name}')
        left,top=round((ow-sprite.width)/2+ox),round((oh-sprite.height)/2-oy)
        if left<0 or top<0 or left+sprite.width>ow or top+sprite.height>oh:
            raise ValueError(f'Trimmed sprite outside original canvas: {name}')
        canvas = Image.new('RGBA',(ow,oh))
        canvas.paste(sprite,(left,top))
        return canvas

    def texture(self, name: str, flip=0, trim_canvas=False, premultiplied=False):
        if name.startswith('"'):name=name[1:]
        if flip not in range(4):raise ValueError(f'Invalid flip mask: {flip}')
        cache_key = (name,flip,trim_canvas,premultiplied)
        if cache_key in self.cache: return self.cache[cache_key]
        image = self.image(name)
        if flip & 1: image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if flip & 2: image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        trim=self.trim(name,image.size,flip)
        if trim_canvas:
            left,top,w,h=trim;image=image.crop((left,top,left+w,top+h))
            trim=[0,0,w,h]
        if premultiplied:image=cocos_premultiplied(image)
        data = io.BytesIO(); image.save(data,format='PNG')
        blob = data.getvalue(); digest = hashlib.sha256(blob).hexdigest()
        # maV's real LoadSkinDisk uses Directory.GetFiles(baseDir), without
        # recursion. Image resources must be direct children of the skin root.
        rel = digest[:24]+'.png'
        tiles=[]
        if trim_canvas and max(image.size)>16384:
            # Preserve every source pixel. One-pixel gutters retain bilinear
            # neighbours across a tile boundary; the shader UV range excludes
            # those gutters. Never feed the oversized source to Unity.
            step=8190
            for top in range(0,image.height,step):
                for left in range(0,image.width,step):
                    right,bottom=min(left+step,image.width),min(top+step,image.height)
                    x0,y0=max(0,left-1),max(0,top-1)
                    x1,y1=min(image.width,right+1),min(image.height,bottom+1)
                    crop=image.crop((x0,y0,x1,y1));buffer=io.BytesIO();crop.save(buffer,format='PNG')
                    encoded=buffer.getvalue();sha=hashlib.sha256(encoded).hexdigest();file=sha[:24]+'.png'
                    path=self.output/file;path.parent.mkdir(parents=True,exist_ok=True)
                    if not path.exists():path.write_bytes(encoded)
                    tiles.append({'file':file,'width':crop.width,'height':crop.height,'sha256':sha,
                        'source_rect':[x0,y0,x1,y1],
                        'range':[left/image.width,top/image.height,right/image.width,bottom/image.height],
                        'uv_rect':[(left-x0)/crop.width,(top-y0)/crop.height,(right-x0)/crop.width,(bottom-y0)/crop.height]})
            rel=tiles[0]['file']
        else:
            path = self.output/rel; path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists(): path.write_bytes(blob)
        result = {'file':rel,'width':image.width,'height':image.height,
                  'frame_height':self.frame_height(name,image.height),
                  'trim':trim,
                  'source_texture_clamp':name.replace('\\','/').casefold() in self.direct}
        if premultiplied:result['alpha_encoding']='cocos-premultiplied-rgb'
        if tiles:result['tiles']=tiles;result['source_png_sha256']=digest
        self.cache[cache_key] = result
        self.records.append({'source':name,'flip':flip,'trim_canvas':trim_canvas,'premultiplied':premultiplied,
                             'sha256':tiles[0]['sha256'] if tiles else digest,**result})
        return result

    def atlas_neighbour_texture(self,name,preserve_extent=False,native_uv=False):
        """Keep the actual one-texel bilinear neighbourhood of a widget frame.

        MusicBarSprite uses atlas ImageView/Sprite resources. Clamping a
        cropped PNG to the frame's edge changes old samples outside that edge.
        The target sprite rect excludes this border; only filtering reads it.
        """
        key=name.replace('\\','/').casefold()
        if key in self.direct:return self.texture(name,premultiplied=True)
        if key not in self.frames:raise FileNotFoundError(f'Texture not found: {name}')
        atlas,frame=self.frames[key]
        canvas=self.image(name)  # Also validate the original atlas/frame bounds.
        if self.trim(name,canvas.size)!=[0,0,*canvas.size]:
            raise ValueError(f'Musicbar trimmed widget frame is not certified: {name}')
        x,y,w,h=map(int,re.findall(r'-?\d+',str(frame.get('frame',frame.get('textureRect')))))
        rotated=frame.get('rotated',frame.get('textureRotated',False))
        physical_w,physical_h=(h,w) if rotated else (w,h)
        if native_uv:
            cache_key=('atlas-native-uv',str(atlas))
            if cache_key not in self.cache:
                with Image.open(atlas) as original:image=original.convert('RGBA')
                if max(image.size)>16384:raise ValueError('Native atlas exceeds the verified texture limit')
                extent=image.size
                image=cocos_premultiplied(image.transpose(Image.Transpose.FLIP_TOP_BOTTOM))
                stream=io.BytesIO();image.save(stream,format='PNG');blob=stream.getvalue()
                digest=hashlib.sha256(blob).hexdigest();rel=digest[:24]+'.png'
                (self.output/rel).write_bytes(blob)
                self.cache[cache_key]={'file':rel,'sha256':digest,'extent':extent}
            stored=self.cache[cache_key];aw,ah=stored['extent']
            corners=([(x+physical_w,y),(x,y),(x+physical_w,y+physical_h),(x,y+physical_h)] if rotated else
                     [(x,y),(x,y+physical_h),(x+physical_w,y),(x+physical_w,y+physical_h)])
            result={'file':stored['file'],'width':canvas.width,'height':canvas.height,'frame_height':canvas.height,
                'trim':[0,0,*canvas.size],'sample_rect':[x,y,physical_w,physical_h],
                'native_uv':[[u/aw,v/ah] for u,v in corners],
                'alpha_encoding':'cocos-premultiplied-rgb'}
            if name.casefold()=='g-white.png':
                result['native_uv']=[[(x+.5)/aw,(y+.5)/ah],[(x+.5)/aw,(y+h-.5)/ah],
                                     [(x+w-.5)/aw,(y+.5)/ah],[(x+w-.5)/aw,(y+h-.5)/ah]]
            self.records.append({'source':name,'sha256':stored['sha256'],'premultiplied':True,
                'sampling':'original-atlas-native-uv','atlas_rows_inverted':True,**result})
            return result
        if preserve_extent:
            # Keeping neighbours alone changes normalized UV precision when
            # the cropped texture has NPOT dimensions. Preserve the original
            # atlas extent and pixel origin; rotate the whole atlas when the
            # original frame is packed sideways, so Sprite.Create can use it.
            cache_key=('atlas-extent',str(atlas),bool(rotated))
            if cache_key not in self.cache:
                with Image.open(atlas) as original:image=original.convert('RGBA')
                if max(image.size)>16384:raise ValueError('Native atlas exceeds the verified texture limit')
                if rotated:image=image.transpose(Image.Transpose.ROTATE_90)
                image=cocos_premultiplied(image)
                stream=io.BytesIO();image.save(stream,format='PNG');blob=stream.getvalue()
                digest=hashlib.sha256(blob).hexdigest();rel=digest[:24]+'.png'
                (self.output/rel).write_bytes(blob)
                self.cache[cache_key]={'file':rel,'sha256':digest,'extent':image.size}
            stored=self.cache[cache_key]
            with Image.open(atlas) as original:atlas_w,atlas_h=original.size
            left,top=(y,atlas_w-x-physical_w) if rotated else (x,y)
            result={'file':stored['file'],'width':canvas.width,'height':canvas.height,'frame_height':canvas.height,
                'trim':[0,0,*canvas.size],'sample_rect':[left,stored['extent'][1]-top-canvas.height,*canvas.size],
                'alpha_encoding':'cocos-premultiplied-rgb'}
            self.records.append({'source':name,'sha256':stored['sha256'],'premultiplied':True,
                'sampling':'original-atlas-extent','atlas_rotated_as_whole':bool(rotated),**result})
            return result
        with Image.open(atlas) as original:
            original=original.convert('RGBA')
            image=original.crop((x-1,y-1,x+physical_w+1,y+physical_h+1))
            # Whole-atlas GL clamp applies only at the atlas's exterior.
            for cy in range(image.height):
                for cx in range(image.width):
                    sx,sy=x-1+cx,y-1+cy
                    if not (0<=sx<original.width and 0<=sy<original.height):
                        image.putpixel((cx,cy),original.getpixel((max(0,min(original.width-1,sx)),max(0,min(original.height-1,sy)))))
        if rotated:image=image.transpose(Image.Transpose.ROTATE_90)
        image=cocos_premultiplied(image)
        stream=io.BytesIO();image.save(stream,format='PNG');blob=stream.getvalue()
        digest=hashlib.sha256(blob).hexdigest();rel=digest[:24]+'.png'
        (self.output/rel).write_bytes(blob)
        result={'file':rel,'width':canvas.width,'height':canvas.height,'frame_height':canvas.height,
            'trim':[0,0,*canvas.size],'sample_rect':[1,1,canvas.width,canvas.height],
            'alpha_encoding':'cocos-premultiplied-rgb'}
        self.records.append({'source':name,'sha256':digest,'premultiplied':True,
            'sampling':'original-atlas-one-texel-neighbourhood',**result})
        return result

    def procedural_white_texture(self):
        stream=io.BytesIO();Image.new('RGBA',(1,1),(255,255,255,255)).save(stream,format='PNG')
        blob=stream.getvalue();digest=hashlib.sha256(blob).hexdigest();rel=digest[:24]+'.png'
        (self.output/rel).write_bytes(blob)
        result={'file':rel,'width':1,'height':1,'frame_height':1,'trim':[0,0,1,1],
                'alpha_encoding':'cocos-premultiplied-rgb'}
        self.records.append({'source':'procedural-musicbar-solid','sha256':digest,'premultiplied':True,**result})
        return result

    def frame_height(self,name,default):
        key=name.replace('\\','/').casefold()
        if key in self.direct or key not in self.frames:return default
        frame=self.frames[key][1]
        return int(re.findall(r'-?\d+',str(frame.get('frame',frame.get('textureRect'))))[3])

    def trim(self,name,size,flip=0):
        """Unrotated drawn rectangle, in pixels from the original canvas's top left."""
        key=name.replace('\\','/').casefold();ow,oh=size
        if key in self.direct or key not in self.frames:return [0,0,ow,oh]
        frame=self.frames[key][1]
        _,_,w,h=[int(v) for v in re.findall(r'-?\d+',str(frame.get('frame',frame.get('textureRect'))))]
        offset=frame.get('offset',frame.get('spriteOffset','{0,0}'))
        ox,oy=[float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',str(offset))][:2]
        left,top=round((ow-w)/2+ox),round((oh-h)/2-oy)
        if flip&1:left=ow-left-w
        if flip&2:top=oh-top-h
        return [left,top,w,h]

    def sequence(self, spec: str, flip=0, trim_canvas=False, premultiplied=False):
        parsed=frame_spec(spec)
        if parsed is None:return [self.texture(spec,flip,trim_canvas,premultiplied)]
        prefix,first,last,_=parsed
        return [self.texture(f'{prefix}-{i}.png',flip,trim_canvas,premultiplied) for i in range(first,last+1)]

    def audio(self, name):
        key=name.replace('\\','/').casefold()
        p=self.direct.get(key)
        if p is None: raise FileNotFoundError(f'Audio not found: {name}')
        blob=p.read_bytes();rel='assets/'+hashlib.sha256(blob).hexdigest()[:24]+p.suffix.lower()
        (self.output/rel).parent.mkdir(parents=True,exist_ok=True);(self.output/rel).write_bytes(blob)
        return rel
