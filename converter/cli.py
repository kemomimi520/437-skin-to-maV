from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
from .compiler import compile_skin


def main(argv=None):
    parser=argparse.ArgumentParser(description='Malody 4.3.7 → Malody V skin compiler')
    parser.add_argument('source',type=Path)
    parser.add_argument('--output','-o',type=Path)
    parser.add_argument('--keys',default='all',help='all or comma-separated counts; original entries only')
    parser.add_argument('--ratio')
    parser.add_argument('--ui-rounding-height',type=float,help='Override source Cocos logical viewport height; otherwise infer verified executable/window context')
    parser.add_argument('--native-font-bank',type=Path,help='Candidate exact old bitmap bank; text acceptance remains blocked')
    parser.add_argument('--native-font-runtime-cache',action='store_true',help='Candidate stateful old glyph packing even for a single literal label; requires --native-font-bank')
    parser.add_argument('--draft',action='store_true',help='Explicitly package blocked candidates as .draft.msp')
    parser.add_argument('--preview',action='store_true',help='Use the current native compatibility test preset and export importable .draft.msp files')
    args=parser.parse_args(argv)
    try:
        if args.source.is_file() and args.source.suffix.lower()=='.msz':
            from .msz import convert_msz
            import shutil
            generated=convert_msz(args.source)
            packages=list(generated) if isinstance(generated,(list,tuple)) else [generated]
            if args.output is not None:
                moved=[]
                for item in packages:
                    target=args.output/item.name if (len(packages)>1 or args.output.is_dir() or args.output.suffix.lower()!='.msp') else args.output
                    if target.resolve()!=item.resolve():
                        target.parent.mkdir(parents=True,exist_ok=True)
                        shutil.move(str(item),str(target))
                        item=target
                    moved.append(item)
                packages=moved
            payload={'source':str(args.source),'package':str(packages[0]),'free':False}
            if len(packages)>1:payload['packages']=[str(p) for p in packages]
            print(json.dumps(payload,ensure_ascii=False))
            return 0
        if args.output is None:raise ValueError('--output is required for unpacked skin folders')
        x,y=map(float,(args.ratio or '16:9').split(':'));ratio=x/y
        if args.preview and args.ratio and abs(ratio-1024/600)>1e-10:raise ValueError('当前测试预设仅验证 1024:600 比例')
        if args.keys=='all':keys=sorted(int(p.stem.split('-')[-1][:-1]) for p in args.source.glob('script-key-*K.mui'))
        else:keys=[int(k) for k in args.keys.split(',')]
        if not keys:raise ValueError('No Key-mode .mui entry found')
        reports=[]
        for count in keys:
            target=args.output/f'{args.source.name}-{count}K'
            if args.preview:
                from .preview import compile_preview
                report=compile_preview(args.source,target,count)
            else:
                report=compile_skin(args.source,target,count,ratio,args.draft,ui_rounding_height=args.ui_rounding_height,native_font_bank=args.native_font_bank,native_font_runtime_cache=args.native_font_runtime_cache)
            reports.append(report)
            print(json.dumps({k:report[k] for k in ['keys','status','errors','module_count','one_to_one_verified']},ensure_ascii=False))
        if args.preview:return 0 if all(r.get('archive') for r in reports) else 2
        return 2 if any(r['errors'] for r in reports) else 0
    except (ValueError,OSError) as error:
        print(str(error),file=sys.stderr);return 1

if __name__=='__main__':raise SystemExit(main())
