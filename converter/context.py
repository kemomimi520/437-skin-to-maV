"""Source-engine display facts proved by the owned native player capture."""
import hashlib
import json
from pathlib import Path

LEGACY_EXE_SHA256='d0cf9ecb493f3fdbd1e3ce48cbfad06ef816d19931ab0c51d9e9655f5eb63ce3'

# Actual Director projection, independently repeated by the native Label and
# MusicBarSprite captures. This is limited to the proved preset/aspect, never
# extrapolated to another old viewport or executable.
UI_PROJECTION_1024_600=[1.0148736238479614,0,0,0,0,1.732050895690918,0,0,
    0,0,-1.00687575340271,-1,-519.6152954101562,-519.6152954101562,
    502.2600402832031,518.7619018554688]


def native_ui_projection(source,height,ratio):
    context=ui_rounding_context(source)
    if context['verified_source_context'] and height==600 and abs(ratio-1024/600)<1e-10:
        return {'matrix':UI_PROJECTION_1024_600,'logical_width':1024,'logical_height':600,
                'executable_sha256':LEGACY_EXE_SHA256}
    return None

def ui_rounding_context(source:Path,explicit=None):
    if explicit is not None:
        if not 240<=explicit<=4320:raise ValueError('Legacy UI rounding height must be between 240 and 4320')
        return {'height':explicit,'method':'explicit','verified_source_context':False}
    for root in list(source.resolve().parents)[:4]:
        config,exe=root/'config.json',root/'malody.exe'
        if not config.is_file() or not exe.is_file():continue
        try:
            window=json.loads(config.read_text(encoding='utf-8-sig')).get('window')
            if window!=5:continue
            digest=hashlib.sha256(exe.read_bytes()).hexdigest()
            if digest==LEGACY_EXE_SHA256:
                # Actual Director::getWinSize = 1024 x 600, parser scale
                # 0.833333313, at window preset 5 in this exact executable.
                return {'height':600,'method':'verified-executable-window-preset',
                        'verified_source_context':True,'window_preset':5,'executable_sha256':digest}
        except (OSError,ValueError):continue
    return {'height':720,'method':'canonical-fallback','verified_source_context':False}
