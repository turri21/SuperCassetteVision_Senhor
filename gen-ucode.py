# Code generator for microcode RAM
#
# Copyright (c) 2024 David Hunter
#
# This program is GPL licensed. See COPYING for the full license.

import yaml
from collections import OrderedDict


with open('ucode.yaml') as f:
    doc = yaml.load(f, Loader=yaml.Loader)


def get_type(name):
    for t in doc['types']:
        if t['name'] == name:
            return t
    return KeyError


def get_column(name):
    for t in doc['columns']:
        if t['name'] == name:
            return t
    return None


def type_to_int(te, val):
    for i, v in enumerate(te['values']):
        if val == v:
            return i
    raise ValueError


# Fill in values of enum e_uaddr
get_type('e_uaddr')['values'] = list(r['addr'] for r in doc['rows'])


with open('uc-types.svh', 'w') as f:
    for t in doc['types']:
        if t['type'] == 'enum':
            name = t['name']
            vals = t['values']

            f.write(f"typedef enum reg [{t['width']-1}:0]\n")
            f.write("{\n")
            for v in vals:
                last = '' if v is vals[-1] else ','
                f.write(f"    {t['prefix']}{v}{last}\n")
            f.write(f"}} {name};    // {t['desc']}\n")
            f.write("\n")

    f.write("typedef struct packed\n")
    f.write("{\n")

    ram_w = 0
    for c in doc['columns']:
        if 'type' in c:
            te = get_type(c['type'])
            (t, w) = (te['name'], te['width'])
        else:
            w = c['width']
            t = f'reg [{w-1}:0]'
        f.write(f"    {t} {c['name']};    // {c['desc']}\n")
        c['start'] = ram_w
        ram_w += w
    f.write("} s_uc;\n")


with open('uc-at.svh', 'w') as f:
    prefix = get_type('e_uaddr')['prefix']
    for r in doc['rows']:
        if 'at' in r:
            f.write(f"    at_lut['h{r['at']:03x}] = {prefix}{r['addr']};\n")


with open('uram.mem', 'w') as f:
    for r in doc['rows']:
        bs = '0' * ram_w
        for k, v in r.items():
            c = get_column(k)
            if c is None:
                continue
            if 'type' in c:
                te = get_type(c['type'])
                w = te['width']
                v = type_to_int(te, v)
            else:
                w = c['width']
            start = c['start']
            end = start + w
            bv = f'{v:b}'
            bv = '0' * (w - len(bv)) + bv
            bs = bs[:start] + bv + bs[end:]
        f.write(bs + "\n")
