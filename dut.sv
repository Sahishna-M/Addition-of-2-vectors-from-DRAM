module dut #(
  parameter int ADDRESS_WIDTH = 32,
  parameter int DQ_WDITH = 8
)(
  // System Signals
  input  wire clk,
  input  wire reset_n, 
 
  // Control signals
  input  wire valid,
  output reg ready,

  // Data signals
  input  wire   [ADDRESS_WIDTH-1:0] src0,
  input  wire   [ADDRESS_WIDTH-1:0] src1,
  input  wire   [ADDRESS_WIDTH-1:0] dst,

  // SDR memory interface
  output reg   [1:0]  CMD,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output reg   [ADDRESS_WIDTH-1:0] addr,
  input  wire  signed[DQ_WDITH-1:0] dout,
  output reg   signed[DQ_WDITH-1:0] din,
  output reg  oe
);
// Start of your code

//DUT source and destination addresses - Intermediate registers
 reg   signed[DQ_WDITH-1:0] dut_src0 [0:7];
 reg   signed [DQ_WDITH-1:0] dut_sum [0:7];
 int temp;                                        //to store the addition value temporarily for clipping
 reg [4:0]burst_counter;                          //counter
 reg  [ADDRESS_WIDTH-1:0]src0_addr;               //To keep src0 address stable at the start
 reg  [ADDRESS_WIDTH-1:0]src1_addr;               //To keep src0 address stable at the start
 reg  [ADDRESS_WIDTH-1:0]dst_addr;                //To keep src0 address stable at the start

//states for DUT

typedef enum logic { 
Idle_dut = 1'b0, 
run = 1'b1
}dut_state;

dut_state current_state, next_state;        //declared current_state and next_state of type dut_state

// Taking inputs from Testbench driver 
always@(posedge clk)
begin
  if(!reset_n)                            //Reset must happen on active low
  begin
    current_state <= Idle_dut;
    burst_counter <= 4'b0000;
  end
  else 
  begin
    current_state <= next_state;

    if(current_state == Idle_dut && next_state == run)      // storing the src0, src1 and dst addresses at first posedge of clk
    begin
      src0_addr <= src0;
      src1_addr <= src1;
      dst_addr <= dst; 
    end   

    if(current_state == Idle_dut)         //Resetting counter if current state is idle
    begin
      burst_counter <= 5'b0;
    end

    else if(current_state == run)         // If current state is run, incerement the counter
    begin
      burst_counter <= burst_counter + 1;

      if(burst_counter >= 6 && burst_counter <= 13)     //Read latency is 5 cycles, next read request can be sent after 8 clock cycles
      begin
        dut_src0[burst_counter-6] <= dout;              // Loading values from dout into intermediate register after 5 clock cycles 
      end

      else if(burst_counter >= 14 && burst_counter <= 21)         // all values of src0 are obtained, src1 will be obtained now
      begin
        temp = dut_src0[burst_counter - 14] + dout;               //directly adding dout as src1 values are obtained only after 8 clock cyles from src0
        if(temp > 127) dut_sum[burst_counter - 14] <= 127;        //performing the subsequent steps to clip values in the range -128 <= value <= 127
        else if (temp < - 128) dut_sum[burst_counter - 14] <= -128;
        else dut_sum[burst_counter - 14] <= temp;  
      end
    
    end
  end
end

//State of DUT
always@(*)
begin
  addr = 32'h0; //giving default values to avoid any unintentional latches
  oe = 1'b0;
  din = 8'b0;
  ready = 1'b0;
  CMD = 2'b00;
  next_state = current_state;

  case (current_state)
  Idle_dut : begin
              ready = 1'b1;               // setting ready to 1 to obtain command from testbench
              CMD = 2'b00;
              oe = 1'b0;      
              next_state = (valid && ready) ? run : Idle_dut;
             end

  run : begin
          ready = 1'b0;                     //will be 0 throughout till this command is executed
          if(burst_counter == 0)            //assinging the src0 address to addr at t = 0
          begin
            CMD = 2'd1;
            addr = src0_addr;
            oe = 1'b0;            
          end

          else if(burst_counter == 8)       //assinging the src1 address to addr at t = 8 (8 cycle latency for read)
          begin
            CMD = 2'd1;
            addr = src1_addr; 
            oe = 1'b0;           
          end

          else if(burst_counter == 17)      //assinging the dst address to addr at t = 17 (9 cycle latency for write aftre read)
          begin
            CMD = 2'd2;
            addr = dst_addr;
            //oe = 1'b1;
          end

          else if(burst_counter >=22 && burst_counter <=29)       //loading computed values onto din after addition is done on both vectors at t = 22
          begin
            din = dut_sum[burst_counter - 22]; 
            oe = 1'b1;
          end

          else if(burst_counter == 30)        //Preparing for next set of commands by going into idle_state and resetting values
          begin
            next_state = Idle_dut;
            ready = 1'b1;
          end

        end
  endcase 
end

// End your code 
endmodule
