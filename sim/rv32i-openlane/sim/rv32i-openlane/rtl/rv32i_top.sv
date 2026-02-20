`include "rv32i_defs.vh"
// ============================================================================
// rv32i_top.sv — 3-Stage Pipelined RV32I Core
// ============================================================================

module rv32i_top (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        stall_in,      // External stall (e.g., from AXI bridge)
  output wire [31:0] imem_addr,
  input  wire [31:0] imem_rdata,
  output wire [31:0] dmem_addr,
  output reg  [31:0] dmem_wdata,
  output reg  [3:0]  dmem_byte_en,
  output wire        dmem_wr_en,
  output wire        dmem_rd_en,
  input  wire [31:0] dmem_rdata
);

  // --- IF stage ---
  reg  [31:0] pc_r;
  wire [31:0] pc_next;
  wire [31:0] if_instruction;

  // --- IF/DE pipeline register ---
  reg  [31:0] de_pc_r;
  reg  [31:0] de_instruction_r;
  reg         de_valid_r;

  // --- DE stage control ---
  wire [3:0]  de_ctrl_alu_op;
  wire        de_ctrl_alu_src;
  wire        de_ctrl_reg_write;
  wire        de_ctrl_mem_read;
  wire        de_ctrl_mem_write;
  wire [1:0]  de_ctrl_mem_width;
  wire        de_ctrl_mem_unsigned;
  wire        de_ctrl_mem_to_reg;
  wire        de_ctrl_is_branch;
  wire        de_ctrl_is_jal;
  wire        de_ctrl_is_jalr;
  wire        de_ctrl_is_lui;
  wire        de_ctrl_is_auipc;
  wire        de_illegal_instr;

  wire [31:0] de_rs1_data, de_rs2_data;
  wire [31:0] de_immediate;
  reg  [31:0] de_alu_a, de_alu_b;
  wire [31:0] de_alu_result;
  wire        de_alu_zero;
  reg         de_branch_taken;
  reg  [31:0] de_branch_target;

  // --- DE/MW pipeline register ---
  reg  [31:0] mw_alu_result_r;
  reg  [31:0] mw_rs2_data_r;
  reg  [31:0] mw_pc_plus4_r;
  reg  [4:0]  mw_rd_addr_r;
  reg         mw_reg_write_r;
  reg         mw_mem_read_r;
  reg         mw_mem_write_r;
  reg  [1:0]  mw_mem_width_r;
  reg         mw_mem_unsigned_r;
  reg         mw_mem_to_reg_r;
  reg         mw_is_jal_r;
  reg         mw_is_jalr_r;
  reg         mw_valid_r;

  // --- MW stage ---
  reg  [31:0] mw_mem_rdata_aligned;
  reg  [31:0] mw_writeback_data;

  // --- Hazard ---
  wire        stall_internal;
  wire        stall;
  wire        flush;

  wire [4:0] de_rs1_addr = de_instruction_r[19:15];
  wire [4:0] de_rs2_addr = de_instruction_r[24:20];

  assign stall_internal = mw_valid_r && mw_mem_read_r && (mw_rd_addr_r != 5'b0) &&
                 de_valid_r &&
                 ((mw_rd_addr_r == de_rs1_addr) ||
                  (mw_rd_addr_r == de_rs2_addr && !de_ctrl_alu_src));

  assign stall = stall_internal || stall_in;

  assign flush = de_branch_taken && de_valid_r && !stall_in;

  // ==========================================================================
  // IF Stage
  // ==========================================================================

  assign pc_next = stall ? pc_r :
                   flush ? de_branch_target :
                   pc_r + 32'd4;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_r <= 32'h0000_0000;
    else
      pc_r <= pc_next;
  end

  assign imem_addr      = pc_r;
  assign if_instruction = imem_rdata;

  // ==========================================================================
  // IF/DE Pipeline Register
  // ==========================================================================

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      de_pc_r          <= 32'b0;
      de_instruction_r <= 32'h0000_0013;
      de_valid_r       <= 1'b0;
    end else if (stall) begin
      // Hold
    end else if (flush) begin
      de_instruction_r <= 32'h0000_0013;
      de_valid_r       <= 1'b0;
    end else begin
      de_pc_r          <= pc_r;
      de_instruction_r <= if_instruction;
      de_valid_r       <= 1'b1;
    end
  end

  // ==========================================================================
  // DE Stage
  // ==========================================================================

  rv32i_control u_control (
    .instruction     (de_instruction_r),
    .ctrl_alu_op     (de_ctrl_alu_op),
    .ctrl_alu_src    (de_ctrl_alu_src),
    .ctrl_reg_write  (de_ctrl_reg_write),
    .ctrl_mem_read   (de_ctrl_mem_read),
    .ctrl_mem_write  (de_ctrl_mem_write),
    .ctrl_mem_width  (de_ctrl_mem_width),
    .ctrl_mem_unsigned(de_ctrl_mem_unsigned),
    .ctrl_mem_to_reg (de_ctrl_mem_to_reg),
    .ctrl_is_branch  (de_ctrl_is_branch),
    .ctrl_is_jal     (de_ctrl_is_jal),
    .ctrl_is_jalr    (de_ctrl_is_jalr),
    .ctrl_is_lui     (de_ctrl_is_lui),
    .ctrl_is_auipc   (de_ctrl_is_auipc),
    .illegal_instr   (de_illegal_instr)
  );

  wire        wb_reg_write;
  wire [4:0]  wb_rd_addr;
  wire [31:0] wb_rd_data;

  rv32i_regfile u_regfile (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (de_rs1_addr),
    .rs2_addr (de_rs2_addr),
    .rs1_data (de_rs1_data),
    .rs2_data (de_rs2_data),
    .wr_en    (wb_reg_write),
    .wr_addr  (wb_rd_addr),
    .wr_data  (wb_rd_data)
  );

  rv32i_imm_gen u_imm_gen (
    .instruction (de_instruction_r),
    .immediate   (de_immediate)
  );

  // ALU inputs
  always @(*) begin
    de_alu_a = de_ctrl_is_auipc ? de_pc_r : de_rs1_data;
    de_alu_b = de_ctrl_alu_src  ? de_immediate : de_rs2_data;
  end

  rv32i_alu u_alu (
    .a      (de_alu_a),
    .b      (de_alu_b),
    .op     (de_ctrl_alu_op),
    .result (de_alu_result),
    .zero   (de_alu_zero)
  );

  // Branch resolution
  always @(*) begin
    de_branch_taken = 1'b0;
    if (de_ctrl_is_jal)
      de_branch_taken = 1'b1;
    else if (de_ctrl_is_jalr)
      de_branch_taken = 1'b1;
    else if (de_ctrl_is_branch) begin
      case (de_instruction_r[14:12])
        3'b000:  de_branch_taken = (de_rs1_data == de_rs2_data);
        3'b001:  de_branch_taken = (de_rs1_data != de_rs2_data);
        3'b100:  de_branch_taken = ($signed(de_rs1_data) < $signed(de_rs2_data));
        3'b101:  de_branch_taken = ($signed(de_rs1_data) >= $signed(de_rs2_data));
        3'b110:  de_branch_taken = (de_rs1_data < de_rs2_data);
        3'b111:  de_branch_taken = (de_rs1_data >= de_rs2_data);
        default: de_branch_taken = 1'b0;
      endcase
    end
  end

  // Branch target
  always @(*) begin
    if (de_ctrl_is_jalr)
      de_branch_target = (de_rs1_data + de_immediate) & ~32'h1;
    else
      de_branch_target = de_pc_r + de_immediate;
  end

  // ==========================================================================
  // DE/MW Pipeline Register
  // ==========================================================================

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mw_alu_result_r   <= 32'b0;
      mw_rs2_data_r     <= 32'b0;
      mw_pc_plus4_r     <= 32'b0;
      mw_rd_addr_r      <= 5'b0;
      mw_reg_write_r    <= 1'b0;
      mw_mem_read_r     <= 1'b0;
      mw_mem_write_r    <= 1'b0;
      mw_mem_width_r    <= `MEM_WORD;
      mw_mem_unsigned_r <= 1'b0;
      mw_mem_to_reg_r   <= 1'b0;
      mw_is_jal_r       <= 1'b0;
      mw_is_jalr_r      <= 1'b0;
      mw_valid_r        <= 1'b0;
    end else if (stall_in) begin
      // External stall: freeze entire pipeline, hold MW values
    end else if (stall_internal) begin
      // Load-use stall: insert bubble in MW
      mw_valid_r     <= 1'b0;
      mw_reg_write_r <= 1'b0;
      mw_mem_read_r  <= 1'b0;
      mw_mem_write_r <= 1'b0;
    end else begin
      mw_alu_result_r   <= de_alu_result;
      mw_rs2_data_r     <= de_rs2_data;
      mw_pc_plus4_r     <= de_pc_r + 32'd4;
      mw_rd_addr_r      <= de_instruction_r[11:7];
      mw_reg_write_r    <= de_ctrl_reg_write && de_valid_r;
      mw_mem_read_r     <= de_ctrl_mem_read  && de_valid_r;
      mw_mem_write_r    <= de_ctrl_mem_write && de_valid_r;
      mw_mem_width_r    <= de_ctrl_mem_width;
      mw_mem_unsigned_r <= de_ctrl_mem_unsigned;
      mw_mem_to_reg_r   <= de_ctrl_mem_to_reg;
      mw_is_jal_r       <= de_ctrl_is_jal;
      mw_is_jalr_r      <= de_ctrl_is_jalr;
      mw_valid_r        <= de_valid_r;
    end
  end

  // ==========================================================================
  // MW Stage
  // ==========================================================================

  assign dmem_addr  = mw_alu_result_r;
  assign dmem_rd_en = mw_mem_read_r;
  assign dmem_wr_en = mw_mem_write_r;

  // Write alignment
  always @(*) begin
    dmem_byte_en = 4'b0000;
    dmem_wdata   = 32'b0;
    case (mw_mem_width_r)
      `MEM_BYTE:
        case (mw_alu_result_r[1:0])
          2'b00: begin dmem_byte_en = 4'b0001; dmem_wdata = {24'b0, mw_rs2_data_r[7:0]}; end
          2'b01: begin dmem_byte_en = 4'b0010; dmem_wdata = {16'b0, mw_rs2_data_r[7:0], 8'b0}; end
          2'b10: begin dmem_byte_en = 4'b0100; dmem_wdata = {8'b0, mw_rs2_data_r[7:0], 16'b0}; end
          2'b11: begin dmem_byte_en = 4'b1000; dmem_wdata = {mw_rs2_data_r[7:0], 24'b0}; end
        endcase
      `MEM_HALF:
        case (mw_alu_result_r[1])
          1'b0: begin dmem_byte_en = 4'b0011; dmem_wdata = {16'b0, mw_rs2_data_r[15:0]}; end
          1'b1: begin dmem_byte_en = 4'b1100; dmem_wdata = {mw_rs2_data_r[15:0], 16'b0}; end
        endcase
      `MEM_WORD: begin
        dmem_byte_en = 4'b1111;
        dmem_wdata   = mw_rs2_data_r;
      end
      default: begin
        dmem_byte_en = 4'b0000;
        dmem_wdata   = 32'b0;
      end
    endcase
  end

  // Read alignment
  reg [7:0]  rd_byte;
  reg [15:0] rd_half;

  always @(*) begin
    rd_byte = 8'b0;
    rd_half = 16'b0;
    mw_mem_rdata_aligned = 32'b0;
    case (mw_mem_width_r)
      `MEM_BYTE: begin
        case (mw_alu_result_r[1:0])
          2'b00: rd_byte = dmem_rdata[7:0];
          2'b01: rd_byte = dmem_rdata[15:8];
          2'b10: rd_byte = dmem_rdata[23:16];
          2'b11: rd_byte = dmem_rdata[31:24];
        endcase
        mw_mem_rdata_aligned = mw_mem_unsigned_r ? {24'b0, rd_byte} : {{24{rd_byte[7]}}, rd_byte};
      end
      `MEM_HALF: begin
        case (mw_alu_result_r[1])
          1'b0: rd_half = dmem_rdata[15:0];
          1'b1: rd_half = dmem_rdata[31:16];
        endcase
        mw_mem_rdata_aligned = mw_mem_unsigned_r ? {16'b0, rd_half} : {{16{rd_half[15]}}, rd_half};
      end
      `MEM_WORD:
        mw_mem_rdata_aligned = dmem_rdata;
      default:
        mw_mem_rdata_aligned = dmem_rdata;
    endcase
  end

  // Writeback
  always @(*) begin
    if (mw_is_jal_r || mw_is_jalr_r)
      mw_writeback_data = mw_pc_plus4_r;
    else if (mw_mem_to_reg_r)
      mw_writeback_data = mw_mem_rdata_aligned;
    else
      mw_writeback_data = mw_alu_result_r;
  end

  assign wb_reg_write = mw_reg_write_r && mw_valid_r;
  assign wb_rd_addr   = mw_rd_addr_r;
  assign wb_rd_data   = mw_writeback_data;

endmodule
