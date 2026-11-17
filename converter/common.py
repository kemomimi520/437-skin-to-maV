"""Shared paths, protobuf schema loader, Lua serialization, and font bank lookup."""
from pathlib import Path
from google.protobuf import descriptor_pool, message_factory

from .mui import is_key_scene_definition, is_scene_custom, native_integer

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(__file__).resolve().parent / 'data'


def skin_class():
    descriptor = DATA / 'skin.descriptor.pb'
    if not descriptor.exists():
        descriptor = ROOT / 'analysis/malody-v/recovered_skin.descriptor.pb'
    pool = descriptor_pool.DescriptorPool()
    pool.AddSerializedFile(descriptor.read_bytes())
    return message_factory.GetMessageClass(pool.FindMessageTypeByName('recovered.SkinFile'))


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'
    if isinstance(value, list):
        return '{' + ','.join(lua(x) for x in value) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'


def uses_scene_text(item):
    return (
        is_key_scene_definition(item)
        and 'text' in item.attrs
        and not item.name.startswith('note-')
        and (not is_scene_custom(item) or native_integer(item.attrs.get('type')) == 1)
    )


def font_bank():
    for path in (DATA / 'native-font-bank', ROOT / 'analysis/malody-4.3.7/native-font-cache/sourcehan24-r2'):
        if (path / 'font-bank.json').is_file():
            return path
    raise FileNotFoundError('测试版字体资源缺失，请使用完整便携目录')


def skin_info_payload(meta, key_count):
    """Build Malody V's SkinJson info.json dictionary from SkinMeta."""
    return {
        'title': meta.title,
        'desc': meta.desc,
        'cover': meta.cover,
        'creator': meta.creator,
        'version': meta.minver,
        'mode': meta.mode,
        'key': key_count,
        'feature': meta.feature,
        'skinid': meta.skinid,
        'updatedTime': meta.updated,
        'special': None,
    }
