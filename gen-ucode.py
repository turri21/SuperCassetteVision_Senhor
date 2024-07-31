# Code generator for microcode ROM
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


def get_column(name, tbl):
    for t in tbl['columns']:
        if t['name'] == name:
            return t
    return None


def type_to_int(te, val):
    for i, v in enumerate(te['values']):
        if val == v:
            return i
    raise ValueError


def get_all_addresses(tbl, col):
    ret = []
    v = 0
    for r in tbl['rows']:
        if col in r:
            a = r[col]
        else:
            a = f"_{v:X}"
        ret.append(a)
        v = v + 1
    return ret


# Fill in values of enums e_uaddr, e_naddr
get_type('e_uaddr')['values'] = get_all_addresses(doc['urom'], 'uaddr')
get_type('e_naddr')['values'] = get_all_addresses(doc['nrom'], 'naddr')


def gen_struct(f, stname, tbl):
    f.write("typedef struct packed\n")
    f.write("{\n")

    stw = 0
    for c in tbl['columns']:
        if 'type' in c:
            te = get_type(c['type'])
            (t, w) = (te['name'], te['width'])
        else:
            w = c['width']
            t = f'reg [{w-1}:0]'
        f.write(f"    {t} {c['name']};    // {c['desc']}\n")
        c['start'] = stw
        stw += w
    f.write(f"}} {stname};\n")
    f.write("\n")
    return stw


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

    gen_struct(f, 's_ird', doc['ird'])
    urom_w = gen_struct(f, 's_uc', doc['urom'])
    nrom_w = gen_struct(f, 's_nc', doc['nrom'])


with open('uc-ird.svh', 'w') as f:
    for r in doc['ird']['rows']:
        at = r['at']
        if isinstance(at, list):
            at = range(at[0], at[1] + 1)
        else:
            at = [at]
        for a in at:
            st = []
            for c in doc['ird']['columns']:
                name = c['name']
                v = r[name] if name in r else '0'
                if 'type' in c:
                    te = get_type(c['type'])
                    v = f"{te['prefix']}{v}"
                else:
                    v = f"{c['width']}'d{v}"
                st.append(v)
            v = '{' + ', '.join(st) + '}'
            f.write(f"    ird_lut['h{a:03x}] = {v};\n")


def gen_rom(f, tbl, rom_w):
    for r in tbl['rows']:
        #print(r)
        bs = '0' * rom_w
        for k, v in r.items():
            c = get_column(k, tbl)
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


with open('urom.mem', 'w') as f:
    gen_rom(f, doc['urom'], urom_w)


with open('nrom.mem', 'w') as f:
    gen_rom(f, doc['nrom'], nrom_w)
