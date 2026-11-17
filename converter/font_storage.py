"""Choose font storage once for the whole package, from actual ZIP costs.

The original outline is shared across sizes/keys/platforms. Per-entry choices
could retain an old bank in one entry while adding the full face in another,
so they cannot establish an actual package-size saving.
"""
import json
import math
import re
import zlib

from .common import DATA, ROOT, uses_scene_text
from .mui import native_dimension
from .font_generator import FontGenerator


def zip_cost(data):
    compressor=zlib.compressobj(6,zlib.DEFLATED,-15)
    return len(compressor.compress(data)+compressor.flush())


def plan_font_storage(documents, reference_path, destination, progress=lambda message:None):
    dynamic_sizes=set()
    has_text=False
    reference=json.loads((reference_path/'font-bank.json').read_text(encoding='utf8'))
    for document in documents:
        for item in document.elements.values():
            if not uses_scene_text(item):continue
            has_text=True
            if re.search(r'\{[^{}]+\}',item.attrs['text']):
                size=int(native_dimension(document,item,'fsize',24))
                dynamic_sizes.add(int(math.floor(size*reference['legacy_render_scale']+.5)))
    if not has_text:return None
    generator=FontGenerator(DATA,ROOT,reference)
    context={'generator':generator,'outline_sizes':set(),'report':{
        'decision_scope':'whole-package-all-keys-and-platforms',
        'dynamic_pixel_sizes':sorted(dynamic_sizes),'backend':'exact-bitmaps',
        'exact_bitmap_zip_bytes':0,'outline_zip_bytes':None}}
    if not dynamic_sizes:return context
    progress('正在选择动态文字的字库存储方式…')
    destination.mkdir()
    face_cost=zip_cost(generator.font_data)
    outline_files=set()
    for size in sorted(dynamic_sizes):
        progress(f'正在读取旧版字体度量：{size}px…')
        font=generator.export_outline_metrics(size,destination)
        outline_files.add(font['packed_index_file'])
    license_file=DATA/'SourceHan-LICENSE.txt'
    outline_cost=face_cost+sum(zip_cost((destination/name).read_bytes()) for name in outline_files)
    if license_file.is_file():outline_cost+=zip_cost(license_file.read_bytes())
    context['report']['outline_zip_bytes']=outline_cost
    exact_cost=0;completed_sizes=0
    threshold=max(outline_cost/.95,outline_cost+65536)
    # Large banks can establish the decision with an actual compressed prefix.
    # No complete BMP bitmap bank is baked solely to discard it afterwards.
    for size in sorted(dynamic_sizes,reverse=True):
        cost,finished=generator.bitmap_zip_lower_bound(size,threshold-exact_cost,progress=progress)
        exact_cost+=cost;completed_sizes+=int(finished)
        if exact_cost>threshold:break
    all_complete=completed_sizes==len(dynamic_sizes)
    context['report']['exact_bitmap_zip_bytes']=exact_cost if all_complete else None
    context['report']['bitmap_zip_lower_bound']=exact_cost
    # Leave room for the small runtime/descriptor delta and ZIP entry headers.
    # No skin names, archive hashes, missing-glyph pruning or resize heuristic.
    if exact_cost-outline_cost>65536 and outline_cost<exact_cost*.95:
        context['outline_sizes']=dynamic_sizes
        context['report'].update(backend='native-outline-original-layout',
            exact_legacy_coverage=False,minimum_resource_saving=exact_cost-outline_cost)
    return context
