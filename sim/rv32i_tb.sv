// ============================================================================
// rv32i_tb.sv — Self-Checking Testbench with SVA + Coverage
// ============================================================================

`timescale 1ns / 1ps

module rv32i_tb;

  parameter MAX_CYCLES = 10000;
  parameter INIT_FILE  = "program.hex";

  logic        clk;
  logic        rst_n;

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_byte_en;
  logic        dmem_wr_en, dmem_rd_en;

  // --- Clock ---
  initial clk = 0;
  always #5 clk = ~clk;

  // --- DUT ---
  rv32i_top u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall_in      (1'b0),
    .imem_addr     (imem_addr),
    .imem_rdata    (imem_rdata),
    .dmem_addr     (dmem_addr),
    .dmem_wdata    (dmem_wdata),
    .dmem_byte_en  (dmem_byte_en),
    .dmem_wr_en    (dmem_wr_en),
    .dmem_rd_en    (dmem_rd_en),
    .dmem_rdata    (dmem_rdata)
  );

  // --- Memory ---
  rv32i_mem #(
    .MEM_SIZE_BYTES (65536),
    .INIT_FILE      (INIT_FILE)
  ) u_mem (
    .clk           (clk),
    .rst_n         (rst_n),
    .imem_addr     (imem_addr),
    .imem_rdata    (imem_rdata),
    .dmem_addr     (dmem_addr),
    .dmem_wdata    (dmem_wdata),
    .dmem_byte_en  (dmem_byte_en),
    .dmem_wr_en    (dmem_wr_en),
    .dmem_rd_en    (dmem_rd_en),
    .dmem_rdata    (dmem_rdata)
  );

  // --- SVA Assertions ---
  rv32i_sva u_sva (
    .clk               (clk),
    .rst_n             (rst_n),
    .pc_r              (u_dut.pc_r),
    .pc_next           (u_dut.pc_next),
    .de_pc_r           (u_dut.de_pc_r),
    .de_instruction_r  (u_dut.de_instruction_r),
    .de_valid_r        (u_dut.de_valid_r),
    .de_ctrl_alu_op    (u_dut.de_ctrl_alu_op),
    .de_ctrl_alu_src   (u_dut.de_ctrl_alu_src),
    .de_ctrl_reg_write (u_dut.de_ctrl_reg_write),
    .de_ctrl_mem_read  (u_dut.de_ctrl_mem_read),
    .de_ctrl_mem_write (u_dut.de_ctrl_mem_write),
    .de_ctrl_is_branch (u_dut.de_ctrl_is_branch),
    .de_ctrl_is_jal    (u_dut.de_ctrl_is_jal),
    .de_ctrl_is_jalr   (u_dut.de_ctrl_is_jalr),
    .de_ctrl_is_lui    (u_dut.de_ctrl_is_lui),
    .de_ctrl_is_auipc  (u_dut.de_ctrl_is_auipc),
    .de_alu_result     (u_dut.de_alu_result),
    .de_branch_taken   (u_dut.de_branch_taken),
    .de_branch_target  (u_dut.de_branch_target),
    .mw_alu_result_r   (u_dut.mw_alu_result_r),
    .mw_rd_addr_r      (u_dut.mw_rd_addr_r),
    .mw_reg_write_r    (u_dut.mw_reg_write_r),
    .mw_mem_read_r     (u_dut.mw_mem_read_r),
    .mw_mem_write_r    (u_dut.mw_mem_write_r),
    .mw_valid_r        (u_dut.mw_valid_r),
    .stall             (u_dut.stall),
    .flush             (u_dut.flush),
    .dmem_addr         (dmem_addr),
    .dmem_byte_en      (dmem_byte_en),
    .dmem_wr_en        (dmem_wr_en),
    .dmem_rd_en        (dmem_rd_en)
  );

  // --- Functional Coverage ---
  rv32i_fcov u_fcov (
    .clk               (clk),
    .rst_n             (rst_n),
    .de_instruction_r  (u_dut.de_instruction_r),
    .de_valid_r        (u_dut.de_valid_r),
    .de_ctrl_alu_op    (u_dut.de_ctrl_alu_op),
    .de_ctrl_reg_write (u_dut.de_ctrl_reg_write),
    .de_ctrl_mem_read  (u_dut.de_ctrl_mem_read),
    .de_ctrl_mem_write (u_dut.de_ctrl_mem_write),
    .de_ctrl_mem_width (u_dut.de_ctrl_mem_width),
    .de_ctrl_is_branch (u_dut.de_ctrl_is_branch),
    .de_ctrl_is_jal    (u_dut.de_ctrl_is_jal),
    .de_ctrl_is_jalr   (u_dut.de_ctrl_is_jalr),
    .de_ctrl_is_lui    (u_dut.de_ctrl_is_lui),
    .de_ctrl_is_auipc  (u_dut.de_ctrl_is_auipc),
    .de_branch_taken   (u_dut.de_branch_taken),
    .stall             (u_dut.stall),
    .flush             (u_dut.flush),
    .mw_valid_r        (u_dut.mw_valid_r),
    .mw_mem_read_r     (u_dut.mw_mem_read_r),
    .mw_mem_write_r    (u_dut.mw_mem_write_r)
  );

  // --- VCD ---
  initial begin
    $dumpfile("rv32i_tb.vcd");
    $dumpvars(0, rv32i_tb);
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

      if (dmem_wr_en && dmem_addr == 32'hFFFFFFF0) begin
        test_done = 1;
        if (dmem_wdata == 32'd1) begin
          test_passed = 1;
          $display("*** PASS *** (cycle %0d)", cycle_count);
        end else begin
          test_passed = 0;
          $display("*** FAIL *** value=%0d (cycle %0d)", dmem_wdata, cycle_count);
        end
      end
    end

    if (!test_done)
      $display("*** TIMEOUT *** after %0d cycles", MAX_CYCLES);

    // Print assertion summary
    u_sva.report_assertions();

    // Print coverage report
    u_fcov.report_coverage();

    // Dump register file for constrained random comparison
    for (int i = 0; i < 32; i = i + 1) begin
      $display("REGDUMP x%0d %08h", i, u_dut.u_regfile.regs[i]);
    end

    #20;
    $finish;
  end

endmodule
