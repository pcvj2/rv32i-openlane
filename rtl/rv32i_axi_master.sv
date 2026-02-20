`include "rv32i_defs.vh"
// ============================================================================
// rv32i_axi_master.sv — AXI4-Lite Master Bridge
//
// Wraps rv32i_top, converting its simple data memory interface to AXI4-Lite.
// Instruction memory remains a simple interface (typically connected to
// a tightly-coupled ROM/SRAM).
//
// AXI4-Lite channels implemented:
//   AW (Write Address), W (Write Data), B (Write Response)
//   AR (Read Address), R (Read Data)
//
// Protocol: Single outstanding transaction. Core stalls while AXI
// transaction is in progress via the 'axi_stall' signal.
// ============================================================================

module rv32i_axi_master (
  input  wire        clk,
  input  wire        rst_n,

  // ---- Instruction Memory (simple, directly wired) ----
  output wire [31:0] imem_addr,
  input  wire [31:0] imem_rdata,

  // ---- AXI4-Lite Master Interface (data port) ----

  // Write Address Channel
  output reg  [31:0] m_axi_awaddr,
  output wire [2:0]  m_axi_awprot,
  output reg         m_axi_awvalid,
  input  wire        m_axi_awready,

  // Write Data Channel
  output reg  [31:0] m_axi_wdata,
  output reg  [3:0]  m_axi_wstrb,
  output reg         m_axi_wvalid,
  input  wire        m_axi_wready,

  // Write Response Channel
  input  wire [1:0]  m_axi_bresp,
  input  wire        m_axi_bvalid,
  output reg         m_axi_bready,

  // Read Address Channel
  output reg  [31:0] m_axi_araddr,
  output wire [2:0]  m_axi_arprot,
  output reg         m_axi_arvalid,
  input  wire        m_axi_arready,

  // Read Data Channel
  input  wire [31:0] m_axi_rdata,
  input  wire [1:0]  m_axi_rresp,
  input  wire        m_axi_rvalid,
  output reg         m_axi_rready
);

  // Protection: unprivileged, secure, data access
  assign m_axi_awprot = 3'b000;
  assign m_axi_arprot = 3'b000;

  // ---- Core Instance ----
  wire [31:0] core_dmem_addr;
  wire [31:0] core_dmem_wdata;
  wire [3:0]  core_dmem_byte_en;
  wire        core_dmem_wr_en;
  wire        core_dmem_rd_en;
  reg  [31:0] core_dmem_rdata;

  rv32i_top u_core (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall_in      (axi_stall),
    .imem_addr     (imem_addr),
    .imem_rdata    (imem_rdata),
    .dmem_addr     (core_dmem_addr),
    .dmem_wdata    (core_dmem_wdata),
    .dmem_byte_en  (core_dmem_byte_en),
    .dmem_wr_en    (core_dmem_wr_en),
    .dmem_rd_en    (core_dmem_rd_en),
    .dmem_rdata    (core_dmem_rdata)
  );

  // ========================================================================
  // AXI-Lite State Machine
  // ========================================================================
  //
  // States:
  //   IDLE     — waiting for core memory request
  //   RD_ADDR  — AR channel handshake
  //   RD_DATA  — R channel handshake, return data to core
  //   WR_ADDR  — AW + W channel handshake (issued simultaneously)
  //   WR_RESP  — B channel handshake
  //
  // The core is stalled (held) whenever the FSM is not in IDLE.

  localparam [2:0] S_IDLE    = 3'd0;
  localparam [2:0] S_RD_ADDR = 3'd1;
  localparam [2:0] S_RD_DATA = 3'd2;
  localparam [2:0] S_WR_ADDR = 3'd3;
  localparam [2:0] S_WR_RESP = 3'd4;

  reg [2:0] state_r, state_next;

  // Track which write sub-channels have completed
  reg aw_done_r, w_done_r;

  // Latched read data
  reg [31:0] rdata_r;

  // Stall signal to core — active immediately when starting or during AXI transaction
  // Uses state_next so stall takes effect on the SAME cycle as the memory request
  wire axi_stall = (state_next != S_IDLE);

  // ---- State register ----
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state_r <= S_IDLE;
    else
      state_r <= state_next;
  end

  // ---- Next state logic ----
  always @(*) begin
    state_next = state_r;
    case (state_r)
      S_IDLE: begin
        if (core_dmem_rd_en)
          state_next = S_RD_ADDR;
        else if (core_dmem_wr_en)
          state_next = S_WR_ADDR;
      end

      S_RD_ADDR: begin
        if (m_axi_arready && m_axi_arvalid)
          state_next = S_RD_DATA;
      end

      S_RD_DATA: begin
        if (m_axi_rvalid && m_axi_rready)
          state_next = S_IDLE;
      end

      S_WR_ADDR: begin
        // Both AW and W must complete before moving to response
        if ((aw_done_r || (m_axi_awready && m_axi_awvalid)) &&
            (w_done_r  || (m_axi_wready  && m_axi_wvalid)))
          state_next = S_WR_RESP;
      end

      S_WR_RESP: begin
        if (m_axi_bvalid && m_axi_bready)
          state_next = S_IDLE;
      end

      default: state_next = S_IDLE;
    endcase
  end

  // ---- AW/W completion tracking ----
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_done_r <= 1'b0;
      w_done_r  <= 1'b0;
    end else if (state_r == S_WR_ADDR) begin
      if (m_axi_awready && m_axi_awvalid)
        aw_done_r <= 1'b1;
      if (m_axi_wready && m_axi_wvalid)
        w_done_r <= 1'b1;
    end else begin
      aw_done_r <= 1'b0;
      w_done_r  <= 1'b0;
    end
  end

  // ---- Output logic ----

  // Read Address Channel
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_araddr  <= 32'b0;
      m_axi_arvalid <= 1'b0;
    end else if (state_r == S_IDLE && core_dmem_rd_en) begin
      m_axi_araddr  <= core_dmem_addr;
      m_axi_arvalid <= 1'b1;
    end else if (m_axi_arready && m_axi_arvalid) begin
      m_axi_arvalid <= 1'b0;
    end
  end

  // Read Data Channel
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_rready <= 1'b0;
      rdata_r      <= 32'b0;
    end else if (state_r == S_RD_ADDR && m_axi_arready && m_axi_arvalid) begin
      m_axi_rready <= 1'b1;
    end else if (m_axi_rvalid && m_axi_rready) begin
      rdata_r      <= m_axi_rdata;
      m_axi_rready <= 1'b0;
    end
  end

  // Write Address Channel
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_awaddr  <= 32'b0;
      m_axi_awvalid <= 1'b0;
    end else if (state_r == S_IDLE && core_dmem_wr_en) begin
      m_axi_awaddr  <= core_dmem_addr;
      m_axi_awvalid <= 1'b1;
    end else if (m_axi_awready && m_axi_awvalid) begin
      m_axi_awvalid <= 1'b0;
    end
  end

  // Write Data Channel
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_wdata  <= 32'b0;
      m_axi_wstrb  <= 4'b0;
      m_axi_wvalid <= 1'b0;
    end else if (state_r == S_IDLE && core_dmem_wr_en) begin
      m_axi_wdata  <= core_dmem_wdata;
      m_axi_wstrb  <= core_dmem_byte_en;
      m_axi_wvalid <= 1'b1;
    end else if (m_axi_wready && m_axi_wvalid) begin
      m_axi_wvalid <= 1'b0;
    end
  end

  // Write Response Channel
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      m_axi_bready <= 1'b0;
    else if (state_next == S_WR_RESP)
      m_axi_bready <= 1'b1;
    else if (m_axi_bvalid && m_axi_bready)
      m_axi_bready <= 1'b0;
  end

  // ---- Data return to core ----
  // Core sees latched read data when returning from read transaction
  always @(*) begin
    if (state_r == S_RD_DATA && m_axi_rvalid)
      core_dmem_rdata = m_axi_rdata;
    else
      core_dmem_rdata = rdata_r;
  end

endmodule
