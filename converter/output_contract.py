"""Non-negotiable delivery boundary for converted Key skins.

The retained compiler is a Free renderer, even when a Key judge is attached.
It cannot satisfy the user's native Key / normal ranked-play requirement.
Do not turn its Free flag off or alter score eligibility to bypass this gate.
"""


class NativeKeyBackendUnavailable(ValueError):
    pass


def require_native_key_backend():
    """Fail before extraction, font work, output writes, or MSP replacement.

    Replace this boundary with a real native Key compiler when that backend
    exists. There is intentionally no draft/research/CLI bypass switch.
    """
    raise NativeKeyBackendUnavailable(
        '原 Free 转换后端已停用：它不符合原生 Key、皮肤上传及正常成绩上传要求。'
        '符合要求的新后端尚未完成，本次未生成或替换 MSP。'
    )


def validate_native_key_package(skin, resource_names, script_sources=None):
    """Structural rejection only; never a claim of server acceptance.

    Native notes belong to the game's renderer. Only byte-reconstructible
    ordinary UI / bounded visual-state research templates are permitted;
    the retained Free program is never permitted, even if relabelled.
    The MSZ frontend separately blocks unverified visual-state candidates.
    """
    problems = []
    if skin.meta.free:
        problems.append('Free 模式')
    if skin.meta.mode != 0 or not skin.meta.HasField('key'):
        problems.append('不是原生 Key 皮肤')
    elif not 0 <= skin.meta.key.keys <= 64:
        problems.append('缺少有效 Key 键数')
    resource_names=tuple(resource_names)
    approved=set()
    if skin.meta.script:
        if skin.meta.script=='native_ui.lua' and script_sources and 'native_ui.json' in script_sources:
            from .native_key import validate_basic_script
            validate_basic_script(script_sources.get('native_ui.lua',b''),script_sources['native_ui.json'])
            approved.add('native_ui.lua')
        else:problems.append('包含尚未审核的运行脚本')
    if any(str(name).casefold().endswith(('.lua', '.luac')) and name not in approved for name in resource_names):
        problems.append('包含未审核的脚本资源')
    if skin.meta.HasField('key') and skin.meta.key.keys == 0:
        # Native SupportPlayMode accepts zero as wildcard. Require the fully
        # reconstructed manifest and every gated native tap/hold branch;
        # relabelling a single-Key or Free renderer is still rejected.
        if skin.meta.script!='native_ui.lua' or not script_sources or 'native_ui.json' not in script_sources:
            problems.append('通配 Key 元信息缺少原生多入口分支')
        else:
            import json
            from .native_multikey import validate_package
            validate_package(skin,json.loads(script_sources['native_ui.json']))
    # Native CustomImage/Text/Number/etc. (5000+) are legal ordinary UI.
    # Requiring native tap AND hold modules prevents merely relabelling the
    # Free renderer, which disabled the built-in notes and drew its own UI.
    types = {module.type for module in skin.modules if module.usage == 1}
    if not types.intersection((1, 2, 7)) or not types.intersection((3, 4, 5, 6)):
        problems.append('缺少原生 Key 单键或长条模块')
    if problems:
        raise ValueError('禁止导出不符合原生 Key 要求的皮肤：' + '；'.join(problems))
