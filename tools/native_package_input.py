"""Read a declarative native Key MSP without requiring a Free Lua program.

Only metadata is staged for observation. The unmodified MSP is imported by
the game's own importer. This is test preparation, not a conversion backend.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import zipfile

from converter.compiler import skin_class
from converter.output_contract import validate_native_key_package

ROOT = Path(__file__).resolve().parents[1]


def inspect_native_package(package, keys):
    package = Path(package).resolve(strict=True)
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        for name in names:
            path = name.replace('\\', '/')
            if (path.startswith('/') or PureWindowsPath(path).drive or
                    '..' in PurePosixPath(path).parts):
                raise ValueError('Native package path escapes import directory')
        if len(names) != len(set(names)):
            raise ValueError('Ambiguous duplicate native package members')
        binary = archive.read('info.asm')
        skin = skin_class().FromString(binary)
        scripts={name:archive.read(name) for name in ('native_ui.lua','native_ui.json') if name in names}
        validate_native_key_package(skin, names, scripts)
        runtime_data=json.loads(scripts['native_ui.json']) if scripts.get('native_ui.json') else {}
        selected_runtimes=[runtime_data]
        if skin.meta.key.keys == 0:
            from converter.native_multikey import validate_package
            branches=validate_package(skin,runtime_data)
            if not any(branch['keys']==keys for branch in branches):
                raise ValueError('Native package has no source-defined branch for chart Key count')
            selected_runtimes=[branch['data'] for branch in branches if branch['keys']==keys]
        elif skin.meta.key.keys != keys:
            raise ValueError('Native package Key count does not match chart')
        images = [module.image for module in skin.modules if module.HasField('image')]
        images += [image for module in skin.modules for image in module.note.images]
        images += [image for module in skin.modules for image in module.images.items]
        missing = sorted({image.file for image in images if image.file and image.file not in names})
        for image in images:
            if image.filebase and image.frames:
                missing.extend(image.filebase+str(i)+'.png' for i in range(image.filestart,image.filestart+image.frames)
                               if image.filebase+str(i)+'.png' not in names)
        missing.extend(module.sound.file for module in skin.modules if module.HasField('sound') and module.sound.file not in names)
        missing.extend(module.number.file for module in skin.modules if module.HasField('number') and module.number.file not in names)
        if missing:
            raise ValueError('Native package image resources missing: ' + ', '.join(missing))
    # Deliberately do not inherit a receipt's claimed passes or assume that
    # the absence of an error proves rendered content / online acceptance.
    compiled = {'keys': keys, 'errors': 0, 'issues': [], 'ui_rounding_height': 600,
                'render_control': 'native_key', 'native_key_package': True,
                'script_present': bool(skin.meta.script), 'skin_script':skin.meta.script, 'archive': str(package),
                'controlled_scale3_binding':any(bool(runtime.get('scale3_recipes')) for runtime in selected_runtimes),
                'native_multikey_package':skin.meta.key.keys==0,
                'script_sha256':hashlib.sha256(scripts['native_ui.lua']).hexdigest() if skin.meta.script else None,
                'info_sha256': hashlib.sha256(binary).hexdigest(),
                'native_render_verified_for_this_package': False,
                'skin_upload_verified': False, 'normal_score_submission_verified': False}
    return binary, compiled


def prepare_native_package_input(incoming, output, keys):
    incoming, output = Path(incoming).resolve(strict=True), Path(output).resolve(strict=True)
    if not output.is_relative_to(ROOT/'output'):
        raise ValueError('Native probe metadata must remain in workspace output')
    if incoming.is_file():
        if incoming.suffix.lower() != '.msp':
            raise ValueError('Direct native validation requires an MSP')
        binary, compiled = inspect_native_package(incoming, keys)
        converted = output/'converted'
        converted.mkdir(exist_ok=False)
        (converted/'info.asm').write_bytes(binary)
        (converted/'conversion-report.json').write_text(json.dumps(compiled, indent=2), encoding='utf-8')
    else:
        if not incoming.is_relative_to(ROOT/'output'):
            raise ValueError('Prepared native fixture must remain in workspace output')
        receipt = json.loads((incoming/'conversion-report.json').read_text(encoding='utf-8'))
        package = Path(receipt['archive']).resolve(strict=True)
        if not package.is_relative_to(ROOT/'output'):
            raise ValueError('Prepared native MSP must remain in workspace output')
        binary, compiled = inspect_native_package(package, keys)
        if (incoming/'info.asm').read_bytes() != binary:
            raise ValueError('Native package and staged metadata differ')
        converted = incoming
    return converted, compiled
