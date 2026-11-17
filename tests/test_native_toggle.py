"""437 toggle's dedicated scanner is not the enum atoi branch."""
import unittest

from converter.mui import native_integer,native_toggle


class NativeToggleTests(unittest.TestCase):
    def test_reverse_decimal_scan_adds_terms_but_does_not_or_or_evaluate(self):
        # Disassembly: 0x50b3d0..0x50b420. ParseFile toggle hash
        # 0x419a24ca6e0 calls this helper and stores int slot 0x104.
        for source,expected in ((None,0),('',0),('1+2',3),('2+1',3),('8+8',16),
                ('12',21),('1-2',21),('1.2',21),('1+2+4',7),('-3',3),('abc',0),
                ('4294967295',1632727628)):
            with self.subTest(source=source):self.assertEqual(native_toggle(source),expected)
        self.assertEqual(native_integer('1+2'),1)


if __name__=='__main__':unittest.main()
