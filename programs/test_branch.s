# test_branch.s — Test all branch and jump instructions
# Pass/fail convention: SW to 0xFFFFFFF0

    # Setup
    addi  x31, x0, -16       # x31 = 0xFFFFFFF0

    addi  x1, x0, 5
    addi  x2, x0, 5
    addi  x3, x0, 10
    addi  x4, x0, -3

    # ---- BEQ: should branch (5 == 5) ----
    beq   x1, x2, beq_ok
    j     fail
beq_ok:

    # ---- BEQ: should NOT branch (5 != 10) ----
    beq   x1, x3, fail

    # ---- BNE: should branch (5 != 10) ----
    bne   x1, x3, bne_ok
    j     fail
bne_ok:

    # ---- BNE: should NOT branch (5 == 5) ----
    bne   x1, x2, fail

    # ---- BLT: should branch (-3 < 5, signed) ----
    blt   x4, x1, blt_ok
    j     fail
blt_ok:

    # ---- BLT: should NOT branch (5 < -3 is false, signed) ----
    blt   x1, x4, fail

    # ---- BGE: should branch (5 >= 5, signed) ----
    bge   x1, x2, bge_ok1
    j     fail
bge_ok1:

    # ---- BGE: should branch (10 >= 5, signed) ----
    bge   x3, x1, bge_ok2
    j     fail
bge_ok2:

    # ---- BGE: should NOT branch (-3 >= 5 is false) ----
    bge   x4, x1, fail

    # ---- BLTU: should branch (5 < 10, unsigned) ----
    bltu  x1, x3, bltu_ok
    j     fail
bltu_ok:

    # ---- BLTU: -3 as unsigned is very large, so 5 < 0xFFFFFFFD ----
    bltu  x1, x4, bltu_ok2
    j     fail
bltu_ok2:

    # ---- BGEU: should branch (10 >= 5, unsigned) ----
    bgeu  x3, x1, bgeu_ok
    j     fail
bgeu_ok:

    # ---- BGEU: should NOT branch (5 >= 10 is false, unsigned) ----
    bgeu  x1, x3, fail

    # ---- JAL: jump and link ----
    jal   x5, jal_target      # x5 = return address
    j     fail                 # should not reach here
jal_target:
    # x5 should hold address of "j fail" above (jal_target - 4 is the j fail, so x5 = addr of j fail)
    # Actually x5 = PC of jal + 4 = addr of "j fail" instruction
    # Verify x5 is nonzero
    beq   x5, x0, fail

    # ---- JALR: jump and link register ----
    # Load address of jalr_target into x6
    jal   x6, jalr_setup
jalr_return:
    # We should arrive here after JALR
    j     jalr_done
jalr_setup:
    # x6 = return addr = addr of jalr_return
    # We want to JALR to jalr_return
    jalr  x7, x6, 0           # jump to jalr_return, x7 = addr of next instr after this
jalr_done:
    # x7 should be non-zero (link address from JALR)
    beq   x7, x0, fail

    # ---- Backward branch test (simple loop) ----
    addi  x10, x0, 0          # counter
    addi  x11, x0, 5          # limit
loop:
    addi  x10, x10, 1
    bne   x10, x11, loop
    # x10 should be 5
    addi  x12, x0, 5
    bne   x10, x12, fail

    # ---- PASS ----
    addi  x1, x0, 1
    sw    x1, 0(x31)
    j     done

fail:
    sw    x0, 0(x31)

done:
    j     done
