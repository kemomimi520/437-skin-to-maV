import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import zipfile
from PIL import Image

from converter.common import skin_class
from converter.msz import convert_msz


class PublicSmokeTests(unittest.TestCase):
    def test_convert_msz_standalone_package(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            src = root / 'sample_skin.msz'
            img_buf = io.BytesIO()
            Image.new('RGBA', (64, 64), (80, 180, 255, 255)).save(img_buf, format='PNG')
            pause_buf = io.BytesIO()
            Image.new('RGBA', (100, 100), (0, 0, 0, 0)).save(pause_buf, format='PNG')
            wav = b'RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00'
            mui = '''@version 4.3.7
@best key.wav
note-[1-4]
 type=2
 anchor=4
 tex=note.png
 tex2=note.png
 tex3=note.png
 size=80,80
 pos=20%$20%,720
 pos2=20%$20%,120
'''
            with zipfile.ZipFile(src, 'w') as z:
                z.writestr('script-key-4K.mui', mui)
                z.writestr('note.png', img_buf.getvalue())
                z.writestr('ui-play-pause.png', pause_buf.getvalue())
                z.writestr('key.wav', wav)
            msp = convert_msz(src)
            self.assertTrue(msp.is_file())
            with zipfile.ZipFile(msp) as z:
                info = json.loads(z.read('info.json'))
                self.assertEqual(info['key'], 4)
                report = json.loads(z.read('conversion-report.json'))
                self.assertFalse(report['free'])
                self.assertEqual(report['render_backend'], 'native_key')
                skin = skin_class()()
                skin.ParseFromString(z.read('info.asm'))
                self.assertFalse(skin.meta.free)
                self.assertTrue(any(m.usage == 2 for m in skin.modules))
                self.assertTrue(any(m.type == 5006 for m in skin.modules))
                lua = z.read('native_ui.lua').decode('utf-8')
                self.assertIn('syncHitsoundVolume', lua)
                self.assertIn('hitsounds', lua)


if __name__ == '__main__':
    unittest.main()
