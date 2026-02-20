#!/usr/bin/env python3
"""
rv32i_asm.py — Minimal RV32I Assembler
Outputs hex file compatible with $readmemh.

Usage: python3 rv32i_asm.py input.s -o output.hex

Supports: All RV32I instructions, labels, basic pseudo-instructions (li, mv, nop, j, ret, call).
Comments with # or //
"""

import sys
import re
import argparse

# ============================================================================
# Register name mapping
# ============================================================================
REG_MAP = {f'x{i}': i for i in range(32)}
REG_MAP.update({
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    'fp': 8, 's0': 8,
    't0': 5, 't1': 6, 't2': 7, 't3': 28, 't4': 29, 't5': 30, 't6': 31,
    's1': 9, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13,
    'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
})


def reg(name):
    """Parse register name to number."""
    name = name.strip().lower()
    if name in REG_MAP:
        return REG_MAP[name]
    raise ValueError(f"Unknown register: {name}")


def imm(value, bits, signed=True):
    """Parse immediate, check range."""
    if isinstance(value, str):
        value = value.strip()
        if value.startswith('0x') or value.startswith('0X'):
            v = int(value, 16)
        elif value.startswith('0b') or value.startswith('0B'):
            v = int(value, 2)
        else:
            v = int(value)
    else:
        v = int(value)

    if signed:
        lo = -(1 << (bits - 1))
        hi = (1 << (bits - 1)) - 1
    else:
        lo = 0
        hi = (1 << bits) - 1

    if not (lo <= v <= hi):
        raise ValueError(f"Immediate {v} out of range [{lo}, {hi}] for {bits}-bit field")

    return v & ((1 << bits) - 1)


# ============================================================================
# Instruction encoders
# ============================================================================
def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(imm12, rs2, rs1, funct3, opcode):
    imm_val = imm12 & 0xFFF
    return ((imm_val >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm_val & 0x1F) << 7) | opcode


def encode_b(imm13, rs2, rs1, funct3, opcode):
    """B-type: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode"""
    v = imm13 & 0x1FFF
    b12 = (v >> 12) & 1
    b11 = (v >> 11) & 1
    b10_5 = (v >> 5) & 0x3F
    b4_1 = (v >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


def encode_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def encode_j(imm21, rd, opcode):
    """J-type: imm[20|10:1|11|19:12] rd opcode"""
    v = imm21 & 0x1FFFFF
    b20 = (v >> 20) & 1
    b19_12 = (v >> 12) & 0xFF
    b11 = (v >> 11) & 1
    b10_1 = (v >> 1) & 0x3FF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | opcode


# ============================================================================
# Assembler
# ============================================================================
class Assembler:
    def __init__(self):
        self.labels = {}
        self.instructions = []  # list of (addr, line_text)
        self.output = []

    def parse_line(self, line):
        """Strip comments, return label (if any) and instruction."""
        # Remove comments
        line = re.sub(r'(//|#).*', '', line).strip()
        if not line:
            return None, None

        label = None
        if ':' in line:
            parts = line.split(':', 1)
            label = parts[0].strip()
            line = parts[1].strip()

        return label, line if line else None

    def first_pass(self, lines):
        """Collect labels and instructions."""
        addr = 0
        for raw_line in lines:
            label, instr = self.parse_line(raw_line)
            if label:
                self.labels[label] = addr

            if instr:
                # Expand pseudo-instructions
                expanded = self.expand_pseudo(instr, addr)
                for exp in expanded:
                    self.instructions.append((addr, exp))
                    addr += 4

    def expand_pseudo(self, instr, addr):
        """Expand pseudo-instructions into real instructions."""
        parts = re.split(r'[,\s]+', instr.strip())
        parts = [p for p in parts if p]  # remove empty
        mnemonic = parts[0].lower()

        if mnemonic == 'nop':
            return ['addi x0, x0, 0']
        elif mnemonic == 'mv':
            return [f'addi {parts[1]}, {parts[2]}, 0']
        elif mnemonic == 'li':
            rd = parts[1].rstrip(',')
            val_str = parts[2]
            val = int(val_str, 0)
            if -2048 <= val <= 2047:
                return [f'addi {rd}, x0, {val}']
            else:
                upper = (val + 0x800) >> 12
                lower = val - (upper << 12)
                result = [f'lui {rd}, {upper}']
                if lower != 0:
                    result.append(f'addi {rd}, {rd}, {lower}')
                return result
        elif mnemonic == 'j':
            return [f'jal x0, {parts[1]}']
        elif mnemonic == 'jr':
            return [f'jalr x0, {parts[1]}, 0']
        elif mnemonic == 'ret':
            return ['jalr x0, ra, 0']
        elif mnemonic == 'call':
            return [f'jal ra, {parts[1]}']
        elif mnemonic == 'not':
            return [f'xori {parts[1]}, {parts[2]}, -1']
        elif mnemonic == 'neg':
            return [f'sub {parts[1]}, x0, {parts[2]}']
        elif mnemonic == 'beqz':
            return [f'beq {parts[1]}, x0, {parts[2]}']
        elif mnemonic == 'bnez':
            return [f'bne {parts[1]}, x0, {parts[2]}']
        elif mnemonic == 'blez':
            return [f'bge x0, {parts[1]}, {parts[2]}']
        elif mnemonic == 'bgez':
            return [f'bge {parts[1]}, x0, {parts[2]}']
        elif mnemonic == 'bltz':
            return [f'blt {parts[1]}, x0, {parts[2]}']
        elif mnemonic == 'bgtz':
            return [f'blt x0, {parts[1]}, {parts[2]}']
        elif mnemonic == 'seqz':
            return [f'sltiu {parts[1]}, {parts[2]}, 1']
        elif mnemonic == 'snez':
            return [f'sltu {parts[1]}, x0, {parts[2]}']
        else:
            return [instr]

    def resolve_imm(self, token, current_addr, bits, relative=False):
        """Resolve immediate or label reference."""
        token = token.strip()
        if token in self.labels:
            val = self.labels[token]
            if relative:
                val = val - current_addr
            return val & ((1 << bits) - 1)
        else:
            return imm(token, bits)

    def assemble_instruction(self, addr, instr):
        """Assemble a single instruction to a 32-bit word."""
        # Parse: handle offset(reg) syntax for loads/stores
        # e.g., "lw x1, 0(x2)" or "sw x1, 4(x2)"
        load_store_match = re.match(
            r'(\w+)\s+(\w+)\s*,\s*(-?\w+)\s*\(\s*(\w+)\s*\)', instr)
        parts = re.split(r'[,\s]+', instr.strip())
        parts = [p for p in parts if p]
        mnemonic = parts[0].lower()

        # R-type
        r_type = {
            'add':  (0b0000000, 0b000), 'sub':  (0b0100000, 0b000),
            'sll':  (0b0000000, 0b001), 'slt':  (0b0000000, 0b010),
            'sltu': (0b0000000, 0b011), 'xor':  (0b0000000, 0b100),
            'srl':  (0b0000000, 0b101), 'sra':  (0b0100000, 0b101),
            'or':   (0b0000000, 0b110), 'and':  (0b0000000, 0b111),
        }

        if mnemonic in r_type:
            f7, f3 = r_type[mnemonic]
            return encode_r(f7, reg(parts[3]), reg(parts[2]), f3, reg(parts[1]), 0b0110011)

        # I-type ALU
        i_alu = {
            'addi': 0b000, 'slti': 0b010, 'sltiu': 0b011,
            'xori': 0b100, 'ori': 0b110, 'andi': 0b111,
        }
        if mnemonic in i_alu:
            f3 = i_alu[mnemonic]
            imm_val = self.resolve_imm(parts[3], addr, 12)
            return encode_i(imm_val, reg(parts[2]), f3, reg(parts[1]), 0b0010011)

        # I-type shifts
        if mnemonic in ('slli', 'srli', 'srai'):
            shamt = int(parts[3], 0) & 0x1F
            if mnemonic == 'slli':
                return encode_r(0b0000000, shamt, reg(parts[2]), 0b001, reg(parts[1]), 0b0010011)
            elif mnemonic == 'srli':
                return encode_r(0b0000000, shamt, reg(parts[2]), 0b101, reg(parts[1]), 0b0010011)
            elif mnemonic == 'srai':
                return encode_r(0b0100000, shamt, reg(parts[2]), 0b101, reg(parts[1]), 0b0010011)

        # Loads: lw rd, offset(rs1)
        load_ops = {'lb': 0b000, 'lh': 0b001, 'lw': 0b010, 'lbu': 0b100, 'lhu': 0b101}
        if mnemonic in load_ops and load_store_match:
            f3 = load_ops[mnemonic]
            rd = reg(load_store_match.group(2))
            offset = self.resolve_imm(load_store_match.group(3), addr, 12)
            rs1 = reg(load_store_match.group(4))
            return encode_i(offset, rs1, f3, rd, 0b0000011)

        # Stores: sw rs2, offset(rs1)
        store_ops = {'sb': 0b000, 'sh': 0b001, 'sw': 0b010}
        if mnemonic in store_ops and load_store_match:
            f3 = store_ops[mnemonic]
            rs2 = reg(load_store_match.group(2))
            offset = self.resolve_imm(load_store_match.group(3), addr, 12)
            rs1 = reg(load_store_match.group(4))
            return encode_s(offset, rs2, rs1, f3, 0b0100011)

        # Branches
        br_ops = {
            'beq': 0b000, 'bne': 0b001, 'blt': 0b100,
            'bge': 0b101, 'bltu': 0b110, 'bgeu': 0b111,
        }
        if mnemonic in br_ops:
            f3 = br_ops[mnemonic]
            offset = self.resolve_imm(parts[3], addr, 13, relative=True)
            return encode_b(offset, reg(parts[2]), reg(parts[1]), f3, 0b1100011)

        # JAL
        if mnemonic == 'jal':
            rd = reg(parts[1])
            offset = self.resolve_imm(parts[2], addr, 21, relative=True)
            return encode_j(offset, rd, 0b1101111)

        # JALR
        if mnemonic == 'jalr':
            if load_store_match:
                rd = reg(load_store_match.group(2))
                offset = self.resolve_imm(load_store_match.group(3), addr, 12)
                rs1 = reg(load_store_match.group(4))
                return encode_i(offset, rs1, 0b000, rd, 0b1100111)
            else:
                # jalr rd, rs1, imm
                rd = reg(parts[1])
                rs1 = reg(parts[2])
                offset = self.resolve_imm(parts[3], addr, 12) if len(parts) > 3 else 0
                return encode_i(offset, rs1, 0b000, rd, 0b1100111)

        # LUI
        if mnemonic == 'lui':
            rd = reg(parts[1])
            imm_val = int(parts[2], 0) & 0xFFFFF
            return encode_u(imm_val, rd, 0b0110111)

        # AUIPC
        if mnemonic == 'auipc':
            rd = reg(parts[1])
            imm_val = int(parts[2], 0) & 0xFFFFF
            return encode_u(imm_val, rd, 0b0010111)

        # ECALL / EBREAK
        if mnemonic == 'ecall':
            return encode_i(0, 0, 0, 0, 0b1110011)
        if mnemonic == 'ebreak':
            return encode_i(1, 0, 0, 0, 0b1110011)

        # FENCE
        if mnemonic == 'fence':
            return encode_i(0, 0, 0, 0, 0b0001111)

        raise ValueError(f"Unknown instruction: {instr}")

    def assemble(self, lines):
        """Two-pass assembly."""
        self.first_pass(lines)
        self.output = []
        for addr, instr in self.instructions:
            word = self.assemble_instruction(addr, instr)
            self.output.append(word)
        return self.output

    def to_hex(self):
        """Output in $readmemh format."""
        lines = []
        for word in self.output:
            lines.append(f'{word:08x}')
        return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description='RV32I Assembler')
    parser.add_argument('input', help='Input assembly file')
    parser.add_argument('-o', '--output', default='program.hex', help='Output hex file')
    args = parser.parse_args()

    with open(args.input, 'r') as f:
        lines = f.readlines()

    asm = Assembler()
    try:
        asm.assemble(lines)
    except Exception as e:
        print(f"Assembly error: {e}", file=sys.stderr)
        sys.exit(1)

    with open(args.output, 'w') as f:
        f.write(asm.to_hex())

    print(f"Assembled {len(asm.output)} instructions -> {args.output}")
    if asm.labels:
        print("Labels:")
        for name, addr in sorted(asm.labels.items(), key=lambda x: x[1]):
            print(f"  {name}: 0x{addr:08x}")


if __name__ == '__main__':
    main()
