# test_mem.s — Test load/store operations
# Pass/fail convention: SW to 0xFFFFFFF0
#
# Uses memory at 0x2000 (word 0x800) as scratch area.

    # Setup
    addi  x31, x0, -16       # x31 = 0xFFFFFFF0

    # Base address for scratch memory
    lui   x30, 2              # x30 = 0x2000

    # ---- SW / LW ----
    addi  x1, x0, 0x7AB      # x1 = 1963
    sw    x1, 0(x30)          # MEM[0x2000] = 1963
    lw    x2, 0(x30)          # x2 should = 1963
    bne   x1, x2, fail

    # Write a negative number
    addi  x1, x0, -1          # x1 = 0xFFFFFFFF
    sw    x1, 4(x30)          # MEM[0x2004] = 0xFFFFFFFF
    lw    x2, 4(x30)
    bne   x1, x2, fail

    # ---- SB / LB / LBU ----
    # Write 0xABCD1234 to memory first
    lui   x1, 0xABCD1
    addi  x1, x1, 0x234
    sw    x1, 8(x30)          # MEM[0x2008] = 0xABCD1234

    # LB: load byte 0 (LSB) — should be 0x34, sign-extended
    lb    x2, 8(x30)
    addi  x3, x0, 0x34        # 0x34 = 52 (positive, sign-ext = 0x00000034)
    bne   x2, x3, fail

    # LBU: load byte 0 — should be 0x34 zero-extended
    lbu   x2, 8(x30)
    bne   x2, x3, fail

    # SB: write a byte
    addi  x1, x0, 0x55
    sb    x1, 12(x30)         # MEM[0x200C] byte 0 = 0x55
    lbu   x2, 12(x30)
    addi  x3, x0, 0x55
    bne   x2, x3, fail

    # ---- SH / LH / LHU ----
    # Write a halfword
    lui   x1, 0xFFFFF         # x1 = 0xFFFFF000
    addi  x1, x1, 0x123       # x1 = 0xFFFFF123 — but that's -3805 or similar
    # Let's use a simpler value
    addi  x1, x0, 0x1AB       # x1 = 427
    sh    x1, 16(x30)         # MEM[0x2010] lower half = 0x01AB
    lh    x2, 16(x30)         # sign-extended load
    bne   x1, x2, fail

    lhu   x2, 16(x30)         # zero-extended load
    bne   x1, x2, fail        # same since value is positive

    # Test negative halfword
    addi  x1, x0, -1          # x1 = 0xFFFFFFFF
    sh    x1, 20(x30)         # MEM[0x2014] lower half = 0xFFFF
    lh    x2, 20(x30)         # should sign-extend to 0xFFFFFFFF = -1
    addi  x3, x0, -1
    bne   x2, x3, fail

    lhu   x2, 20(x30)         # should zero-extend to 0x0000FFFF = 65535
    lui   x3, 0x10            # x3 = 0x10000 = 65536
    addi  x3, x3, -1          # x3 = 65535
    bne   x2, x3, fail

    # ---- Load-use stall test ----
    # Store a value, load it, and immediately use it
    addi  x1, x0, 42
    sw    x1, 24(x30)
    lw    x2, 24(x30)         # load
    addi  x3, x2, 8           # use immediately (should trigger load-use stall)
    addi  x4, x0, 50
    bne   x3, x4, fail

    # ---- Multiple stores then loads (check no aliasing) ----
    addi  x1, x0, 10
    addi  x2, x0, 20
    addi  x3, x0, 30
    sw    x1, 28(x30)
    sw    x2, 32(x30)
    sw    x3, 36(x30)
    lw    x4, 28(x30)
    lw    x5, 32(x30)
    lw    x6, 36(x30)
    bne   x4, x1, fail
    bne   x5, x2, fail
    bne   x6, x3, fail

    # ---- PASS ----
    addi  x1, x0, 1
    sw    x1, 0(x31)
    j     done

fail:
    sw    x0, 0(x31)

done:
    j     done
