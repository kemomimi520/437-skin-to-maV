"""Touch NumericExpression regression using original-parser readback values."""
import tempfile
import unittest
from pathlib import Path
from converter.mui import parse,touch_coordinates


class TouchNumericContextTests(unittest.TestCase):
    def test_touch_uses_assignment_time_defines_and_unit_not_python_arithmetic(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'script-key-4K.mui').write_text('''@unit 1080
@define width 140
@define interval 14
touch
 type=1
 rect=50%-{width}-{width}-{interval}-{interval},0,{width}+{interval},100%
@define width 999
@unit 720
''',encoding='utf-8')
            doc=parse(root,4,1024/600,logical_height=600)
            values=touch_coordinates(doc,doc.elements['touch'],'rect')
            self.assertAlmostEqual(values[0][0]*1024+values[0][1]*600/720,340.8888854980469,places=4)
            self.assertAlmostEqual(values[2][0]*1024+values[2][1]*600/720,85.5555648803711,places=4)
            self.assertEqual(values[1],[0,0])
            self.assertEqual(values[3],[1,0])

    def test_polygon_operands_keep_percent_pixel_and_variable_modes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'script-key-4K.mui').write_text('''@unit 1080
@define edge 90
touch
 type=3
 array=10%,{edge},20%,30px,40%,50%
''',encoding='utf-8')
            doc=parse(root,4,16/9,logical_height=600)
            values=touch_coordinates(doc,doc.elements['touch'],'array')
            expected=[[.1,0],[0,60],[.2,0],[0,36],[.4,0],[.5,0]]
            for actual,wanted in zip(values,expected):
                for value,reference in zip(actual,wanted):
                    self.assertAlmostEqual(value,reference,places=4)
