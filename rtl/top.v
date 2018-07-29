// Description  | Shift in key, read analog inputs using ADC, send through FIR filter, output to LEDs if over threshold
//              | 
//              | I2C Register Map:
//              | Base = 0x30 (Wr base: 0x60, Rd base: 0x61)
//              | 	01: ADC start/stop
//              | 		[7:1]	unused
//              | 		[0]   1 = start, 0 = stop
// ----------------------------------------------------------------------------

`timescale 1ns/1ps


module top (
	
	//clock
	input					xxCLK,
	
	//JTAG
	input 				xxTCK,
	input 				xxRST_N,
	input 				xxTDI,
	input 				xxTMS,
	output 				xxTDO,
	
	//i2c
	input					xxSCL,
	inout					xxSDA,
	
	//GPIO
	output	[7:0]		OUT_LED
);



	reg					reset_n_r;
	reg					reset_n_rr;
	wire					clk_core;
	wire					clk_adc;
	wire					locked;
	reg			      adc_response_valid;
	reg [4:0]	      adc_response_channel;
	reg [11:0]	      adc_response_data;
	reg		         adc_response_startofpacket;
	reg			      adc_response_endofpacket;
	reg		         adc_sequencer_csr_address;
	reg			      adc_sequencer_csr_read;
	reg			      adc_sequencer_csr_write;
	reg  [31:0]	      adc_sequencer_csr_writedata;
	reg  [31:0]	      adc_sequencer_csr_readdata;
	wire [7:0]        adc_cmd;
	reg  [7:0]        autoreg;	
	reg  [7:0]	      reg_ch0_upper, reg_ch0_lower;
	reg  [7:0]	      reg_ch1_upper, reg_ch1_lower;
	reg  [7:0]	      reg_ch2_upper, reg_ch2_lower;
   reg  [7:0]	      reg_ch3_upper, reg_ch3_lower;
   reg  [7:0]	      reg_ch4_upper, reg_ch4_lower;
   reg  [7:0]	      reg_ch5_upper, reg_ch5_lower;
   reg               adc_run, adc_run_r, adc_run_rr, adc_stop;
	reg					initial_turnon, initial_turnon_r, initial_turnon_rr;
   reg  [11:0]       adc_ch0_raw_data;
   reg  [11:0]       adc_ch1_raw_data;
   reg  [11:0]       adc_ch2_raw_data;
   reg  [11:0]       adc_ch3_raw_data;
   reg  [11:0]       adc_ch4_raw_data;
   reg  [11:0]       adc_ch5_raw_data;
   wire [12:0]       adc_ch0_fir_data;
   wire [12:0]       adc_ch1_fir_data;
   wire [12:0]       adc_ch2_fir_data;
   wire [12:0]       adc_ch3_fir_data;
   wire [12:0]       adc_ch4_fir_data;
   wire [12:0]       adc_ch5_fir_data;
	wire [11:0]			thrsh_val;
	wire [31:0]	      key;
	reg  [31:0]	      shift_key;
	wire              key_valid;


//--------------------------
//	PLL
//-----------
pll pll_inst (
   .inclk0 ( xxCLK ),
   .c0 ( clk_adc ),	// 10 MHz clock dedicated to ADC
   .c1 ( clk_core ),	// 50 MHz system clock
   .locked ( locked )
);


//--------------------------
//	Reset - Synchronous deassert after PLL locked
//-----------
//Synchronize Reset
always @(posedge xxCLK) begin
	if (!locked)
		begin
		reset_n_r <= 1'b0;
		reset_n_rr <= 1'b0;
		end
	else
		begin
		reset_n_r <= 1'b1;
		reset_n_rr <= reset_n_r;
		end
end



//--------------------------
//	The I2C Slave
//-----------
i2cSlave i2c_inst(
	.clk (clk_core),
	.rst (!reset_n_rr),
	.sda (xxSDA),
	.scl (xxSCL),
	.reg0_auto_in (autoreg[7:0]),
   .reg1_adc_cmd_out (adc_cmd), 
   .reg2_ch0_upper_in (reg_ch0_upper),
   .reg3_ch0_lower_in (reg_ch0_lower),
   .reg4_ch1_upper_in (reg_ch1_upper),
   .reg5_ch1_lower_in (reg_ch1_lower),
   .reg6_ch2_upper_in (reg_ch2_upper),
   .reg7_ch2_lower_in (reg_ch2_lower),
   .reg8_ch3_upper_in (reg_ch3_upper),
   .reg9_ch3_lower_in (reg_ch3_lower),
   .reg10_ch4_upper_in (reg_ch4_upper),
   .reg11_ch4_lower_in (reg_ch4_lower),
   .reg12_ch5_upper_in (reg_ch5_upper),
   .reg13_ch5_lower_in (reg_ch5_lower),	
);

//--------------------------
//	Shift in correct key value via JTAG pins, and check if key matches
//-----------

always @(posedge xxTCK) begin
	if (!xxRST_N)
			shift_key <= 0;
	else 
		if (xxTMS)
			shift_key <= {shift_key[31:0], xxTDI};
end
		
assign key = 32'hDEADBEEF;
assign key_valid = (key==shift_key);  



//--------------------------
//	ADC Commands
//-----------

// Begin ADC 2 clocks after reset deasserts or obtain start and stop ADC commands from I2C
always @(posedge clk_core or negedge reset_n_rr) begin
   if (!reset_n_rr) 
		begin
			adc_run_r <= 1'b0;
			adc_run_rr <= 1'b0;
			adc_run <= 1'b0;
			initial_turnon <= 1'b1;
			initial_turnon_r <= 1'b0;
			initial_turnon_rr <= 1'b0;
		end 
	else 
		begin
			initial_turnon <= 1'b0;
			initial_turnon_r <= initial_turnon;
			initial_turnon_rr <= initial_turnon_r;
			adc_run_r <= adc_cmd[0];
			adc_run_rr <= adc_run_r;
			
			if (initial_turnon_rr) 
				begin
					adc_run <= 1'b1;
				end 
			else 
				// Rising edge detect
				if (adc_run_r & ~adc_run_rr) 
					begin  
						adc_run <= 1'b1;
					end 
				else 
					begin
						adc_run <= 1'b0;
					end 
				// Falling edge detect	
				if (!adc_run_r & adc_run_rr) 
					begin  
						adc_stop <= 1'b1;
					end 
				else 
					begin
						adc_stop <= 1'b0;
					end 
		end
	end

// Issue ADC sequencer start and stop commands
always @(posedge clk_core or negedge reset_n_rr) begin
   if (!reset_n_rr) begin
      adc_sequencer_csr_address <= 1'b0;
      adc_sequencer_csr_read <= 1'b0;
      adc_sequencer_csr_write <= 1'b0;
      adc_sequencer_csr_writedata <= 32'b0;
   end 
	else begin
      if (adc_run && key_valid) begin
  	      adc_sequencer_csr_address <= 1'b0;
	      adc_sequencer_csr_read <= 1'b0;
	      adc_sequencer_csr_write <= 1'b1;
	      adc_sequencer_csr_writedata <= 32'b1;
      end else if (adc_stop) begin
  	      adc_sequencer_csr_address <= 1'b0;
	      adc_sequencer_csr_read <= 1'b0;
	      adc_sequencer_csr_write <= 1'b1;
	      adc_sequencer_csr_writedata <= 32'b0;
	   end else begin
	 	   adc_sequencer_csr_address <= 1'b0;
	      adc_sequencer_csr_read <= 1'b0;
	      adc_sequencer_csr_write <= 1'b0;
	      adc_sequencer_csr_writedata <= 32'b0;
      end
   end
end


//--------------------------
//	ADC- 6 channels: ch 0-5
//-----------

adc u0 (
	.clk_clk                     (clk_core),                    //               clk.clk
	.reset_reset_n               (reset_n_rr),                  //             reset.reset_n
	.adc_pll_clock_clk           (clk_adc),                    	//     adc_pll_clock.clk
	.adc_pll_locked_export       (locked),                   	//    adc_pll_locked.export
	.adc_response_valid          (adc_response_valid),     		//      adc_response.valid
	.adc_response_channel        (adc_response_channel),        //                  .channel
	.adc_response_data           (adc_response_data),           //                  .data
	.adc_response_startofpacket  (adc_response_startofpacket),  //                  .startofpacket
	.adc_response_endofpacket    (adc_response_endofpacket),    //                  .endofpacket
	.adc_sequencer_csr_address   (adc_sequencer_csr_address),   // adc_sequencer_csr.address
	.adc_sequencer_csr_read      (adc_sequencer_csr_read),      //                  .read
	.adc_sequencer_csr_write     (adc_sequencer_csr_write),     //                  .write
	.adc_sequencer_csr_writedata (adc_sequencer_csr_writedata), //                  .writedata
	.adc_sequencer_csr_readdata  (adc_sequencer_csr_readdata)   //                  .readdata
);


//--------------------------
//	Capture ADC channel data
//-----------

always @(posedge clk_core or negedge reset_n_rr) begin
   if (!reset_n_rr) begin
		adc_ch0_raw_data <= 12'b0;
		adc_ch1_raw_data <= 12'b0;
		adc_ch2_raw_data <= 12'b0;
		adc_ch3_raw_data <= 12'b0;
		adc_ch4_raw_data <= 12'b0;
		adc_ch5_raw_data <= 12'b0;
   end else begin
      if (adc_response_valid) begin 
         case (adc_response_channel)
            5'h00: adc_ch0_raw_data <= adc_response_data;
            5'h01: adc_ch1_raw_data <= adc_response_data;
            5'h02: adc_ch2_raw_data <= adc_response_data;
            5'h03: adc_ch3_raw_data <= adc_response_data;
            5'h04: adc_ch4_raw_data <= adc_response_data;
            5'h05: adc_ch5_raw_data <= adc_response_data;
         endcase
      end
   end
end


//--------------------------
//	FIR filter for ADC ch 0-5
//	Filters raw data using Daubechies
//-----------

fir_gen fir_gen0_inst (
	 .clk      (clk_adc), 
	 .load_val (adc_response_valid), 
	 .val_in   (adc_ch0_raw_data), 
	 .fir_out  (adc_ch0_fir_data)
);

fir_gen fir_gen1_inst (
	 .clk      (clk_adc), 
	 .load_val (adc_response_valid), 
	 .val_in   (adc_ch1_raw_data), 
	 .fir_out  (adc_ch1_fir_data)
);

fir_gen fir_gen2_inst (
	 .clk      (clk_adc), 
	 .load_val (adc_response_valid), 
	 .val_in   (adc_ch2_raw_data), 
	 .fir_out  (adc_ch2_fir_data)
);

fir_gen fir_gen3_inst (
	 .clk      (clk_adc), 
	 .load_val (adc_response_valid), 
	 .val_in   (adc_ch3_raw_data), 
	 .fir_out  (adc_ch3_fir_data)
);

fir_gen fir_gen4_inst (
	 .clk      (clk_adc), 
	 .load_val (adc_response_valid), 
	 .val_in   (adc_ch4_raw_data), 
	 .fir_out  (adc_ch4_fir_data)
);

fir_gen fir_gen5_inst (
	 .clk      (clk_adc), 
	 .load_val (adc_response_valid), 
	 .val_in   (adc_ch5_raw_data), 
	 .fir_out  (adc_ch5_fir_data)
);


always @(posedge clk_core or negedge reset_n_rr) begin
	if (!reset_n_rr) begin
      reg_ch0_upper <= 8'b0;
      reg_ch0_lower <= 8'b0;	
      reg_ch1_upper <= 8'b0;
      reg_ch1_lower <= 8'b0;	
      reg_ch2_upper <= 8'b0;
      reg_ch2_lower <= 8'b0;	
      reg_ch3_upper <= 8'b0;
      reg_ch3_lower <= 8'b0;	
      reg_ch4_upper <= 8'b0;
      reg_ch4_lower <= 8'b0;	
      reg_ch5_upper <= 8'b0;
      reg_ch5_lower <= 8'b0;	
	end else begin
	   if (adc_response_endofpacket) begin
			{reg_ch0_upper, reg_ch0_lower} <= {4'b0, adc_ch0_fir_data[11:0]}; 
			{reg_ch1_upper, reg_ch1_lower} <= {4'b0, adc_ch1_fir_data[11:0]}; 
			{reg_ch2_upper, reg_ch2_lower} <= {4'b0, adc_ch2_fir_data[11:0]}; 
			{reg_ch3_upper, reg_ch3_lower} <= {4'b0, adc_ch3_fir_data[11:0]}; 
			{reg_ch4_upper, reg_ch4_lower} <= {4'b0, adc_ch4_fir_data[11:0]}; 
			{reg_ch5_upper, reg_ch5_lower} <= {4'b0, adc_ch5_fir_data[11:0]}; 
		end
	end
end



//--------------------------
// Output channels to LEDs if over threshold value
//-----------



assign thrsh_val = 12'hA0D;
								
assign OUT_LED[0] = ~({reg_ch0_upper[4:0],reg_ch0_lower} > thrsh_val); 								
assign OUT_LED[1] = ~({reg_ch1_upper[4:0],reg_ch1_lower} > thrsh_val);								
assign OUT_LED[2] = ~({reg_ch2_upper[4:0],reg_ch2_lower} > thrsh_val);								
assign OUT_LED[3] = ~({reg_ch3_upper[4:0],reg_ch3_lower} > thrsh_val);
assign OUT_LED[4] = ~({reg_ch4_upper[4:0],reg_ch4_lower} > thrsh_val);
assign OUT_LED[5] = ~({reg_ch5_upper[4:0],reg_ch5_lower} > thrsh_val);

endmodule
