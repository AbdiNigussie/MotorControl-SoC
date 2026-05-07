`timescale 1ns / 1ps

module CondLogic(
    input CLK,
    input PCS,          // PC Write Enable (from Decode stage)
    input RegW,         // Register Write Enable
    input MemW,         // Memory Write Enable
    input NoWrite,      // *Safety*: If 1, prevents RegWrite (useful for CMP)
    input [1:0] FlagW,  // Flag Write Enable [1]:NZ, [0]:CV
    input [3:0] Cond,   // Condition Code from Instruction
    input [3:0] ALUFlags, // Current Flags from ALU
    input M_W,          // Multiplier Write Enable
    
    output PCSrc,       // To Fetch/Decode (Branch taken?)
    output RegWrite,    // Final Register Write Enable
    output MemWrite,    // Final Memory Write Enable
    output M_Write      // Final Multiplier Write Enable
    ); 
    
    reg CondEx;
    // Internal Flag Registers
    reg N = 0, Z = 0, C = 0, V = 0;

    // 1. Flag Register Update (Sequential)
    always @(posedge CLK) begin
        // Update N and Z flags if Cond passed and FlagW[1] is set
        if (FlagW[1] && CondEx) begin
            {N,Z} <= ALUFlags[3:2];
        end
        // Update C and V flags if Cond passed and FlagW[0] is set
        if (FlagW[0] && CondEx) begin
            {C,V} <= ALUFlags[1:0];
        end   
    end

    // 2. Condition Check (Combinational)
    always @(*) begin
        case(Cond)
            4'b0000: CondEx = Z;             // EQ
            4'b0001: CondEx = ~Z;            // NE
            4'b0010: CondEx = C;             // CS/HS
            4'b0011: CondEx = ~C;            // CC/LO
            4'b0100: CondEx = N;             // MI
            4'b0101: CondEx = ~N;            // PL
            4'b0110: CondEx = V;             // VS
            4'b0111: CondEx = ~V;            // VC
            4'b1000: CondEx = C & ~Z;        // HI
            4'b1001: CondEx = ~C | Z;        // LS
            4'b1010: CondEx = ~(N ^ V);      // GE
            4'b1011: CondEx = N ^ V;         // LT
            4'b1100: CondEx = ~Z & ~(N ^ V); // GT
            4'b1101: CondEx = Z | (N ^ V);   // LE
            4'b1110: CondEx = 1;             // AL (Always)
            default: CondEx = 0;             // Safety
        endcase
    end

    // 3. Output Gating
    assign PCSrc    = CondEx & PCS;
    assign RegWrite = CondEx & RegW & ~NoWrite; // Checks NoWrite for CMP
    assign MemWrite = CondEx & MemW;
    assign M_Write  = CondEx & M_W;             // Checks Condition for MUL
    
endmodule