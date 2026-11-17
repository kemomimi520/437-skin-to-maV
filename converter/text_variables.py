"""Unambiguous old Label callback tokens; nested placeholder syntax stays gated."""
import hashlib
import re

# Original 0x5a8e00 recognizes these six names and returns empty otherwise.
# maV Composer_GetTextVariableToken uses different artist/version spellings.
ALIASES={'title':'title','artist':'art','creator':'creator','version':'ver','player':'player','bpm':'bpm'}
SIMPLE=re.compile(r'(?<!\{)\{([A-Za-z][A-Za-z0-9_]*)\}(?!\})')


def translate(text, *, version_alias=None):
    emptied=set()
    def replace(match):
        token=match[1]
        if token=='version' and version_alias is not None:return '{'+version_alias+'}'
        if token in ALIASES:return '{'+ALIASES[token]+'}'
        emptied.add(token)
        return ''
    translated=SIMPLE.sub(replace,text)
    # Do not infer old escaping/nested or formatted-placeholder grammar.
    residual=SIMPLE.sub('',text)
    unresolved=set(re.findall(r'\{([^{}]+)\}',residual))
    return translated,emptied,unresolved


def translate_native_key(text):
    """Keep native metadata resolution, but reserve 437's raw version value."""
    count=sum(match[1]=='version' for match in SIMPLE.finditer(text))
    if not count:
        return (*translate(text),None)
    token='__ma_source_version_'+hashlib.sha256(text.encode('utf8')).hexdigest()[:24]
    translated,emptied,unresolved=translate(text,version_alias=token)
    return translated,emptied,unresolved,{'version_marker':'{'+token+'}', 'version_count':count}
