"""Generate arbitrary old Label sizes with its actual FreeType/CFF rules.

The size and glyph repertoire come from the font, never from a skin name.
Coverage is compressed per glyph so large type does not embed hundreds of MB
of expanded bitmap strings, and maV only allocates glyphs its text actually uses.
"""
import base64
import ctypes as C
import gzip
import hashlib
import json
import struct
import zlib
from pathlib import Path


def externalize_font(font, destination, *, block_limit=256 * 1024):
    """Store exact coverage once as bounded compressed blocks, outside Lua.

    Dynamic metadata can contain any BMP glyph. Keep that repertoire, but do
    not repeat a Base64 copy in each Key script or inflate the whole bank on
    first text use. The runtime expands only the block containing a new glyph.
    """
    if not font.get('packed_record_size'):
        return font
    old_record = struct.Struct('<IIHHhfh')
    record = struct.Struct('<IIIIHHhfh')
    old_index = gzip.decompress(base64.b64decode(font['packed_index']))
    old_coverage = base64.b64decode(font['packed_coverage'])
    index = bytearray(record.size * 65536)
    payload = bytearray()
    block = bytearray()
    pending = []

    def flush():
        if not pending:
            return
        encoded = gzip.compress(block, compresslevel=9, mtime=0)
        offset = len(payload)
        payload.extend(encoded)
        for code, start, count, metrics in pending:
            record.pack_into(index, code * record.size, offset, len(encoded),
                             start, count, *metrics)
        block.clear()
        pending.clear()

    for code in range(65536):
        offset, count, *metrics = old_record.unpack_from(old_index, code * old_record.size)
        raw = gzip.decompress(old_coverage[offset:offset + count]) if count else b''
        if len(raw) != metrics[0] * metrics[1]:
            raise ValueError('Invalid exact-font coverage length')
        if block and len(block) + len(raw) > block_limit:
            flush()
        if raw:
            pending.append((code, len(block), len(raw), metrics))
            block.extend(raw)
        else:
            record.pack_into(index, code * record.size, 0, 0, 0, 0, *metrics)
    flush()
    encoded_index = gzip.compress(index, compresslevel=9, mtime=0)
    digest = hashlib.sha256(encoded_index + payload).hexdigest()
    name = 'font-' + digest
    destination = Path(destination)
    index_file, coverage_file = name + '.index.gz', name + '.glyphs.bin'
    (destination / index_file).write_bytes(encoded_index)
    (destination / coverage_file).write_bytes(payload)
    result = {k: v for k, v in font.items() if k not in ('packed_index', 'packed_coverage')}
    result.update(packed_index_file=index_file, packed_coverage_file=coverage_file,
                  packed_record_size=record.size, packed_block_format=2)
    return result


class FontGenerator:
    def __init__(self, data_root, project_root, reference):
        self.reference = reference
        self.license_file = data_root / 'SourceHan-LICENSE.txt'
        self.cache = {}
        candidates = [data_root / 'legacy-font.otf']
        local = project_root / 'project.local.json'
        if not local.is_file() and project_root.parent.name == 'dist':
            local = project_root.parent.parent / 'project.local.json'
        if local.is_file():
            legacy = json.loads(local.read_text(encoding='utf-8')).get('legacy')
            if legacy:
                candidates.append(Path(legacy) / 'skin-ex.bin')
        self.font_data = next((p.read_bytes() for p in candidates if p.is_file()), None)
        if self.font_data is None:
            raise ValueError('便携包缺少原版字体资源 legacy-font.otf')
        if hashlib.sha256(self.font_data).hexdigest() != reference['font_sha256']:
            raise ValueError('原版字体资源哈希不符，未使用替代字体')
        self.library = C.CDLL(str((data_root / 'freetype250.dll').resolve()))
        self.library.msb_font_open.argtypes = [C.c_char_p, C.c_int, C.c_int]
        self.library.msb_font_open.restype = C.c_void_p
        self.library.msb_font_close.argtypes = [C.c_void_p]
        self.library.msb_font_glyph.argtypes = [C.c_void_p, C.c_uint, C.POINTER(C.c_int), C.POINTER(C.c_ubyte), C.c_int]
        self.library.msb_font_glyph.restype = C.c_int

    def _render_external_font(self, size, codes=None, stop_after=None, progress=lambda message:None):
        """Stream the exact block format, without per-glyph GZip/Base64 copies.

        A size decision may stop after an actual emitted ZIP prefix exceeds
        the competing outline cost. Future input cannot retract emitted bytes;
        no guessed compression ratio or truncated bank is used for rendering.
        """
        if not 1 <= size <= 1024:raise ValueError('字体像素尺寸必须在 1..1024 范围内')
        record=struct.Struct('<IIIIHHhfh');index=bytearray(record.size*65536)
        face=self.library.msb_font_open(self.font_data,len(self.font_data),size)
        if not face:raise ValueError('FreeType 2.5.0 无法创建原版字体')
        metrics=(C.c_int*10)();pixels=(C.c_ubyte*((size*2+16)**2))()
        block=bytearray();pending=[];payload=bytearray();count=0;line_height=None
        outer=zlib.compressobj(6,zlib.DEFLATED,-15);emitted=0
        def flush():
            nonlocal emitted
            if not pending:return
            encoded=gzip.compress(block,compresslevel=9,mtime=0);offset=len(payload)
            payload.extend(encoded);emitted+=len(outer.compress(encoded))
            for code,start,length,values in pending:
                record.pack_into(index,code*record.size,offset,len(encoded),start,length,*values)
            block.clear();pending.clear()
        try:
            for code in range(32,65536) if codes is None else sorted(set(codes)):
                if code%4096==0:progress(f'正在分析 {size}px 字库，已检查 {code} 个字符…')
                if 0xD800<=code<=0xDFFF:continue
                length=self.library.msb_font_glyph(face,code,metrics,pixels,len(pixels))
                if length==-1:continue
                if length<0 or length>len(pixels):raise ValueError(f'字体 U+{code:04X} 无法栅格化')
                count+=1
                w,h,ox,top,advance,line_height,ascender,descender=metrics[:8]
                if w and h:
                    width=w+2;raw=bytearray(width*h)
                    source=C.string_at(pixels,length)
                    for row in range(h):raw[row*width+1:row*width+1+w]=source[row*w:(row+1)*w]
                    if block and len(block)+len(raw)>256*1024:
                        flush()
                        if stop_after is not None and emitted>stop_after:
                            return None,emitted
                    values=(width,h,ox+1,(ascender+line_height+descender)*.5-top-1,advance)
                    pending.append((code,len(block),len(raw),values));block.extend(raw)
                else:record.pack_into(index,code*record.size,0,0,0,0,0,0,0,0,advance)
            flush();emitted+=len(outer.flush())
        finally:self.library.msb_font_close(face)
        if line_height is None:raise ValueError('原版字体没有可用字形')
        encoded_index=gzip.compress(index,compresslevel=9,mtime=0)
        compressor=zlib.compressobj(6,zlib.DEFLATED,-15)
        total=emitted+len(compressor.compress(encoded_index)+compressor.flush())
        name='font-'+hashlib.sha256(encoded_index+payload).hexdigest()
        font={'pixel_size':size,'render_scale':self.reference['legacy_render_scale'],
            'logical_height':self.reference['legacy_logical_height'],'line_height':line_height,
            'native_ui_projection':self.reference['native_ui_projection'],
            'native_v_coordinates':True,'runtime_cache':True,
            'glyph_cache_initial_state':'runtime-cold-candidate',
            'missing_glyphs_are_zero':True,'utf16_code_units':True,
            'glyphs':{},'pages':{},'coverage':{},'coverage_encoding':'gzip','coverage_binary':True,
            'packed_index_file':name+'.index.gz','packed_coverage_file':name+'.glyphs.bin',
            'packed_record_size':record.size,'packed_block_format':2,'glyph_count':count,
            'font_sha256':self.reference['font_sha256'],
            'rasterizer':'FreeType 2.5.0 / Adobe CFF / FT_LOAD_RENDER | FT_LOAD_NO_AUTOHINT'}
        return (font,encoded_index,bytes(payload)),total

    def bitmap_zip_lower_bound(self, size, stop_after, progress=lambda message:None):
        key=('external',size)
        if key not in self.cache:
            rendered,cost=self._render_external_font(size,stop_after=stop_after,progress=progress)
            if rendered is not None:self.cache[key]=(rendered,cost)
            return cost,rendered is not None
        return self.cache[key][1],True

    def _render_hybrid_font(self, size, progress=lambda message:None):
        """Compact exact-subset bitmap bank + BMP layout metrics + OS TextCore fallback.

        Pre-bakes exact FreeType 2.5.0 coverage for ASCII, punctuation and Kana
        (~15-25 KB) while storing exact BMP layout metrics (left/top included)
        for every other Unicode code point so dynamic CJK text renders on demand
        via OS fonts without shipping a 9-18 MB font payload.
        """
        if not 1 <= size <= 1024:raise ValueError('字体像素尺寸必须在 1..1024 范围内')
        baked=(set(range(32,127))|{0x00A0,0x00B0,0x00D7,0x00F7}
            |set(range(0x2010,0x203E))|set(range(0x3000,0x3100))|set(range(0xFF01,0xFF5F)))
        record=struct.Struct('<IIIIHHhfh hh');index=bytearray(record.size*65536)
        face=self.library.msb_font_open(self.font_data,len(self.font_data),size)
        if not face:raise ValueError('FreeType 2.5.0 无法创建原版字体')
        metrics=(C.c_int*10)();pixels=(C.c_ubyte*((size*2+16)**2))()
        block=bytearray();pending=[];payload=bytearray();count=0;line_height=None
        def flush():
            if not pending:return
            encoded=gzip.compress(block,compresslevel=9,mtime=0);offset=len(payload)
            payload.extend(encoded)
            for code,start,length,values in pending:
                record.pack_into(index,code*record.size,offset,len(encoded),start,length,*values)
            block.clear();pending.clear()
        try:
            for code in range(32,65536):
                if 0xD800<=code<=0xDFFF:continue
                want_bitmap=code in baked
                length=self.library.msb_font_glyph(face,code,metrics,pixels if want_bitmap else None,len(pixels) if want_bitmap else 0)
                if length==-1:continue
                if length<0 or (want_bitmap and length>len(pixels)):raise ValueError(f'字体 U+{code:04X} 无法栅格化')
                count+=1
                w,h,ox,top,advance,line_height,ascender,descender,left,bitmap_top=metrics
                if w and h:
                    width=w+2;oy=(ascender+line_height+descender)*.5-top-1
                    if want_bitmap and length>0:
                        raw=bytearray(width*h)
                        source=C.string_at(pixels,length)
                        for row in range(h):raw[row*width+1:row*width+1+w]=source[row*w:(row+1)*w]
                        if block and len(block)+len(raw)>64*1024:flush()
                        values=(width,h,ox+1,oy,advance,0,0)
                        pending.append((code,len(block),len(raw),values));block.extend(raw)
                    else:
                        record.pack_into(index,code*record.size,0,0,0,0,width,h,ox+1,oy,advance,left,bitmap_top)
                else:
                    record.pack_into(index,code*record.size,0,0,0,0,0,0,0,0,advance,0,0)
            flush()
        finally:self.library.msb_font_close(face)
        if line_height is None:raise ValueError('原版字体没有可用字形')
        encoded_index=gzip.compress(index,compresslevel=9,mtime=0)
        name='font-hybrid-'+hashlib.sha256(encoded_index+payload).hexdigest()
        font={'pixel_size':size,'render_scale':self.reference['legacy_render_scale'],
            'logical_height':self.reference['legacy_logical_height'],'line_height':line_height,
            'native_ui_projection':self.reference['native_ui_projection'],
            'native_v_coordinates':True,'runtime_cache':True,
            'glyph_cache_initial_state':'runtime-cold-candidate',
            'missing_glyphs_are_zero':True,'utf16_code_units':True,
            'glyphs':{},'pages':{},'coverage':{},'coverage_encoding':'gzip','coverage_binary':True,
            'packed_index_file':name+'.index.gz','packed_coverage_file':name+'.glyphs.bin',
            'packed_record_size':record.size,'packed_block_format':3,'hybrid_os_fallback':True,
            'glyph_count':count,'font_sha256':self.reference['font_sha256'],
            'rasterizer':'FreeType 2.5.0 / Adobe CFF subset + runtime OS fallback'}
        return (font,encoded_index,bytes(payload)),len(encoded_index)+len(payload)

    def export_external_size(self, size, codepoints, destination, progress=lambda message:None, *, hybrid=False):
        if codepoints is not None:
            return externalize_font(self.export_size(size,codepoints),destination)
        if hybrid:
            key=('hybrid',size)
            if key not in self.cache:self.cache[key]=self._render_hybrid_font(size,progress=progress)
            (font,index,payload),_=self.cache[key]
            destination=Path(destination)
            (destination/font['packed_index_file']).write_bytes(index)
            (destination/font['packed_coverage_file']).write_bytes(payload)
            return dict(font)
        key=('external',size)
        if key not in self.cache:self.cache[key]=self._render_external_font(size,progress=progress)
        (font,index,payload),_=self.cache[key]
        destination=Path(destination)
        (destination/font['packed_index_file']).write_bytes(index)
        (destination/font['packed_coverage_file']).write_bytes(payload)
        return dict(font)

    def export_outline_metrics(self, size, destination):
        """Research storage: old layout metrics plus the original OpenType face.

        Coverage is generated by TextCore only when a character is displayed.
        This deliberately has a distinct raster contract; it is not an exact
        FreeType 2.5 bitmap bank and must not silently replace that format.
        """
        if not 1 <= size <= 1024:
            raise ValueError('字体像素尺寸必须在 1..1024 范围内')
        cache_key=('outline',size)
        if cache_key in self.cache:
            result,encoded=self.cache[cache_key]
            self._write_outline_files(destination,result,encoded)
            return dict(result)
        record = struct.Struct('<HHhfh hh')
        index = bytearray(record.size * 65536)
        face = self.library.msb_font_open(self.font_data, len(self.font_data), size)
        if not face:
            raise ValueError('FreeType 2.5.0 无法创建原版字体')
        metrics = (C.c_int * 10)()
        line_height = None
        try:
            for code in range(32, 65536):
                if 0xD800 <= code <= 0xDFFF:
                    continue
                count = self.library.msb_font_glyph(face, code, metrics, None, 0)
                if count == -1:
                    continue
                if count < 0:
                    raise ValueError(f'字体 U+{code:04X} 无法取得原版度量')
                w, h, ox, top, advance, line_height, ascender, descender, left, bitmap_top = metrics
                if not w or not h:
                    record.pack_into(index, code * record.size, 0, 0, 0, 0, advance, left, bitmap_top)
                else:
                    record.pack_into(index, code * record.size, w + 2, h, ox + 1,
                        (ascender + line_height + descender) * .5 - top - 1,
                        advance, left, bitmap_top)
        finally:
            self.library.msb_font_close(face)
        if line_height is None:
            raise ValueError('原版字体没有可用字形')
        encoded = gzip.compress(index, compresslevel=9, mtime=0)
        index_file = 'font-metrics-' + hashlib.sha256(encoded).hexdigest() + '.gz'
        outline_file = 'font-outline-' + self.reference['font_sha256'] + '.otf'
        result={'pixel_size': size, 'render_scale': self.reference['legacy_render_scale'],
            'logical_height': self.reference['legacy_logical_height'], 'line_height': line_height,
            'native_ui_projection': self.reference['native_ui_projection'],
            'native_v_coordinates': True, 'runtime_cache': True,
            'missing_glyphs_are_zero': True, 'utf16_code_units': True,
            'glyphs': {}, 'pages': {}, 'coverage': {}, 'coverage_binary': True,
            'packed_index_file': index_file, 'packed_record_size': record.size,
            'native_outline_file': outline_file,
            'font_sha256': self.reference['font_sha256'],
            'rasterizer': 'TextCore SMOOTH_HINTED / original face / original FreeType 2.5 layout metrics',
            'exact_legacy_coverage': False, 'research_storage': True}
        self.cache[cache_key]=(result,encoded)
        self._write_outline_files(destination,result,encoded)
        return dict(result)

    def _write_outline_files(self, destination, font, encoded):
        destination=Path(destination)
        (destination/font['packed_index_file']).write_bytes(encoded)
        # One face is shared by all sizes and by the ordinary resource merger.
        outline_path=destination/font['native_outline_file']
        if not outline_path.exists():outline_path.write_bytes(self.font_data)
        if self.license_file.is_file():
            (destination/'font-outline-license.txt').write_bytes(self.license_file.read_bytes())

    def export_size(self, size, codepoints=None, *, compact=True):
        cache_key=(size,tuple(sorted(set(codepoints))) if codepoints is not None else None,compact)
        if cache_key in self.cache:
            return self.cache[cache_key]
        if not 1 <= size <= 1024:
            raise ValueError('字体像素尺寸必须在 1..1024 范围内')
        font = self.library.msb_font_open(self.font_data, len(self.font_data), size)
        if not font:
            raise ValueError('FreeType 2.5.0 无法创建原版字体')
        metrics = (C.c_int * 10)()
        pixels = (C.c_ubyte * ((size * 2 + 16) ** 2))()
        glyphs, coverage = {}, {}
        line_height = None
        try:
            for code in cache_key[1] if codepoints is not None else range(32, 65536):
                if 0xD800 <= code <= 0xDFFF:
                    continue
                count = self.library.msb_font_glyph(font, code, metrics, pixels, len(pixels))
                if count == -1:
                    continue
                if count < 0 or count > len(pixels):
                    raise ValueError(f'字体 U+{code:04X} 无法栅格化')
                w, h, ox, top, advance, line_height, ascender, descender = metrics[:8]
                if w and h:
                    width = w + 2
                    packed = bytearray(width * h)
                    raw = C.string_at(pixels, count)
                    for row in range(h):
                        packed[row * width + 1:row * width + 1 + w] = raw[row * w:(row + 1) * w]
                    glyphs[code] = [0, 0, 0, width, h, ox + 1,
                                    (ascender + line_height + descender) * .5 - top - 1, advance]
                    coverage[code] = base64.b64encode(gzip.compress(packed, compresslevel=6, mtime=0)).decode('ascii')
                else:
                    glyphs[code] = [0, 0, 0, 0, 0, 0, 0, advance]
        finally:
            self.library.msb_font_close(font)
        if line_height is None:
            raise ValueError('原版字体没有可用字形')
        result = {'pixel_size': size, 'render_scale': self.reference['legacy_render_scale'],
                  'logical_height': self.reference['legacy_logical_height'], 'line_height': line_height,
                  'native_ui_projection': self.reference['native_ui_projection'],
                  'native_v_coordinates': True, 'runtime_cache': True,
                  'glyph_cache_initial_state': 'runtime-cold-candidate',
                  'missing_glyphs_are_zero': True, 'utf16_code_units': True,
                  'glyphs': glyphs, 'pages': {}, 'coverage': coverage, 'coverage_encoding': 'gzip',
                  'font_sha256': self.reference['font_sha256'],
                  'rasterizer': 'FreeType 2.5.0 / Adobe CFF / FT_LOAD_RENDER | FT_LOAD_NO_AUTOHINT'}
        if compact and len(glyphs)>512:
            # A fixed BMP index replaces tens of thousands of GC-visible Lua
            # tables. Coverage stays byte-identical, compressed per glyph.
            record=struct.Struct('<IIHHhfh')
            index=bytearray(record.size*65536);packed=bytearray()
            for code,glyph in glyphs.items():
                image=base64.b64decode(coverage[code]) if code in coverage else b''
                record.pack_into(index,code*record.size,len(packed),len(image),
                    glyph[3],glyph[4],glyph[5],glyph[6],glyph[7])
                packed.extend(image)
            result.update(glyphs={},coverage={},coverage_binary=True,
                packed_index=base64.b64encode(gzip.compress(index,mtime=0)).decode('ascii'),
                packed_coverage=base64.b64encode(packed).decode('ascii'),
                packed_record_size=record.size,glyph_count=len(glyphs))
        self.cache[cache_key] = result
        return result
