`include "rv32i_defs.vh"
// ============================================================================
// rv32i_control.sv — RV32I Instruction Decoder
// ============================================================================

module rv32i_control (
  input  wire [31:0] instruction,
  output reg  [3:0]  ctrl_alu_op,
  output reg         ctrl_alu_src,
  output reg         ctrl_reg_write,
  output reg         ctrl_mem_read,
  output reg         ctrl_mem_write,
  output reg  [1:0]  ctrl_mem_width,
  output reg         ctrl_mem_unsigned,
  output reg         ctrl_mem_to_reg,
  output reg         ctrl_is_branch,
  output reg         ctrl_is_jal,
  output reg         ctrl_is_jalr,
  output reg         ctrl_is_lui,
  output reg         ctrl_is_auipc,
  output reg         illegal_instr
);

  wire [6:0] opcode = instruction[6:0];
  wire [2:0] funct3 = instruction[14:12];
  wire [6:0] funct7 = instruction[31:25];

  always @(*) begin
    ctrl_alu_op      = `ALU_ADD;
    ctrl_alu_src     = 1'b0;
    ctrl_reg_write   = 1'b0;
    ctrl_mem_read    = 1'b0;
    ctrl_mem_write   = 1'b0;
    ctrl_mem_width   = `MEM_WORD;
    ctrl_mem_unsigned = 1'b0;
    ctrl_mem_to_reg  = 1'b0;
    ctrl_is_branch   = 1'b0;
    ctrl_is_jal      = 1'b0;
    ctrl_is_jalr     = 1'b0;
    ctrl_is_lui      = 1'b0;
    ctrl_is_auipc    = 1'b0;
    illegal_instr    = 1'b0;

    case (opcode)
      7'b0110111: begin // LUI
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;
        ctrl_alu_op    = `ALU_PASS_B;
        ctrl_is_lui    = 1'b1;
      end
      7'b0010111: begin // AUIPC
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;
        ctrl_alu_op    = `ALU_ADD;
        ctrl_is_auipc  = 1'b1;
      end
      7'b1101111: begin // JAL
        ctrl_reg_write = 1'b1;
        ctrl_is_jal    = 1'b1;
      end
      7'b1100111: begin // JALR
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;
        ctrl_alu_op    = `ALU_ADD;
        ctrl_is_jalr   = 1'b1;
      end
      7'b1100011: begin // Branches
        ctrl_is_branch = 1'b1;
        ctrl_alu_src   = 1'b0;
        ctrl_alu_op    = `ALU_SUB;
      end
      7'b0000011: begin // Loads
        ctrl_reg_write  = 1'b1;
        ctrl_alu_src    = 1'b1;
        ctrl_alu_op     = `ALU_ADD;
        ctrl_mem_read   = 1'b1;
        ctrl_mem_to_reg = 1'b1;
        case (funct3)
          3'b000: begin ctrl_mem_width = `MEM_BYTE; ctrl_mem_unsigned = 1'b0; end
          3'b001: begin ctrl_mem_width = `MEM_HALF; ctrl_mem_unsigned = 1'b0; end
          3'b010: begin ctrl_mem_width = `MEM_WORD; ctrl_mem_unsigned = 1'b0; end
          3'b100: begin ctrl_mem_width = `MEM_BYTE; ctrl_mem_unsigned = 1'b1; end
          3'b101: begin ctrl_mem_width = `MEM_HALF; ctrl_mem_unsigned = 1'b1; end
          default: illegal_instr = 1'b1;
        endcase
      end
      7'b0100011: begin // Stores
        ctrl_alu_src   = 1'b1;
        ctrl_alu_op    = `ALU_ADD;
        ctrl_mem_write = 1'b1;
        case (funct3)
          3'b000: ctrl_mem_width = `MEM_BYTE;
          3'b001: ctrl_mem_width = `MEM_HALF;
          3'b010: ctrl_mem_width = `MEM_WORD;
          default: illegal_instr = 1'b1;
        endcase
      end
      7'b0010011: begin // I-type ALU
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b1;
        case (funct3)
          3'b000: ctrl_alu_op = `ALU_ADD;
          3'b010: ctrl_alu_op = `ALU_SLT;
          3'b011: ctrl_alu_op = `ALU_SLTU;
          3'b100: ctrl_alu_op = `ALU_XOR;
          3'b110: ctrl_alu_op = `ALU_OR;
          3'b111: ctrl_alu_op = `ALU_AND;
          3'b001: begin
            if (funct7 == 7'b0000000) ctrl_alu_op = `ALU_SLL;
            else illegal_instr = 1'b1;
          end
          3'b101: begin
            if (funct7 == 7'b0000000)      ctrl_alu_op = `ALU_SRL;
            else if (funct7 == 7'b0100000)  ctrl_alu_op = `ALU_SRA;
            else illegal_instr = 1'b1;
          end
          default: illegal_instr = 1'b1;
        endcase
      end
      7'b0110011: begin // R-type ALU
        ctrl_reg_write = 1'b1;
        ctrl_alu_src   = 1'b0;
        case ({funct7, funct3})
          {7'b0000000, 3'b000}: ctrl_alu_op = `ALU_ADD;
          {7'b0100000, 3'b000}: ctrl_alu_op = `ALU_SUB;
          {7'b0000000, 3'b001}: ctrl_alu_op = `ALU_SLL;
          {7'b0000000, 3'b010}: ctrl_alu_op = `ALU_SLT;
          {7'b0000000, 3'b011}: ctrl_alu_op = `ALU_SLTU;
          {7'b0000000, 3'b100}: ctrl_alu_op = `ALU_XOR;
          {7'b0000000, 3'b101}: ctrl_alu_op = `ALU_SRL;
          {7'b0100000, 3'b101}: ctrl_alu_op = `ALU_SRA;
          {7'b0000000, 3'b110}: ctrl_alu_op = `ALU_OR;
          {7'b0000000, 3'b111}: ctrl_alu_op = `ALU_AND;
          default: illegal_instr = 1'b1;
        endcase
      end
      7'b0001111: begin end // FENCE — NOP
      7'b1110011: begin end // SYSTEM — NOP
      default: illegal_instr = 1'b1;
    endcase
  end

endmodule
