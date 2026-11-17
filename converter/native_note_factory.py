"""437 CreateNoteSprite dispatch, before any resource or geometry conversion.

The default one-image Scale3, quad Part3, sliced Part3 and tiled Part3 have
different movement and alpha contracts. A type value is not a maV note type.
Evidence: 0x4f29f0, its installed vtables, 0x4f1120/1580/1c90/2070 and
KeyUIS admission 0x5ac1b0. This module does not certify a maV representation.
"""
from dataclasses import asdict, dataclass

from .mui import native_integer


@dataclass(frozen=True)
class HoldFactory:
    name: str
    vtable_rva: int
    move_rva: int
    head_suffix: str | None
    tail_suffix: str | None
    sliced_body: bool
    premultiplied_body: bool | None
    trim_body_canvas: bool | None
    body_geometry: str
    lock_state: str

    def record(self):
        row=asdict(self)
        for field in ('vtable_rva','move_rva'):row[field]=hex(row[field])
        return row


def select_hold_factory(attrs):
    """Only attributes consumed by the selected original branch are selected.

    Even a defined tex5/tex3 is unused by the default Scale3. An absent tail
    falls back to the SELECTED LN head for the other three branches, not tap.
    Mere presence of parsed part selects Scale3Sprite in type=2. type2 does not
    select the factory; it selects quad edge axes only in plain Part3.
    """
    kind=native_integer(attrs.get('type'))
    head='5' if 'tex5' in attrs else ''
    tail='3' if 'tex3' in attrs else head
    if kind==2:
        if 'part' in attrs:
            return HoldFactory('scale3part3',0x3a9a30,0xf1c90,head,tail,True,False,True,
                               'head-bottom-to-tail-top','retained-float-distance')
        return HoldFactory('part3',0x3a9994,0xf1580,head,tail,False,True,True,
                           'sprite-centres-quad','retained-float-distance')
    if kind==3:
        # TileSprite creates ordinary Sprite children, including their PMA
        # blend contract; never encode its texture like a ShapeSprite quad.
        return HoldFactory('tile3',0x3a994c,0xf2070,head,tail,False,False,False,
                           'sprite-centres-tile','retained-float-distance')
    return HoldFactory('scale3',0x3a99dc,0xf1120,None,None,True,False,True,
                       'one-sprite-fixed-admission-height','whole-note-hit-visibility')


def require_mapped_hold_factories(elements):
    """Select the 4.3.7 factory independently for every Key lane.

    ``CreateNoteSprite`` is called once per lane.  A skin is therefore allowed
    to use the default whole-image Scale3 factory for some lanes and the plain
    Part3 factory for others; the old implementation incorrectly rejected the
    entire entry when the set was mixed.  The native source adapter keeps the
    factory on each recipe and dispatches the visual path per admitted lane.
    Unsupported factories still stop before any image work so they cannot be
    silently rendered as a different geometry.
    """
    plans={name:select_hold_factory(item.attrs) for name,item in elements.items()
           if name.startswith('note-')}
    unmapped=[name+' ('+plan.name+')' for name,plan in plans.items()
              if plan.name not in ('part3','scale3','scale3part3','tile3')]
    if unmapped:
        raise ValueError('437 长条工厂尚未映射原生 Key：'+', '.join(unmapped)+
                         '；这些工厂的资源、边界或生命周期不同，不能按 Part3 生成替代皮肤')
    return plans
