# RV32I RISC-V Processor Core

A 3-stage pipelined RV32I processor core in SystemVerilog with complete RTL-to-GDSII ASIC flow using OpenLane 2 and the SkyWater 130nm PDK. Includes AXI4-Lite master interface, constrained random verification, architectural assertions, and functional coverage.

![GDSII Layout](docs/layout.png)
*Physical layout of rv32i_top — SkyWater 130nm, 462 × 472 µm die*

## Key Results

| Metric | Value |
|--------|-------|
| ISA | RV32I (37 instructions) |
| Pipeline | 3-stage (IF → DE → MW) |
| Fmax (typical) | ~110 MHz |
| Fmax (worst-case) | ~57 MHz |
| Area | 0.218 mm² (101k µm² std cells) |
| Power @ 50 MHz | 10.1 mW |
| Power @ 100 MHz | 20.8 mW |
| DRC / LVS | Clean ✅ |
| Assertions | 20 checks, all passing |
| Functional coverage | 91% (45 bins across 3 tests) |
| Constrained random | 100/100 tests passing |
| AXI4-Lite | Master interface, verified at multiple latencies |

## Architecture

**Pipeline stages:**

| Stage | Function |
|-------|----------|
| IF | Instruction fetch, PC management |
| DE | Decode, register read, ALU execute, branch resolution |
| MW | Memory access, load alignment, register writeback |

**Hazard handling:**

- **Data hazards:** Write-forwarding in register file (MW→DE). Load-use detection with 1-cycle stall bubble.
- **Control hazards:** Static not-taken prediction. Flush on taken branch/jump (1-cycle penalty).

**Supported instructions:** LUI, AUIPC, JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU, LB, LH, LW, LBU, LHU, SB, SH, SW, ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI, ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND.

## Synthesis Results (SkyWater 130nm)

Synthesised using OpenLane 2 with the `sky130_fd_sc_hd` standard cell library across multiple PVT corners.

| Metric | 50 MHz (20 ns) | 100 MHz (10 ns) |
|--------|---------------|-----------------|
| Setup slack (typical, 25°C, 1.8V) | +8.89 ns | +0.91 ns |
| Setup slack (slow-slow, 100°C, 1.6V) | −2.03 ns | −7.45 ns |
| Setup slack (fast-fast, −40°C, 1.95V) | +11.56 ns | +3.87 ns |
| Hold violations | 0 | 0 |
| Cell area (µm²) | 101,145 | 104,896 |
| Standard cells | 11,956 | 12,147 |
| Sequential cells | 1,201 | 1,201 |
| Total power | 10.1 mW | 20.8 mW |
| Core utilisation | 50.0% | 51.9% |
| DRC | Clean | Clean |
| LVS | Clean | Clean |
| Antenna violations | 41 nets | 51 nets |

The critical path is approximately 9.1 ns at the typical corner, giving a theoretical Fmax of ~110 MHz. At worst-case conditions (slow-slow, 100°C, 1.6V), the maximum achievable frequency is approximately 57 MHz.

Antenna repair was not enabled in this flow; violations do not affect functional correctness or STA results.

## Verification

### Test Programs

Three directed test programs cover the full RV32I instruction set. Each program writes 1 to address `0xFFFFFFF0` on pass or 0 on fail.

| Test | Status | Cycles | What it covers |
|------|--------|--------|----------------|
| test_alu | PASS ✅ | 83 | All R-type and I-type ALU ops, LUI, AUIPC |
| test_branch | PASS ✅ | 57 | BEQ/BNE/BLT/BGE/BLTU/BGEU taken and not-taken, JAL, JALR, loops |
| test_mem | PASS ✅ | 68 | LW/LH/LB/LHU/LBU, SW/SH/SB, load-use stall verification |

### Architectural Assertions (20 checks)

Procedural assertions run on every clock cycle and verify:

- **PC invariants:** 4-byte alignment, correct increment, hold during stall
- **Pipeline control:** Stall/flush mutual exclusion, flush invalidates DE, stall inserts MW bubble
- **Memory protocol:** No simultaneous read/write, byte enables active on write, word/half alignment
- **Control decode:** No simultaneous mem_read/mem_write, JAL/JALR assert reg_write, branches don't write registers
- **Branch behaviour:** JAL/JALR always taken, branch targets aligned, PC matches target after taken branch

All 20 assertions pass across all three test programs with zero failures.

### Functional Coverage (45 bins, 91% combined)

| Category | Bins | Combined Hit Rate |
|----------|------|-------------------|
| Instruction types (R/I/Load/Store/Branch/JAL/JALR/LUI/AUIPC/FENCE/SYSTEM) | 11 | 9/11 |
| ALU operations (ADD through PASS_B) | 11 | 10/11 |
| Branch directions (6 types × taken/not-taken) | 12 | 11/12 |
| Memory access widths (byte/half/word × load/store) | 6 | 6/6 |
| Hazard scenarios (load-use stall, branch/JAL/JALR flush, load→branch) | 5 | 4/5 |

Coverage gaps: FENCE and SYSTEM instructions (treated as NOP, not exercised), PASS_B ALU op (internal to LUI), BLTU not-taken.

### Constrained Random Testing (100/100 passing)

A Python-based framework (`rv32i_random_test.py`) that generates random but legal RV32I programs and compares execution between a Python reference model and RTL simulation.

- **Random program generator:** Weighted instruction mix (30% R-type, 20% I-ALU, 12% loads, 10% stores, 10% branches, etc.) with constraints for valid opcodes, safe memory addresses, and bounded forward-only branches.
- **Python reference model:** Full RV32I ISA simulator used as golden reference.
- **Automatic comparison:** All 32 registers compared after execution; mismatches reported with seed for reproducibility.

```bash
cd sim
python3 rv32i_random_test.py --num-tests 100 --seed 42
```

## AXI4-Lite Interface

An AXI4-Lite master bridge (`rv32i_axi_master.sv`) wraps the core for SoC-compatible data bus integration. The instruction port remains tightly coupled for single-cycle fetch.

- **5-state FSM:** IDLE → RD_ADDR → RD_DATA for reads; IDLE → WR_ADDR → WR_RESP for writes.
- **Simultaneous AW+W handshake** with independent completion tracking.
- **Pipeline stall integration:** Core freezes via `stall_in` during multi-cycle AXI transactions.
- **Latency tolerant:** Verified at 1-cycle and 3-cycle slave response latencies.

| Test | Direct (cycles) | AXI lat=1 (cycles) |
|------|----------------|---------------------|
| test_alu | 83 | 84 |
| test_branch | 57 | 58 |
| test_mem | 68 | 171 |

## Project Structure

```
rv32i-openlane/
├── rtl/                        # Synthesisable RTL
│   ├── rv32i_defs.vh           # Shared constants (ALU ops, mem widths)
│   ├── rv32i_alu.sv            # ALU (11 operations)
│   ├── rv32i_regfile.sv        # 32×32 register file with write-forwarding
│   ├── rv32i_imm_gen.sv        # Immediate extraction (I/S/B/U/J formats)
│   ├── rv32i_control.sv        # Instruction decoder
│   ├── rv32i_top.sv            # Top-level pipelined datapath
│   └── rv32i_axi_master.sv     # AXI4-Lite master bridge
├── sim/                        # Simulation and verification
│   ├── rv32i_tb.sv             # Self-checking testbench (direct memory)
│   ├── rv32i_axi_tb.sv         # AXI-Lite integration testbench
│   ├── rv32i_axi_mem.sv        # AXI-Lite slave memory model
│   ├── rv32i_sva.sv            # Architectural assertions (20 checks)
│   ├── rv32i_fcov.sv           # Functional coverage (45 bins)
│   ├── rv32i_random_test.py    # Constrained random test framework
│   ├── rv32i_mem.sv            # Simulation memory model (64 KB)
│   ├── rv32i_asm.py            # Python RV32I assembler
│   └── Makefile                # Build and run automation
├── programs/                   # Assembly test programs
│   ├── test_alu.s              # ALU instruction tests
│   ├── test_branch.s           # Branch and jump tests
│   └── test_mem.s              # Load/store and hazard tests
├── openlane/                   # ASIC flow configuration
│   ├── config.json             # OpenLane 2 settings
│   └── rv32i_top.sdc           # Timing constraints
└── docs/                       # Documentation
    └── layout.png              # GDSII layout screenshot
```

## Quick Start

### Prerequisites

```bash
sudo apt install -y iverilog python3 make
```

### Run All Tests (direct memory)

```bash
cd sim
make run_all
```

### Run All Tests (AXI-Lite interface)

```bash
cd sim
make run_axi_all
```

### Constrained Random Testing

```bash
cd sim
make random                          # 100 tests, seed=42
make random RANDOM_N=500 RANDOM_SEED=123  # custom
```

### Run a Single Test

```bash
cd sim
make run_test_alu        # direct memory
make run_axi_test_mem    # via AXI-Lite
```

### ASIC Synthesis (requires Docker + OpenLane 2)

```bash
pip install openlane
openlane --dockerized openlane/config.json
```

Results are written to `openlane/runs/<tag>/final/` including GDSII, gate-level netlist, timing reports, and PPA metrics.

## Tools

| Tool | Purpose |
|------|---------|
| Icarus Verilog | RTL simulation |
| OpenLane 2 | RTL-to-GDSII flow |
| Yosys | Logic synthesis |
| OpenROAD | Place and route, CTS, STA |
| Magic / KLayout | DRC, LVS, GDS viewing |
| SkyWater 130nm PDK | Standard cell library and technology files |

## Roadmap

- [x] RTL design (3-stage pipeline)
- [x] Basic test suite (ALU, branches, memory)
- [x] Architectural assertions (20 procedural checks)
- [x] Functional coverage (45 bins, 91% combined)
- [x] Constrained random testing (100/100 passing)
- [x] AXI4-Lite memory interface
- [x] OpenLane synthesis + PPA at 50 MHz and 100 MHz
- [x] Full documentation

## License

MIT
