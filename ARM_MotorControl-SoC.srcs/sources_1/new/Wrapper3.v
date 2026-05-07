`timescale 1ns / 1ps
//>>>>>>>>>>>> ******* FOR SIMULATION. DO NOT SYNTHESIZE THIS DIRECTLY (This is used as a component in TOP.v for Synthesis) ******* <<<<<<<<<<<<

module Wrapper
#(
	parameter N_LEDs = 16,       // Number of LEDs displaying Result. LED(15 downto 15-N_LEDs+1). 16 by default
	parameter N_DIPs = 7         // Number of DIPs. 16 by default	                             
)
(
	input  [N_DIPs-1:0] DIP, 		 		// DIP switch inputs, used as a user definied memory address for checking memory content.
	output reg [N_LEDs-1:0] LED, 	// LED light display. Display the value of program counter.
	output reg [31:0] SEVENSEGHEX, 			// 7 Seg LED Display. The 32-bit value will appear as 8 Hex digits on the display. Used to display memory content.
	input  RESET,							// Active high.
	input  CLK,								// Divided Clock from TOP.
	
	// NEW: Route PWM signals out to observe them in simulation!
    output wire pwm_u,
    output wire pwm_v,
    output wire pwm_w
);                                             

//----------------------------------------------------------------
// ARM signals
//----------------------------------------------------------------
wire[31:0] PC ;
wire[31:0] Instr ;
reg[31:0] ReadData ;
wire MemWrite ;
wire[31:0] ALUResult ;
wire[31:0] WriteData ;

//----------------------------------------------------------------
// Address Decode signals
//---------------------------------------------------------------
wire dec_DATA_CONST, dec_DATA_VAR;  // 'enable' signals from data memory address decoding

//----------------------------------------------------------------
// Memory read for IO signals
//----------------------------------------------------------------
wire [31:0] ReadData_IO;

//----------------------------------------------------------------
// Memory declaration
//-----------------------------------------------------------------
reg [31:0] INSTR_MEM		[0:127]; // instruction memory
reg [31:0] DATA_CONST_MEM	[0:127]; // data (constant) memory
reg [31:0] DATA_VAR_MEM     [0:127]; // data (variable) memory
integer i;

// ----------------------------------------------------------------
// Data (Constant) Memory - Stores the values we want to use
// ----------------------------------------------------------------
initial begin
    for(i = 0; i < 128; i = i+1) DATA_CONST_MEM[i] = 32'h0;
    
    DATA_CONST_MEM[0] = 32'h00000A00; // Index 0 (Addr 0): PWM Base Address
    DATA_CONST_MEM[1] = 32'h00000064; // Index 1 (Addr 4): Period = 100 cycles
    DATA_CONST_MEM[2] = 32'h00000019; // Index 2 (Addr 8): Phase U = 25 (25% Duty)
    DATA_CONST_MEM[3] = 32'h00000032; // Index 3 (Addr 12): Phase V = 50 (50% Duty)
    DATA_CONST_MEM[4] = 32'h0000004B; // Index 4 (Addr 16): Phase W = 75 (75% Duty)
end

// ----------------------------------------------------------------
// Instruction Memory - The ARM Machine Code
// ----------------------------------------------------------------
initial begin
    for(i = 0; i < 128; i = i+1) INSTR_MEM[i] = 32'hEAFFFFFE; // Default: Branch to self
    
    // 1. Load values from Constant Memory
    INSTR_MEM[0] = 32'hE3A01000; // MOV R1, #0
    INSTR_MEM[1] = 32'hE5910000; // LDR R0, [R1, #0]  -> R0 = 0x00000A00
    INSTR_MEM[2] = 32'hE5912004; // LDR R2, [R1, #4]  -> R2 = 100
    INSTR_MEM[3] = 32'hE5913008; // LDR R3,[R1, #8]  -> R3 = 25
    INSTR_MEM[4] = 32'hE591400C; // LDR R4,[R1, #12] -> R4 = 50
    INSTR_MEM[5] = 32'hE5915010; // LDR R5, [R1, #16] -> R5 = 75

    // 2. Memory-Mapped I/O Writes to the PWM Peripheral
    INSTR_MEM[6] = 32'hE5802000; // STR R2, [R0, #0]  -> Write Period
    INSTR_MEM[7] = 32'hE5803004; // STR R3, [R0, #4]  -> Write Phase U
    INSTR_MEM[8] = 32'hE5804008; // STR R4, [R0, #8]  -> Write Phase V
    INSTR_MEM[9] = 32'hE580500C; // STR R5,[R0, #12] -> Write Phase W
    
    // 10. Halt
    INSTR_MEM[10] = 32'hEAFFFFFE; // B loop
end
// ----------------------------------------------------------------
// Data (Variable) Memory - Stores the value pointed to by R5
// ----------------------------------------------------------------
initial begin
    for(i = 0; i < 128; i = i+1) DATA_VAR_MEM[i] = 32'h0;

    // Value 3 at Address 0x810 (Index 4)
    DATA_VAR_MEM[4] = 32'h00000003; 
end


//----------------------------------------------------------------
// ARM port map
//----------------------------------------------------------------
ARM ARM1(
	CLK,
	RESET,
	Instr,
	ReadData,
	MemWrite,
	PC,
	ALUResult,
	WriteData
);
//----------------------------------------------------------------
// Motor Control PWM Peripheral
//----------------------------------------------------------------
wire dec_PWM; 

wire pwm_u_out, pwm_v_out, pwm_w_out;

PWM_Generator motor_pwm (
    .clk(CLK),
    .reset(RESET),
    .we(MemWrite && dec_PWM), // Only write if MemWrite is high AND address matches PWM space
    .addr(ALUResult),         // Pass the address to select the register
    .wdata(WriteData),        // Pass the data from the CPU
    .pwm_u(pwm_u),            // CHANGED: Connect directly to the output port
    .pwm_v(pwm_v),            // CHANGED: Connect directly to the output port
    .pwm_w(pwm_w)             // CHANGED: Connect directly to the output port
);
//----------------------------------------------------------------
// Data memory address decoding
//----------------------------------------------------------------
assign dec_DATA_CONST = (ALUResult < 32'h00000200) ? 1'b1 : 1'b0;
assign dec_DATA_VAR			= (ALUResult >= 32'h00000200 && ALUResult <= 32'h000009FC) ? 1'b1 : 1'b0;


// NEW: Assign PWM registers to address space 0x00000A00 to 0x00000A0C

assign dec_PWM = (ALUResult >= 32'h00000A00 && ALUResult <= 32'h00000A0C) ? 1'b1 : 1'b0;



//----------------------------------------------------------------
// Data memory read 1
//----------------------------------------------------------------
always@( * ) begin
if (dec_DATA_VAR)
	ReadData <= DATA_VAR_MEM[ALUResult[8:2]] ; 
else if (dec_DATA_CONST)
	ReadData <= DATA_CONST_MEM[ALUResult[8:2]] ; 	
else
	ReadData <= 32'h0 ; 
end

//----------------------------------------------------------------
// Data memory read 2
//----------------------------------------------------------------
assign ReadData_IO = DATA_VAR_MEM[DIP[6:0]];

//----------------------------------------------------------------
// Data Memory write
//----------------------------------------------------------------
always@(posedge CLK) begin
    if( MemWrite && dec_DATA_VAR ) 
        DATA_VAR_MEM[ALUResult[8:2]] <= WriteData ;
end

//----------------------------------------------------------------
// Instruction memory read
//----------------------------------------------------------------
assign Instr = ( (PC >= 32'h00000000) && (PC <= 32'h000001FC) ) ? // To check if address is in the valid range, assuming 128 word memory. Also helps minimize warnings
                 INSTR_MEM[PC[8:2]] : 32'h00000000 ; 
  
//----------------------------------------------------------------
// LED light - display PC value
//----------------------------------------------------------------
//always@(posedge CLK or posedge RESET) begin
//    if(RESET)
//        LED <= 'b0 ;
//    else 
//        LED <= PC ;
//end
reg [31:0] LED_reg1, LED_reg2, LED_reg3;
always@(posedge CLK or posedge RESET) begin
    if(RESET) begin
        LED_reg1 <= 32'b0;
        LED_reg2 <= 32'b0;
		LED_reg3 <= 32'b0;
        LED <= 32'b0;
    end
    else begin
		LED_reg1 <= PC;
		LED_reg2 <= LED_reg1;
		LED_reg3 <= LED_reg2;
		LED <= LED_reg3;
	end
end
//----------------------------------------------------------------
// SevenSeg LED - display memory content
//----------------------------------------------------------------
always @(posedge CLK or posedge RESET) begin
	if (RESET)
		SEVENSEGHEX <= 32'b0;
	else
		SEVENSEGHEX <= ReadData_IO;
end

endmodule 
