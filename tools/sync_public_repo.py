"""Export a clean open-source snapshot from the private workspace to the public repository."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STAGE = ROOT / 'output/.public-export-repo'
PUBLIC_REMOTE = 'public'
PUBLIC_REPO_SLUG = 'kemomimi520/437-skin-to-maV'

ROOT_FILES = (
    '.gitattributes',
    'LICENSE',
    'README.md',
    'requirements.txt',
    'ma_skin_bridge.py',
    'Ma Skin Bridge.pyw',
)

PUBLIC_GITIGNORE = """__pycache__/
*.py[cod]
*.pyo
.pytest_cache/
output/
dist/
*.msp
*.msz
*.log
.env
.env.*
project.local.json
"""

PUBLIC_CMD = (
    "@echo off\r\n"
    "if exist \"%~dp0runtime\\pythonw.exe\" (\r\n"
    "  start \"\" \"%~dp0runtime\\pythonw.exe\" \"%~dp0Ma Skin Bridge.pyw\" %*\r\n"
    ") else (\r\n"
    "  start \"\" pythonw \"%~dp0Ma Skin Bridge.pyw\" %*\r\n"
    ")\r\n"
)

PUBLIC_TEST_FILES = (
    'tests/test_public_smoke.py',
    'tests/test_legacy_note_space.py',
    'tests/test_legacy_sprite_uv.py',
    'tests/test_native_dense_performance.py',
    'tests/test_native_note_images.py',
    'tests/test_native_toggle.py',
    'tests/test_text_variables.py',
    'tests/test_touch_numeric_context.py',
    'tests/data/legacy-keyuis-units.json',
    'tests/data/legacy-metadata-token-values.json',
    'tests/data/legacy-scale3-texcoords.json',
    'tests/data/native-dense-performance.json',
    'tests/data/native-key-offset-units.json',
)

PUBLIC_TOOLS = (
    'tools/build_portable.py',
    'tools/local_paths.py',
    'tools/native_package_input.py',
    'tools/sync_public_repo.py',
)


def _git(cwd: Path, *args: str, capture: bool = True) -> str:
    res = subprocess.run(
        ['git', *args],
        cwd=str(cwd),
        text=True,
        encoding='utf-8',
        capture_output=capture,
        check=True,
    )
    return res.stdout if capture else ''


def _handle_remove_readonly(func, path, exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def _ensure_stage_clean(stage: Path) -> None:
    if stage.exists():
        shutil.rmtree(stage, onerror=_handle_remove_readonly)
    stage.mkdir(parents=True)


def stage_public_tree(stage: Path) -> dict:
    _ensure_stage_clean(stage)

    # 1. Root files & launcher
    for rel in ROOT_FILES:
        src = ROOT / rel
        if not src.is_file():
            raise FileNotFoundError(f'Missing required public root file: {rel}')
        shutil.copy2(src, stage / rel)
    (stage / '.gitignore').write_text(PUBLIC_GITIGNORE, encoding='utf-8')
    (stage / 'MSZ转MSP.cmd').write_bytes(PUBLIC_CMD.encode('ascii'))

    # 2. All tracked converter/ files (excluding __pycache__)
    tracked_converter = _git(ROOT, 'ls-files', '-z', 'converter/').split('\0')
    for rel in tracked_converter:
        if not rel or '__pycache__' in Path(rel).parts:
            continue
        dst = stage / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, dst)

    # 3. Runtime assets in converter/data/ (excluding dev debug symbols .pdb/.lib)
    data_dst = stage / 'converter/data'
    data_dst.mkdir(parents=True, exist_ok=True)
    pb_src = ROOT / 'analysis/malody-v/recovered_skin.descriptor.pb'
    if not pb_src.is_file():
        pb_src = ROOT / 'converter/data/skin.descriptor.pb'
    shutil.copy2(pb_src, data_dst / 'skin.descriptor.pb')

    leg_src = ROOT / 'analysis/malody-4.3.7/resources'
    if not leg_src.is_dir():
        leg_src = ROOT / 'converter/data/legacy'
    shutil.copytree(leg_src, data_dst / 'legacy', dirs_exist_ok=True)

    font_src = ROOT / 'analysis/malody-4.3.7/native-font-cache/sourcehan24-r2'
    if not font_src.is_dir():
        font_src = ROOT / 'converter/data/native-font-bank'
    shutil.copytree(font_src, data_dst / 'native-font-bank', dirs_exist_ok=True)

    for name in ('legacy-font.otf', 'freetype250.dll', 'FreeType-LICENSE.txt', 'SourceHan-LICENSE.txt'):
        src = ROOT / 'converter/data' / name
        if not src.is_file():
            raise FileNotFoundError(f'Missing runtime asset: converter/data/{name}')
        shutil.copy2(src, data_dst / name)

    # 4. Curated user-facing docs
    docs_dst = stage / 'docs'
    docs_dst.mkdir(parents=True, exist_ok=True)
    if (ROOT / 'docs/STATUS.md').is_file():
        shutil.copy2(ROOT / 'docs/STATUS.md', docs_dst / 'STATUS.md')

    # 5. Selected unit tests & public helper scripts (keep reverse-engineering internals private)
    for rel in (*PUBLIC_TEST_FILES, *PUBLIC_TOOLS):
        src = ROOT / rel
        if src.is_file():
            dst = stage / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    # Safety audit: no >50MB blobs, no AGENTS.md/project.local.json/analysis/output leaks
    all_files = [p for p in stage.rglob('*') if p.is_file()]
    oversized = [(str(p.relative_to(stage)), p.stat().st_size) for p in all_files if p.stat().st_size > 50 * 1024 * 1024]
    if oversized:
        raise ValueError(f'Public export contains >50MB files: {oversized}')
    forbidden = {'AGENTS.md', 'project.local.json'}
    leaked = [str(p.relative_to(stage)) for p in all_files if p.name in forbidden]
    if leaked:
        raise ValueError(f'Forbidden private files in public export: {leaked}')

    return {
        'stage': str(stage),
        'file_count': len(all_files),
        'total_bytes': sum(p.stat().st_size for p in all_files),
    }


def push_public_repo(stage: Path, remote_url: str, branch: str, message: str, *, push: bool) -> dict:
    # Preserve clean incremental commits on top of existing remote public branch
    # without inheriting the private repo's historical commits.
    _git(stage, 'init', '-b', branch)
    name = _git(ROOT, 'config', 'user.name').strip() or 'kemomimi520'
    email = _git(ROOT, 'config', 'user.email').strip() or '184949760+kemomimi520@users.noreply.github.com'
    _git(stage, 'config', 'user.name', name)
    _git(stage, 'config', 'user.email', email)
    _git(stage, 'remote', 'add', 'public', remote_url)
    fetch = subprocess.run(
        ['git', 'fetch', 'public', branch],
        cwd=str(stage),
        text=True,
        capture_output=True,
    )
    if fetch.returncode == 0:
        _git(stage, 'reset', '--soft', 'FETCH_HEAD')
    _git(stage, 'add', '-A')
    status = _git(stage, 'status', '--short')
    committed = False
    if status.strip():
        _git(stage, 'commit', '-m', message)
        committed = True
    commit_sha = _git(stage, 'rev-parse', '--short', 'HEAD').strip()
    if push:
        _git(
            stage,
            '-c', 'http.postBuffer=524288000',
            '-c', 'http.version=HTTP/1.1',
            'push', 'public', f'HEAD:{branch}',
            capture=False,
        )
    return {'branch': branch, 'commit': commit_sha, 'committed': committed, 'pushed': push}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, default=DEFAULT_STAGE)
    parser.add_argument('--remote-url', default=f'https://github.com/{PUBLIC_REPO_SLUG}.git')
    parser.add_argument('--branch', default='main')
    parser.add_argument('--message', default='Sync latest Malody-Skin-Bridge release')
    parser.add_argument('--push', action='store_true', help='Push clean export commit to public remote')
    parser.add_argument('--release-tag', help='Create or update GitHub release on public repo with clean portable zip')
    parser.add_argument('--release-zip', type=Path, default=ROOT / 'output/Ma-Skin-Bridge-0.3.0-dev8-win-x64.zip')
    args = parser.parse_args()

    staged = stage_public_tree(args.stage.resolve())
    result = {'staged': staged}
    result['git'] = push_public_repo(args.stage.resolve(), args.remote_url, args.branch, args.message, push=args.push)

    if args.release_tag:
        subprocess.run(
            [sys.executable, str(ROOT / 'tools/build_portable.py'), '--refresh', '--zip', str(args.release_zip)],
            check=True,
        )
        repo_flag = PUBLIC_REPO_SLUG
        exists = subprocess.run(
            ['gh', 'release', 'view', args.release_tag, '--repo', repo_flag],
            capture_output=True,
        )
        if exists.returncode == 0:
            subprocess.run(
                ['gh', 'release', 'upload', args.release_tag, str(args.release_zip), '--clobber', '--repo', repo_flag],
                check=True,
            )
        else:
            notes = (ROOT / 'docs/STATUS.md').read_text(encoding='utf-8') if (ROOT / 'docs/STATUS.md').is_file() else args.message
            subprocess.run(
                [
                    'gh', 'release', 'create', args.release_tag, str(args.release_zip),
                    '--repo', repo_flag,
                    '--title', f'Ma Skin Bridge {args.release_tag}',
                    '--notes', notes,
                ],
                check=True,
            )
        result['release'] = {'tag': args.release_tag, 'zip': str(args.release_zip)}

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
