module fir_gen #(
	 parameter W_IN 			 = 11, // Input bit width
    parameter W_MU          = 22, // 2x for Multiplier width
    parameter W_ADD         = 23, // Adder width
    parameter W_O           = 13, // Output bit width 
    parameter L             = 4 , // Filter Length
	 parameter Mpipe         = 3  // pipeline stages of multiplier
	 //parameter divider       = 4   // Value to shift divide final output to bring out to LEDs
)	(
	 
	 input 						 clk, 
	 input 						 load_val, 
	 input signed [W_IN-1:0] val_in, 
	 
	 output signed [W_O-1:0] fir_out
); 


reg signed  [W_IN-1:0]  val;
wire signed [W_ADD-1:0] sumOfProd;

// 1D array types i.e. memories supported by Quartus
reg signed  [W_IN-1:0]  coeff   [0:3];  // Coefficient array
wire signed [W_MU-1:0]  product [0:3];  // Product array
reg signed  [W_ADD-1:0] adder   [0:3];  // Adder array
	
wire signed [W_MU-1:0] sum; 
wire clken;
wire aclr;

assign coeff_0 = 'd124;
assign coeff_1 = 'd214;
assign coeff_2 = 'd57;
assign coeff_3 = 'd33; 

assign sum   =0; 
assign aclr  =0; // Default for mult
assign clken =0;

// Load Data or Coefficient
always @(posedge clk)
	begin
		if (!load_val) begin
			coeff[3] <= coeff_3; // Store coefficient in register
			coeff[2] <= coeff_2; 
			coeff[1] <= coeff_1;
			coeff[0] <= coeff_0;		
		end
		else begin
			val <= val_in; // Get one data sample at a time
		end
	end
	
	
// Compute sum-of-products
always @(posedge clk)
	begin
	// Compute the transposed filter additions
		adder[0] <= product[0] + adder[1];
		adder[1] <= product[1] + adder[2];
		adder[2] <= product[2] + adder[3];
		adder[3] <= product[3]; // First TAP has only a register
	end

assign sumOfProd = adder[0];

genvar I; 
generate
for (I=0; I<L; I=I+1) 
	begin: MultGen
	// Instantiate L pipelined multiplier x*c[I] = p[I]
		lpm_mult mult_I (
			.clock(clk), 
			.dataa(val), 
			.datab(coeff[I]), 
			.result(product[I])
		// .sum(sum), 
		//	.clken(clken), 
		//	.aclr(aclr)
			);
			defparam mult_I.lpm_widtha = W_IN;
			defparam mult_I.lpm_widthb = W_IN;
			defparam mult_I.lpm_widthp = W_MU;
			defparam mult_I.lpm_widths = W_MU;
			defparam mult_I.lpm_pipeline = Mpipe;
			defparam mult_I.lpm_representation = "SIGNED";
	end
endgenerate

assign fir_out = sumOfProd[W_ADD-1:W_ADD-W_O];

endmodule	