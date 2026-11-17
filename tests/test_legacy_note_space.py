"""Different 437 constants and the real source viewport constrain the plan."""
import json
from pathlib import Path
import struct
import unittest

from converter.legacy_note_space import (MOVE_WINDOW_NUMERATOR,MUI_SIZE_DIVISOR,
    RETIRE_DISPLAY_DISTANCE,LEGACY_KEYUIS_BASE_SCALE,display_window,keyuis_units,
    admission_to_motion_ratio)
from converter.native_scale3_layout import range_layout

ROOT=Path(__file__).resolve().parents[1]
PROOF=json.loads((ROOT/'tests/data/legacy-keyuis-units.json').read_text())
NATIVE=json.loads((ROOT/'tests/data/native-key-offset-units.json').read_text())


class LegacyNoteSpaceTests(unittest.TestCase):
    def test_distinct_constants_match_original_binary_bytes(self):
        expected={'move_window':MOVE_WINDOW_NUMERATOR,'mui_size_divisor':MUI_SIZE_DIVISOR,
                  'retirement_distance':RETIRE_DISPLAY_DISTANCE}
        for name,value in expected.items():
            row=PROOF['legacy_constants'][name]
            self.assertEqual(struct.unpack('<'+row['format'],bytes.fromhex(row['hex']))[0],value)
            self.assertEqual(row['value'],value)
        self.assertNotEqual(MOVE_WINDOW_NUMERATOR,MUI_SIZE_DIVISOR)
        self.assertNotEqual(MOVE_WINDOW_NUMERATOR,RETIRE_DISPLAY_DISTANCE)

    def test_motion_and_admission_speed_terms_cancel_without_erasing_632_point_5_over_720(self):
        ratio=admission_to_motion_ratio(600,560*600/720)
        for speed in (.25,1,3,9.5):
            for scale in (1,.8333333134651184,.6666666865348816,1.25):
                terms=keyuis_units(600,speed,scale)
                actual=terms['height_per_display_unit']*terms['display_window']/(560*600/720)
                self.assertAlmostEqual(actual,ratio,delta=2e-7)
        self.assertAlmostEqual(ratio,632.5/560,delta=1e-7)
        self.assertNotAlmostEqual(ratio,720/560,places=3)

    def test_source_viewport_and_parser_scale_share_the_visible_height(self):
        for height in (480,600,720,1080):
            terms=keyuis_units(height,632.5,1)
            self.assertEqual(terms['display_window'],1)
            self.assertAlmostEqual(terms['mui_unit_scale'],height/720,delta=1e-7)
            self.assertAlmostEqual(admission_to_motion_ratio(height,height*560/720),632.5/560,delta=1e-7)

    def test_default_legacy_scale_controls_prefetch_reach_and_matches_old_capture(self):
        self.assertAlmostEqual(LEGACY_KEYUIS_BASE_SCALE,.7)
        self.assertAlmostEqual(display_window(1,LEGACY_KEYUIS_BASE_SCALE),903.571443,delta=1e-5)
        self.assertAlmostEqual(keyuis_units(600,1,LEGACY_KEYUIS_BASE_SCALE)['display_window'],
                               display_window(1,LEGACY_KEYUIS_BASE_SCALE),delta=0)
        self.assertEqual(display_window(2,LEGACY_KEYUIS_BASE_SCALE),
                         display_window(1,LEGACY_KEYUIS_BASE_SCALE)/2)

    def test_plan_requires_unclipped_motion_for_both_original_sliced_factories(self):
        for factory in ('scale3','scale3part3'):
            plan=range_layout(factory,(20,24),(90,60),head_size=(90,60),tail_size=(90,60),
                logical_height=600,field_height_720=720,travel_720=560,units_per_720=1)
            self.assertTrue(plan['requires_unclipped_motion_range'])
            self.assertFalse(plan['actual_ln_lifetime_verified'])
        self.assertEqual(PROOF['native_distance_clamp']['instruction'],'minss xmm1, dword ptr [rbx + 0x78]')

    def test_invalid_game_speed_or_viewport_is_rejected_before_division(self):
        for values in ((0,1,1),(600,0,1),(600,1,-1),(600,float('nan'),1)):
            with self.assertRaises(ValueError):keyuis_units(*values)

    def test_actual_native_call_operands_write_offsets_after_both_motion_branches(self):
        targets={}
        for row in NATIVE['instructions']:
            code=bytes.fromhex(row['hex'])
            self.assertIn(code[0],(0xe8,0xe9))
            target=int(row['va'],16)+5+int.from_bytes(code[1:],'little',signed=True)
            self.assertEqual(target,int(row['target'],16))
            targets[row['role']]=target
        self.assertEqual(targets['ordinary_range_write'],targets['dynamic_range_write'])
        self.assertEqual(targets['ordinary_range_write'],0x1814f85c0)
        self.assertEqual(targets['range_write_offset_min'],0x181fd4830)
        self.assertEqual(targets['range_write_offset_max'],0x181fd45e0)


if __name__=='__main__':unittest.main()
