`timescale 1ns / 1ps

module Extend(
    input [1:0] ImmSrc,
    input [23:0] InstrImm, // Instr[23:0] from the pipeline
    output reg [31:0] ExtImm
    );  
    
    always @(*) begin
        case (ImmSrc)
            // 2'b00: Data-processing (Zero Extend 8-bit)
            // Acceptable for simplified Lab/Project requirements.
            2'b00: ExtImm = {24'b0, InstrImm[7:0]};
                        // 2'b01: Memory (LDR/STR) - 12-bit offset
            //  ASSUMPTION: The ALU operation for LDR/STR is ALWAYS 'ADD'.
            // The Extend unit handles the sign (U-bit at InstrImm[23]).
            2'b01: begin
                if (InstrImm[23]) // U=1 (Up/Positive)
                    ExtImm = {20'b0, InstrImm[11:0]};
                else              // U=0 (Down/Negative) -> 2's Complement
                   ExtImm = {20'hFFFFF, (InstrImm[11:0])};  // sign-extend---negative
            end
            
                // 2'b10: Branch immediate                
            2'b10: ExtImm = {{6{InstrImm[23]}}, InstrImm[23:0], 2'b00};                
            
            default: ExtImm = 32'b0;
        endcase
    end    
endmodule