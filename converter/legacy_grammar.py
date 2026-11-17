"""Recognition rules recovered from 4.3.7 ParseFile, not a style validator.

The original property regex has one optional digit. Only the indexed families
add that digit minus one to the stored ID; scalar families ignore it. Unknown
hashes never enter the attribute map. Factory support is a separate question.
"""
import re

PROPERTY_PATTERN = re.compile(r'(\b[^=\d]+)(\d?)=(.+)', re.ASCII)
DIRECTIVE_PATTERN = re.compile(r'@(\S+)\s(.+)', re.ASCII)
INDEXED_ATTRIBUTES = frozenset('tex pos size zindex interval type frame part rect anchor array toggle'.split())
FIXED_ATTRIBUTES = frozenset('fsize count flip color blend rotate text fix etag opacity padding show align file lang tag skew react parent'.split())
EVENTS = frozenset('motion hover leave press release action'.split())


def attribute_name(base, suffix):
    """Return the native slot spelling, or None for an ignored property hash."""
    if base in INDEXED_ATTRIBUTES:
        return base if suffix in ('', '1') else base + suffix
    if base in FIXED_ATTRIBUTES:
        return base
    if base in EVENTS:
        return base + suffix if base == 'action' and suffix not in ('', '1') else base
    return None
