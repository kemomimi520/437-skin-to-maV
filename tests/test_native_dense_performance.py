"""Dense MC evidence remains a failure record until the real gaps are fixed."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]


class NativeDensePerformanceTests(unittest.TestCase):
    def test_dense_pair_does_not_turn_average_fps_into_an_acceptance_claim(self):
        data=json.loads((ROOT/'tests/data/native-dense-performance.json').read_text())
        converted=data['runs']['r60-native-dense-kingfish-play-r2']
        native=data['runs']['r60-native-dense-circle-play-r1']
        self.assertEqual(data['notes'],1759);self.assertEqual(data['holds'],725)
        self.assertGreater(converted['above_8_33_ms'],0)
        self.assertGreater(converted['max_ms'],native['max_ms'])
        self.assertNotEqual(converted['final_accuracy'],100.0)
        self.assertNotEqual(converted['window_focus_at_play'],native['window_focus_at_play'])
        self.assertFalse(data['full_acceptance'])

    def test_recorded_spikes_are_real_chart_times_and_not_synthetic_input_errors(self):
        data=json.loads((ROOT/'tests/data/native-dense-performance.json').read_text())
        spikes=data['runs']['r60-native-dense-kingfish-play-r2']['spikes']
        self.assertTrue(spikes)
        self.assertTrue(all(s['chart_time']>=0 and s['ms']>=8.33 for s in spikes))
        self.assertEqual(data['runs']['r60-native-dense-kingfish-play-r2']['native_skin_lua_errors'],[])


if __name__=='__main__':unittest.main()
