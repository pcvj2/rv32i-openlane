#!/usr/bin/env python3
"""
rv32i_random_test.py — Constrained Random Test Generator for RV32I

Generates random but legal RV32I programs, runs them through a Python
reference model, then compares against RTL simulation register dumps.

Usage:
    python3 rv32i_random_test.py [--num-tests 100] [--num-instr 50] [--seed 42]

Flow:
    1. Generate random program → program.hex
    2. Generate expected register state → expected_regs.txt
    3. RTL simulation dumps actual registers → actual_regs.txt
    4. Compare and report
"""

import random
import struct
import argparse
import subprocess
import sys
import os

# =============================================================================
# RV32I Reference Model
# =============================================================================

class RV32IModel:
    """Simple RV32I ISA simulator for reference checking."""

    def __init__(self, mem_size=65536):
        self.regs = [0] * 32
        self.pc = 0
        # Initialize memory with NOP (0x00000013) to match RTL memory model
        self.mem = bytearray(mem_size)
        for i in range(0, mem_size, 4):
            struct.pack_into('<I', self.mem, i, 0x00000013)
        self.mem_size = mem_size
        self.halted = False

    def load_hex(self, words):
        """Load list of 32-bit words into memory starting at address 0."""
        for i, w in enumerate(words):
            addr = i * 4
            if addr + 4 <= self.mem_size:
                struct.pack_into('<I', self.mem, addr, w & 0xFFFFFFFF)

    def read_word(self, addr):
        addr = addr & 0xFFFFFFFF
        if addr + 4 > self.mem_size:
            return 0x00000013  # NOP
        return struct.unpack_from('<I', self.mem, addr)[0]

    def write_byte(self, addr, val):
        if addr < self.mem_size:
            self.mem[addr] = val & 0xFF

    def read_byte(self, addr):
        if addr < self.mem_size:
            return self.mem[addr]
        return 0

    def set_reg(self, rd, val):
        if rd != 0:
            self.regs[rd] = val & 0xFFFFFFFF

    def get_reg(self, rs):
        if rs == 0:
            return 0
        return self.regs[rs]

    def sext(self, val, bits):
        """Sign-extend a value from 'bits' width to 32 bits."""
        if val & (1 << (bits - 1)):
            val |= ~((1 << bits) - 1)
        return val & 0xFFFFFFFF

    def to_signed(self, val):
        """Convert unsigned 32-bit to signed Python int."""
        val = val & 0xFFFFFFFF
        if val & 0x80000000:
            return val - 0x100000000
        return val

    def step(self):
        """Execute one instruction. Returns False if halted."""
        if self.halted:
            return False

        instr = self.read_word(self.pc)
        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F

        # Immediate extraction
        imm_i = self.sext(instr >> 20, 12)
        imm_s = self.sext(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = self.sext(
            (((instr >> 31) & 1) << 12) |
            (((instr >> 7) & 1) << 11) |
            (((instr >> 25) & 0x3F) << 5) |
            (((instr >> 8) & 0xF) << 1), 13)
        imm_u = instr & 0xFFFFF000
        imm_j = self.sext(
            (((instr >> 31) & 1) << 20) |
            (((instr >> 12) & 0xFF) << 12) |
            (((instr >> 20) & 1) << 11) |
            (((instr >> 21) & 0x3FF) << 1), 21)

        rs1_val = self.get_reg(rs1)
        rs2_val = self.get_reg(rs2)
        next_pc = self.pc + 4

        if opcode == 0b0110111:  # LUI
            self.set_reg(rd, imm_u)

        elif opcode == 0b0010111:  # AUIPC
            self.set_reg(rd, (self.pc + imm_u) & 0xFFFFFFFF)

        elif opcode == 0b1101111:  # JAL
            self.set_reg(rd, self.pc + 4)
            next_pc = (self.pc + self.to_signed(imm_j)) & 0xFFFFFFFF

        elif opcode == 0b1100111:  # JALR
            target = (rs1_val + self.to_signed(imm_i)) & 0xFFFFFFFE
            self.set_reg(rd, self.pc + 4)
            next_pc = target

        elif opcode == 0b1100011:  # Branches
            taken = False
            s1 = self.to_signed(rs1_val)
            s2 = self.to_signed(rs2_val)
            if funct3 == 0b000:    taken = rs1_val == rs2_val       # BEQ
            elif funct3 == 0b001:  taken = rs1_val != rs2_val       # BNE
            elif funct3 == 0b100:  taken = s1 < s2                  # BLT
            elif funct3 == 0b101:  taken = s1 >= s2                 # BGE
            elif funct3 == 0b110:  taken = rs1_val < rs2_val        # BLTU
            elif funct3 == 0b111:  taken = rs1_val >= rs2_val       # BGEU
            if taken:
                next_pc = (self.pc + self.to_signed(imm_b)) & 0xFFFFFFFF

        elif opcode == 0b0000011:  # Loads
            addr = (rs1_val + self.to_signed(imm_i)) & 0xFFFFFFFF
            if funct3 == 0b010:  # LW
                val = 0
                for i in range(4):
                    val |= self.read_byte((addr + i) & 0xFFFFFFFF) << (i * 8)
                self.set_reg(rd, val)
            elif funct3 == 0b001:  # LH
                val = self.read_byte(addr) | (self.read_byte(addr + 1) << 8)
                self.set_reg(rd, self.sext(val, 16))
            elif funct3 == 0b000:  # LB
                val = self.read_byte(addr)
                self.set_reg(rd, self.sext(val, 8))
            elif funct3 == 0b101:  # LHU
                val = self.read_byte(addr) | (self.read_byte(addr + 1) << 8)
                self.set_reg(rd, val)
            elif funct3 == 0b100:  # LBU
                val = self.read_byte(addr)
                self.set_reg(rd, val)

        elif opcode == 0b0100011:  # Stores
            addr = (rs1_val + self.to_signed(imm_s)) & 0xFFFFFFFF
            # Check for halt signal
            if addr == 0xFFFFFFF0:
                self.halted = True
                self.pc = next_pc
                return False
            if funct3 == 0b010:  # SW
                for i in range(4):
                    self.write_byte((addr + i) & 0xFFFFFFFF, (rs2_val >> (i * 8)) & 0xFF)
            elif funct3 == 0b001:  # SH
                self.write_byte(addr, rs2_val & 0xFF)
                self.write_byte(addr + 1, (rs2_val >> 8) & 0xFF)
            elif funct3 == 0b000:  # SB
                self.write_byte(addr, rs2_val & 0xFF)

        elif opcode == 0b0010011:  # I-type ALU
            iv = self.to_signed(imm_i)
            ivu = imm_i & 0xFFFFFFFF
            shamt = (instr >> 20) & 0x1F
            if funct3 == 0b000:    self.set_reg(rd, (self.to_signed(rs1_val) + iv))      # ADDI
            elif funct3 == 0b010:  self.set_reg(rd, 1 if self.to_signed(rs1_val) < iv else 0)  # SLTI
            elif funct3 == 0b011:  self.set_reg(rd, 1 if rs1_val < ivu else 0)            # SLTIU
            elif funct3 == 0b100:  self.set_reg(rd, rs1_val ^ ivu)                        # XORI
            elif funct3 == 0b110:  self.set_reg(rd, rs1_val | ivu)                        # ORI
            elif funct3 == 0b111:  self.set_reg(rd, rs1_val & ivu)                        # ANDI
            elif funct3 == 0b001:  self.set_reg(rd, rs1_val << shamt)                     # SLLI
            elif funct3 == 0b101:
                if funct7 & 0x20:
                    self.set_reg(rd, self.to_signed(rs1_val) >> shamt)                    # SRAI
                else:
                    self.set_reg(rd, rs1_val >> shamt)                                    # SRLI

        elif opcode == 0b0110011:  # R-type ALU
            s1 = self.to_signed(rs1_val)
            s2 = self.to_signed(rs2_val)
            if funct3 == 0b000:
                if funct7 & 0x20:
                    self.set_reg(rd, s1 - s2)       # SUB
                else:
                    self.set_reg(rd, s1 + s2)       # ADD
            elif funct3 == 0b001:  self.set_reg(rd, rs1_val << (rs2_val & 0x1F))          # SLL
            elif funct3 == 0b010:  self.set_reg(rd, 1 if s1 < s2 else 0)                  # SLT
            elif funct3 == 0b011:  self.set_reg(rd, 1 if rs1_val < rs2_val else 0)        # SLTU
            elif funct3 == 0b100:  self.set_reg(rd, rs1_val ^ rs2_val)                    # XOR
            elif funct3 == 0b101:
                if funct7 & 0x20:
                    self.set_reg(rd, s1 >> (rs2_val & 0x1F))                              # SRA
                else:
                    self.set_reg(rd, rs1_val >> (rs2_val & 0x1F))                         # SRL
            elif funct3 == 0b110:  self.set_reg(rd, rs1_val | rs2_val)                    # OR
            elif funct3 == 0b111:  self.set_reg(rd, rs1_val & rs2_val)                    # AND

        elif opcode == 0b0001111:  # FENCE — NOP
            pass
        elif opcode == 0b1110011:  # ECALL/EBREAK — NOP
            pass

        # Ensure x0 stays 0
        self.regs[0] = 0
        # Mask all regs to 32 bits
        for i in range(32):
            self.regs[i] = self.regs[i] & 0xFFFFFFFF

        self.pc = next_pc & 0xFFFFFFFF
        return True

    def run(self, max_cycles=10000):
        """Run until halt or timeout."""
        for _ in range(max_cycles):
            if not self.step():
                return True  # halted normally
        return False  # timeout


# =============================================================================
# Constrained Random Program Generator
# =============================================================================

# Data memory region: 0x2000-0x3FFC (8 KB region, word-aligned base)
DATA_BASE = 0x2000
DATA_SIZE = 0x2000  # 8 KB

def encode_r(funct7, rs2, rs1, funct3, rd, opcode=0b0110011):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s(imm12, rs2, rs1, funct3, opcode=0b0100011):
    v = imm12 & 0xFFF
    return ((v >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((v & 0x1F) << 7) | opcode

def encode_b(imm13, rs2, rs1, funct3, opcode=0b1100011):
    v = imm13 & 0x1FFF
    return (((v >> 12) & 1) << 31) | (((v >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (funct3 << 12) | (((v >> 1) & 0xF) << 8) | (((v >> 11) & 1) << 7) | opcode

def encode_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

def encode_j(imm21, rd, opcode=0b1101111):
    v = imm21 & 0x1FFFFF
    return (((v >> 20) & 1) << 31) | (((v >> 1) & 0x3FF) << 21) | (((v >> 11) & 1) << 20) | \
           (((v >> 12) & 0xFF) << 12) | (rd << 7) | opcode


class RandomProgramGen:
    """Generate constrained random RV32I programs."""

    def __init__(self, num_instr=50, seed=None):
        self.num_instr = num_instr
        self.rng = random.Random(seed)
        self.words = []

        # Available registers for random ops (avoid x0, x1 used for base addr, x31 for halt)
        self.gp_regs = list(range(2, 31))

    def rand_reg(self):
        return self.rng.choice(self.gp_regs)

    def rand_rd(self):
        """Random destination register (never x0)."""
        return self.rng.choice(self.gp_regs)

    def rand_imm12(self):
        return self.rng.randint(-2048, 2047) & 0xFFF

    def rand_small_imm(self):
        """Small immediate for offsets."""
        return self.rng.randint(-64, 63) & 0xFFF

    def rand_shamt(self):
        return self.rng.randint(0, 31)

    def gen_r_type(self):
        """Random R-type instruction."""
        ops = [
            (0b0000000, 0b000),  # ADD
            (0b0100000, 0b000),  # SUB
            (0b0000000, 0b001),  # SLL
            (0b0000000, 0b010),  # SLT
            (0b0000000, 0b011),  # SLTU
            (0b0000000, 0b100),  # XOR
            (0b0000000, 0b101),  # SRL
            (0b0100000, 0b101),  # SRA
            (0b0000000, 0b110),  # OR
            (0b0000000, 0b111),  # AND
        ]
        f7, f3 = self.rng.choice(ops)
        return encode_r(f7, self.rand_reg(), self.rand_reg(), f3, self.rand_rd())

    def gen_i_alu(self):
        """Random I-type ALU instruction."""
        f3 = self.rng.choice([0b000, 0b010, 0b011, 0b100, 0b110, 0b111])  # ADDI..ANDI
        return encode_i(self.rand_imm12(), self.rand_reg(), f3, self.rand_rd(), 0b0010011)

    def gen_i_shift(self):
        """Random shift-immediate instruction."""
        shamt = self.rand_shamt()
        choice = self.rng.randint(0, 2)
        if choice == 0:   # SLLI
            return encode_r(0b0000000, shamt, self.rand_reg(), 0b001, self.rand_rd(), 0b0010011)
        elif choice == 1:  # SRLI
            return encode_r(0b0000000, shamt, self.rand_reg(), 0b101, self.rand_rd(), 0b0010011)
        else:              # SRAI
            return encode_r(0b0100000, shamt, self.rand_reg(), 0b101, self.rand_rd(), 0b0010011)

    def gen_lui(self):
        """Random LUI."""
        return encode_u(self.rng.randint(0, 0xFFFFF), self.rand_rd(), 0b0110111)

    def gen_auipc(self):
        """Random AUIPC."""
        return encode_u(self.rng.randint(0, 0xFFFFF), self.rand_rd(), 0b0010111)

    def gen_load(self):
        """Random load from data region. Uses x1 as base pointer."""
        # Offset within data region, aligned appropriately
        f3 = self.rng.choice([0b000, 0b001, 0b010, 0b100, 0b101])  # LB/LH/LW/LBU/LHU
        if f3 == 0b010:    # LW — word aligned
            offset = self.rng.randrange(0, DATA_SIZE - 4, 4)
        elif f3 in (0b001, 0b101):  # LH/LHU — half aligned
            offset = self.rng.randrange(0, DATA_SIZE - 2, 2)
        else:               # LB/LBU
            offset = self.rng.randint(0, DATA_SIZE - 1)
        return encode_i(offset & 0xFFF, 1, f3, self.rand_rd(), 0b0000011)  # rs1=x1 (base)

    def gen_store(self):
        """Random store to data region. Uses x1 as base pointer."""
        f3 = self.rng.choice([0b000, 0b001, 0b010])  # SB/SH/SW
        if f3 == 0b010:
            offset = self.rng.randrange(0, DATA_SIZE - 4, 4)
        elif f3 == 0b001:
            offset = self.rng.randrange(0, DATA_SIZE - 2, 2)
        else:
            offset = self.rng.randint(0, DATA_SIZE - 1)
        return encode_s(offset & 0xFFF, self.rand_reg(), 1, f3)  # rs1=x1 (base)

    def gen_branch(self, current_idx, total_instr):
        """Random branch with bounded forward target (no backward to avoid loops)."""
        f3 = self.rng.choice([0b000, 0b001, 0b100, 0b101, 0b110, 0b111])
        # Branch forward by 4 to 20 instructions (skip 1-5 instrs)
        max_skip = min(5, total_instr - current_idx - 2)
        if max_skip < 1:
            max_skip = 1
        skip = self.rng.randint(1, max_skip)
        offset = skip * 4  # always positive, always aligned
        return encode_b(offset & 0x1FFF, self.rand_reg(), self.rand_reg(), f3)

    def generate(self):
        """Generate a complete random test program."""
        self.words = []

        # Preamble: set up x1 as data base pointer
        # LUI x1, (DATA_BASE >> 12)
        self.words.append(encode_u(DATA_BASE >> 12, 1, 0b0110111))
        # ADDI x1, x1, (DATA_BASE & 0xFFF)
        self.words.append(encode_i(DATA_BASE & 0xFFF, 1, 0b000, 1, 0b0010011))

        # Seed some registers with interesting values
        seed_values = [0, 1, -1, 0x7FFFFFFF, 0x80000000, 0xFF, 0xDEAD, 42]
        for i, r in enumerate(range(2, min(10, 31))):
            val = self.rng.choice(seed_values) if i < len(seed_values) else self.rng.randint(-2048, 2047)
            self.words.append(encode_i(val & 0xFFF, 0, 0b000, r, 0b0010011))  # ADDI rd, x0, imm

        preamble_len = len(self.words)

        # Weighted instruction mix
        generators = [
            (self.gen_r_type,  30),   # R-type: 30%
            (self.gen_i_alu,   20),   # I-type ALU: 20%
            (self.gen_i_shift, 10),   # Shifts: 10%
            (self.gen_load,    12),   # Loads: 12%
            (self.gen_store,   10),   # Stores: 10%
            (self.gen_lui,      5),   # LUI: 5%
            (self.gen_auipc,    3),   # AUIPC: 3%
            (None,             10),   # Branch: 10% (special)
        ]

        # Build weight table
        choices = []
        weights = []
        for gen, w in generators:
            choices.append(gen)
            weights.append(w)

        for i in range(self.num_instr):
            gen = self.rng.choices(choices, weights=weights, k=1)[0]
            if gen is None:
                # Branch instruction
                instr = self.gen_branch(preamble_len + i, preamble_len + self.num_instr)
            else:
                instr = gen()
            self.words.append(instr)

        # Epilogue: signal halt by writing 1 to 0xFFFFFFF0
        # ADDI x31, x0, -16  (x31 = 0xFFFFFFF0)
        self.words.append(encode_i((-16) & 0xFFF, 0, 0b000, 31, 0b0010011))
        # ADDI x30, x0, 1
        self.words.append(encode_i(1, 0, 0b000, 30, 0b0010011))
        # SW x30, 0(x31)
        self.words.append(encode_s(0, 30, 31, 0b010))
        # Infinite loop (just in case)
        # JAL x0, 0 (jump to self)
        self.words.append(encode_j(0, 0))

        return self.words

    def to_hex(self):
        """Output as $readmemh format."""
        return '\n'.join(f'{w & 0xFFFFFFFF:08x}' for w in self.words) + '\n'


# =============================================================================
# Runner
# =============================================================================

def run_reference(words, max_cycles=10000):
    """Run program through Python reference model, return register state."""
    model = RV32IModel()
    model.load_hex(words)
    completed = model.run(max_cycles)
    return model.regs, completed


def run_rtl(hex_file, sim_dir, max_cycles=10000):
    """Run RTL simulation, parse register dump, return register state."""
    # Run simulation
    result = subprocess.run(
        ['vvp', os.path.join(sim_dir, 'rv32i_sim')],
        capture_output=True, text=True, cwd=sim_dir, timeout=60
    )

    # Parse register dump from stdout
    regs = [0] * 32
    for line in result.stdout.split('\n'):
        if line.startswith('REGDUMP'):
            # Format: REGDUMP x<n> <hex_value>
            parts = line.split()
            if len(parts) == 3:
                rnum = int(parts[1][1:])  # strip 'x'
                rval = int(parts[2], 16)
                regs[rnum] = rval

    passed = '*** PASS ***' in result.stdout
    timeout = '*** TIMEOUT ***' in result.stdout

    return regs, passed, timeout, result.stdout


def compare_regs(ref_regs, rtl_regs):
    """Compare register state, return list of mismatches."""
    mismatches = []
    for i in range(32):
        ref = ref_regs[i] & 0xFFFFFFFF
        rtl = rtl_regs[i] & 0xFFFFFFFF
        if ref != rtl:
            mismatches.append((i, ref, rtl))
    return mismatches


def main():
    parser = argparse.ArgumentParser(description='RV32I Constrained Random Tester')
    parser.add_argument('--num-tests', type=int, default=100, help='Number of random tests')
    parser.add_argument('--num-instr', type=int, default=50, help='Instructions per test')
    parser.add_argument('--seed', type=int, default=None, help='Random seed (None for random)')
    parser.add_argument('--sim-dir', default='.', help='Simulation directory')
    parser.add_argument('--max-cycles', type=int, default=5000, help='Max simulation cycles')
    parser.add_argument('--verbose', '-v', action='store_true', help='Print each test result')
    parser.add_argument('--save-failing', action='store_true', help='Save failing hex files')
    args = parser.parse_args()

    sim_dir = os.path.abspath(args.sim_dir)

    # Verify simulation binary exists
    sim_bin = os.path.join(sim_dir, 'rv32i_sim')
    if not os.path.exists(sim_bin):
        print(f"ERROR: Simulation binary not found at {sim_bin}")
        print(f"Run 'make sim' in {sim_dir} first.")
        sys.exit(1)

    base_seed = args.seed if args.seed is not None else random.randint(0, 2**32 - 1)
    print(f"Random test: {args.num_tests} tests, {args.num_instr} instructions each, base seed={base_seed}")
    print()

    passed = 0
    failed = 0
    timeouts = 0
    errors = 0

    for t in range(args.num_tests):
        test_seed = base_seed + t
        gen = RandomProgramGen(num_instr=args.num_instr, seed=test_seed)
        words = gen.generate()

        # Run reference model
        ref_regs, ref_completed = run_reference(words, max_cycles=args.max_cycles)

        if not ref_completed:
            if args.verbose:
                print(f"  Test {t:4d} [seed={test_seed}]: REF TIMEOUT — skipping")
            timeouts += 1
            continue

        # Write hex and run RTL
        hex_path = os.path.join(sim_dir, 'program.hex')
        with open(hex_path, 'w') as f:
            f.write(gen.to_hex())

        try:
            rtl_regs, rtl_passed, rtl_timeout, stdout = run_rtl(hex_path, sim_dir, args.max_cycles)
        except subprocess.TimeoutExpired:
            if args.verbose:
                print(f"  Test {t:4d} [seed={test_seed}]: RTL TIMEOUT")
            timeouts += 1
            continue
        except Exception as e:
            if args.verbose:
                print(f"  Test {t:4d} [seed={test_seed}]: ERROR — {e}")
            errors += 1
            continue

        if rtl_timeout:
            if args.verbose:
                print(f"  Test {t:4d} [seed={test_seed}]: RTL TIMEOUT")
            timeouts += 1
            continue

        # Compare registers
        mismatches = compare_regs(ref_regs, rtl_regs)

        if len(mismatches) == 0:
            passed += 1
            if args.verbose:
                print(f"  Test {t:4d} [seed={test_seed}]: PASS")
        else:
            failed += 1
            print(f"  Test {t:4d} [seed={test_seed}]: FAIL — {len(mismatches)} register mismatches:")
            for rnum, ref_val, rtl_val in mismatches:
                print(f"    x{rnum}: ref=0x{ref_val:08x} rtl=0x{rtl_val:08x}")

            if args.save_failing:
                fail_path = os.path.join(sim_dir, f'fail_seed{test_seed}.hex')
                with open(fail_path, 'w') as f:
                    f.write(gen.to_hex())
                print(f"    Saved to {fail_path}")

    # Summary
    total = passed + failed + timeouts + errors
    print()
    print("=" * 50)
    print(f"  CONSTRAINED RANDOM TEST RESULTS")
    print(f"  Base seed: {base_seed}")
    print("=" * 50)
    print(f"  Tests run:  {total}")
    print(f"  Passed:     {passed}")
    print(f"  Failed:     {failed}")
    print(f"  Timeouts:   {timeouts}")
    print(f"  Errors:     {errors}")
    if total > 0:
        print(f"  Pass rate:  {passed * 100 // total}%")
    print("=" * 50)

    sys.exit(0 if failed == 0 else 1)


if __name__ == '__main__':
    main()
