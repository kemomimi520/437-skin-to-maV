"""Non-executing MUI parser, retaining expressions and source locations."""
from __future__ import annotations
import ast
import copy
from dataclasses import dataclass, field
import math
from pathlib import Path
import re
import struct
from .native_numeric import expression, float32
from .legacy_grammar import PROPERTY_PATTERN, DIRECTIVE_PATTERN, attribute_name


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    source: str = ""


@dataclass
class Element:
    name: str
    attrs: dict[str, str] = field(default_factory=dict)
    origins: dict[str, str] = field(default_factory=dict)
    indices: dict[str, int] = field(default_factory=dict)
    # ParseFile resolves references immediately. Retain the expression program
    # at that assignment, so reopening a referenced block cannot move old users.
    pair_programs: dict = field(default_factory=dict)
    group: str = '__def_group'
    motion_bindings: dict = field(default_factory=dict)
    numeric_contexts: dict = field(default_factory=dict)


@dataclass
class Document:
    root: Path
    keys: int
    elements: dict[str, Element] = field(default_factory=dict)
    animations: dict[str, list[dict]] = field(default_factory=dict)
    directives: dict[str, str] = field(default_factory=dict)
    packs: list[str] = field(default_factory=list)
    variables: dict[str, str] = field(default_factory=dict)
    issues: list[Issue] = field(default_factory=list)
    files: list[str] = field(default_factory=list)
    directive_origins: dict[str,str] = field(default_factory=dict)
    unit: int = 720
    numeric_variables: dict[str,float] = field(default_factory=dict)
    features: set[str] = field(default_factory=set)
    aspect_thresholds: set[tuple[bool,float]] = field(default_factory=set)


def native_dimension(doc, element, attr, default=0):
    """NumericExpression's stored native float; fsize uses the height axis."""
    context=element.numeric_contexts.get(attr,{})
    height=getattr(doc,'ui_rounding_height',720)
    return expression(str(element.attrs.get(attr,default)),height,
        float32(height/context.get('unit',720)),float32(height*getattr(doc,'ratio',16/9)),context.get('variables'))


def is_scene_custom(element: Element) -> bool:
    """KeyUIS calls GetCustomElements with an empty filter (0x511600).

    That selects exactly __def_group, irrespective of the element's name.
    Named groups are definitions for other consumers, not global scene UI.
    """
    return element.group == '__def_group'


def is_key_scene_definition(element: Element) -> bool:
    """Names requested explicitly by KeyUIS, or its default custom vector.

    Lane bounds and individual factory support are checked by consumers.
    Arbitrary parsed helpers/named groups do not become visible scene nodes.
    """
    return is_scene_custom(element) or bool(re.fullmatch(r'(key|note|hit|press|judge|hp)-\d+', element.name)) or element.name in {
        'score-acc','score-combo','score-maxcombo','score-score','score-hp',
        'hit-fast','hit-slow','bar','touch','progress','musicbar','pause'}


def split_values(value: str, delimiter=",") -> list[str]:
    result, start, depth = [], 0, 0
    for i, char in enumerate(value):
        if char in "([{": depth += 1
        if char in ")]}": depth -= 1
        if char == delimiter and depth == 0:
            result.append(value[start:i].strip()); start = i + 1
    result.append(value[start:].strip())
    return result


def native_integer(value,default=0):
    """ParseFile's atoi branch; enum fields are not arithmetic expressions."""
    if value is None:return default
    match=re.match(r'\s*([+-]?\d+)',str(value))
    result=int(match[1]) if match else 0
    if not -(2**31)<=result<2**31:raise ValueError('Native integer exceeds the supported signed int32 range')
    return result


def native_toggle(value):
    """ParseFile toggle calls 0x50b3d0, not atoi or arithmetic evaluation.

    Scan right-to-left, accumulating decimal digits in scan order; '+' adds
    and clears a term, other characters do nothing. x86 int32 wraps. Thus
    '1+2' is 3, '8+8' is 16 (not OR), and '12' is surprisingly 21.
    """
    result=term=0
    text='' if value is None else str(value)
    for i in range(len(text)-1,-1,-1):
        char=text[i]
        if '0'<=char<='9':term=(term*10+ord(char)-48)&0xffffffff
        if i==0 or char=='+':result=(result+term)&0xffffffff;term=0
    return result if result<0x80000000 else result-0x100000000


def native_float(value,default=0):
    """atof prefix followed by the original single-precision store."""
    if value is None:return default
    match=re.match(r'\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)',str(value))
    result=float(match[1]) if match else 0.
    if not math.isfinite(result):raise ValueError('Native scalar exceeds finite float range')
    try:return struct.unpack('<f',struct.pack('<f',result))[0]
    except OverflowError as error:raise ValueError('Native scalar exceeds finite float range') from error


def native_scalar(element,attr,default=0):
    raw=element.attrs.get(attr)
    if raw is None:return default
    index=element.indices.get(attr,0)
    if attr=='zindex':
        first,separator,step=raw.partition('$')
        return native_integer(first)+(native_integer(step)*index if separator else 0)
    if attr=='rotate':
        first,separator,step=raw.partition('$');value=native_float(first)
        if separator:
            for _ in range(index):value=native_float(math.trunc(value)+native_float(step))
        return math.trunc(value) # ApplyAttributes passes int-cast rotation.
    if attr=='opacity':
        # 0x5106f1 stores the atof*2.55 result to float before cvttss2si;
        # ApplyAttributes then passes its low byte. Range stepping touches the
        # unused float slot, not this byte-bearing integer slot.
        first=raw.split('$',1)[0]
        match=re.match(r'\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)',first)
        value=float(match[1]) if match else 0.
        byte=math.trunc(native_float(value*2.55))&255
        return byte/2.55
    return native_float(raw,default)


def expand_selector(value: str) -> list[str]:
    match = re.fullmatch(r"([^\[\]]+-)\[(.+)\]", value)
    if not match: return [value]
    numbers = []
    for part in match[2].split(","):
        if re.fullmatch(r"\d+-\d+", part.strip()):
            first, last = map(int, part.split("-"))
            if abs(last-first) > 256: raise ValueError("Selector range exceeds 256")
            numbers.extend(range(first, last+1))
        elif part.strip().isdigit(): numbers.append(int(part))
        else: raise ValueError(f"Invalid selector {value}")
    return [match[1] + str(number) for number in numbers]


def linear(value: str, index: int = 0) -> tuple[float, float]:
    """Return (axis fraction, design units); no eval or arbitrary function calls."""
    value = value.strip()
    if "$" in value:
        start, step = value.split("$", 1)
        a, b = linear(start); c, d = linear(step)
        return a + index*c, b + index*d
    value = re.sub(r"(?<=\d)x(?=[\d.(])", "*", value)
    value = re.sub(r"(\d+(?:\.\d*)?|\.\d+)%", r"P(\1)", value)
    value = re.sub(r"(?<=\d)px\b", "", value)
    def walk(node):
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            return 0.0, float(node.value)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "P" and len(node.args) == 1 and not node.keywords:
            p, u = walk(node.args[0])
            if p: raise ValueError("Nested percentage")
            return u/100, 0.0
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            p, u = walk(node.operand); s = -1 if isinstance(node.op, ast.USub) else 1
            return p*s, u*s
        if isinstance(node, ast.BinOp):
            a, b = walk(node.left); c, d = walk(node.right)
            if isinstance(node.op, ast.Add): return a+c, b+d
            if isinstance(node.op, ast.Sub): return a-c, b-d
            if isinstance(node.op, ast.Mult) and not (a and c): return a*d+c*b, b*d
            if isinstance(node.op, ast.Div) and not c and d: return a/d, b/d
        raise ValueError(f"Unsupported numeric expression: {value}")
    try: result = walk(ast.parse(value, mode="eval").body)
    except SyntaxError as error: raise ValueError(f"Invalid numeric expression: {value}") from error
    if not all(math.isfinite(x) for x in result): raise ValueError("Non-finite expression")
    return result


def parse(root: Path, keys: int, ratio=16/9, *, logical_height=720, platform='windows', phone_predicate: bool | None = None) -> Document:
    if platform not in ('windows','android'):
        raise ValueError('Unsupported source platform: '+str(platform))
    root = root.resolve()
    doc = Document(root, keys)
    doc.ratio=ratio
    doc.ui_rounding_height=logical_height
    active = []
    def numeric_context(value,source):
        names=set(re.findall(r'\{([^{}]+)\}',value))
        variables={name:doc.numeric_variables[name] for name in names if name in doc.numeric_variables}
        for name in names-doc.numeric_variables.keys():
            doc.issues.append(Issue('warning','native-undefined-variable',f'Undefined numeric variable {{{name}}} evaluates to zero in native 0x50b789..0x50b79d',source))
        if doc.unit==720 and not names:return {}
        return {'unit':doc.unit,'variables':variables}
    def condition(value,source):
        # Native 0x50d3e0: exact, case-sensitive token hashes. Do not invent aliases.
        if value in ('windows','android','ios','touch','mac'):
            return value==platform or value=='touch' and platform=='android'
        if value in ('phone','phonex'):
            if platform=='windows':return False
            if phone_predicate is None:
                raise ValueError('Android phone/phonex condition requires the original device predicate; cannot discard its branch')
            if value=='phone':return bool(phone_predicate)
            threshold=float32(1.94)
            doc.aspect_thresholds.add((False,float(threshold)))
            aspect=float32(float32(logical_height*ratio)/float32(logical_height))
            return aspect > threshold
        # Native Condition falls through to atof, including numeric prefixes.
        # An invalid/zero threshold logs a diagnostic and returns false.
        threshold=native_float(value[1:].strip() if value.startswith(('<','>')) else value)
        if threshold>0:
            is_less=value.startswith('<')
            doc.aspect_thresholds.add((is_less,float(threshold)))
            # Assembly 0x50d568..0x50d573: '<' selects <=, the other forms select >.
            aspect=float32(float32(logical_height*ratio)/float32(logical_height))
            return aspect <= threshold if is_less else aspect > threshold
        doc.issues.append(Issue('warning','native-false-condition',f'Original Condition logs an invalid threshold and returns false: {value}',source))
        return False
    def animation_record(line,source):
        params={};has_name=False
        for part in split_values(line):
            if '=' in part:
                key,value=part.split('=',1);key=key.strip()
                if key in ('name','n'):
                    if has_name:params['_duplicate_name']=True
                    has_name=True
                params[key]=value.strip()
        params['source']=source
        context=numeric_context(line,source)
        if context:params['_numeric']=context
        return params
    def motion_binding(value,source):
        if value.startswith(':'):
            return {'raw':value,'name':None,'records':[animation_record(value[1:],source)],'delay':0}
        pieces=value.split(None,1);name=pieces[0] if pieces else ''
        if name not in doc.animations:
            # A missing bare name creates an empty native event collection;
            # defining that name later does not populate this snapshot.
            if not re.fullmatch(r'[\w-]+',name) or (root/name).is_file():
                raise ValueError(f'External native motion resource is not implemented: {name}')
            doc.issues.append(Issue('warning','native-empty-motion',f'Native motion is not defined at assignment: {name}; preserve its empty collection',source))
            return {'raw':value,'name':name,'records':[],'delay':0}
        delay=0
        if len(pieces)==2:
            for option in split_values(pieces[1]):
                key,separator,amount=option.partition('=')
                if separator and key.strip()=='delay':delay+=native_integer(amount)
        return {'raw':value,'name':name,'records':copy.deepcopy(doc.animations[name]),'delay':delay}
    def read(path,origin=''):
        path = path.resolve()
        if not path.is_relative_to(root): raise ValueError("Include escapes skin root")
        if path in active: raise ValueError("Cyclic include")
        if len(active) >= 32: raise ValueError("Excessive include depth")
        try:data = path.read_bytes()
        except FileNotFoundError:
            # A missing nested include returns false to its caller. ParseFile
            # does not turn that return value into an exception or stop itself.
            if active:
                doc.issues.append(Issue('warning','native-missing-include',f'Original nested include returned false: {path.relative_to(root)}',origin or str(active[-1].relative_to(root))))
                return
            raise
        try: text = data.decode("utf-8-sig")
        except UnicodeDecodeError: text = data.decode("gb18030")
        active.append(path); doc.files.append(str(path.relative_to(root)))
        selected, animation = [], None
        skipping=False
        group=''
        for number, original in enumerate(text.splitlines(), 1):
            line = original.rstrip(' \t\r\n')
            source = f"{path.relative_to(root)}:{number}"
            if not line or line.startswith('#'): continue
            # Native 0x50d5c0 uses one skip flag, not a nested preprocessor.
            # The first @endif ends a false branch, even after another @if.
            if skipping:
                if line.startswith('@endif'):skipping=False
                continue
            # First-byte dispatch precedes regex_search in the real parser.
            # Text containing @ and indented directives are not commands.
            directive = DIRECTIVE_PATTERN.search(line) if line.startswith('@') else None
            try:
                if directive:
                    name, value = directive[1], directive[2]
                    if name == "if":
                        skipping=not condition(value,source);continue
                    if name == "endif":
                        continue
                    if name == 'version':
                        # 0x50e572..0x50e68b: regex_search accepts a numeric
                        # substring, each component is stored through a byte.
                        # An unrecognized version ends THIS file successfully;
                        # an included caller can still continue after it.
                        version=re.search(r'(\d+)\.(\d+)\.(\d+)',value,re.ASCII)
                        if version is None:
                            doc.issues.append(Issue('warning','native-version-file-end',f'Original parser ends this file after an unrecognized version: {value}',source))
                            break
                        numbers=tuple(int(part)&255 for part in version.groups())
                        if numbers>(4,3,7):
                            doc.issues.append(Issue('error','native-version-upgrade',f'Original 4.3.7 requires an upgrade for version {value}',source))
                            break
                        doc.directives[name]=value;doc.directive_origins[name]=source
                        continue
                    if name == "define":
                        parts = value.split(None, 1)
                        if len(parts) != 2:
                            doc.issues.append(Issue('warning','native-ignored-define','Original parser ignores malformed @define',source));continue
                        doc.variables[parts[0]] = parts[1]
                        doc.numeric_variables[parts[0]]=expression(parts[1],logical_height,
                            float32(logical_height/doc.unit),float32(logical_height*ratio),doc.numeric_variables)
                        continue
                    if name=='unit':
                        unit=native_integer(value)
                        if unit>0:doc.unit=unit
                    if name=='apply' and value in ('3d','soundend'):doc.features.add(value)
                    if name in ('include','includex'):
                        parts = value.split(None, 1)
                        if len(parts) == 2:
                            if not condition(parts[0],source): continue
                            value = parts[1]
                        read(root / value.strip('"'),source)
                        if name=='includex':break
                        continue
                    if name=='del':
                        doc.elements.pop(value,None);continue
                    if name == "texpack": doc.packs.append(value)
                    elif name in ("best", "cool", "good", "miss", "apply", "unit", "angle"):
                        doc.directives[name] = value
                        doc.directive_origins[name] = source
                    else: doc.issues.append(Issue('warning','native-ignored-directive',f'Original parser logs and ignores unknown directive @{name}',source))
                    continue
                if line.startswith('@'):
                    if line=='@endif':continue
                    doc.issues.append(Issue('warning','native-ignored-directive','Original parser logs and ignores malformed directive',source));continue
                # Only NumericExpression consumes @define values. atoi/atof
                # properties and runtime text placeholders keep their raw text.
                if not line.startswith((' ','\t')):
                    if line.startswith('+'):
                        group=line[1:].strip();continue
                    if line.startswith(':'):
                        animation=expand_selector(line[1:].strip())
                        for name in animation:doc.animations.setdefault(name,[])
                        selected=[];continue
                    selected = expand_selector(line); animation = None
                    for name in selected: doc.elements.setdefault(name, Element(name,group=group or ('__def_group' if name.startswith('_') else '')))
                    continue
                if animation is not None:
                    params=animation_record(line,source)
                    for name in animation:doc.animations[name].append(dict(params))
                    continue
                if not selected:continue # No selected element: the original skips the line.
                match=PROPERTY_PATTERN.search(line)
                name=attribute_name(match[1],match[2]) if match else None
                if name is None:
                    doc.issues.append(Issue('warning','native-ignored-attribute',f'Original parser does not store this property: {line.lstrip()}',source));continue
                value=match[3]
                for index, selector in enumerate(selected):
                    item = doc.elements[selector]
                    context=numeric_context(value,source) if re.fullmatch(r'(pos|size|rect|array)[2-9]?|fsize',name) else None
                    program=None
                    if re.fullmatch(r'(pos|size)[2-9]?',name):
                        # Resolve against the previous native map BEFORE the
                        # replacement is stored, including a self reference.
                        pending=copy.copy(item)
                        pending.attrs={**item.attrs,name:value};pending.indices={**item.indices,name:index}
                        pending.origins={**item.origins,name:source}
                        pending.numeric_contexts={**item.numeric_contexts,name:context}
                        program=_pair_program(doc,pending,name,trail=(),use_cache=False)
                    item.attrs[name] = value; item.origins[name] = source; item.indices[name] = index
                    if context is not None:item.numeric_contexts[name]=context
                    if program is not None:
                        item.pair_programs[name]=(value,index,program)
                    if re.fullmatch(r'(motion|hover|leave|press|release|action)[2-9]?',name):
                        item.motion_bindings[name]=motion_binding(value,source)
            except (ValueError, OSError) as error:
                doc.issues.append(Issue("error", "parse", str(error), source))
        active.pop()
    entry = root/f"script-key-{keys}K.mui"
    if not entry.is_file(): raise ValueError(f"No {keys}K entry in {root.name}")
    read(entry)
    return doc


def pair(doc: Document, element: Element, attr: str, default="0,0", trail=()) -> list[list[float]]:
    program=_pair_program(doc,element,attr,default,trail)
    from .position import coordinate
    result=[[0.,0.],[0.,0.]]
    for i,terms in enumerate(program):
        for text in terms:
            value=coordinate(text,ratio=getattr(doc,'ratio',16/9),logical_height=getattr(doc,'ui_rounding_height',720))
            for j in range(2):result[i][j]+=value[j]
    return result


def touch_coordinates(doc: Document, element: Element, attr: str) -> list[list[float]]:
    """Touch rect/array operands use NumericExpression, with assignment-time defines.

    ParseFile calls 0x50b6b0 for each operand, just as for pos/size. The
    arithmetic-only linear() helper cannot consume these variable snapshots.
    """
    from .position import coordinate
    context=element.numeric_contexts.get(attr,{})
    return [list(coordinate(dict(context,text=value),
        ratio=getattr(doc,'ratio',16/9),
        logical_height=getattr(doc,'ui_rounding_height',720)))
        for value in split_values(element.attrs[attr])]


def _pair_program(doc,element,attr,default='0,0',trail=(),use_cache=True):
    key=(element.name,attr)
    raw=element.attrs.get(attr,default);index=element.indices.get(attr,0)
    cached=element.pair_programs.get(attr)
    if use_cache and cached is not None and cached[:2]==(raw,index):
        return [list(terms) for terms in cached[2]]
    if key in trail:raise ValueError(f'Cyclic position reference: {element.name}')
    # Callers pass the primary size as the secondary-size fallback. Use its
    # already captured value, including earlier reference and selector steps.
    if attr not in element.attrs and attr.startswith('size') and default==element.attrs.get('size'):
        return _pair_program(doc,element,'size',trail=trail+(key,))
    reference=re.match(r'([^\s,]+)\s+(.+)',raw)
    base=[[],[]];value=raw
    if reference:
        target=doc.elements.get(reference[1])
        # 0x50f7d0..0x50f800 asks for the same attribute slot first, then
        # its unsuffixed family. A size reference never reads the target pos.
        target_attr=attr if target is not None and attr in target.attrs else re.sub(r'\d+$','',attr)
        if target is None or target_attr not in target.attrs:
            doc.issues.append(Issue('warning','native-zero-reference',f'Original parser retains zero reference base for {reference[1]}.{attr}',element.origins.get(attr,'')))
        else:base=_pair_program(doc,target,target_attr,trail=trail+(key,))
        value=reference[2]
    parts=value.split(',',1)
    if len(parts)!=2:raise ValueError(f'Expected a pair, got {value}')
    for i,part in enumerate(parts):
        pieces=part.split('$')
        if len(pieces)>2:raise ValueError(f'Invalid selector increment: {part}')
        context=element.numeric_contexts.get(attr,{})
        def capture(text):return dict(context,text=text.strip()) if context else text.strip()
        base[i].append(capture(pieces[0]))
        if len(pieces)==2:base[i].extend([capture(pieces[1])]*index)
    return base


def numeric_pair_program(doc: Document, element: Element, attr, default='0,0'):
    """Retain native scanner input and reference-addition boundaries."""
    program=_pair_program(doc,element,attr,default)
    for terms in program:
        for part in terms:
            compact=(part['text'] if isinstance(part,dict) else part).replace(' ','')
            numeric=re.sub(r'\{[^{}]+\}','0',compact)
            # Unknown bytes are ignored by the original scanner. Keep only
            # the existing bound on Lua's integer place accumulator; a
            # character whitelist rejects otherwise valid original skins.
            if any(len(d)>9 for d in re.findall(r'\d+',numeric)):return None
    return [[dict(term,text=term['text'].replace(' ','')) if isinstance(term,dict) else term.replace(' ','') for term in terms] for terms in program]


def position_program(doc: Document, element: Element, trail=()):
    return numeric_pair_program(doc,element,'pos')
