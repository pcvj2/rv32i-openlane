// ============================================================================
// rv32i_regfile.sv — 32×32-bit Register File with write-forwarding
// ============================================================================

module rv32i_regfile (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [4:0]  rs1_addr,
  input  wire [4:0]  rs2_addr,
  output wire [31:0] rs1_data,
  output wire [31:0] rs2_data,
  input  wire        wr_en,
  input  wire [4:0]  wr_addr,
  input  wire [31:0] wr_data
);

  reg [31:0] regs [0:31];
  integer i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 32; i = i + 1)
        regs[i] <= 32'b0;
    end else if (wr_en && wr_addr != 5'b0) begin
      regs[wr_addr] <= wr_data;
    end
  end

  assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 :
                    (wr_en && rs1_addr == wr_addr) ? wr_data : regs[rs1_addr];

  assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 :
                    (wr_en && rs2_addr == wr_addr) ? wr_data : regs[rs2_addr];

endmodule
