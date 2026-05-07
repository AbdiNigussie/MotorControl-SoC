/*
 * Module: ALU (Arithmetic Logic Unit)
 * Description: Behavioral implementation compatible with Pipeline.
 */
module ALU(
    input [31:0] Src_A,           // RENAMED from A to Src_A
    input [31:0] Src_B,           // RENAMED from B to Src_B
    input [1:0] ALUControl,
    
    output reg [31:0] ALUResult,
    output reg [3:0] ALUFlags     // {N, Z, C, V}
);

    wire [31:0] B_muxed;   
    wire [31:0] Sum;       
    wire Cin;             
    wire Cout;            
    wire [32:0] Sum_ext;   

    // 1. Prepare Operand B (Handle Subtraction)
    assign B_muxed = (ALUControl[0]) ? ~Src_B : Src_B;
    assign Cin = ALUControl[0];
    
    // 2. Perform Addition
    assign Sum_ext = Src_A + B_muxed + Cin;
    assign Sum = Sum_ext[31:0];
    assign Cout = Sum_ext[32]; 

    // 3. Result MUX
    always @(*) begin
        case (ALUControl)
            2'b00: ALUResult = Sum;       // ADD
            2'b01: ALUResult = Sum;       // SUB
            2'b10: ALUResult = Src_A & Src_B;   // AND
            2'b11: ALUResult = Src_A | Src_B;   // ORR
            default: ALUResult = 32'b0;
        endcase
    end

    // 4. Flags
    wire N = ALUResult[31];
    wire Z = (ALUResult == 32'b0);
    wire C = Cout & ~ALUControl[1];
    // Overflow: If A and B_muxed have same sign, but Sum has diff sign
    wire V = (Src_A[31] == B_muxed[31]) && (Src_A[31] != Sum[31]) & ~ALUControl[1];

    always @(*) begin
        ALUFlags = {N, Z, C, V};
    end

endmodule