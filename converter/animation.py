"""4.3.7 ParseAni name aliases (original rolling-131 dispatch, 0x50be70).

Names are language syntax; no skin identity or source path selects behavior.
"""
ALIASES = {
    'move': 'm', 'movex': 'mx', 'movey': 'my', 'rotate': 'r',
    'fade': 'f', 'scale': 's', 'scalex': 'sx', 'scaley': 'sy',
    'width': 'w', 'height': 'h',
}

# Recognition is distinct from the runtime's supported subset. This table is
# checked against accepted original ParseAni returns, not a skin name list.
NATIVE_KINDS = {
    'm':1,'move':1,'mx':2,'movex':2,'my':3,'movey':3,'r':4,'rotate':4,
    'f':5,'fade':5,'tint':6,'s':7,'scale':7,'sx':8,'scalex':8,'sy':9,'scaley':9,
    'hide':10,'show':11,'skewx':12,'skewy':13,'skew':14,
    'w':16,'width':16,'h':17,'height':17,'size':18,'etag':20,'tag':21,
    'skewxo':24,'skewyo':25,'skewo':26,
}

OPTION_ALIASES={'n':'name','f':'from','tr':'trans','t':'time','r':'repeat'}
# Exact float controls recovered from original UnitBezier construction.
NATIVE_EASES={
    'easein':[0.33333298563957214,0.0,1.0,0.6666600108146667],
    'easeout':[0.0,0.3333300054073334,0.6666659712791443,1.0],
}


def normalize_record(record):
    result={};names=0
    for key,value in record.items():
        key=OPTION_ALIASES.get(key,key)
        if key=='name':names+=1
        result[key]=value
        if key in ('time','atime'):result['_time_value']=value
    if names>1:result['_duplicate_name']=True
    return result


def canonical(name):
    return ALIASES.get(name, name)


def rejected_options(record):
    # Original ParseAni's option dispatch rejects the complete record on an
    # unknown token, including spelling errors. 'source' is our provenance.
    record=normalize_record(record)
    result=set(record)-{'name','from','to','time','atime','repeat','trans','source','_time_value','_duplicate_name','_numeric'}
    if record.get('_duplicate_name'):result.add('duplicated name')
    return result
