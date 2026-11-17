"""Legacy Key scene traversal, not a translation of per-element zindex.

4.3.7: 0x5a9a00 creates the play plane (root Z 1), bars then notes
(both initially Z 10). BarFactoryConstruct overrides the *bar parent* Z.
0x5ac4f1/0x5ac774 attach every note/bar child at local Z 0.
The original scene creates fixed UI roles before its custom-element vector.
"""
import re


def creation_order(name,source_index):
    match=re.fullmatch(r'(press|key|hit|judge)-(\d+)',name)
    if match:
        return {'press':100,'key':200,'hit':300,'judge':400}[match[1]]+int(match[2])
    return {'score-acc':500,'score-combo':600,'score-maxcombo':700,
            'score-score':800,'hit-fast':900,'hit-slow':1000,'score-hp':1100,
            'progress':1300,'musicbar':1400,'pause':1500}.get(name,2000+source_index)


def scene_key(name,zindex,source_index=0):
    if name=='bar':return [1,0,10 if zindex is None else zindex,0]
    if name.startswith('note-'):return [1,0,10,1]
    arrival=creation_order(name,source_index)
    if zindex is not None and 1<=zindex<=98:return [1,0,zindex,arrival]
    return [0 if zindex is None else zindex,arrival,0,0]


def plan(entries,notes):
    for index,e in enumerate(entries):
        z=e['order'] if 'zindex' in e['attrs'] else None
        e['scene_key']=scene_key(e['name'],z,index)
    for e in notes.values():e['scene_key']=scene_key(e['name'],None)
    return {'model':'legacy-parent-traversal-v1','note_local_z':0,
            'hold_attachment_order':['body','head','tail'],
            'pool_equivalence_verified':False,'full_scene_rgba_verified':False}


def canvas_batches(entries, notes, motions, *, canvas_text=False):
    """Join only contiguous Image elements in the recovered painter traversal.

    A note/bar/custom mesh is a hard boundary. A 3D font renderer is also a
    boundary; opt-in CanvasRenderer fonts retain the same sibling traversal.
    Skew owns its entire old
    element parent and remains isolated. No grouping by texture or skin name.
    """
    rows=sorted([*entries,*notes.values()],key=lambda e:e['scene_key'])
    clusters=[];cluster=[];plane=None
    def flush():
        if len(cluster)>1:
            batch=len(clusters)+1
            clusters.append([e['name'] for e in cluster])
            for rank,e in enumerate(cluster):
                e['canvas_batch']={'id':batch,'rank':rank,'scene_key':cluster[0]['scene_key']}
        cluster.clear()
    for e in rows:
        eligible=(e in entries and e['name']!='bar' and (canvas_text or not e.get('bitmap_font')) and not e.get('musicbar') and
                  not any(a['kind'] in ('skew','skewx','skewy') for a in motions.get(e.get('motion'),[])))
        current=e['scene_key'][:2]==[1,0]
        if not eligible or current!=plane:flush()
        if eligible:cluster.append(e)
        plane=current
    flush()
    return clusters
