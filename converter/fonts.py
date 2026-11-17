"""Old native bitmap font metrics, with no replacement font rasterization."""
from pathlib import Path
import hashlib
import json
import math
import base64
from PIL import Image

from .context import LEGACY_EXE_SHA256

class NativeFontBank:
    def __init__(self,path:Path):
        self.root=Path(path).resolve()
        self.data=json.loads((self.root/'font-bank.json').read_text(encoding='utf-8'))
        d=self.data
        if not (d.get('format')==1 and d.get('native_coverage_bytes_preserved')
                and d.get('source_executable_sha256')==LEGACY_EXE_SHA256):
            raise ValueError('Unverified native font bank')
        for name,digest in d['atlas_sha256'].items():
            target=(self.root/name).resolve()
            if not target.is_relative_to(self.root) or hashlib.sha256(target.read_bytes()).hexdigest()!=digest:
                raise ValueError('Native font atlas integrity mismatch')
        self.glyphs={int(k):v for k,v in d['glyphs'].items()}
        self.pages={int(k):v for k,v in d['pages'].items()}
        self.line_height=float(d['line_height'])
        if not math.isfinite(self.line_height) or self.line_height<=0:raise ValueError('Invalid native line height')

    def layout(self,text:str):
        """No-wrap layout in native raster units, before Node anchor/scale.

        This exact glyph placement is checked against old Label GPU quads.
        Newline and trailing whitespace remain explicit until native proofs
        cover their bounds/anchor rules; do not silently approximate them.
        """
        if '\n' in text or '\r' in text:raise ValueError('Native multiline font layout is not verified')
        if text.endswith((' ','\t')):raise ValueError('Native trailing-whitespace bounds are not verified')
        pen=0;quads=[];width=0
        for character in text:
            code=ord(character)
            if code not in self.glyphs:raise ValueError(f'Native font bank has no U+{code:04X}')
            page,u,v,w,h,ox,oy,advance=self.glyphs[code]
            if w>0 and h>0:
                x=pen+ox;top=self.line_height-oy;bottom=top-h
                quads.append({'unicode':code,'page':page,'positions':[[x,top,0],[x,bottom,0],[x+w,top,0],[x+w,bottom,0]],
                              'uv_pixels':[[u,v],[u,v+h],[u+w,v],[u+w,v+h]]})
                width=x+w
            pen+=advance
        return {'quads':quads,'width':width,'height':self.line_height if text else 0,'advance':pen}

    def export(self,destination:Path,text_batches=None):
        pages={};glyphs=self.glyphs
        source_pages=self.pages;generated={}
        coverage={}
        if text_batches is None:
            # Native LoadSkin makes imported textures unreadable. Store only
            # original alpha bytes for runtime allocation; no image API read,
            # shader capture, font substitution or rasterization is required.
            loaded={}
            for code,(page,x,y,w,h,*_) in self.glyphs.items():
                if w and h:
                    if page not in loaded:
                        with Image.open(self.root/self.pages[page]['file']) as source:loaded[page]=source.getchannel('A')
                    coverage[code]=base64.b64encode(loaded[page].crop((x,y,x+w,y+h)).tobytes()).decode('ascii')
            source_pages={}
        if text_batches is not None:
            from .font_atlas import pack_atlas
            for text in text_batches:self.layout(text)
            positions=pack_atlas(text_batches,self.glyphs,self.line_height);glyphs={}
            loaded={}
            for code,(page,x,y) in positions.items():
                original,u,v,w,h,ox,oy,advance=self.glyphs[code]
                glyphs[code]=[page,x,y,w,h,ox,oy,advance]
                if w and h:
                    if any(int(value)!=value for value in (u,v,w,h,x,y)):raise ValueError('Fractional native atlas grid is not verified')
                    if original not in loaded:
                        with Image.open(self.root/self.pages[original]['file']) as source:loaded[original]=source.convert('RGBA')
                    if page not in generated:generated[page]=Image.new('RGBA',(512,512),(255,255,255,0))
                    if x+w>512 or y+h>512:raise ValueError('Native glyph outside reconstructed page')
                    generated[page].paste(loaded[original].crop((u,v,u+w,v+h)),(int(x),int(y)))
            source_pages={page:{'width':512,'height':512} for page in generated}
        for index,page in source_pages.items():
            name=f'native-font-{self.data["pixel_size"]}-{index}.png'
            # Unity's PNG upload reverses row orientation relative to this
            # native GL atlas. Reverse rows in the OUTPUT pixels so the shader
            # can retain the old V values. Doing 1-V at the vertices instead
            # produced two strict RGB errors in the actual native proof.
            if index in generated:generated[index].transpose(Image.Transpose.FLIP_TOP_BOTTOM).save(destination/name)
            else:
                with Image.open(self.root/page['file']) as source:
                    source.transpose(Image.Transpose.FLIP_TOP_BOTTOM).save(destination/name)
            pages[index]={**page,'file':name}
        return {'pixel_size':self.data['pixel_size'],'render_scale':self.data['legacy_render_scale'],
                'logical_height':self.data['legacy_logical_height'],'line_height':self.line_height,
                'native_ui_projection':self.data.get('native_ui_projection'),
                'native_v_coordinates':True,
                'runtime_cache':text_batches is None,
                'coverage':coverage,
                'glyph_cache_initial_state':'cold-candidate' if text_batches is not None else 'runtime-cold-candidate',
                'glyphs':glyphs,'pages':pages,'font_sha256':self.data['font_sha256']}
