# Microcode generator
#
# Copyright (c) 2024 David Hunter
#
# This program is GPL licensed. See COPYING for the full license.

import yaml


ird_rows = []
uc_rows = []
nc_rows = []


def uc_row(row):
    uc_rows.append(row)

def nc_row(nc):
    if nc in nc_rows:
        i = nc_rows.index(nc)
    else:
        i = len(nc_rows)
        nc_rows.append(nc)
    return i


class ucode_seq():
    def __init__(self, name):
        name = name.translate(str.maketrans('+-', 'PN'))
        self.name = name
        self.steps = []

    def step(self, nc):
        naddr = nc_row(nc)
        self.steps.append(naddr)

    def commit(self, nsteps):
        steps_len = len(self.steps)
        for i in range(steps_len):
            ucrow = {}
            if i == 0:
                ucrow['uaddr'] = self.name
            ucrow['naddr'] = self.steps[i]
            nsteps = nsteps - 1
            if nsteps == 0:
                ucrow['m1'] = 1
            if i == steps_len - 1:
                ucrow['bm'] = 'END'
            uc_row(ucrow)


def ird_row(ir, nsteps, noper, ucs):
    if isinstance(ir, list):
        ir0, ir1 = ir
        ats = f'[0x{ir0:02x}, 0x{ir1:02x}]'
    else:
        ir0 = ir
        ats = f'0x{ir:02x}'

    nsteps -= 8 if ir0 >= 0x100 else 4

    if isinstance(ucs, ucode_seq):
        ucname = ucs.name
        ucs.commit(nsteps)
    else:
        ucname = ucs

    irdrow = {'_at': ats, 'at': ir, 'uaddr': ucname}
    if nsteps == 0:
        irdrow['m1_overlap'] = 1
    if noper:
        irdrow['skipn'] = noper

    ird_rows.append(irdrow)


######################################################################
# Instruction base

def ins(ir, nsteps, ucname, noper, ncs):
    assert(isinstance(ncs, list))
    ucs = ucode_seq(ucname)
    for s in ncs:
        ucs.step(s)
    ird_row(ir, nsteps, noper, ucs)

def idb_sel(rbs, op):
    if rbs in [0, 'AI', 'BI', 'CO', 'DB', 'DOR']:
        bc = {'r': 'idbs', 'w': 'lts'}[op]
        return {bc: rbs}

    if '_' not in rbs:
        rbs = 'RF_' + rbs
    bs, rs = rbs.split('_')
    bc, rc = {
        'RF-w': ('lts', 'rfts'),
        'SPR-w': ('lts', 'sprs'),
        'RF-r': ('idbs', 'rfos'),
        'SPR-r': ('idbs', 'sprs'),
        'SDG-r': ('idbs', 'sdgs'),
    }[bs + '-' + op]
    return {bc: bs, rc: rs}

def idb_rd(rbs):
    return idb_sel(rbs, 'r')

def idb_wr(rbs):
    if rbs == 'DB':
        rbs = 'DOR'                 # write equivalent of idb_rd('DB')
    return idb_sel(rbs, 'w')

def aor_wr(abs):
    return {'abs': abs, 'aout': 1}

######################################################################
# Common nrom operations

nc_idle = {}
nc_pc_out_inc = {'aout': 1, 'pc_inc': 1}
nc_load = {'load': 1}
nc_store = {'store': 1}         # dor -> DB
nc_write_db_to_w = {'idbs': 'DB', 'lts': 'RF', 'rfts': 'W'}
# DB -> idb -> AI, 0 -> BI, AI + BI -> CO
nc_write_db_to_co = {'idbs': 'DB', 'lts': 'AI', 'bi0': 1, 'aluop': 'SUM'}
nc_dec_sp = {'abs': 'SP', 'ab_dec': 1, 'abits': 'SP'} # SP - 1 -> SP
nc_inc_sp = {'abs': 'SP', 'ab_inc': 1, 'abits': 'SP'} # SP + 1 -> SP
nc_store_co_to_vw = idb_rd('CO') | idb_wr('DOR') | aor_wr('VW')

# Pre-populate nrom rows
nc_row(nc_idle)
nc_row(nc_pc_out_inc)
nc_row(nc_load)
nc_row(nc_store)

######################################################################
# Move / load / store data

def move(ir, nsteps, dst, src):
    imm = src == 'IMM'
    noper = 1 if imm else 0

    ucs = ucode_seq(f'MOV_{dst}_{src}')

    if imm:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        ucs.step({'idbs': 'DB'} | idb_wr(dst))
    else:
        ucs.step(idb_rd(src) | idb_wr(dst))
        ucs.step(nc_idle)
        ucs.step(nc_idle)

    ird_row(ir, nsteps, noper, ucs)

def load_wa(ir, nsteps, dst):
    ucs = ucode_seq(f'LD_{dst}_WA')
    ucs.step(nc_pc_out_inc)
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_w)
    ucs.step(aor_wr('VW'))
    ucs.step(nc_load)
    ucs.step(idb_rd('DB') | idb_wr(dst))
    ird_row(ir, nsteps, 1, ucs)

def load_imm16(ir, nsteps, reg):
    regl, regh = {
        'SP': ('SPL', 'SPH'),
        'BC': ('C', 'B'),
        'DE': ('E', 'D'),
        'HL': ('L', 'H'),
    }[reg]

    ucs = ucode_seq(f'LDX_{reg}_IMM')
    ucs.step(nc_pc_out_inc)
    ucs.step(nc_load)
    ucs.step({'idbs': 'DB', 'rfts': regl, 'lts': 'RF'})
    ucs.step(nc_pc_out_inc)
    ucs.step(nc_load)
    ucs.step({'idbs': 'DB', 'rfts': regh, 'lts': 'RF'})
    ird_row(ir, nsteps, 2, ucs)

def loadx(ir, nsteps, rp, dst, mod=''):
    nc_mod_rp = {}
    if mod == '+':
        nc_mod_rp = {'ab_inc': 1, 'abits': rp}
    elif mod == '-':
        nc_mod_rp = {'ab_dec': 1, 'abits': rp}

    ucs = ucode_seq(f'LDX{mod}_{rp}_{dst}')

    ucs.step(aor_wr(rp) | nc_mod_rp)
    ucs.step(nc_load)
    ucs.step(idb_rd('DB') | idb_wr(dst))

    ird_row(ir, nsteps, 0, ucs)

def load_abs(ir, nsteps):
    ucs = ucode_seq(f'LD_IR210_ABS')
    ucs.step(nc_pc_out_inc)     # Fetch word lo
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_w)
    ucs.step(nc_pc_out_inc)     # Fetch word hi
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_co)
    # W -> abl -> aorl, CO -> idb -> abh -> aorh
    ucs.step({'idbs': 'CO'} | aor_wr('IDB_W'))
    ucs.step(nc_load)
    # DB -> idb -> PCH
    ucs.step(idb_rd('DB') | idb_wr('RF_IR210'))
    ird_row(ir, nsteps, 2, ucs)

def storex(ir, nsteps, rp, src, mod=''):
    imm = src == 'IMM'
    if imm:
        src = 'RF_W'
    noper = 1 if imm else 0
    nc_write_src_to_dor = idb_rd(src) | {'lts': 'DOR'}
    nc_write_dst_to_aor = aor_wr(rp)
    nc_mod_dst = {}
    if mod == '+':
        nc_mod_dst = {'ab_inc': 1, 'abits': rp}

    ucs = ucode_seq(f'STX{mod}_{rp}_{src}')

    if imm:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        ucs.step({'idbs': 'DB'} | idb_wr(src))
        ucs.step(nc_write_src_to_dor | nc_write_dst_to_aor)
    else:
        ucs.step(nc_write_src_to_dor | nc_write_dst_to_aor | nc_mod_dst)
    ucs.step(nc_store)
    ucs.step(nc_idle)

    ird_row(ir, nsteps, noper, ucs)

def storew(ir, nsteps, src, mod=''):
    imm = src == 'IMM'
    noper = 2 if imm else 1

    ucs = ucode_seq(f'STW_{src}')

    ucs.step(nc_pc_out_inc)
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_w)
    if imm:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        # DB -> idb -> AI, 0 -> BI, AI + BI -> CO
        ucs.step({'idbs': 'DB', 'lts': 'AI', 'bi0': 1, 'aluop': 'SUM'})
        # CO -> idb -> dor
        nc_write_val_to_dor = {'idbs': 'CO', 'lts': 'DOR'}
    else:
        # A -> idb -> dor
        nc_write_val_to_dor = {'rfos': 'A', 'idbs': 'RF', 'lts': 'DOR'}
    # VW -> ab -> aor
    ucs.step(nc_write_val_to_dor | aor_wr('VW'))
    ucs.step(nc_store)
    ucs.step(nc_idle)

    ird_row(ir, nsteps, noper, ucs)

def store_abs(ir, nsteps):
    ucs = ucode_seq(f'ST_IR210_ABS')
    # r2 -> idb -> dor
    ucs.step(nc_pc_out_inc)     # Fetch word lo
    ucs.step(nc_load | idb_rd('RF_IR210') | idb_wr('DOR'))
    ucs.step(nc_write_db_to_w)
    ucs.step(nc_pc_out_inc)     # Fetch word hi
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_co)
    # W -> abl -> aorl, CO -> idb -> abh -> aorh
    ucs.step({'idbs': 'CO'} | aor_wr('IDB_W'))
    ucs.step(nc_store)
    ucs.step(nc_idle)
    ird_row(ir, nsteps, 2, ucs)

# BLOCK: (DE)+ <- (HL)+, C <- C - 1, end if borrow
def block(ir, nsteps):
    ucs = ucode_seq('BLOCK')
    # HL -> ab -> aor
    ucs.step(aor_wr('HL'))
    # HL + 1 -> HL
    ucs.step({'abs': 'HL', 'ab_inc': 1, 'abits': 'HL', 'load': 1})
    # DB -> idb -> W
    ucs.step({'idbs': 'DB', 'rfts': 'W', 'lts': 'RF'})
    # W -> idb -> dor, DE -> ab -> aor
    ucs.step({'rfos': 'W', 'idbs': 'RF', 'lts': 'DOR'} | aor_wr('DE'))
    # dor -> DB, DE + 1 -> DE
    ucs.step(nc_store | {'abs': 'DE', 'ab_inc': 1, 'abits': 'DE'})
    ucs.step(nc_idle)
    # C -> idb -> AI, AI - 1 -> CO
    ucs.step({'rfos': 'C', 'idbs': 'RF', 'lts': 'AI', 'aluop': 'DEC'})
    # CO -> idb -> C
    ucs.step({'rfts': 'C', 'idbs': 'CO', 'lts': 'RF'})
    # !CCO -> PSW.SK, repeat ins. until skipped
    ucs.step({'pswsk': 'NC', 'abs': 'PC', 'ab_dec': 1})
    ird_row(ir, nsteps, 0, ucs)

######################################################################
# Math / logic / test

def logic(ir, nsteps, op, dst, src):
    imm = src == 'IMM'
    wa = src == 'WA'
    noper = 1 if imm else 0

    ucname = f'{op}_{dst}_{src}'
    src = 'DB' if (imm or wa) else src
    ncop = {
        'AND': {'aluop': 'AND'},
        'OR': {'aluop': 'OR'},
        'XOR': {'aluop': 'EOR'},
        'SLR': {'aluop': 'LSL'},
        'SLL': {'aluop': 'LSR'},
    }[op]
    if op in ['AND', 'OR', 'XOR']:
        ncpsw = {'pswz': 1}                       # Update PSW.Z
    elif op in ['SLR', 'SLL']:
        ncpsw = {'pswcy': 1}                      # Update PSW.CY
    else:
        raise RuntimeError('unknown op')
    nc_write_dst_to_ai = idb_rd(dst) | idb_wr('AI')
    nc_write_src_to_bi = idb_rd(src) | idb_wr('BI') if src else {}

    ucs = ucode_seq(ucname)
    if imm:
        ucs.step(nc_pc_out_inc | nc_write_dst_to_ai)
        ucs.step(nc_load)
    elif wa:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        ucs.step(nc_write_db_to_w)
        # VW -> ab -> aor
        ucs.step(aor_wr('VW') | nc_write_dst_to_ai)
        ucs.step(nc_load)
    else:
        ucs.step(nc_write_dst_to_ai)
    ucs.step(nc_write_src_to_bi | ncop)
    ucs.step({'idbs': 'CO'} | idb_wr(dst) | ncpsw)
    ird_row(ir, nsteps, noper, ucs)

def logic_imm(ir, nsteps, op, reg):
    logic(ir, nsteps, op, reg, 'IMM')

def test(ir, nsteps, op, dst, src):
    imm = src == 'IMM'
    wa = dst == 'WA'
    onoff = op in ['ON', 'OFF']
    noper = 1 if imm else 0

    if onoff:
        # DB -> idb -> BI, AI & BI -> CO
        ncop = {'aluop': 'AND'}
    else:
        # DB -> idb -> BI, AI - BI (- 1) -> CO
        ncop = {'aluop': 'SUM', 'bin': 1, 'cis': int(op != 'GTI')}
    ncsk = {'pswsk': {
        'EQ': 'Z',
        'NEQ': 'NZ',
        'GT': 'C',
        'LT': 'NC',
        'ON': 'NZ',
        'OFF': 'Z',
    }[op]}
    nc_write_dst_to_ai = idb_rd('DB' if wa else dst) | {'lts': 'AI'}
    nc_write_src_to_bi = idb_rd('DB' if imm else src) | {'lts': 'BI'}

    ucs = ucode_seq(f'{op}_{dst}_{src}')
    if wa:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        ucs.step(nc_write_db_to_w)
        # VW -> ab -> aor
        ucs.step(aor_wr('VW'))
        ucs.step(nc_load)
        ucs.step(nc_write_dst_to_ai)
    if imm:
        ucs.step(nc_pc_out_inc)
        if wa:
            ucs.step(nc_load)
        else:
            ucs.step(nc_write_dst_to_ai | nc_load)
    else:
        ucs.step(nc_write_dst_to_ai)
    ucs.step(nc_write_src_to_bi | ncop)
    ncsk |= {'pswz': 1}                           # Update PSW.Z
    if not onoff:
        ncsk |= {'pswcy': 1,                      # Update PSW.CY
                 'pswhc': 1}                      # Update PSW.HC
    ucs.step(ncsk)

    ird_row(ir, nsteps, noper, ucs)

def test_imm(ir, nsteps, op, reg):
    test(ir, nsteps, op, reg, 'IMM')

def math(ir, nsteps, op, dst, src, skip=''):
    imm = src == 'IMM'
    wa = src == 'WA'
    noper = 1 if (imm or wa) else 0
    ncop = {
        'ADD': {'aluop': 'SUM'},
        'ADC': {'aluop': 'SUM', 'cis': 'PSW_CY'},
        'SUB': {'aluop': 'SUM', 'bin': 1, 'cis': 1},
        'SBB': {'aluop': 'SUM', 'bin': 1, 'cis': 'PSW_CY'},
    }[op]
    ncsk = {
        '': {},
        'NC': {'pswsk': 'NC'},  # !CCO -> PSW.SK
        'NB': {'pswsk': 'C'},   # CCO -> PSW.SK
    }[skip]
    nc_write_dst_to_ai = idb_rd(dst) | idb_wr('AI')
    nc_write_src_to_bi = idb_rd('DB' if (imm or wa) else src) | idb_wr('BI')

    ucs = ucode_seq(f'{op}{skip}_{dst}_{src}')
    if imm:
        ucs.step(nc_pc_out_inc | nc_write_dst_to_ai)
        ucs.step(nc_load)
    elif wa:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        ucs.step(nc_write_db_to_w)
        # VW -> ab -> aor
        ucs.step(aor_wr('VW') | nc_write_dst_to_ai)
        ucs.step(nc_load)
    else:
        ucs.step(nc_write_dst_to_ai)
    ucs.step(nc_write_src_to_bi | ncop)
    ucs.step({'idbs': 'CO'} | idb_wr(dst) | {
        'pswz': 1,              # Update PSW.Z
        'pswcy': 1,             # Update PSW.CY
        'pswhc': 1,             # Update PSW.HC
    } | ncsk)

    ird_row(ir, nsteps, noper, ucs)

def math_imm(ir, nsteps, op, reg, skip=''):
    math(ir, nsteps, op, reg, 'IMM', skip)

def incdec(ir, nsteps, op, reg):
    wa = reg == 'WA'
    ncsk = {
        'INC': {'pswsk': 'C'},   # CCO -> PSW.SK
        'DEC': {'pswsk': 'NC'},  # !CCO -> PSW.SK
    }[op]
    ncpsw = {
        'pswz': 1,              # Update PSW.Z
        'pswcy': 1,             # Update PSW.CY
        'pswhc': 1,             # Update PSW.HC
    } | ncsk                    # Update PSW.SK

    ucs = ucode_seq(f'{op}R_{reg}')

    if wa:
        ucs.step(nc_pc_out_inc)
        ucs.step(nc_load)
        ucs.step(nc_write_db_to_w)
        # VW -> ab -> aor
        ucs.step(aor_wr('VW'))
        ucs.step(nc_load)
        reg = 'DB'
    # r2 -> idb -> AI, AI +/- 1 -> CO
    ucs.step(idb_rd(reg) | idb_wr('AI') | {'aluop': op})
    if wa:
        ucs.step(nc_store_co_to_vw)
        ucs.step(nc_store)
        ucs.step(ncpsw)
    else:
        # CO -> idb -> r2
        ucs.step(idb_rd('CO') | idb_wr(reg) | ncpsw)

    ird_row(ir, nsteps, 0, ucs)

def incdecx(ir, nsteps, op, rp):
    abid = 'ab_inc' if op == 'INC' else 'ab_dec'

    ucs = ucode_seq(f'{op}_{rp}')
    ucs.step({'abs': rp, abid: 1, 'abits': rp})
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ird_row(ir, nsteps, 0, ucs)

# DAA: Decimal Adjust A
def daa(ir, nsteps):
    ucs = ucode_seq('DAA')
    ucs.step(idb_rd('A') | idb_wr('AI') | {'daa': 1, 'aluop': 'SUM'})
    ucs.step(idb_rd('CO') | idb_wr('A') | {'pswz': 1, 'pswhc': 1, 'pswcy': 1})
    ird_row(ir, nsteps, 0, ucs)

######################################################################
# Jump / call / return

def jr(ir, nsteps):
    ucs = ucode_seq('JR')
    # PCL -> idb -> AI
    ucs.step({'rfos': 'PCL', 'idbs': 'RF', 'lts': 'AI'})
    # IR[5:0] -> idb -> BI
    ucs.step({'idbs': 'SDG', 'sdgs': 'JRL', 'lts': 'BI'})
    # AI + BI -> CO
    ucs.step({'aluop': 'SUM', 'cis': 0})
    # CO -> idb -> PCL
    ucs.step({'idbs': 'CO', 'lts': 'RF', 'rfts': 'PCL'})
    # PCH -> idb -> AI
    ucs.step({'rfos': 'PCH', 'idbs': 'RF', 'lts': 'AI'})
    # sign-ext. IR[5] -> idb -> BI
    ucs.step({'idbs': 'SDG', 'sdgs': 'JRH', 'lts': 'BI'})
    # AI + BI + CCO -> CO
    ucs.step({'aluop': 'SUM', 'cis': 'CCO'})
    # CO -> idb -> PCH
    ucs.step({'idbs': 'CO', 'lts': 'RF', 'rfts': 'PCH'})
    ucs.step(nc_idle)
    ird_row(ir, nsteps, 0, ucs)

def jre(ir, nsteps, sign):
    ucs = ucode_seq(f'JRE_{sign}')
    ucs.step(nc_pc_out_inc)
    # PCL -> idb -> AI
    ucs.step({'rfos': 'PCL', 'idbs': 'RF', 'lts': 'AI', 'load': 1})
    # DB -> idb -> BI, AI + BI -> CO
    ucs.step({'idbs': 'DB', 'lts': 'BI', 'aluop': 'SUM', 'cis': 0})
    # CO -> idb -> PCL
    ucs.step({'idbs': 'CO', 'lts': 'RF', 'rfts': 'PCL'})
    # PCH -> idb -> AI, 0 -> BI, AI +/- BI +/- CCO -> CO
    ucs.step({'rfos': 'PCH', 'idbs': 'RF', 'lts': 'AI', 'bi0': 1,
              'bin': sign == '-', 'aluop': 'SUM', 'cis': 'CCO'})
    # CO -> idb -> PCH
    ucs.step({'idbs': 'CO', 'lts': 'RF', 'rfts': 'PCH'})
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ird_row(ir, nsteps, 1, ucs)

def jmp(ir, nsteps):
    ucs = ucode_seq('JMP')
    ucs.step(nc_pc_out_inc)                       # Fetch word lo
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_w)
    ucs.step(aor_wr('PC'))                        # Fetch word hi
    # W -> idb -> PCL
    ucs.step(idb_rd('RF_W') | idb_wr('RF_PCL') | nc_load)
    # DB -> idb -> PCH
    ucs.step({'idbs': 'DB'} | idb_wr('RF_PCH'))
    ird_row(ir, nsteps, 2, ucs)

def calf(ir, nsteps):
    ucs = ucode_seq('CALF')
    # SP <- SP-1, PC <- PC+1 (next ins.)
    ucs.step({'pc_inc': 1})
    ucs.step(nc_load)
    ucs.step(nc_write_db_to_w | nc_dec_sp)
    # (SP) <- PCH, SP <- SP-1
    ucs.step(idb_rd('RF_PCH') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step(nc_dec_sp)
    # (SP) <- PCL, PC <- PC-1 (operand)
    ucs.step(idb_rd('RF_PCL') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step({'abs': 'PC', 'ab_dec': 1, 'abits': 'PC'})
    # PCL <- oper., PCH <- {5'b00001, IR[2:0]}
    ucs.step(aor_wr('PC'))                        # fetch word lo
    ucs.step(nc_load | idb_rd('SDG_CALF') | idb_wr('RF_PCH'))
    ucs.step(idb_rd('DB') | idb_wr('RF_PCL'))

    ird_row(ir, nsteps, 1, ucs)

def calt(ir, nsteps):
    ucs = ucode_seq('CALT')
    # SP <- SP-1
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ucs.step(nc_dec_sp)
    # (SP) <- PCH, SP <- SP-1
    ucs.step(idb_rd('RF_PCH') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step(nc_dec_sp)
    # (SP) <- PCL
    ucs.step(idb_rd('RF_PCL') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    # effective naddr lo. -> idb -> W
    ucs.step({'idx': 0} | idb_rd('SDG_CALT') | idb_wr('RF_W'))
    # PCL <- (128 + 2ta)
    # W -> abl -> aorl, 0 -> idb -> abh -> aorh
    ucs.step(idb_rd(0) | aor_wr('IDB_W'))
    # effective naddr hi. -> idb -> W
    ucs.step(nc_load | {'idx': 1} | idb_rd('SDG_CALT') | idb_wr('RF_W'))
    ucs.step(idb_rd('DB') | idb_wr('RF_PCL'))
    # PCH <- (129 + 2ta)
    ucs.step(idb_rd(0) | aor_wr('IDB_W'))
    ucs.step(nc_load)
    ucs.step(idb_rd('DB') | idb_wr('RF_PCH'))
    ird_row(ir, nsteps, 0, ucs)

# SOFTI/INT (Software/Hardware Interrupt) [19 states]
def softi(ir, nsteps):
    ucs = ucode_seq('INT')
    # SP <- SP-1
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ucs.step(nc_dec_sp)
    # (SP) <- PSW, SP <- SP-1
    ucs.step(idb_rd('RF_PSW') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step(nc_dec_sp)
    # (SP) <- PCH, SP <- SP-1
    ucs.step(idb_rd('RF_PCH') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step(nc_dec_sp)
    # (SP) <- PCL
    ucs.step(idb_rd('RF_PCL') | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    # effective naddr lo. -> idb -> W
    ucs.step({'idx': 0} | idb_rd('SDG_CALT') | idb_wr('RF_W'))
    # PCH <- 0
    ucs.step(idb_rd(0) | idb_wr('RF_PCH'))
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    # PCL <- 'h60
    ucs.step(idb_rd('SDG_INTVA') | idb_wr('RF_PCL'))
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ird_row(ir, nsteps, 0, ucs)

# RET / RETI (Return from Subroutine / Interrupt)
def ret(ir, nsteps, ucname):
    ucs = ucode_seq(ucname)
    # PCL <- (SP), SP <- SP+1
    ucs.step(aor_wr('SP'))
    ucs.step(nc_load | nc_inc_sp)
    ucs.step(idb_rd('DB') | idb_wr('PCL'))
    # PCH <- (SP), SP <- SP+1
    ucs.step(aor_wr('SP'))
    ucs.step(nc_load | nc_inc_sp)
    ucs.step(idb_rd('DB') | idb_wr('PCH'))
    if ucname == 'RETI':
        # PSW <- (SP), SP <- SP+1
        ucs.step(aor_wr('SP'))
        ucs.step(nc_load | nc_inc_sp)
        ucs.step(idb_rd('DB') | idb_wr('PSW'))
    ird_row(ir, nsteps, 0, ucs)

######################################################################
# Stack

# PUSH (Push Register Pair on Stack)
def push16(ir, nsteps, rp):
    ucs = ucode_seq(f'PUSH_{rp}')
    # SP <- SP-1
    ucs.step(nc_idle)
    ucs.step(nc_idle)
    ucs.step(nc_dec_sp)
    # (SP) <- rph <- SP-1
    ucs.step(idb_rd(rp[0]) | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step(nc_dec_sp)
    # (SP) <- rpl
    ucs.step(idb_rd(rp[1]) | idb_wr('DOR') | aor_wr('SP'))
    ucs.step(nc_store)
    ucs.step(nc_idle)
    ird_row(ir, nsteps, 0, ucs)

# POP (Pop Register Pair from Stack)
def pop16(ir, nsteps, rp):
    ucs = ucode_seq(f'POP_{rp}')
    # rph <- (SP), SP <- SP+1
    ucs.step(aor_wr('SP') | nc_inc_sp)
    ucs.step(nc_load)
    ucs.step(idb_rd('DB') | idb_wr(rp[1]))
    # rpl <- (SP), SP <- SP+1
    ucs.step(aor_wr('SP') | nc_inc_sp)
    ucs.step(nc_load)
    ucs.step(idb_rd('DB') | idb_wr(rp[0]))
    ird_row(ir, nsteps, 0, ucs)


######################################################################
# Skip

def skip(ir, nsteps, sk):
    ucs = ucode_seq(f'SKIP_{sk}')
    ucs.step({'pswsk': sk})
    ird_row(ir, nsteps, 0, ucs)
    

######################################################################
# Pre-populate urom rows

uc_row({'uaddr': 'IDLE', 'naddr': nc_row(nc_idle), 'bm': 'END'})

# Idle cycles for skipping instructions w/ 1-2 operands
uc_row({'uaddr': 'SKIP_OP2', 'naddr': nc_row(nc_pc_out_inc)})
uc_row({'naddr': nc_row(nc_load)})
uc_row({'naddr': nc_row(nc_idle)})
uc_row({'uaddr': 'SKIP_OP1', 'naddr': nc_row(nc_pc_out_inc)})
uc_row({'naddr': nc_row(nc_load)})
uc_row({'naddr': nc_row(nc_idle), 'm1': 1, 'bm': 'END'})

######################################################################
# no prefix opcode

move([0x0a, 0x0f], 4, 'A', 'RF_IR210')            # MOV A, r1
move([0x1a, 0x1f], 4, 'RF_IR210', 'A')            # MOV r1, A
move([0x68, 0x6f], 7, 'RF_IR210', 'IMM')          # MVI r, byte

load_wa(0x28, 10, 'A')                            # LDAW wa

load_imm16(0x04, 10, 'SP')                        # LXI SP, bbaa
load_imm16(0x14, 10, 'BC')                        # LXI BC, bbaa
load_imm16(0x24, 10, 'DE')                        # LXI DE, bbaa
load_imm16(0x34, 10, 'HL')                        # LXI HL, bbaa

loadx(0x29, 7, 'BC', 'A')                         # LDAX B
loadx(0x2a, 7, 'DE', 'A')                         # LDAX D
loadx(0x2b, 7, 'HL', 'A')                         # LDAX H
loadx(0x2c, 7, 'DE', 'A', '+')                    # LDAX D+
loadx(0x2d, 7, 'HL', 'A', '+')                    # LDAX H+
loadx(0x2e, 7, 'DE', 'A', '-')                    # LDAX D-
loadx(0x2f, 7, 'HL', 'A', '-')                    # LDAX H-

storex(0x3a, 7, 'DE', 'A')                        # STAX D/H/L
storex(0x3b, 7, 'HL', 'A')
storex(0x3c, 7, 'DE', 'A', '+')
storex(0x3d, 7, 'HL', 'A', '+')

storex([0x48, 0x4b], 10, 'IR10', 'IMM')           # MVIX rpa1, byte

storew(0x38, 10, 'A')                             # STAW wa
storew(0x71, 13, 'IMM')                           # MVIW wa, byte

block(0x31, 13)                                   # BLOCK

test_imm(0x45, 13, 'ON', 'WA')                    # ONIW wa, byte

logic_imm(0x07, 7, 'AND', 'A')                    # ANI A, byte
logic_imm(0x16, 7, 'XOR', 'A')                    # XRI A, byte
logic_imm(0x17, 7, 'OR', 'A')                     # ORI A, byte

test_imm(0x27, 7, 'GT', 'A')                      # GTI A, byte
test_imm(0x47, 7, 'ON', 'A')                      # ONI A, byte
test_imm(0x57, 7, 'OFF', 'A')                     # OFFI A, byte
test_imm(0x67, 7, 'NEQ', 'A')                     # NEI A, byte
test_imm(0x77, 7, 'EQ', 'A')                      # EQI A, byte

math_imm(0x26, 7, 'ADD', 'A', 'NC')               # ADINC A, byte
math_imm(0x36, 7, 'SUB', 'A', 'NB')               # SUINB A, byte
math_imm(0x46, 7, 'ADD', 'A')                     # ADI A, byte
math_imm(0x56, 7, 'ADC', 'A')                     # ACI A, byte
math_imm(0x66, 7, 'SUB', 'A')                     # SUI A, byte
math_imm(0x76, 7, 'SBB', 'A')                     # SBI A, byte

incdec(0x20, 13, 'INC', 'WA')                     # INRW wa
incdec(0x30, 13, 'DEC', 'WA')                     # DCRW wa

incdec([0x41, 0x43], 4, 'INC', 'RF_IR210')        # INR r2
incdec([0x51, 0x53], 4, 'DEC', 'RF_IR210')        # DCR r2

incdecx(0x22, 7, 'INC', 'DE')                     # INX D

daa(0x61, 4)                                      # DAA

jr([0xc0, 0xff], 13)                              # JR
jre(0x4e, 13, '+')                                # JRE (+jdisp)
jre(0x4f, 13, '-')                                # JRE (-jdisp)
jmp(0x54, 10)                                     # JMP word
calf([0x78, 0x7f], 16)                            # CALF word
calt([0x80, 0xbf], 19)                            # CALT
softi(0x72, 22)                                   # SOFTI / INT
# Note: Data sheet says 15 cycles, but I think that's a typo.
ret(0x08, 10, 'RET')                              # RET
ret(0x62, 13, 'RETI')                             # RETI

ird_row(0x00, 4, 0, 'IDLE')                       # NOP
# TODO
ins(0x19, 4, 'STM', 0, [{}])                      # STM

######################################################################
# 0x1xx: prefix 0x48

logic(0x134, 8, 'SLL', 'A', '')                   # SLL A
logic(0x135, 8, 'SLR', 'A', '')                   # SLR A

push16(0x10e, 17, 'VA')                           # PUSH V
pop16(0x10f, 14, 'VA')                            # POP V
push16(0x11e, 17, 'BC')                           # PUSH B
pop16(0x11f, 14, 'BC')                            # POP B
push16(0x12e, 17, 'DE')                           # PUSH D
pop16(0x12f, 14, 'DE')                            # POP D
push16(0x13e, 17, 'HL')                           # PUSH H
pop16(0x13f, 14, 'HL')                            # POP H

skip([0x100, 0x104], 8, 'I')                      # SKIT irf
skip(0x10a, 8, 'C')                               # SKCY
skip([0x110, 0x114], 8, 'NI')                     # SKNIT irf
skip(0x11a, 8, 'NC')                              # SKNCY

ins(0x120, 8, 'EI', 0, [{'idx': 1, 'lts': 'IE'}]) # EI
ins(0x124, 8, 'DI', 0, [{'idx': 0, 'lts': 'IE'}]) # DI

######################################################################
# 0x2xx: prefix 0x4C

move([0x2c0, 0x2c9], 8, 'A', 'SPR_IR3')           # MOV A, sr

######################################################################
# 0x3xx: prefix 0x4D

move([0x3c0, 0x3c9], 8, 'SPR_IR3', 'A')           # MOV sr, A

######################################################################
# 0x4xx: prefix 0x60

math([0x420, 0x427], 8, 'ADD', 'RF_IR210', 'A', 'NC')
math([0x430, 0x437], 8, 'SUB', 'RF_IR210', 'A', 'NB')
math([0x440, 0x447], 8, 'ADD', 'RF_IR210', 'A')
math([0x450, 0x457], 8, 'ADC', 'RF_IR210', 'A')
math([0x460, 0x467], 8, 'SUB', 'RF_IR210', 'A')
math([0x470, 0x477], 8, 'SBB', 'RF_IR210', 'A')
math([0x4a0, 0x427], 8, 'ADD', 'A', 'RF_IR210', 'NC')
math([0x4b0, 0x4b7], 8, 'SUB', 'A', 'RF_IR210', 'NB')
math([0x4c0, 0x4c7], 8, 'ADD', 'A', 'RF_IR210')
math([0x4d0, 0x4d7], 8, 'ADC', 'A', 'RF_IR210')
math([0x4e0, 0x4e7], 8, 'SUB', 'A', 'RF_IR210')
math([0x4f0, 0x4f7], 8, 'SBB', 'A', 'RF_IR210')

######################################################################
# 0x5xx: prefix 0x64

# ADI(NC)/SUI(NB) r, byte
math_imm([0x520, 0x527], 11, 'ADD', 'RF_IR210', 'NC')
math_imm([0x530, 0x537], 11, 'SUB', 'RF_IR210', 'NB')
math_imm([0x540, 0x547], 11, 'ADD', 'RF_IR210')
math_imm([0x550, 0x557], 11, 'ADC', 'RF_IR210')
test_imm([0x558, 0x55f], 11, 'OFF', 'RF_IR210')
math_imm([0x560, 0x567], 11, 'SUB', 'RF_IR210')
math_imm([0x570, 0x577], 11, 'SBB', 'RF_IR210')

logic_imm([0x588, 0x58f], 11, 'AND', 'SPR_IR2')   # ANI sr2, byte
logic_imm([0x590, 0x597], 11, 'XOR', 'SPR_IR2')   # XRI sr2, byte
logic_imm([0x598, 0x59f], 11, 'OR',  'SPR_IR2')   # ORI sr2, byte

test_imm([0x5c8, 0x5cf], 11, 'ON',  'SPR_IR2')    # ONI sr2, byte
test_imm([0x5d8, 0x5df], 11, 'OFF', 'SPR_IR2')    # OFFI sr2, byte

######################################################################
# 0x6xx: prefix 0x70

load_abs([0x668, 0x66f], 17)                      # MOV r, word

store_abs([0x678, 0x67f], 17)                     # MOV word, r

######################################################################
# 0x7xx: prefix 0x74

math(0x7c0, 14, 'ADD', 'A', 'WA')                 # ADDW A, wa

######################################################################

for i in range(len(nc_rows)):
    nc_rows[i] = {'naddr': i} | nc_rows[i] # debugging aid

with open('ucode-gen.yaml', 'w') as f:
    yaml.safe_dump({'ird': {'rows': ird_rows}}, f, sort_keys=False)
    yaml.safe_dump({'urom': {'rows': uc_rows}}, f, sort_keys=False)
    yaml.safe_dump({'nrom': {'rows': nc_rows}}, f, sort_keys=False)
