"""Original NumericExpression float32 scanner (0x50b6b0), including variables.

The caller supplies the parser's current unit scale and a snapshot of its
already-evaluated variable dictionary. This is not Python arithmetic syntax.
"""
import math
import struct


def float32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def tokens(text, variables=None, *, rounded=False):
    f = float32 if rounded else float
    value, place, mode, variable = 0., 1, 0, ''
    variables = variables or {}
    for i in range(len(text)-1, -1, -1):
        char = text[i]
        if char == '{':
            value = variables.get(variable, value)
            variable, place, mode = '', 10, 5
        elif mode == 4:
            variable = char + variable
            continue
        elif '0' <= char <= '9':
            value = f(f(value/10) + int(char))
            place *= 10
        elif char == '.':
            place = 1
            continue
        elif char == '%':mode = 1
        elif char == 'x':mode = 2
        elif char == 'w':mode = 3
        elif char == '}':mode = 4
        elif char == '$':
            value, place, mode = 0., 1, 0
            yield 0, 0., -1
            continue
        if i == 0 or char in '+-':
            yield -1 if char == '-' else 1, f(math.trunc(place/10)*value), mode
            value, place, mode = 0., 1, 0


def expression(text, extent, scale, width, variables=None):
    f = float32
    result = 0.
    for sign, value, mode in tokens(text, variables, rounded=True):
        if mode == -1:
            result = 0.
            continue
        if mode == 0:value = f(value*scale)
        elif mode == 1:value = f(f(value*extent)/100)
        elif mode == 3:value = f(f(value*width)/1280)
        result = f(result + sign*value)
    return result
