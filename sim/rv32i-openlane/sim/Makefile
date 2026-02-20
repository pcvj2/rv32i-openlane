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

# Test programs
TESTS = test_alu test_branch test_mem

.PHONY: all clean run_all $(TESTS)

all: run_all

# Assemble all test programs
%.hex: $(PROG_DIR)/%.s rv32i_asm.py
	$(ASM) $< -o $@

# Compile testbench
rv32i_sim: $(RTL_SRCS)
	$(IVERILOG) -g2012 -I$(RTL_DIR) -o $@ -DINIT_FILE=\"program.hex\" $^

# Run a single test
run_%: %.hex rv32i_sim
	@echo "========================================"
	@echo "Running $*..."
	@echo "========================================"
	@cp $*.hex program.hex
	@$(VVP) rv32i_sim +INIT_FILE=$*.hex 2>&1 | tee $*_result.log
	@echo ""

# Run all tests
run_all: $(addprefix run_,$(TESTS))
	@echo "========================================"
	@echo "Summary:"
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

clean:
	rm -f *.hex *.vcd rv32i_sim *_result.log program.hex
