// ============================================================================
// rv32i_axi_tb.sv — AXI-Lite Integration Testbench
//
// Tests rv32i_axi_master with:
//   - Simple instruction ROM (same as original)
//   - AXI4-Lite slave memory for data port
//
// Uses the same pass/fail convention: write 1 to 0xFFFFFFF0 = PASS
// ============================================================================

`timescale 1ns / 1ps

module rv32i_axi_tb;

  parameter MAX_CYCLES = 50000;  // More cycles needed due to AXI latency
  parameter INIT_FILE  = "program.hex";

  logic        clk;
  logic        rst_n;

  // Instruction memory (simple interface)
  logic [31:0] imem_addr, imem_rdata;

  // AXI4-Lite signals
  logic [31:0] m_axi_awaddr;
  logic [2:0]  m_axi_awprot;
  logic        m_axi_awvalid, m_axi_awready;
  logic [31:0] m_axi_wdata;
  logic [3:0]  m_axi_wstrb;
  logic        m_axi_wvalid, m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid, m_axi_bready;
  logic [31:0] m_axi_araddr;
  logic [2:0]  m_axi_arprot;
  logic        m_axi_arvalid, m_axi_arready;
  logic [31:0] m_axi_rdata;
  logic [1:0]  m_axi_rresp;
  logic        m_axi_rvalid, m_axi_rready;

  // --- Clock ---
  initial clk = 0;
  always #5 clk = ~clk;

  // --- DUT: AXI Master (wraps rv32i_top) ---
  rv32i_axi_master u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .imem_addr      (imem_addr),
    .imem_rdata     (imem_rdata),
    .m_axi_awaddr   (m_axi_awaddr),
    .m_axi_awprot   (m_axi_awprot),
    .m_axi_awvalid  (m_axi_awvalid),
    .m_axi_awready  (m_axi_awready),
    .m_axi_wdata    (m_axi_wdata),
    .m_axi_wstrb    (m_axi_wstrb),
    .m_axi_wvalid   (m_axi_wvalid),
    .m_axi_wready   (m_axi_wready),
    .m_axi_bresp    (m_axi_bresp),
    .m_axi_bvalid   (m_axi_bvalid),
    .m_axi_bready   (m_axi_bready),
    .m_axi_araddr   (m_axi_araddr),
    .m_axi_arprot   (m_axi_arprot),
    .m_axi_arvalid  (m_axi_arvalid),
    .m_axi_arready  (m_axi_arready),
    .m_axi_rdata    (m_axi_rdata),
    .m_axi_rresp    (m_axi_rresp),
    .m_axi_rvalid   (m_axi_rvalid),
    .m_axi_rready   (m_axi_rready)
  );

  // --- Instruction ROM (simple, combinational read) ---
  localparam IMEM_WORDS = 16384;  // 64 KB
  reg [31:0] imem [0:IMEM_WORDS-1];

  integer imem_i;
  initial begin
    for (imem_i = 0; imem_i < IMEM_WORDS; imem_i = imem_i + 1)
      imem[imem_i] = 32'h0000_0013;
    $readmemh(INIT_FILE, imem);
  end

  wire [31:0] imem_word_addr = {2'b0, imem_addr[31:2]};
  assign imem_rdata = (imem_word_addr < IMEM_WORDS) ? imem[imem_word_addr] : 32'h0000_0013;

  // --- AXI Slave Data Memory ---
  rv32i_axi_mem #(
    .MEM_SIZE_BYTES (65536),
    .INIT_FILE      (INIT_FILE),
    .RESP_LATENCY   (1)
  ) u_axi_mem (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axi_awaddr   (m_axi_awaddr),
    .s_axi_awprot   (m_axi_awprot),
    .s_axi_awvalid  (m_axi_awvalid),
    .s_axi_awready  (m_axi_awready),
    .s_axi_wdata    (m_axi_wdata),
    .s_axi_wstrb    (m_axi_wstrb),
    .s_axi_wvalid   (m_axi_wvalid),
    .s_axi_wready   (m_axi_wready),
    .s_axi_bresp    (m_axi_bresp),
    .s_axi_bvalid   (m_axi_bvalid),
    .s_axi_bready   (m_axi_bready),
    .s_axi_araddr   (m_axi_araddr),
    .s_axi_arprot   (m_axi_arprot),
    .s_axi_arvalid  (m_axi_arvalid),
    .s_axi_arready  (m_axi_arready),
    .s_axi_rdata    (m_axi_rdata),
    .s_axi_rresp    (m_axi_rresp),
    .s_axi_rvalid   (m_axi_rvalid),
    .s_axi_rready   (m_axi_rready)
  );

  // --- VCD ---
  initial begin
    $dumpfile("rv32i_axi_tb.vcd");
    $dumpvars(0, rv32i_axi_tb);
  end

  // --- Test control ---
  integer cycle_count;
  logic test_done;
  logic test_passed;

  initial begin
    test_done   = 0;
    test_passed = 0;
    cycle_count = 0;

    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;

    while (!test_done && cycle_count < MAX_CYCLES) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;

      // Detect halt: AXI write to 0xFFFFFFF0
      if (m_axi_awvalid && m_axi_awaddr == 32'hFFFFFFF0 &&
          m_axi_wvalid && m_axi_wdata == 32'd1) begin
        test_done   = 1;
        test_passed = 1;
        $display("*** AXI PASS *** (cycle %0d)", cycle_count);
      end else if (m_axi_awvalid && m_axi_awaddr == 32'hFFFFFFF0 &&
                   m_axi_wvalid && m_axi_wdata != 32'd1) begin
        test_done   = 1;
        test_passed = 0;
        $display("*** AXI FAIL *** value=%0d (cycle %0d)", m_axi_wdata, cycle_count);
      end
    end

    if (!test_done)
      $display("*** AXI TIMEOUT *** after %0d cycles", MAX_CYCLES);

    // Dump registers
    for (int i = 0; i < 32; i = i + 1)
      $display("REGDUMP x%0d %08h", i, u_dut.u_core.u_regfile.regs[i]);

    #20;
    $finish;
  end

endmodule
