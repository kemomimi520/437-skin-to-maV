"""Bundle the already installed Python runtime and compiler, entirely inside the workspace."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/Ma-Skin-Bridge-0.3.0-dev8'

def refresh_payload():
    shutil.copytree(ROOT/'converter',OUT/'converter',dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__','data'))
    data=OUT/'converter/data';data.mkdir(exist_ok=True)
    pb_src=ROOT/'analysis/malody-v/recovered_skin.descriptor.pb'
    if not pb_src.is_file():pb_src=ROOT/'converter/data/skin.descriptor.pb'
    if (pb_src.resolve()!=((data/'skin.descriptor.pb').resolve())):
        shutil.copy2(pb_src,data/'skin.descriptor.pb')
    leg_src=ROOT/'analysis/malody-4.3.7/resources'
    if not leg_src.is_dir():leg_src=ROOT/'converter/data/legacy'
    if (leg_src.resolve()!=((data/'legacy').resolve())):
        shutil.copytree(leg_src,data/'legacy',dirs_exist_ok=True)
    font_src=ROOT/'analysis/malody-4.3.7/native-font-cache/sourcehan24-r2'
    if not font_src.is_dir():font_src=ROOT/'converter/data/native-font-bank'
    if (font_src.resolve()!=((data/'native-font-bank').resolve())):
        shutil.copytree(font_src,data/'native-font-bank',dirs_exist_ok=True)
    for name in ('legacy-font.otf','freetype250.dll','FreeType-LICENSE.txt','SourceHan-LICENSE.txt'):
        source=ROOT/'converter/data'/name;target=data/name
        # A running converter can hold the already identical font DLL open.
        # Refreshing source files does not require rewriting unchanged data.
        if not target.is_file() or hashlib.sha256(source.read_bytes()).digest()!=hashlib.sha256(target.read_bytes()).digest():
            shutil.copy2(source,target)
    for name in ('ma_skin_bridge.py','Ma Skin Bridge.pyw'):
        shutil.copy2(ROOT/name,OUT/name)
    for name in ('README.md','LICENSE'):
        if (ROOT/name).is_file():shutil.copy2(ROOT/name,OUT/name)
    if (ROOT/'docs/STATUS.md').is_file():shutil.copy2(ROOT/'docs/STATUS.md',OUT/'STATUS.md')
    if (ROOT/'docs/usage.md').is_file():shutil.copy2(ROOT/'docs/usage.md',OUT/'使用说明.md')
    for extra in (
        'generic-key-validation.md','legacy-language-coverage.md','android-and-package-status-r37.md',
        'corpus-r38-status.md','corpus-r39-status.md','corpus-r40-status.md','corpus-r41-status.md',
        'corpus-r42-status.md','retained-text-r43-status.md','corpus-r44-status.md',
        'font-transform-r45-status.md','platform-branches-r46-status.md','font-layer-r47-status.md',
        'architecture-correction-r48.md','performance-causality-r49.md','loader-contract-r52.md',
        'visibility-r53.md','official-corpus-r54.md','performance-root-r55.md',
        'performance-root-r56.md','package-size-r57.md','loader-size-and-storage-r58.md',
        'ranked-native-key-contract-r59.md',
    ):
        src_doc=ROOT/'docs'/extra
        if src_doc.is_file():shutil.copy2(src_doc,OUT/extra)
    manifest={'version':'0.3.0-dev8','test_release':True,
              'conversion_enabled':True,'native_key_backend_implemented':True,
              'render_backend':'native_key (free=false); retained Free compiler disabled before output',
              'required_backend':'native Key; original input, judge, score and replay',
              'required_skin_upload':True,'required_normal_score_upload':True,
              'skin_upload_verified':False,'normal_score_submission_verified':False,
              'performance_verified':False,'one_to_one_verified':False,
              'minimum_native_fps_ratio':.85,'game_installations_modified':False,
              'existing_msp_replaced':False,'bypass_switch_available':False,
              'historical_r58_reports':'Retained analysis only; Free outputs do not meet current delivery requirements',
              'files':{p.relative_to(OUT/'converter').as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in sorted((OUT/'converter').rglob('*')) if p.is_file() and '__pycache__' not in p.parts}}
    (OUT/'测试版校验.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    payload=[p for p in OUT.rglob('*') if p.is_file() and p.relative_to(OUT).parts[0]!='output' and '__pycache__' not in p.parts]
    print(json.dumps({'distribution':str(OUT),'program_file_count':len(payload),
        'program_bytes':sum(p.stat().st_size for p in payload)}))

def write_release_zip(zip_path: Path):
    zip_path=zip_path.resolve();zip_path.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as archive:
        for p in sorted(OUT.rglob('*')):
            if not p.is_file():continue
            rel=p.relative_to(OUT)
            if rel.parts[0]=='output' or '__pycache__' in rel.parts or p.suffix.lower() in ('.pyc','.pyo'):continue
            archive.write(p,(Path(OUT.name)/rel).as_posix())
    print(json.dumps({'release_zip':str(zip_path),'bytes':zip_path.stat().st_size}))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh',action='store_true',help='Update the compiler/resources in place; retain the existing runtime')
    parser.add_argument('--zip',type=Path,help='Package the clean portable build (excluding output/ and caches) into a zip archive')
    args=parser.parse_args()
    if OUT.exists():
        if not args.refresh and not args.zip:raise FileExistsError('Distribution exists; use --refresh to update its payload in place')
        if args.refresh:refresh_payload()
        if args.zip:write_release_zip(args.zip)
        return
    runtime=OUT/'runtime';runtime.mkdir(parents=True)
    base=Path(sys.base_prefix)
    for name in ['python.exe','pythonw.exe','python311.dll','python3.dll','vcruntime140.dll','vcruntime140_1.dll','LICENSE.txt']:
        if (base/name).is_file():shutil.copy2(base/name,runtime/name)
    shutil.copytree(base/'DLLs',runtime/'DLLs',ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(base/'tcl',runtime/'tcl')
    with zipfile.ZipFile(runtime/'python311.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in (base/'Lib').rglob('*'):
            if not p.is_file():continue
            rel=p.relative_to(base/'Lib')
            if set(rel.parts)&{'site-packages','test','tests','__pycache__','idlelib','turtledemo','ensurepip'}:continue
            if p.suffix.lower() in ['.py','.pickle','.txt','.pem']:
                archive.write(p,rel.as_posix())
    site=runtime/'Lib/site-packages';site.mkdir(parents=True)
    import PIL,google.protobuf
    shutil.copytree(Path(PIL.__file__).parent,site/'PIL',ignore=shutil.ignore_patterns('__pycache__'))
    google_root=Path(google.protobuf.__file__).parents[1]
    for name in ['protobuf','_upb']:
        if (google_root/name).is_dir():shutil.copytree(google_root/name,site/'google'/name,ignore=shutil.ignore_patterns('__pycache__'))
    (runtime/'python311._pth').write_text('python311.zip\nDLLs\nLib\nLib/site-packages\n..\n',encoding='utf-8')
    (OUT/'打开转换器.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0runtime\\pythonw.exe" "%~dp0Ma Skin Bridge.pyw" %*\r\n',encoding='ascii',newline='')
    (OUT/'ma-convert.cmd').write_text('@echo off\r\n"%~dp0runtime\\python.exe" -X utf8 "%~dp0ma_skin_bridge.py" %*\r\n',encoding='ascii',newline='')
    launcher='@echo off\r\nstart "" "%~dp0runtime\\pythonw.exe" "%~dp0Ma Skin Bridge.pyw" %*\r\n'
    (OUT/'MSZ转MSP.cmd').write_text(launcher,encoding='ascii',newline='')
    (OUT/'一键转换-拖入皮肤文件夹.cmd').write_text(launcher,encoding='ascii',newline='')
    refresh_payload()

if __name__=='__main__':main()
