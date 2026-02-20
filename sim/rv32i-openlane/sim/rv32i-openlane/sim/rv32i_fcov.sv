// ============================================================================
// rv32i_fcov.sv — Functional Coverage for RV32I Core
//
// Tracks coverage of:
//   - Instruction types (R/I/S/B/U/J)
//   - ALU operations
//   - Branch types and directions (taken/not-taken)
//   - Memory access widths
//   - Hazard scenarios (load-use stalls, branch flushes)
//   - Pipeline state combinations
// ============================================================================

`include "rv32i_defs.vh"

module rv32i_fcov (
  input wire        clk,
  input wire        rst_n,

  // Instruction being decoded
  input wire [31:0] de_instruction_r,
  input wire        de_valid_r,

  // Control signals
  input wire [3:0]  de_ctrl_alu_op,
  input wire        de_ctrl_reg_write,
  input wire        de_ctrl_mem_read,
  input wire        de_ctrl_mem_write,
  input wire [1:0]  de_ctrl_mem_width,
  input wire        de_ctrl_is_branch,
  input wire        de_ctrl_is_jal,
  input wire        de_ctrl_is_jalr,
  input wire        de_ctrl_is_lui,
  input wire        de_ctrl_is_auipc,

  // Branch/hazard
  input wire        de_branch_taken,
  input wire        stall,
  input wire        flush,

  // MW stage
  input wire        mw_valid_r,
  input wire        mw_mem_read_r,
  input wire        mw_mem_write_r
);

  // ========================================================================
  // Decode instruction fields
  // ========================================================================

  wire [6:0] opcode = de_instruction_r[6:0];
  wire [2:0] funct3 = de_instruction_r[14:12];
  wire [6:0] funct7 = de_instruction_r[31:25];
  wire [4:0] rd     = de_instruction_r[11:7];
  wire [4:0] rs1    = de_instruction_r[19:15];
  wire [4:0] rs2    = de_instruction_r[24:20];

  // Valid instruction decode
  wire valid_instr = de_valid_r && rst_n;

  // ========================================================================
  // Coverage Group 1: Instruction Type Coverage
  // ========================================================================

  // Track which instruction types have been seen
  reg seen_r_type, seen_i_alu, seen_load, seen_store;
  reg seen_branch, seen_jal, seen_jalr, seen_lui, seen_auipc;
  reg seen_fence, seen_system;

  always @(posedge clk) begin
    if (!rst_n) begin
      seen_r_type <= 0; seen_i_alu  <= 0; seen_load   <= 0;
      seen_store  <= 0; seen_branch <= 0; seen_jal    <= 0;
      seen_jalr   <= 0; seen_lui    <= 0; seen_auipc  <= 0;
      seen_fence  <= 0; seen_system <= 0;
    end else if (valid_instr) begin
      case (opcode)
        7'b0110011: seen_r_type <= 1;
        7'b0010011: seen_i_alu  <= 1;
        7'b0000011: seen_load   <= 1;
        7'b0100011: seen_store  <= 1;
        7'b1100011: seen_branch <= 1;
        7'b1101111: seen_jal    <= 1;
        7'b1100111: seen_jalr   <= 1;
        7'b0110111: seen_lui    <= 1;
        7'b0010111: seen_auipc  <= 1;
        7'b0001111: seen_fence  <= 1;
        7'b1110011: seen_system <= 1;
      endcase
    end
  end

  // ========================================================================
  // Coverage Group 2: ALU Operation Coverage
  // ========================================================================

  reg [10:0] seen_alu_ops; // one bit per ALU op

  always @(posedge clk) begin
    if (!rst_n)
      seen_alu_ops <= 11'b0;
    else if (valid_instr && (opcode == 7'b0110011 || opcode == 7'b0010011))
      seen_alu_ops[de_ctrl_alu_op] <= 1'b1;
  end

  // ========================================================================
  // Coverage Group 3: Branch Type and Direction Coverage
  // ========================================================================

  reg [5:0] seen_branch_taken;     // BEQ..BGEU taken
  reg [5:0] seen_branch_not_taken; // BEQ..BGEU not taken

  // Map funct3 to index: BEQ=0, BNE=1, BLT=4->2, BGE=5->3, BLTU=6->4, BGEU=7->5
  function [2:0] branch_idx;
    input [2:0] f3;
    case (f3)
      3'b000: branch_idx = 3'd0; // BEQ
      3'b001: branch_idx = 3'd1; // BNE
      3'b100: branch_idx = 3'd2; // BLT
      3'b101: branch_idx = 3'd3; // BGE
      3'b110: branch_idx = 3'd4; // BLTU
      3'b111: branch_idx = 3'd5; // BGEU
      default: branch_idx = 3'd0;
    endcase
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      seen_branch_taken     <= 6'b0;
      seen_branch_not_taken <= 6'b0;
    end else if (valid_instr && de_ctrl_is_branch) begin
      if (de_branch_taken)
        seen_branch_taken[branch_idx(funct3)] <= 1'b1;
      else
        seen_branch_not_taken[branch_idx(funct3)] <= 1'b1;
    end
  end

  // ========================================================================
  // Coverage Group 4: Memory Access Width Coverage
  // ========================================================================

  reg [2:0] seen_load_width;  // byte, half, word
  reg [2:0] seen_store_width;

  always @(posedge clk) begin
    if (!rst_n) begin
      seen_load_width  <= 3'b0;
      seen_store_width <= 3'b0;
    end else if (valid_instr) begin
      if (de_ctrl_mem_read)
        seen_load_width[de_ctrl_mem_width] <= 1'b1;
      if (de_ctrl_mem_write)
        seen_store_width[de_ctrl_mem_width] <= 1'b1;
    end
  end

  // ========================================================================
  // Coverage Group 5: Hazard Scenario Coverage
  // ========================================================================

  reg seen_load_use_stall;
  reg seen_branch_flush;
  reg seen_jal_flush;
  reg seen_jalr_flush;
  reg seen_back_to_back_branch;
  reg seen_load_then_branch;

  always @(posedge clk) begin
    if (!rst_n) begin
      seen_load_use_stall    <= 0;
      seen_branch_flush      <= 0;
      seen_jal_flush         <= 0;
      seen_jalr_flush        <= 0;
      seen_back_to_back_branch <= 0;
      seen_load_then_branch  <= 0;
    end else begin
      if (stall)
        seen_load_use_stall <= 1;
      if (flush && de_ctrl_is_branch)
        seen_branch_flush <= 1;
      if (flush && de_ctrl_is_jal)
        seen_jal_flush <= 1;
      if (flush && de_ctrl_is_jalr)
        seen_jalr_flush <= 1;
      // Back-to-back: flush this cycle, next DE is also a branch
      if (flush && de_ctrl_is_branch)
        seen_back_to_back_branch <= 1;
      // Load followed by branch (potential load-use + branch interaction)
      if (mw_mem_read_r && de_ctrl_is_branch)
        seen_load_then_branch <= 1;
    end
  end

  // ========================================================================
  // Coverage Group 6: Register Usage
  // ========================================================================

  reg [31:0] seen_rd_written;  // which rd registers have been written
  reg [31:0] seen_rs1_read;    // which rs1 registers have been read
  reg [31:0] seen_rs2_read;    // which rs2 registers have been read

  always @(posedge clk) begin
    if (!rst_n) begin
      seen_rd_written <= 32'b0;
      seen_rs1_read   <= 32'b0;
      seen_rs2_read   <= 32'b0;
    end else if (valid_instr) begin
      if (de_ctrl_reg_write && rd != 5'd0)
        seen_rd_written[rd] <= 1'b1;
      seen_rs1_read[rs1] <= 1'b1;
      if (!de_ctrl_is_lui && !de_ctrl_is_auipc && !de_ctrl_is_jal)
        seen_rs2_read[rs2] <= 1'b1;
    end
  end

  // ========================================================================
  // Coverage Report (printed at end of simulation)
  // ========================================================================

  integer total_bins, hit_bins;
  integer i;

  task report_coverage;
    begin
      total_bins = 0;
      hit_bins   = 0;

      $display("");
      $display("========================================");
      $display("  FUNCTIONAL COVERAGE REPORT");
      $display("========================================");

      // Instruction types (11 bins)
      $display("");
      $display("--- Instruction Types ---");
      $display("  R-type:   %s", seen_r_type ? "HIT" : "MISS");
      $display("  I-ALU:    %s", seen_i_alu  ? "HIT" : "MISS");
      $display("  Load:     %s", seen_load   ? "HIT" : "MISS");
      $display("  Store:    %s", seen_store  ? "HIT" : "MISS");
      $display("  Branch:   %s", seen_branch ? "HIT" : "MISS");
      $display("  JAL:      %s", seen_jal    ? "HIT" : "MISS");
      $display("  JALR:     %s", seen_jalr   ? "HIT" : "MISS");
      $display("  LUI:      %s", seen_lui    ? "HIT" : "MISS");
      $display("  AUIPC:    %s", seen_auipc  ? "HIT" : "MISS");
      $display("  FENCE:    %s", seen_fence  ? "HIT" : "MISS");
      $display("  SYSTEM:   %s", seen_system ? "HIT" : "MISS");

      total_bins = total_bins + 11;
      hit_bins = hit_bins + seen_r_type + seen_i_alu + seen_load + seen_store
                 + seen_branch + seen_jal + seen_jalr + seen_lui + seen_auipc
                 + seen_fence + seen_system;

      // ALU ops (11 bins)
      $display("");
      $display("--- ALU Operations ---");
      $display("  ADD=%0d SUB=%0d SLL=%0d SLT=%0d SLTU=%0d",
               seen_alu_ops[0], seen_alu_ops[1], seen_alu_ops[2],
               seen_alu_ops[3], seen_alu_ops[4]);
      $display("  XOR=%0d SRL=%0d SRA=%0d OR=%0d  AND=%0d PASS_B=%0d",
               seen_alu_ops[5], seen_alu_ops[6], seen_alu_ops[7],
               seen_alu_ops[8], seen_alu_ops[9], seen_alu_ops[10]);

      total_bins = total_bins + 11;
      for (i = 0; i < 11; i = i + 1)
        hit_bins = hit_bins + seen_alu_ops[i];

      // Branch directions (12 bins: 6 types × taken/not-taken)
      $display("");
      $display("--- Branch Directions (taken/not-taken) ---");
      $display("  BEQ:  T=%0d NT=%0d", seen_branch_taken[0], seen_branch_not_taken[0]);
      $display("  BNE:  T=%0d NT=%0d", seen_branch_taken[1], seen_branch_not_taken[1]);
      $display("  BLT:  T=%0d NT=%0d", seen_branch_taken[2], seen_branch_not_taken[2]);
      $display("  BGE:  T=%0d NT=%0d", seen_branch_taken[3], seen_branch_not_taken[3]);
      $display("  BLTU: T=%0d NT=%0d", seen_branch_taken[4], seen_branch_not_taken[4]);
      $display("  BGEU: T=%0d NT=%0d", seen_branch_taken[5], seen_branch_not_taken[5]);

      total_bins = total_bins + 12;
      for (i = 0; i < 6; i = i + 1)
        hit_bins = hit_bins + seen_branch_taken[i] + seen_branch_not_taken[i];

      // Memory widths (6 bins)
      $display("");
      $display("--- Memory Access Widths ---");
      $display("  Load:  byte=%0d half=%0d word=%0d",
               seen_load_width[0], seen_load_width[1], seen_load_width[2]);
      $display("  Store: byte=%0d half=%0d word=%0d",
               seen_store_width[0], seen_store_width[1], seen_store_width[2]);

      total_bins = total_bins + 6;
      for (i = 0; i < 3; i = i + 1)
        hit_bins = hit_bins + seen_load_width[i] + seen_store_width[i];

      // Hazard scenarios (6 bins)
      $display("");
      $display("--- Hazard Scenarios ---");
      $display("  Load-use stall:    %s", seen_load_use_stall   ? "HIT" : "MISS");
      $display("  Branch flush:      %s", seen_branch_flush     ? "HIT" : "MISS");
      $display("  JAL flush:         %s", seen_jal_flush        ? "HIT" : "MISS");
      $display("  JALR flush:        %s", seen_jalr_flush       ? "HIT" : "MISS");
      $display("  Load→branch:       %s", seen_load_then_branch ? "HIT" : "MISS");

      total_bins = total_bins + 5;
      hit_bins = hit_bins + seen_load_use_stall + seen_branch_flush
                 + seen_jal_flush + seen_jalr_flush + seen_load_then_branch;

      // Register usage summary
      $display("");
      $display("--- Register Usage ---");
      $display("  rd written: %0d/31 registers", $countones(seen_rd_written));
      $display("  rs1 read:   %0d/32 registers", $countones(seen_rs1_read));
      $display("  rs2 read:   %0d/32 registers", $countones(seen_rs2_read));

      // Total
      $display("");
      $display("========================================");
      $display("  TOTAL COVERAGE: %0d / %0d bins (%0d%%)",
               hit_bins, total_bins, (hit_bins * 100) / total_bins);
      $display("========================================");
      $display("");
    end
  endtask

endmodule
