`timescale 1ns/1ps
// `default_nettype none

`ifndef ADDR_WIDTH
`define ADDR_WIDTH 32
`endif

module tb;
  //--------------------------------------------------------------------------
  // Clock @ 100 MHz
  //--------------------------------------------------------------------------
  parameter CLK_PHASE=5;
  logic 		reset_n;
  logic 		clk;

  time startTime;
  time endTime;

  initial 
  begin
    clk                     = 1'b0;
    forever # CLK_PHASE clk = ~clk;
  end


  //string input_dir = "/home/jasteve4/TA/ECE-564-fall2025/project-dev/inputs";
  //string output_dir = "/home/jasteve4/TA/ECE-564-fall2025/project-dev/outputs";
  string input_dir =  "";
  string output_dir = "";
  string sim_dir = "";
  integer file_handle;
  event ev_load_memory;
  event ev_check_mem;

  //--------------------------------------------------------------------------
  // Runtime-config knobs (read from +plusargs)
  //   +tb_dqwidth=<N>      (fallback: +mc_dqwidth)
  //   +tb_burstlen=<N>     (fallback: +mc_burstlen, default 8)
  //   +tb_rdlat=<N>        (fallback: +mc_rdlat,   default -1 => wait for non-Z)
  //--------------------------------------------------------------------------
  localparam TB_DQW      = 8;   // default 16-bit "column width"
  localparam TB_BURST    = 8;    // default model burst length
  localparam TB_RDLAT    = 5;   // sample_wait; -1 => wait for non-Z
  localparam ADDRESS_WIDTH = `ADDR_WIDTH;

  localparam ADDRESS_OFFSET_WIDTH = 3;
  localparam DATA_MASK = 1<<TB_DQW-1;
  localparam MEM_WORD_WIDTH = TB_DQW<<ADDRESS_OFFSET_WIDTH;

  logic [MEM_WORD_WIDTH-1:0] ref_mem [longint];

  //--------------------------------------------------------------------------
  // Bus + TB-side IO
  //--------------------------------------------------------------------------
  wire 			ready;
  logic [ADDRESS_WIDTH-1:0] 		src0;
  logic [ADDRESS_WIDTH-1:0] 		src1;
  logic [ADDRESS_WIDTH-1:0] 		dst;
  logic 		valid;

  logic [1:0]  		CMD;
  logic [ADDRESS_WIDTH-1:0] 		Address;
  wire  [TB_DQW-1:0] 	DQ;           // actual bidirectional bus to mem_ctrl

  logic [TB_DQW-1:0] 	dut_DQ_din;   // TB drive data (we mask to TB_DQW)
  logic [TB_DQW-1:0] 	dut_DQ_dout;    // TB sampled bus
  logic        	     	DQ_oe_dut;    // TB tri-state enable (broadcast to all bits)

  //--------------------------------------------------------------------------
  // Memory controller (DPI model behind it)
  //--------------------------------------------------------------------------
  dram #(
    .ADDRESS_WIDTH(ADDRESS_WIDTH),
    .DQ_WIDTH(TB_DQW)
  ) dram_inst (
    .clk    (clk),
    .CMD    (CMD),
    .Address(Address),
    .DQ     (DQ)
  );

  tri_state_driver tri_dq_dut[TB_DQW-1:0] (
    .din 	(dut_DQ_din),
    .oe		(DQ_oe_dut),
    .pad    	(DQ),
    .dout 	(dut_DQ_dout)
  );

  dut #(
      .ADDRESS_WIDTH(ADDRESS_WIDTH),
      .DQ_WDITH(TB_DQW)
  ) dut_inst (
    .clk	(clk),
    .reset_n 	(reset_n), 
  
    .valid 	(valid),
    .ready 	(ready),
    .src0 	(src0),
    .src1 	(src1),
    .dst  	(dst),
 
 
    .CMD 	(CMD),
    .addr 	(Address),
    .dout	(dut_DQ_dout),
    .oe	        (DQ_oe_dut),
    .din	(dut_DQ_din)
  );

  //--------------------------------------------------------------------------
  // Helpers & Tasks
  //--------------------------------------------------------------------------
  // Place in a package or before any initial/always blocks
  function automatic bit compare_mem();
    foreach (ref_mem[k]) begin
      if (!tb.dram_inst.mem.exists(k))  return 0;
      if (tb.dram_inst.mem[k] !== ref_mem[k]) return 0;
    end
    return 1;
  endfunction



  function automatic int read_csv_addr3(string filename,ref int address[][3],input bit has_header = 0);
    
    int fd = $fopen(filename, "r");
    typedef int triple_t[3];
    triple_t rows[$]; 
    string line;
    int a, b, c;

    if (!fd) return -1;
    if (has_header) void'($fgets(line, fd));
    while ($fgets(line, fd)) begin
      if (line.len() == 0) continue;
      if (line.tolower().substr(0,0) == "#") continue;

      if ($sscanf(line, " %h , %h , %h ", a, b, c) == 3) begin
	rows.push_back('{a, b, c});
      end
    end
    
    $fclose(fd);
    address = new[rows.size()];
    for (int i = 0; i < rows.size(); i++) address[i] = rows[i];
    return address.size();
  endfunction

  int totalNumOfCases = 0;
  int totalNumOfPasses= 0;

  task automatic test(input int testNum);

    int n = 0;
    int addrs [][3];
    repeat(2) @(posedge clk);
    $display("INFO::[TB] ######## Running Test: %0d ########",testNum);
    $fdisplay(file_handle, "INFO::[TB] ######## Running Test: %0d #######",testNum);
    tb.dram_inst.mem.delete();
    tb.dram_inst.loadMem($sformatf("%s/input%0d.dat",input_dir,testNum));
    ref_mem.delete();
    $readmemh($sformatf("%s/output%0d.dat",output_dir,testNum),ref_mem);
    $display("INFO::[TB] Reading output memory file: '%s'", $sformatf("%s/output%0d.dat",output_dir,testNum));
    $display("%s",$sformatf("%s/input%0d.csv",input_dir,testNum));
    n = read_csv_addr3($sformatf("%s/input%0d.csv",input_dir,testNum), addrs, 0);
    repeat(2) @(posedge clk);
    ->ev_load_memory;
    reset_n = 'b1;
    valid   = 'b0;
    src0    = 'bx;
    src1    = 'bx;
    dst     = 'bx;

    repeat(2) @(posedge clk);
    reset_n = 1'b0;
    valid   = 'b0;
    src0    = 'b0;
    src1    = 'b0;
    dst     = 'b0;

    repeat(4) @(posedge clk);
    reset_n = 1'b1;
    for(int i=0;i<n;i++) begin
        @(posedge clk iff ready);
        valid = 'b1;
        src0 = addrs[i][0][ADDRESS_WIDTH-1:0];
        src1 = addrs[i][1][ADDRESS_WIDTH-1:0];
        dst  = addrs[i][2][ADDRESS_WIDTH-1:0];
        @(posedge clk);
        valid = 'b0;
        src0 = 'bx;
        src1 = 'bx;
        dst  = 'bx;
        @(posedge clk iff !ready);
    end

    @(posedge clk iff ready);
    totalNumOfCases++;

    ->ev_check_mem;
    $writememh($sformatf("%s/output%0d.dat",sim_dir,testNum), tb.dram_inst.mem);

    if (compare_mem()) begin
      $display("INFO::[TB] Test: Passed");
      $fdisplay(file_handle, "INFO:LVL0: Test: Passed");
      totalNumOfPasses++;
    end else begin
      $display("INFO::[TB] Test: Faild");
      $fdisplay(file_handle, "INFO:LVL0: Test: Faild");
    end
  endtask


  initial begin
      repeat (4000) @(posedge clk);
      $display("###################################");
      $display("             TIMEOUT               ");
      $display("###################################");
      $fdisplay(file_handle,"###################################");
      $fdisplay(file_handle,"             TIMEOUT               ");
      $fdisplay(file_handle,"###################################");
      $finish;
  end


  int n =0;
  int numOfTest = 2;
  int test_case = -1;
  string log_file;

  initial begin
    $dumpfile("waves.vcd"); $dumpvars(0, tb);
    if($value$plusargs("input_dir=%s",input_dir));
    if($value$plusargs("output_dir=%s",output_dir));
    if($value$plusargs("sim_output_dir=%s",sim_dir));
    if($value$plusargs("number_of_test=%d",numOfTest));
    if($value$plusargs("log_file=%s",log_file));
    if($value$plusargs("test=%d",test_case));
    file_handle = $fopen(log_file, "w"); 
    $display("[TB] start");
    $fdisplay(file_handle,"[TB] start");

    startTime=$time;
    if(test_case == -1) begin
      for(int i=0;i<numOfTest;i++) begin
        test(i);
      end
    end else begin
      test(test_case);
    end
    endTime=$time;
    $display("[TB] done");
    $fdisplay(file_handle,"[TB] done");
    if(totalNumOfCases != 0)
    begin
      $display("INFO[TB]: Total number of cases  : %0d",totalNumOfCases);
      $display("INFO[TB]: Total number of passes : %0d",totalNumOfPasses);
      $display("INFO[TB]: Finial Results         : %6.2f",(totalNumOfPasses * 100)/totalNumOfCases);
      $display("INFO[TB]: Finial Time Result     : %0t ",endTime-startTime);
      $display("INFO[TB]: Finial Cycle Result    : %0d cycles\n",((endTime-startTime)/CLK_PHASE));
      $fdisplay(file_handle,"INFO[TB]: Total number of cases  : %0d",totalNumOfCases);
      $fdisplay(file_handle,"INFO[TB]: Total number of passes : %0d",totalNumOfPasses);
      $fdisplay(file_handle,"INFO[TB]: Finial Results         : %6.2f",(totalNumOfPasses * 100)/totalNumOfCases);
      $fdisplay(file_handle,"INFO[TB]: Finial Time Result     : %0t ns",endTime-startTime);
      $fdisplay(file_handle,"INFO[TB]: Finial Cycle Result    : %0d cycles\n",((endTime-startTime)/CLK_PHASE));
    end
    $finish;
  end
endmodule

