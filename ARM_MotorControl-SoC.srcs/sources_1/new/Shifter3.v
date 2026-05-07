/* 
 * MODULE: Barrel Shifter
 * 
 * Description: 
 * Implements a 32-bit combinational barrel shifter. 
 * Unlike a sequential shifter (looping), this shifts in a single clock cycle 
 * using cascaded multiplexers.
 * 
 * Operations:
 * 00: LSL (Logical Shift Left)  - Shift left, fill with 0
 * 01: LSR (Logical Shift Right) - Shift right, fill with 0
 * 10: ASR (Arithmetic Shift Right) - Shift right, preserve Sign Bit (MSB)
 * 11: ROR (Rotate Right) - Shift right, LSB wraps around to MSB
 */
module Shifter(
    input [1:0] Sh,       // Shift Control: 00=LSL, 01=LSR, 10=ASR, 11=ROR
    input [4:0] Shamt5,   // Shift Amount: 5-bit integer (0 to 31)
    input [31:0] ShIn,    // Input Data: The 32-bit value to be shifted
    
    output [31:0] ShOut   // Output Data: The shifted result
    );

       reg [31:0] r;
       // Temporary variables to hold intermediate shift stages
       // s0 = Input, s1 = After shift 16, s2 = After shift 8, etc.
       reg [31:0] s0, s1, s2, s3, s4, s5;
   
       always @(*) begin
           case (Sh)
               // =================================================
               // 00: LSL (Logical Shift Left)
               // Multiplies by 2^n. Zeros inserted at LSB.
               // =================================================
               2'b00: begin
                   s0 = ShIn;
                   // Stage 1: If bit 4 of Shamt is 1, shift left by 16. Else keep value.
                   s1 = Shamt5[4] ? {s0[15:0], 16'b0} : s0;
                   // Stage 2: If bit 3 of Shamt is 1, shift left by 8.
                   s2 = Shamt5[3] ? {s1[23:0], 8'b0}  : s1;
                   // Stage 3: Shift left by 4
                   s3 = Shamt5[2] ? {s2[27:0], 4'b0}  : s2;
                   // Stage 4: Shift left by 2
                   s4 = Shamt5[1] ? {s3[29:0], 2'b0}  : s3;
                   // Stage 5: Shift left by 1
                   s5 = Shamt5[0] ? {s4[30:0], 1'b0}  : s4;
                   r  = s5;
               end
   
               // =================================================
               // 01: LSR (Logical Shift Right)
               // Unsigned Division by 2^n. Zeros inserted at MSB.
               // =================================================
               2'b01: begin
                   s0 = ShIn;
                   // Logic mirrors LSL, but shifts Right and fills with 0s at the top.
                   s1 = Shamt5[4] ? {16'b0, s0[31:16]} : s0;
                   s2 = Shamt5[3] ? {8'b0,  s1[31:8]}  : s1;
                   s3 = Shamt5[2] ? {4'b0,  s2[31:4]}  : s2;
                   s4 = Shamt5[1] ? {2'b0,  s3[31:2]}  : s3;
                   s5 = Shamt5[0] ? {1'b0,  s4[31:1]}  : s4;
                   r  = s5;
               end
   
               // =================================================
               // 10: ASR (Arithmetic Shift Right)
               // Signed Division. Preserves the Sign Bit (MSB).
               // =================================================
               2'b10: begin
                   s0 = ShIn;
                   // Note: {{N{Bit}}} duplicates the bit N times (Sign Extension)
                   // If MSB is 1 (negative), we fill with 1s. If 0, fill with 0s.
                   s1 = Shamt5[4] ? {{16{s0[31]}}, s0[31:16]} : s0;
                   s2 = Shamt5[3] ? {{ 8{s1[31]}}, s1[31:8]}  : s1;
                   s3 = Shamt5[2] ? {{ 4{s2[31]}}, s2[31:4]}  : s2;
                   s4 = Shamt5[1] ? {{ 2{s3[31]}}, s3[31:2]}  : s3;
                   s5 = Shamt5[0] ? {{ 1{s4[31]}}, s4[31:1]}  : s4;
                   r  = s5;
               end
   
               // =================================================
               // 11: ROR (Rotate Right)
               // Bits pushed out the right re-enter on the left.
               // =================================================
               default: begin
                   s0 = ShIn;
                   // Example: If shifting 16, Top 16 move to Bottom, Bottom 16 move to Top.
                   s1 = Shamt5[4] ? {s0[15:0], s0[31:16]} : s0; 
                   s2 = Shamt5[3] ? {s1[7:0],  s1[31:8]}  : s1; 
                   s3 = Shamt5[2] ? {s2[3:0],  s2[31:4]}  : s2; 
                   s4 = Shamt5[1] ? {s3[1:0],  s3[31:2]}  : s3; 
                   s5 = Shamt5[0] ? {s4[0],    s4[31:1]}  : s4; 
                   r  = s5; 
               end
           endcase
       end
   
       assign ShOut = r;  
endmodule