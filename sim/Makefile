# Makefile for RV32I simulation

IVERILOG = iverilog
VVP      = vvp
ASM      = python3 rv32i_asm.py

RTL_DIR  = ../rtl
PROG_DIR = ../programs

# RTL sources (order matters for packages)
RTL_SRCS = \
    $(RTL_DIR)/rv32i_alu.sv \
    $(RTL_DIR)/rv32i_regfile.sv \
    $(RTL_DIR)/rv32i_imm_gen.sv \
    $(RTL_DIR)/rv32i_control.sv \
    $(RTL_DIR)/rv32i_top.sv \
    rv32i_mem.sv \
    rv32i_sva.sv \
    rv32i_fcov.sv \
    rv32i_tb.sv

# AXI RTL sources
RTL_SRCS_AXI = \
    $(RTL_DIR)/rv32i_alu.sv \
    $(RTL_DIR)/rv32i_regfile.sv \
    $(RTL_DIR)/rv32i_imm_gen.sv \
    $(RTL_DIR)/rv32i_control.sv \
    $(RTL_DIR)/rv32i_top.sv \
    $(RTL_DIR)/rv32i_axi_master.sv \
    rv32i_axi_mem.sv \
    rv32i_axi_tb.sv

# Test programs
TESTS = test_alu test_branch test_mem

# Constrained random settings
RANDOM_N    ?= 100
RANDOM_SEED ?= 42

.PHONY: all clean run_all run_axi_all random $(TESTS)

all: run_all

# Assemble all test programs
%.hex: $(PROG_DIR)/%.s rv32i_asm.py
	$(ASM) $< -o $@

# Compile testbench (direct memory)
rv32i_sim: $(RTL_SRCS)
	$(IVERILOG) -g2012 -I$(RTL_DIR) -o $@ -DINIT_FILE=\"program.hex\" $^

# Compile AXI testbench
rv32i_axi_sim: $(RTL_SRCS_AXI)
	$(IVERILOG) -g2012 -I$(RTL_DIR) -o $@ $^

# Run a single test (direct)
run_%: %.hex rv32i_sim
	@echo "========================================"
	@echo "Running $*..."
	@echo "========================================"
	@cp $*.hex program.hex
	@$(VVP) rv32i_sim +INIT_FILE=$*.hex 2>&1 | tee $*_result.log
	@echo ""

# Run a single test (AXI)
run_axi_%: %.hex rv32i_axi_sim
	@echo "========================================"
	@echo "Running $* (AXI)..."
	@echo "========================================"
	@cp $*.hex program.hex
	@$(VVP) rv32i_axi_sim 2>&1 | tee $*_axi_result.log
	@echo ""

# Run all tests (direct)
run_all: $(addprefix run_,$(TESTS))
	@echo "========================================"
	@echo "Summary (direct):"
	@echo "========================================"
	@for t in $(TESTS); do \
		if grep -q "PASS" $${t}_result.log 2>/dev/null; then \
			echo "  $$t: PASS"; \
		elif grep -q "FAIL" $${t}_result.log 2>/dev/null; then \
			echo "  $$t: FAIL"; \
		else \
			echo "  $$t: TIMEOUT/ERROR"; \
		fi; \
	done

# Run all tests (AXI)
run_axi_all: $(addprefix run_axi_,$(TESTS))
	@echo "========================================"
	@echo "Summary (AXI):"
	@echo "========================================"
	@for t in $(TESTS); do \
		if grep -q "AXI PASS" $${t}_axi_result.log 2>/dev/null; then \
			echo "  $$t: PASS"; \
		elif grep -q "AXI FAIL" $${t}_axi_result.log 2>/dev/null; then \
			echo "  $$t: FAIL"; \
		else \
			echo "  $$t: TIMEOUT/ERROR"; \
		fi; \
	done

# Constrained random testing
random: rv32i_sim $(addsuffix .hex,$(TESTS))
	@echo "========================================"
	@echo "Constrained random: $(RANDOM_N) tests, seed=$(RANDOM_SEED)"
	@echo "========================================"
	python3 rv32i_random_test.py --num-tests $(RANDOM_N) --seed $(RANDOM_SEED) --sim-dir .

clean:
	rm -f *.hex *.vcd rv32i_sim rv32i_axi_sim *_result.log *_axi_result.log program.hex
