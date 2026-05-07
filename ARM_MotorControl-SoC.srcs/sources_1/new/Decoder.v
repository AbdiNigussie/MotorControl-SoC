`timescale 1ns / 1ps

/* 
 * DECODER MODULE
 * Function: Decodes ARM Instructions into Control Signals.
 */

module Decoder(
    input [31:0] Instr,
	
    output PCS,            // PC Select (0: PC+4, 1: Branch/PC dest)
    output BranchTakenD,    // NEW: Signal to Flush Fetch Stage 
    output reg RegW,        // Register Write Enable
    output reg MemW,        // Memory Write Enable
    output reg MemtoReg,    // 0: ALU Result -> Reg, 1: Mem Data -> Reg
    output reg ALUSrc,      // 0: RegB, 1: Immediate
    output reg [1:0] ImmSrc,// Immediate Type (00: DP, 01: Mem, 10: Branch)
    output reg [2:0] RegSrc,// Register Bank Select Mux Control
                            // [0]: Rn vs 15 (Port 1), [1]: Rm vs Rd (Port 2)
                            // [2]: Swap Rn/Rd (Used for MUL)
    output reg [1:0] ALUControl, // Selects ALU Operation
    output reg [1:0] FlagW,      // Flag Write Enable ([1]: NZ, [0]: CV)
    output reg NoWrite,          // Safety signal: Forces RegWrite=0 (for CMP)
    output reg M_Start,          // Multi-cycle Start Pulse
    output reg MCycleOp,         // 0: MUL, 1: DIV
    output reg M_W               // Write Multi-cycle Result to Reg
); 
    reg [1:0] ALUOp;    // Internal: Categorizes Instr for ALU Decoder
    reg [1:0] MCOp;     // Internal: Multi-cycle Opcode
    reg Branch;         // Internal: Branch detected

    wire [3:0] Rd;
    wire [1:0] Op;
    wire [5:0] Funct;
    wire [1:0] ExInstr; // Detects special instructions (MUL/DIV)

    // Field Extraction
    assign Rd = Instr[15:12];
    assign Op = Instr[27:26];
    assign Funct = Instr[25:20]; // [25]:I, [24-21]:Cmd, [20]:S
    
    // Extended Instruction Detection (Bits 4-7 and 21-25)
    // ExInstr[0]: Multiply (00000xxxx1001)
    assign ExInstr[0] = (Instr[25:21] == 5'b00000) && (Instr[7:4] == 4'b1001);
    // ExInstr[1]: Divide (Reserved/Custom encoding 111111xxxx1111)
    assign ExInstr[1] = (Instr[25:20] == 6'b111111) && (Instr[7:4] == 4'b1111);
    
    // =========================================================================
    //           Main Decoder (Control Table)
    // =========================================================================
    // Funct bits used in case: [5]=I(Immediate), [3]=U(Up/Down), [0]=S(SetFlags)
    // NOTE: LDR/STR cases merged to ALUOp=00 because Extend handles sign.
    
    always @(*) begin
        casex({Op, ExInstr, Funct[5], Funct[3], Funct[0]})
            // ------------------------------------------------------------------------------------------
            // CASE FORMAT: {Op, ExInstr, I, U, S} -> {Branch, MtoR, MemW, ALUSrc, ImmSrc, RegW, RegSrc, ALUOp, MCOp}
            // ------------------------------------------------------------------------------------------
            
            // 1. Data Processing (Register-based)
            // Op=00, Ex=00, I=0, S=x
            7'b00_00_0xx: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_0_0_0_00_1_000_11_00; 
            
            // 2. Data Processing (Immediate)
            // Op=00, Ex=00, I=1, S=x
            7'b00_00_1xx: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_0_0_1_00_1_000_11_00;

            // 3. STR (Store Register) - ALWAYS ADD OFFSET
            // Op=01, Ex=00, I=x, U=x, S=0 (Funct[0] for LDR/STR is L-bit, 0=Store)
            7'b01_00_xx0: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_0_1_1_01_0_010_00_00;

            // 4. LDR (Load Register) - ALWAYS ADD OFFSET
            // Op=01, Ex=00, I=x, U=x, S=1 (Funct[0] for LDR/STR is L-bit, 1=Load)
            7'b01_00_xx1: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_1_0_1_01_1_000_00_00;

            // 5. Branch (B / BL)
            // Op=10
            7'b10_00_xxx: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b1_0_0_1_10_0_001_00_00;

            // 6. Multiply (MUL)
            // Op=00, Ex=01 (MUL)
            // Note: RegSrc=100 (Bit 2 set) swaps Rn/Rd wires to match MUL syntax
            7'b00_01_xxx: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_0_0_0_00_1_100_00_01;

            // 7. Divide (DIV)
            // Op=01, Ex=10 (DIV)
            7'b01_10_xxx: {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_0_0_0_00_1_100_00_10;

            // Default: Safe NOP (Prevents accidental writes)
            default:      {Branch,MemtoReg,MemW,ALUSrc,ImmSrc,RegW,RegSrc,ALUOp,MCOp} = 14'b0_0_0_0_00_0_000_00_00;
        endcase
    end

    // =========================================================================
    //            ALU Decoder (Opcode -> Control)
    // =========================================================================
    
    always @(*) begin
        casex({ALUOp[1:0], Funct[4:0]}) // Look at Cmd bits
            // --------------------------------------------------------
            // MEMORY / BRANCH (ALUOp determines action)
            // --------------------------------------------------------
            // ALUOp=00 -> ADD (Used for LDR/STR/Branch)
            7'b00xxxxx: {ALUControl,FlagW,NoWrite} = 5'b00000; 
            // ALUOp=01 -> SUB (Reserved for specific neg-offset logic if needed)
            7'b01xxxxx: {ALUControl,FlagW,NoWrite} = 5'b01000; 

            // --------------------------------------------------------
            // DATA PROCESSING (ALUOp=11, Look at Funct cmd)
            // --------------------------------------------------------
            // ADD (0100)
            7'b1101000: {ALUControl,FlagW,NoWrite} = 5'b00000; // ADD No Flags
            7'b1101001: {ALUControl,FlagW,NoWrite} = 5'b00110; // ADDS (NZCV)
            // SUB (0010)
            7'b1100100: {ALUControl,FlagW,NoWrite} = 5'b01000; // SUB No Flags
            7'b1100101: {ALUControl,FlagW,NoWrite} = 5'b01110; // SUBS (NZCV)
            // AND (0000)
            7'b1100000: {ALUControl,FlagW,NoWrite} = 5'b10000; // AND No Flags
            7'b1100001: {ALUControl,FlagW,NoWrite} = 5'b10100; // ANDS (NZ)
            // ORR (1100)
            7'b1111000: {ALUControl,FlagW,NoWrite} = 5'b11000; // ORR No Flags
            7'b1111001: {ALUControl,FlagW,NoWrite} = 5'b11100; // ORRS (NZ)
            
            // --------------------------------------------------------
            // COMPARISONS (Result is discarded, only Flags update)
            // --------------------------------------------------------
            // CMP (1010) - Like SUB, but NoWrite=1
            7'b1110101: {ALUControl,FlagW,NoWrite} = 5'b01111; // CMP (SUB + Flags)
            // CMN (1011) - Like ADD, but NoWrite=1
            7'b1110111: {ALUControl,FlagW,NoWrite} = 5'b00111; // CMN (ADD + Flags)
            
            default:    {ALUControl,FlagW,NoWrite} = 5'b00000;
        endcase
    end

    // =========================================================================
    //         Multi-Cycle Decoder
    // =========================================================================
    always @(*) begin
        case(MCOp)
            // No MCycle
            2'b00: {M_Start,MCycleOp,M_W} = 3'b000;
            // MUL
            2'b01: {M_Start,MCycleOp,M_W} = 3'b101; // Start=1, Op=0, Write=1
            // DIV
            2'b10: {M_Start,MCycleOp,M_W} = 3'b111; // Start=1, Op=1, Write=1

            default: {M_Start,MCycleOp,M_W} = 3'b000;
        endcase
    end

  
        // =========================================================================
        //            EARLY BTA & PC LOGIC
        // =========================================================================
        
        // 1. Detect Condition Code "AL" (Always / Unconditional)
        // Bits [31:28] are the Condition field. 1110 is "AL".
          // PCS is 1 if:
          // 1. It is a Branch instruction (B/BL)
          // 2. It is a Data Processing writing to R15 (PC)
        wire CondAL;
        assign CondAL = (Instr[31:28] == 4'b1110);
        
        assign PCS = ((Rd == 4'd15) & RegW) | (Branch & ~CondAL );

    
        // 2. PCSrcD (Early BTA)
        // If it is a Branch instruction AND it is Unconditional, we take it NOW.
 
        assign BranchTakenD = Branch & CondAL;
    
        // 3. BranchTakenD (Signal to Flush Fetch Stage)
        // Same as PCSrcD for our purpose.
    
        // 4. PCS (General PC Write)
        // This goes to ID/EX register to warn the Execute stage that PC was modified.
        // It includes Early Branches OR Late Register Writes (MOV PC, R14).
        //assign PCS = ((Rd == 4'd15) & RegW) | Branch;
   
endmodule