"""Read machine-specific native installations without versioning private paths."""
import json
import os
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def installation(kind):
    if kind not in ('legacy','mav'):raise ValueError('Unknown native installation')
    name={'legacy':'MA_LEGACY_INSTALL','mav':'MAV_INSTALL'}[kind]
    value=os.environ.get(name)
    config=ROOT/'project.local.json'
    if not value and config.exists():value=json.loads(config.read_text(encoding='utf-8')).get(kind)
    if not value:raise ValueError(f'Set {name} or the {kind!r} path in ignored project.local.json')
    return Path(value).resolve(strict=True)
