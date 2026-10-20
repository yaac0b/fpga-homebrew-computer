#!/usr/bin/env python3
"""
HackL - a small high-level language for the Tang Nano Hack computer.

    python3 hl.py program.hl                 -> program.asm
    python3 hl.py program.hl --hack          -> program.asm + program.hack
                                                (needs assembler.py etc. beside it)
    python3 hl.py program.hl --iters 8805    -> change the delay calibration

The compiler emits plain Hack assembly for YOUR assembler, so nothing
else in the toolchain changes.  See HackL_Reference.md for the language.
"""
import argparse
import os
import re
import sys

# ----------------------------------------------------------------------
# Hardware map (matches memory.v of the GPU/SDRAM/ADC build)
# ----------------------------------------------------------------------
P1_ADDR      = 24596   # 0x6014  external LED register
ADC_CH_ADDR  = 24592   # 0x6010  channel select (bits 1:0)
ADC_CTL_ADDR = 24593   # 0x6011  write 1 = start; read bit0 busy, bit1 valid
ADC_DAT_ADDR = 24594   # 0x6012  16-bit signed result

# Delay calibration: your CountToMax_1sec.asm loop (100 x 65535 x 3 instr)
# is "about 1 second", so 1 ms = 100*65535/1000 = 6553 loop passes.
DEFAULT_ITERS = 8805   # measured: 6550 gave 744 ms for delay(1000) on the board; 6550*1000/744 = 8805

# GPU registers (gpu_top.v): CONTROL, STATUS, COMMAND, X, Y, X2, Y2, COLOR
GPU_CTL, GPU_CMD = 24576, 24578
GPU_X, GPU_Y, GPU_X2, GPU_Y2, GPU_COLOR = 24579, 24580, 24581, 24582, 24583
CMD_PIXEL, CMD_CLEAR, CMD_FILL = 1, 2, 3
# RGB332 colours available as constants
COLORS = {'BLACK': 0x00, 'WHITE': 0xFF, 'RED': 0xE0, 'GREEN': 0x1C,
          'BLUE': 0x03, 'YELLOW': 0xFC, 'CYAN': 0x1F, 'MAGENTA': 0xE3,
          'ORANGE': 0xF0, 'GRAY': 0x92}

VAR_BASE  = 16        # user variables live in RAM[16...]
TEMP_BASE = 5         # expression temporaries R5..R10
TEMP_MAX  = 6
# R11,R12 : library scratch / remainder
# R13     : argument 1,  R15 : argument 2,  R14 : return address


class HLError(Exception):
    pass


# ----------------------------------------------------------------------
# Lexer
# ----------------------------------------------------------------------
TOKEN_RE = re.compile(r'''
    (?P<ws>[ \t\r]+) | (?P<nl>\n) | (?P<cmt>//[^\n]*) | (?P<bcmt>/\*.*?\*/) |
    (?P<num>0[xX][0-9a-fA-F]+|0[bB][01]+|\d+) |
    (?P<id>[A-Za-z_]\w*) |
    (?P<op>\+\+|--|\+=|-=|==|!=|<=|>=|&&|\|\||[-+*/%&|~!<>=(){};,])
''', re.X | re.S)


def lex(src):
    toks, pos, line = [], 0, 1
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise HLError(f"line {line}: unexpected character {src[pos]!r}")
        kind = m.lastgroup
        text = m.group()
        if kind == 'nl':
            line += 1
        elif kind == 'bcmt':
            line += text.count('\n')
        elif kind == 'num':
            toks.append(('num', int(text, 0), line))
        elif kind in ('id', 'op'):
            toks.append((kind, text, line))
        pos = m.end()
    toks.append(('eof', None, line))
    return toks


# ----------------------------------------------------------------------
# Parser
# ----------------------------------------------------------------------
KEYWORDS = {'var', 'const', 'if', 'else', 'while', 'break', 'continue', 'halt'}
LEVELS = [['||'], ['&&'], ['==', '!=', '<', '>', '<=', '>='],
          ['|'], ['&'], ['+', '-'], ['*', '/', '%']]


class Parser:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i]

    def next(self):
        tok = self.t[self.i]
        self.i += 1
        return tok

    def at(self, val):
        k, v, _ = self.peek()
        return k in ('op', 'id') and v == val

    def accept(self, val):
        if self.at(val):
            self.i += 1
            return True
        return False

    def expect(self, val):
        if not self.accept(val):
            k, v, ln = self.peek()
            got = 'end of file' if k == 'eof' else repr(v)
            raise HLError(f"line {ln}: expected {val!r}, found {got}")

    def ident(self):
        k, v, ln = self.next()
        if k != 'id' or v in KEYWORDS:
            raise HLError(f"line {ln}: expected a name, found {v!r}")
        return v

    # ---- statements ----
    def program(self):
        out = []
        while self.peek()[0] != 'eof':
            out.append(self.stmt())
        return out

    def block(self):
        self.expect('{')
        out = []
        while not self.at('}'):
            if self.peek()[0] == 'eof':
                raise HLError(f"line {self.peek()[2]}: missing '}}'")
            out.append(self.stmt())
        self.expect('}')
        return out

    def stmt(self):
        k, v, ln = self.peek()
        if self.at('{'):
            return ('block', ln, self.block())
        if k == 'id' and v == 'var':
            self.next()
            decls = []
            while True:
                name = self.ident()
                init = self.expr() if self.accept('=') else None
                decls.append((name, init))
                if not self.accept(','):
                    break
            self.expect(';')
            return ('var', ln, decls)
        if k == 'id' and v == 'const':
            self.next()
            name = self.ident()
            self.expect('=')
            e = self.expr()
            self.expect(';')
            return ('const', ln, name, e)
        if k == 'id' and v == 'if':
            self.next()
            self.expect('(')
            c = self.expr()
            self.expect(')')
            then = self.block()
            els = None
            if self.accept('else'):
                els = [self.stmt()] if self.at('if') else self.block()
            return ('if', ln, c, then, els)
        if k == 'id' and v == 'while':
            self.next()
            self.expect('(')
            c = self.expr()
            self.expect(')')
            return ('while', ln, c, self.block())
        if k == 'id' and v in ('break', 'continue', 'halt'):
            self.next()
            self.expect(';')
            return (v, ln)
        if k == 'id' and v not in KEYWORDS:
            nxt = self.t[self.i + 1]
            if nxt[0] == 'op' and nxt[1] == '(':           # call statement
                name = self.next()[1]
                self.expect('(')
                args = []
                if not self.at(')'):
                    args.append(self.expr())
                    while self.accept(','):
                        args.append(self.expr())
                self.expect(')')
                self.expect(';')
                return ('call', ln, name, args)
            name = self.next()[1]
            target = ('p1',) if name == 'P1' else ('var', name)
            op = self.next()
            if op[0] == 'op' and op[1] == '=':
                e = self.expr()
            elif op[0] == 'op' and op[1] in ('+=', '-='):
                e = ('bin', op[1][0], target, self.expr())
            elif op[0] == 'op' and op[1] in ('++', '--'):
                e = ('bin', op[1][0], target, ('num', 1))
            else:
                raise HLError(f"line {ln}: expected '=' after {name!r}")
            self.expect(';')
            return ('assign', ln, target, e)
        raise HLError(f"line {ln}: unexpected {v!r}")

    # ---- expressions ----
    def expr(self):
        return self.level(0)

    def level(self, lvl):
        if lvl == len(LEVELS):
            return self.unary()
        left = self.level(lvl + 1)
        while self.peek()[0] == 'op' and self.peek()[1] in LEVELS[lvl]:
            op = self.next()[1]
            left = ('bin', op, left, self.level(lvl + 1))
        return left

    def unary(self):
        k, v, ln = self.peek()
        if k == 'op' and v in ('-', '~', '!'):
            self.next()
            return ('un', v, self.unary())
        return self.primary()

    def primary(self):
        k, v, ln = self.next()
        if k == 'num':
            if v > 0xFFFF:
                raise HLError(f"line {ln}: number {v} does not fit in 16 bits")
            return ('num', v)
        if k == 'op' and v == '(':
            e = self.expr()
            self.expect(')')
            return e
        if k == 'id' and v not in KEYWORDS:
            if self.accept('('):
                args = []
                if not self.at(')'):
                    args.append(self.expr())
                    while self.accept(','):
                        args.append(self.expr())
                self.expect(')')
                return ('call', v, args)
            return ('p1',) if v == 'P1' else ('var', v)
        raise HLError(f"line {ln}: unexpected {v!r} in expression")


# ----------------------------------------------------------------------
# Code generator
# ----------------------------------------------------------------------
CMP_JUMP = {'==': 'JEQ', '!=': 'JNE', '<': 'JLT', '>': 'JGT',
            '<=': 'JLE', '>=': 'JGE'}
ALU = {'+': '+', '-': '-', '&': '&', '|': '|'}


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


class Gen:
    def __init__(self, source, iters):
        self.src_lines = source.split('\n')
        self.iters = iters
        self.out = []
        self.n = 0
        self.vars = {}
        self.consts = dict(COLORS)
        self.next_var = VAR_BASE
        self.loops = []
        self.used = set()
        self.line = 0

    # ---- helpers ----
    def err(self, msg):
        raise HLError(f"line {self.line}: {msg}")

    def emit(self, *lines):
        self.out.extend(lines)

    def label(self, kind):
        self.n += 1
        return f"HL_{kind}{self.n}"

    def var_addr(self, name):
        if name not in self.vars:
            self.err(f"variable {name!r} is not declared (use: var {name};)")
        return self.vars[name]

    def fold(self, e):
        k = e[0]
        if k == 'var' and e[1] in self.consts:
            return ('num', self.consts[e[1]])
        if k == 'un':
            x = self.fold(e[2])
            if x[0] == 'num':
                v = x[1]
                if e[1] == '-':
                    return ('num', (-v) & 0xFFFF)
                if e[1] == '~':
                    return ('num', (~v) & 0xFFFF)
                return ('num', 0xFFFF if v == 0 else 0)
            return ('un', e[1], x)
        if k == 'bin':
            l, r = self.fold(e[2]), self.fold(e[3])
            if l[0] == 'num' and r[0] == 'num':
                a, b, op = l[1], r[1], e[1]
                sa, sb = s16(a), s16(b)
                if op == '+': return ('num', (a + b) & 0xFFFF)
                if op == '-': return ('num', (a - b) & 0xFFFF)
                if op == '*': return ('num', (a * b) & 0xFFFF)
                if op == '&': return ('num', a & b)
                if op == '|': return ('num', a | b)
                if op in ('/', '%'):
                    if sa < 0 or sb <= 0:
                        self.err("/ and % need a non-negative dividend and a positive divisor")
                    return ('num', (sa // sb) if op == '/' else (sa % sb))
                if op == '&&': return ('num', 0xFFFF if (a and b) else 0)
                if op == '||': return ('num', 0xFFFF if (a or b) else 0)
                res = {'==': sa == sb, '!=': sa != sb, '<': sa < sb,
                       '>': sa > sb, '<=': sa <= sb, '>=': sa >= sb}[op]
                return ('num', 0xFFFF if res else 0)
            return ('bin', e[1], l, r)
        if k == 'call':
            return ('call', e[1], [self.fold(a) for a in e[2]])
        return e

    def is_bool(self, e):
        return (e[0] == 'bin' and (e[1] in CMP_JUMP or e[1] in ('&&', '||'))) \
            or (e[0] == 'un' and e[1] == '!')

    def simple(self, e):
        """Operand that can be addressed directly: returns (lines, 'A'|'M') or None."""
        if e[0] == 'num' and e[1] <= 32767:
            return ([f"@{e[1]}"], 'A')
        if e[0] == 'var':
            return ([f"@{self.var_addr(e[1])}"], 'M')
        if e[0] == 'p1':
            return ([f"@{P1_ADDR}"], 'M')
        return None

    def temp(self, d):
        if d >= TEMP_MAX:
            self.err("expression is nested too deeply; split it using a variable")
        return TEMP_BASE + d

    def load_const(self, v):
        if v == 0: self.emit("D=0")
        elif v == 1: self.emit("D=1")
        elif v == 0xFFFF: self.emit("D=-1")
        elif v <= 32767: self.emit(f"@{v}", "D=A")
        else: self.emit(f"@{0xFFFF - v}", "D=!A")

    def bool_jump(self, jump):
        t, e = self.label('T'), self.label('E')
        self.emit(f"@{t}", f"D;{jump}", "D=0", f"@{e}", "0;JMP",
                  f"({t})", "D=-1", f"({e})")

    def call_lib(self, name):
        self.used.add(name)
        ret = self.label('ret')
        self.emit(f"@{ret}", "D=A", "@R14", "M=D",
                  f"@HL_{name}", "0;JMP", f"({ret})")

    # ---- expressions (result in D) ----
    def expr(self, e, d=0):
        e = self.fold(e)
        k = e[0]
        if k == 'num':
            self.load_const(e[1])
        elif k == 'var':
            self.emit(f"@{self.var_addr(e[1])}", "D=M")
        elif k == 'p1':
            self.emit(f"@{P1_ADDR}", "D=M")
        elif k == 'un':
            self.expr(e[2], d)
            if e[1] == '-': self.emit("D=-D")
            elif e[1] == '~': self.emit("D=!D")
            else: self.bool_jump('JEQ')
        elif k == 'call':
            if e[1] == 'adc' and len(e[2]) == 1:
                self.expr(e[2][0], d)
                self.emit("@R13", "M=D")
                self.call_lib('adc')
            elif e[1] == 'peek' and len(e[2]) == 1:
                self.expr(e[2][0], d)
                self.emit("A=D", "D=M")
            else:
                self.err(f"{e[1]}() cannot be used as a value here")
        elif k == 'bin':
            self.binary(e, d)

    def boolexpr(self, e, d):
        self.expr(e, d)
        if not self.is_bool(self.fold(e)):
            self.bool_jump('JNE')

    def combine(self, op, operand):
        if op in ALU:
            self.emit(f"D=D{ALU[op]}{operand}")
        else:                       # comparison
            self.emit(f"D=D-{operand}")
            self.bool_jump(CMP_JUMP[op])

    def binary(self, e, d):
        op, l, r = e[1], e[2], e[3]
        logical = op in ('&&', '||')
        if logical:
            gl = lambda dd: self.boolexpr(l, dd)
            gr = lambda dd: self.boolexpr(r, dd)
            alu_op = '&' if op == '&&' else '|'
            T = self.temp(d)
            gr(d)
            self.emit(f"@{T}", "M=D")
            gl(d + 1)
            self.emit(f"@{T}")
            self.combine(alu_op, 'M')
            return
        if op in ('*', '/', '%'):
            T = self.temp(d)
            self.expr(r, d)
            self.emit(f"@{T}", "M=D")
            self.expr(l, d + 1)
            self.emit("@R13", "M=D", f"@{T}", "D=M", "@R15", "M=D")
            self.call_lib('mul' if op == '*' else 'div')
            if op == '%':
                self.emit("@R12", "D=M")
            return
        sr = self.simple(r)
        if sr:                                     # right operand addressable
            self.expr(l, d)
            self.emit(*sr[0])
            self.combine(op, sr[1])
            return
        sl = self.simple(l)
        if sl and op in ('+', '&', '|', '==', '!='):    # commutative
            self.expr(r, d)
            self.emit(*sl[0])
            self.combine(op, sl[1])
            return
        T = self.temp(d)                            # general case
        self.expr(r, d)
        self.emit(f"@{T}", "M=D")
        self.expr(l, d + 1)
        self.emit(f"@{T}")
        self.combine(op, 'M')

    # ---- statements ----
    def note(self, ln):
        self.line = ln
        text = self.src_lines[ln - 1].strip() if ln - 1 < len(self.src_lines) else ''
        if text:
            self.emit(f"// {text}")

    def store(self, target, e):
        addr = P1_ADDR if target[0] == 'p1' else self.var_addr(target[1])
        self.store_addr(addr, e)

    def store_addr(self, addr, e):
        f = self.fold(e)
        if f[0] == 'num' and f[1] in (0, 1, 0xFFFF):
            self.emit(f"@{addr}", f"M={ {0: '0', 1: '1', 0xFFFF: '-1'}[f[1]] }")
        else:
            self.expr(f)
            self.emit(f"@{addr}", "M=D")

    def stmts(self, lst):
        for st in lst:
            self.stmt(st)

    def stmt(self, st):
        k, ln = st[0], st[1]
        if k in ('if', 'while'):
            self.note(ln)
        elif k != 'block':
            self.note(ln)
        self.line = ln
        if k == 'block':
            self.stmts(st[2])
        elif k == 'const':
            f = self.fold(st[3])
            if f[0] != 'num':
                self.err("const needs a constant value")
            self.consts[st[2]] = f[1]
        elif k == 'var':
            for name, init in st[2]:
                if name in self.vars or name in self.consts or name == 'P1':
                    self.err(f"{name!r} is already defined")
                self.vars[name] = self.next_var
                self.next_var += 1
                self.store(('var', name), init if init is not None else ('num', 0))
        elif k == 'assign':
            if st[2][0] == 'var' and st[2][1] in self.consts:
                self.err(f"{st[2][1]!r} is a const and cannot be changed")
            self.store(st[2], st[3])
        elif k == 'call':
            name, args = st[2], st[3]
            if name == 'delay' and len(args) == 1:
                self.expr(args[0])
                self.emit("@R13", "M=D")
                self.call_lib('delay')
            elif name == 'adc' and len(args) == 1:
                self.expr(('call', 'adc', args))      # value discarded
            elif name == 'gpu_on' and not args:
                self.store_addr(GPU_CTL, ('num', 1))
            elif name == 'clear' and not args:
                self.store_addr(GPU_CMD, ('num', CMD_CLEAR))
            elif name == 'pixel' and len(args) == 3:
                for addr, a in zip((GPU_X, GPU_Y, GPU_COLOR), args):
                    self.store_addr(addr, a)
                self.store_addr(GPU_CMD, ('num', CMD_PIXEL))
            elif name == 'fill' and len(args) == 5:
                for addr, a in zip((GPU_X, GPU_Y, GPU_X2, GPU_Y2, GPU_COLOR), args):
                    self.store_addr(addr, a)
                self.store_addr(GPU_CMD, ('num', CMD_FILL))
            elif name == 'poke' and len(args) == 2:
                T = self.temp(0)
                self.expr(args[1], 0)
                self.emit(f"@{T}", "M=D")
                self.expr(args[0], 1)
                self.emit("@R13", "M=D", f"@{T}", "D=M", "@R13", "A=M", "M=D")
            else:
                self.err(f"unknown function {name}() or wrong number of arguments")
        elif k == 'halt':
            self.emit("@HL_END", "0;JMP")
        elif k == 'break':
            if not self.loops: self.err("'break' outside a loop")
            self.emit(f"@{self.loops[-1][1]}", "0;JMP")
        elif k == 'continue':
            if not self.loops: self.err("'continue' outside a loop")
            self.emit(f"@{self.loops[-1][0]}", "0;JMP")
        elif k == 'if':
            c = self.fold(st[2])
            els, end = self.label('else'), self.label('endif')
            if c[0] == 'num':                      # constant condition
                self.stmts(st[3] if c[1] else (st[4] or []))
                return
            self.expr(c)
            self.emit(f"@{els}", "D;JEQ")
            self.stmts(st[3])
            if st[4]:
                self.emit(f"@{end}", "0;JMP")
            self.emit(f"({els})")
            if st[4]:
                self.stmts(st[4])
                self.emit(f"({end})")
        elif k == 'while':
            top, end = self.label('loop'), self.label('endloop')
            c = self.fold(st[2])
            self.emit(f"({top})")
            if c[0] == 'num' and c[1] == 0:
                self.emit(f"({end})")
                return
            if c[0] != 'num':
                self.expr(c)
                self.emit(f"@{end}", "D;JEQ")
            self.loops.append((top, end))
            self.stmts(st[3])
            self.loops.pop()
            self.emit(f"@{top}", "0;JMP", f"({end})")

    # ---- runtime library ----
    def library(self):
        lib = []
        if 'delay' in self.used:       # R13 = milliseconds (0..65535)
            lib += ["// --- delay(ms): ~1 ms per outer pass ---",
                    "(HL_delay)", "@R13", "D=M", "@HL_delay_end", "D;JEQ",
                    "(HL_delay_ms)", f"@{self.iters}", "D=A",
                    "(HL_delay_in)", "D=D-1", "@HL_delay_in", "D;JNE",
                    "@R13", "M=M-1", "D=M", "@HL_delay_ms", "D;JNE",
                    "(HL_delay_end)", "@R14", "A=M", "0;JMP"]
        if 'adc' in self.used:         # R13 = channel -> D = result
            lib += ["// --- adc(ch): start a conversion, wait, read ---",
                    "(HL_adc)", "@R13", "D=M", f"@{ADC_CH_ADDR}", "M=D",
                    "D=1", f"@{ADC_CTL_ADDR}", "M=D",
                    "(HL_adc_wait)", f"@{ADC_CTL_ADDR}", "D=M", "@2", "D=D&A",
                    "@HL_adc_wait", "D;JEQ",
                    f"@{ADC_DAT_ADDR}", "D=M", "@R14", "A=M", "0;JMP"]
        if 'mul' in self.used:         # R13 * R15 -> D (low 16 bits)
            lib += ["// --- multiply: shift-add over a 16-bit mask ---",
                    "(HL_mul)", "@R12", "M=0", "@R11", "M=1",
                    "(HL_mul_loop)", "@R15", "D=M", "@R11", "D=D&M",
                    "@HL_mul_skip", "D;JEQ", "@R13", "D=M", "@R12", "M=D+M",
                    "(HL_mul_skip)", "@R13", "D=M", "M=D+M",
                    "@R11", "D=M", "M=D+M", "D=M", "@HL_mul_loop", "D;JNE",
                    "@R12", "D=M", "@R14", "A=M", "0;JMP"]
        if 'div' in self.used:         # R13 / R15 -> D, remainder in R12
            lib += ["// --- divide: repeated subtraction (non-negative operands) ---",
                    "(HL_div)", "@R15", "D=M", "@HL_div_zero", "D;JLE",
                    "@R13", "D=M", "@R12", "M=D", "@R11", "M=0",
                    "(HL_div_loop)", "@R15", "D=M", "@R12", "D=M-D",
                    "@HL_div_done", "D;JLT", "@R12", "M=D", "@R11", "M=M+1",
                    "@HL_div_loop", "0;JMP",
                    "(HL_div_done)", "@R11", "D=M", "@R14", "A=M", "0;JMP",
                    "(HL_div_zero)", "@R12", "M=0", "D=0", "@R14", "A=M", "0;JMP"]
        return lib


def compile_source(source, iters=DEFAULT_ITERS):
    prog = Parser(lex(source)).program()
    g = Gen(source, iters)
    g.emit("// Generated by hl.py - HackL compiler")
    g.stmts(prog)
    g.emit("// --- end of program ---", "(HL_END)", "@HL_END", "0;JMP")
    g.emit(*g.library())
    return "\n".join(g.out) + "\n"


def main():
    ap = argparse.ArgumentParser(description="HackL -> Hack assembly")
    ap.add_argument("source")
    ap.add_argument("-o", "--output")
    ap.add_argument("--iters", type=int, default=DEFAULT_ITERS,
                    help="delay loop passes per millisecond (default %(default)s)")
    ap.add_argument("--hack", action="store_true",
                    help="also assemble to .hack using assembler.py")
    a = ap.parse_args()
    try:
        asm = compile_source(open(a.source).read(), a.iters)
    except HLError as ex:
        sys.exit(f"{a.source}: {ex}")
    out = a.output or os.path.splitext(a.source)[0] + ".asm"
    open(out, "w").write(asm)
    words = sum(1 for l in asm.split('\n')
                if l.strip() and not l.startswith('//') and not l.startswith('('))
    print(f"wrote {out}  ({words} instructions)")
    if a.hack:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from assembler import Assembler
        hack = os.path.splitext(out)[0] + ".hack"
        Assembler(out, hack).assemble()
        print(f"wrote {hack}")


if __name__ == "__main__":
    main()
