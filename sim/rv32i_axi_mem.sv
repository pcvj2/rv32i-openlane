// ============================================================================
// rv32i_axi_mem.sv — AXI4-Lite Slave Memory Model (Simulation Only)
//
// Simple memory that responds to AXI4-Lite read/write transactions.
// Configurable response latency for testing pipeline stall behaviour.
// ============================================================================

module rv32i_axi_mem #(
  parameter MEM_SIZE_BYTES = 65536,
  parameter INIT_FILE      = "program.hex",
  parameter RESP_LATENCY   = 1          // Cycles before ready (1 = immediate)
) (
  input  wire        clk,
  input  wire        rst_n,

  // AXI4-Lite Slave Interface

  // Write Address
  input  wire [31:0] s_axi_awaddr,
  input  wire [2:0]  s_axi_awprot,
  input  wire        s_axi_awvalid,
  output reg         s_axi_awready,

  // Write Data
  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,
  input  wire        s_axi_wvalid,
  output reg         s_axi_wready,

  // Write Response
  output reg  [1:0]  s_axi_bresp,
  output reg         s_axi_bvalid,
  input  wire        s_axi_bready,

  // Read Address
  input  wire [31:0] s_axi_araddr,
  input  wire [2:0]  s_axi_arprot,
  input  wire        s_axi_arvalid,
  output reg         s_axi_arready,

  // Read Data
  output reg  [31:0] s_axi_rdata,
  output reg  [1:0]  s_axi_rresp,
  output reg         s_axi_rvalid,
  input  wire        s_axi_rready
);

  localparam NUM_WORDS = MEM_SIZE_BYTES / 4;
  reg [31:0] mem [0:NUM_WORDS-1];

  // ---- Initialization ----
  integer init_i;
  initial begin
    for (init_i = 0; init_i < NUM_WORDS; init_i = init_i + 1)
      mem[init_i] = 32'h0000_0013;
    $readmemh(INIT_FILE, mem);
  end

  // ---- Latency counters ----
  reg [7:0] rd_lat_cnt;
  reg [7:0] wr_lat_cnt;

  // ---- Read FSM ----
  reg [31:0] rd_addr_r;
  reg        rd_pending;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_arready <= 1'b0;
      s_axi_rdata   <= 32'b0;
      s_axi_rresp   <= 2'b00;
      s_axi_rvalid  <= 1'b0;
      rd_pending     <= 1'b0;
      rd_lat_cnt     <= 8'b0;
      rd_addr_r      <= 32'b0;
    end else begin
      // Default: deassert ready after handshake
      if (s_axi_arready && s_axi_arvalid)
        s_axi_arready <= 1'b0;

      // Accept read address
      if (s_axi_arvalid && !rd_pending && !s_axi_rvalid) begin
        s_axi_arready <= 1'b1;
        rd_addr_r     <= s_axi_araddr;
        rd_pending    <= 1'b1;
        rd_lat_cnt    <= RESP_LATENCY;
      end

      // Count down latency
      if (rd_pending && rd_lat_cnt > 0)
        rd_lat_cnt <= rd_lat_cnt - 1;

      // Produce read data
      if (rd_pending && rd_lat_cnt == 0 && !s_axi_rvalid) begin
        if ({2'b0, rd_addr_r[31:2]} < NUM_WORDS)
          s_axi_rdata <= mem[rd_addr_r[31:2]];
        else
          s_axi_rdata <= 32'hDEAD_BEEF;
        s_axi_rresp  <= 2'b00;  // OKAY
        s_axi_rvalid <= 1'b1;
        rd_pending   <= 1'b0;
      end

      // Clear rvalid after handshake
      if (s_axi_rvalid && s_axi_rready)
        s_axi_rvalid <= 1'b0;
    end
  end

  // ---- Write FSM ----
  reg [31:0] wr_addr_r;
  reg [31:0] wr_data_r;
  reg [3:0]  wr_strb_r;
  reg        aw_received, w_received;
  reg        wr_pending;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
      s_axi_bresp   <= 2'b00;
      s_axi_bvalid  <= 1'b0;
      aw_received    <= 1'b0;
      w_received     <= 1'b0;
      wr_pending     <= 1'b0;
      wr_lat_cnt     <= 8'b0;
      wr_addr_r      <= 32'b0;
      wr_data_r      <= 32'b0;
      wr_strb_r      <= 4'b0;
    end else begin
      // Deassert ready after handshake
      if (s_axi_awready && s_axi_awvalid)
        s_axi_awready <= 1'b0;
      if (s_axi_wready && s_axi_wvalid)
        s_axi_wready <= 1'b0;

      // Accept write address
      if (s_axi_awvalid && !aw_received && !wr_pending) begin
        s_axi_awready <= 1'b1;
        wr_addr_r     <= s_axi_awaddr;
        aw_received   <= 1'b1;
      end

      // Accept write data
      if (s_axi_wvalid && !w_received && !wr_pending) begin
        s_axi_wready <= 1'b1;
        wr_data_r    <= s_axi_wdata;
        wr_strb_r    <= s_axi_wstrb;
        w_received   <= 1'b1;
      end

      // Both received — start write
      if (aw_received && w_received && !wr_pending) begin
        wr_pending  <= 1'b1;
        wr_lat_cnt  <= RESP_LATENCY;
        aw_received <= 1'b0;
        w_received  <= 1'b0;
      end

      // Count down latency
      if (wr_pending && wr_lat_cnt > 0)
        wr_lat_cnt <= wr_lat_cnt - 1;

      // Execute write and produce response
      if (wr_pending && wr_lat_cnt == 0 && !s_axi_bvalid) begin
        if ({2'b0, wr_addr_r[31:2]} < NUM_WORDS) begin
          if (wr_strb_r[0]) mem[wr_addr_r[31:2]][7:0]   <= wr_data_r[7:0];
          if (wr_strb_r[1]) mem[wr_addr_r[31:2]][15:8]  <= wr_data_r[15:8];
          if (wr_strb_r[2]) mem[wr_addr_r[31:2]][23:16] <= wr_data_r[23:16];
          if (wr_strb_r[3]) mem[wr_addr_r[31:2]][31:24] <= wr_data_r[31:24];
        end
        s_axi_bresp  <= 2'b00;  // OKAY
        s_axi_bvalid <= 1'b1;
        wr_pending   <= 1'b0;
      end

      // Clear bvalid after handshake
      if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;
    end
  end

endmodule
