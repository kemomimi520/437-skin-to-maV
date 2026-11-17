"""Source quad readback distinguishes pixel sampling from geometric cuts."""
import json
from pathlib import Path
import unittest

from converter.legacy_sprite_uv import sprite_uv

ROOT=Path(__file__).resolve().parents[1]
PROOF=json.loads((ROOT/'tests/data/legacy-scale3-texcoords.json').read_text())


class LegacySpriteUVTests(unittest.TestCase):
    def test_original_quad_uvs_match_installed_factory_readback(self):
        for row in PROOF['source_parts']:
            self.assertTrue(row['texture_rect_fixed'])
            actual=sprite_uv(row['frame_rect'],row['texture_size'],rotated=row['texture_rotated'])
            for got,wanted in zip(actual,row['texture_uv']):
                for a,b in zip(got,wanted):self.assertAlmostEqual(a,b,delta=1e-7)

    def test_one_texel_strip_has_constant_uv_without_changing_its_geometry(self):
        row=next(x for x in PROOF['source_parts'] if x['case']=='note-1' and x['frame_rect'][3]==1)
        fixed=sprite_uv(row['frame_rect'],row['texture_size'])
        ordinary=sprite_uv(row['frame_rect'],row['texture_size'],rect_fixed=False)
        self.assertEqual(len({p[1] for p in fixed}),1)
        self.assertEqual(len({p[1] for p in ordinary}),2)
        self.assertEqual(row['frame_rect'][3],1)

    def test_empty_cap_uv_is_reversed_but_not_a_drawable_positive_cap(self):
        row=next(x for x in PROOF['source_parts'] if x['frame_rect'][3]==0)
        uv=sprite_uv(row['frame_rect'],row['texture_size'])
        self.assertGreater(uv[0][1],uv[1][1])

    def test_current_native_rectangle_edge_sampling_is_an_explicit_known_mismatch(self):
        native=PROOF['native_before_fix']
        self.assertEqual(native['scope'],'recorded original borrowed renderer, before source sampling fix')
        self.assertEqual(len({p[1] for p in native['sprite_uv']}),2)
        self.assertEqual(native['sprite_rect'][1],1)
        self.assertFalse(PROOF['native_sampling_parity_verified'])


if __name__=='__main__':unittest.main()
