// ============================================================================
// rv32i_defs.vh — Shared constants for RV32I core (preprocessor macros)
// ============================================================================

`ifndef RV32I_DEFS_VH
`define RV32I_DEFS_VH

// ALU operations
`define ALU_ADD    4'd0
`define ALU_SUB    4'd1
`define ALU_SLL    4'd2
`define ALU_SLT    4'd3
`define ALU_SLTU   4'd4
`define ALU_XOR    4'd5
`define ALU_SRL    4'd6
`define ALU_SRA    4'd7
`define ALU_OR     4'd8
`define ALU_AND    4'd9
`define ALU_PASS_B 4'd10

// Memory width
`define MEM_BYTE 2'd0
`define MEM_HALF 2'd1
`define MEM_WORD 2'd2

`endif
