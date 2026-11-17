"""Metadata callback values from the actual old resolver."""
import json
import unittest
from converter.compiler import ROOT
from converter.text_variables import translate,translate_native_key,ALIASES


class TextVariableTests(unittest.TestCase):
    def test_simple_callback_names_and_empty_fallback(self):
        evidence=json.loads((ROOT/'tests/data/legacy-metadata-token-values.json').read_text('utf8'))
        for row in evidence['rows']:
            token=row['token']
            text,empty,unresolved=translate('{'+token+'}')
            with self.subTest(token=token,bpm=row['bpm_input']):
                self.assertFalse(unresolved)
                if row['value']=='':
                    self.assertEqual(text,'')
                    self.assertEqual(empty,{token})
                else:
                    self.assertEqual(text,'{'+ALIASES[token]+'}')
                    self.assertFalse(empty)

    def test_keeps_unknown_nested_grammar_explicit(self):
        for text in ('{{level}}',r'{{title}}','{title:format}','{123}'):
            result,empty,unresolved=translate(text)
            self.assertEqual(result,text)
            self.assertFalse(empty)
            self.assertTrue(unresolved)

    def test_literals_survive_empty_callbacks(self):
        self.assertEqual(translate('v {version} {level} / {unknown}.'),
            ('v {ver}  / .',{'level','unknown'},set()))

    def test_native_key_reserves_only_original_version_tokens(self):
        text='前 {version}/{version}: {title} {artist} {bpm} {player} {unknown}'
        translated,empty,unresolved,version=translate_native_key(text)
        marker=version['version_marker']
        self.assertEqual(version['version_count'],2)
        self.assertEqual(translated,'前 '+marker+'/'+marker+': {title} {art} {bpm} {player} ')
        self.assertEqual(empty,{'unknown'});self.assertFalse(unresolved)
        self.assertEqual(translate('{version}')[0],'{ver}')
        plain=translate_native_key('literal {title} {{version}}')
        self.assertIsNone(plain[3]);self.assertTrue(plain[2])


if __name__=='__main__':unittest.main()
