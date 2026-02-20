// ============================================================================
// rv32i_mem.sv — Simulation Memory Model
//
// Unified memory with separate instruction and data ports.
// Byte-addressable, word-aligned reads, byte-enable writes.
// Loads initial program from hex file.
// ============================================================================

module rv32i_mem #(
  parameter MEM_SIZE_BYTES = 65536,  // 64 KB
  parameter INIT_FILE      = "program.hex"
) (
  input  logic        clk,
  input  logic        rst_n,

  // Instruction port (read-only, word-aligned)
  input  logic [31:0] imem_addr,
  output logic [31:0] imem_rdata,

  // Data port
  input  logic [31:0] dmem_addr,
  input  logic [31:0] dmem_wdata,
  input  logic [3:0]  dmem_byte_en,
  input  logic        dmem_wr_en,
  input  logic        dmem_rd_en,
  output logic [31:0] dmem_rdata
);

  localparam NUM_WORDS = MEM_SIZE_BYTES / 4;

  logic [31:0] mem [0:NUM_WORDS-1];

  // --- Initialization ---
  initial begin
    for (int i = 0; i < NUM_WORDS; i++)
      mem[i] = 32'h0000_0013; // NOP (ADDI x0, x0, 0)
    $readmemh(INIT_FILE, mem);
  end

  // --- Instruction read (combinational, word-aligned) ---
  wire [31:0] imem_word_addr = {2'b0, imem_addr[31:2]};
  assign imem_rdata = (imem_word_addr < NUM_WORDS) ? mem[imem_word_addr] : 32'h0000_0013;

  // --- Data read (combinational) ---
  wire [31:0] dmem_word_addr = {2'b0, dmem_addr[31:2]};
  assign dmem_rdata = (dmem_rd_en && dmem_word_addr < NUM_WORDS) ? mem[dmem_word_addr] : 32'b0;

  // --- Data write (synchronous, byte-granular) ---
  always_ff @(posedge clk) begin
    if (dmem_wr_en && dmem_word_addr < NUM_WORDS) begin
      if (dmem_byte_en[0]) mem[dmem_word_addr][7:0]   <= dmem_wdata[7:0];
      if (dmem_byte_en[1]) mem[dmem_word_addr][15:8]  <= dmem_wdata[15:8];
      if (dmem_byte_en[2]) mem[dmem_word_addr][23:16] <= dmem_wdata[23:16];
      if (dmem_byte_en[3]) mem[dmem_word_addr][31:24] <= dmem_wdata[31:24];
    end
  end

endmodule
