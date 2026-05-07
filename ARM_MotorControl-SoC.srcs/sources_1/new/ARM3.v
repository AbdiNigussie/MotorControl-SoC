/* ARM CORE: PARALLEL MCYCLE & EARLY BTA IMPLEMENTATION */
module ARM(
    input CLK,
    input Reset,
    input [31:0] Instr,
    input [31:0] ReadData,

    output MemWrite,
    output [31:0] PC,
    output [31:0] OpResult,
    output [31:0] WriteData
); 
    // ******************************************************
    //              SIGNAL DECLARATIONS
    // ******************************************************

    // Fetch
    wire StallF, Real_StallF;
    wire [31:0] PCF, PC_Plus_4F, InstrF;

    // Decode
    wire StallD, Real_StallD, FlushD;
    reg [31:0] InstrD;
    wire BranchTakenD;
    wire [31:0] BranchTargetD;

    wire PCSD, RegWD, MemWD, MemtoRegD, ALUSrcD, NoWriteD, M_StartD, MCycleOpD, M_WD;
    wire [1:0] FlagWD, ALUControlD, ImmSrcD;
    wire [2:0] RegSrcD;
    wire [3:0] CondD, RA1D, RA2D, WA3D;
    wire [6:0] shControlD;
    wire [31:0] RD1D, RD2D, PC_Plus_8D, InstrImmD, ExtImmD;

    // Execute
    wire  Real_StallE, FlushE;
    wire [1:0] ForwardAE, ForwardBE;
    reg [31:0] InstrE;
    reg PCSE, RegWE, MemWE, MemtoRegE, ALUSrcE, NoWriteE, M_StartE, MCycleOpE, M_WE;
    reg [1:0] FlagWE, ALUControlE;
    reg [3:0] CondE, RA1E, RA2E, WA3E;
    reg [6:0] shControlE;
    reg [31:0] RD1E, RD2E, ExtImmE;
    
    wire PCSrcE, RegWriteE, MemWriteE, M_WriteE, M_BusyE;
    wire [31:0] ALUResultE, OpResultE, MCycleResultE, WriteDataE;
    wire [3:0] ALUFlagsE;
    wire [1:0] ShE;
    wire [4:0] Shamt5E;
    wire [31:0] ShInE, ShOutE, SrcAE, SrcBE;

    // Memory
    wire FlushM, Real_StallM, ForwardM;
    reg [31:0] InstrM, OpResultM, WriteDataM;
    reg RegWriteM, MemWriteM, MemtoRegM;
    reg [3:0] RA2M, WA3M;
    wire [31:0] ReadDataM;

    // Write Back
    wire Real_StallW;
    reg [31:0] InstrW, ReadDataW, OpResultW;
    reg RegWriteW, MemtoRegW;
    reg [3:0] WA3W;
    wire [31:0] ResultW;

    // ******************************************************
    //      PARALLEL MCYCLE SUPPORT LOGIC
    // ******************************************************
    
    // 1. Track the Destination of the running Multiplier
    reg [3:0] M_WA3E;
    always @(posedge CLK) begin
        if (Reset) M_WA3E <= 0;
        else if (M_StartE) M_WA3E <= WA3E; // Capture destination when MUL starts
    end

    // 2. Detect Completion (Falling Edge of Busy)
    reg M_Busy_Prev;
    always @(negedge CLK) M_Busy_Prev <= M_BusyE;
    wire Mul_Done = (M_Busy_Prev && !M_BusyE)? 1'b1: 1'b0; 

    // 3. Port Stealing (Structural Hazard Resolution)
    // When MUL finishes, we stall the whole pipeline for 1 cycle to let MUL write.
    wire StructuralStall = Mul_Done ;
    
    assign Real_StallF = StallF || StructuralStall;
    assign Real_StallD = StallD || StructuralStall;
    assign Real_StallE = StructuralStall;
    assign Real_StallM = StructuralStall; // Freeze MEM
    assign Real_StallW = StructuralStall; // Freeze WB

    // ******************************************************
    //              PIPELINE STAGES
    // ******************************************************

    // --- FETCH ---
    wire [31:0] NextPC;
    assign NextPC = (PCSrcE=== 1'b1)       ? OpResultE :
                    (BranchTakenD) ? BranchTargetD :
                    PC_Plus_4F;

    ProgramCounter PC1 (
        .CLK(CLK), 
        .Reset(Reset),
        .PCSrc(1'b1), 
        .Result(NextPC),
        .Stall(Real_StallF),
        .PC(PCF),
        .PC_Plus_4(PC_Plus_4F)
    );
    assign PC = PCF;
    assign InstrF = Instr;

    // IF/ID Register
    always @(posedge CLK) begin
        if (FlushD) InstrD <= 32'b0;
        else if (Real_StallD) InstrD <= InstrD;
        else InstrD <= InstrF;
    end

    // --- DECODE ---
    Decoder Decoder1(
        .Instr(InstrD),
        .PCS(PCSD),
         .BranchTakenD(BranchTakenD),
        .RegW(RegWD),
         .MemW(MemWD), 
         .MemtoReg(MemtoRegD),
        .ALUSrc(ALUSrcD), 
        .ImmSrc(ImmSrcD), 
        .RegSrc(RegSrcD),
        .ALUControl(ALUControlD), 
        .FlagW(FlagWD), 
        .NoWrite(NoWriteD),
        .M_Start(M_StartD), 
        .MCycleOp(MCycleOpD),
         .M_W(M_WD)
    );

    assign RA1D = RegSrcD[2]? InstrD[11:8]:
                 RegSrcD[0]? 4'd15: 
                 InstrD[19:16];
    assign RA2D = RegSrcD[1]? InstrD[15:12]: InstrD[3:0];
    assign WA3D = RegSrcD[2]? InstrD[19:16]: InstrD[15:12];
    assign PC_Plus_8D = PC_Plus_4F; 
    assign CondD = InstrD[31:28];
    assign shControlD = InstrD[11:5];
    
    // -- Register File with Port Stealing --
    wire [3:0]  Final_WA3 = Mul_Done? M_WA3E : WA3W;
    wire [31:0] Final_WD3 = (Mul_Done) ? MCycleResultE  : ResultW;
    wire        Final_WE3 = StructuralStall ? 1'b1           : RegWriteW;

    RegisterFile RF1 (
        .CLK(CLK),
        .WE3(Final_WE3), // Muxed Write Enable
        .A1(RA1D), .A2(RA2D),
        .A3(Final_WA3),  // Muxed Address
        .WD3(Final_WD3), // Muxed Data
        .R15(PC_Plus_8D),
        .RD1(RD1D), .RD2(RD2D)
    );
    
    assign InstrImmD = InstrD[23:0];
    Extend Extend1 (.ImmSrc(ImmSrcD), .InstrImm(InstrImmD), .ExtImm(ExtImmD));
    assign BranchTargetD = PC_Plus_4F + ExtImmD;

    // ID/EX Register
    always @(posedge CLK) begin
        if (FlushE) begin
            InstrE <= 0;
            PCSE <= 0; RegWE <= 0; MemWE <= 0; FlagWE <= 0;
            ALUControlE <= 0; MemtoRegE <= 0; ALUSrcE <= 0; NoWriteE <= 0;
            M_StartE <= 0; MCycleOpE <= 0; M_WE <= 0;
            CondE <= 0; shControlE <= 0;
            RA1E <= 0; RA2E <= 0; WA3E <= 0;
            RD1E <= 0; RD2E <= 0; ExtImmE <= 0;
        end
        else if (Real_StallE) begin
            InstrE <= InstrE; PCSE <= PCSE; RegWE <= RegWE; MemWE <= MemWE; FlagWE <= FlagWE;
            ALUControlE <= ALUControlE; MemtoRegE <= MemtoRegE; ALUSrcE <= ALUSrcE; NoWriteE <= NoWriteE;
            M_StartE <= M_StartE; MCycleOpE <= MCycleOpE; M_WE <= M_WE;
            CondE <= CondE; shControlE <= shControlE;
            RA1E <= RA1E; RA2E <= RA2E; WA3E <= WA3E;
            RD1E <= RD1E; RD2E <= RD2E; ExtImmE <= ExtImmE;
        end
        else begin
            InstrE <= InstrD;
            PCSE <= PCSD; RegWE <= RegWD; MemWE <= MemWD; FlagWE <= FlagWD;
            ALUControlE <= ALUControlD; MemtoRegE <= MemtoRegD; ALUSrcE <= ALUSrcD; NoWriteE <= NoWriteD;
            M_StartE <= M_StartD; MCycleOpE <= MCycleOpD; M_WE <= M_WD;
            CondE <= CondD; shControlE <= shControlD;
            RA1E <= RA1D; RA2E <= RA2D; WA3E <= WA3D;
            RD1E <= RD1D; RD2E <= RD2D; ExtImmE <= ExtImmD;
        end
    end

    // --- EXECUTE ---
    CondLogic CondLogic1(
        .CLK(CLK),
        .RegW(RegWE),
         .MemW(MemWE),
          .NoWrite(NoWriteE),
           .FlagW(FlagWE),
        .Cond(CondE), 
        .ALUFlags(ALUFlagsE), 
        .M_W(M_WE),
        .RegWrite(RegWriteE), 
        .MemWrite(MemWriteE), 
        .M_Write(M_WriteE)
    );
    //  CondLogic handles PCSrc logic internally or via combination
    assign PCSrcE = (CondLogic1.CondEx & PCSE); // Internal access or explicit output

    assign ShE = shControlE[1:0];
    assign Shamt5E = shControlE[6:2];
        // ShInE feeds the Shifter, which feeds ALU Input B
    assign ShInE = (ForwardBE == 2'b11) ? MCycleResultE :
                   (ForwardBE[1])       ? OpResultM :
                   (ForwardBE[0])       ? ResultW : 
                   RD2E;
    assign WriteDataE = ShInE;

    Shifter Shifter1(
    .Sh(ShE), 
    .Shamt5(Shamt5E), 
    .ShIn(ShInE), 
    .ShOut(ShOutE)
    );

    /*assign SrcAE = ForwardAE[1]? OpResultM: 
                   (ForwardAE[0]? ResultW: 
                   RD1E);*/
    assign SrcAE = (ForwardAE == 2'b11) ? MCycleResultE :
                   (ForwardAE[1])       ? OpResultM : 
                   (ForwardAE[0])       ? ResultW : 
                    RD1E;
    assign SrcBE = ALUSrcE? ExtImmE: ShOutE;

    ALU ALU1 (
    .Src_A(SrcAE), 
    .Src_B(SrcBE), 
    .ALUControl(ALUControlE), 
    .ALUResult(ALUResultE), 
    .ALUFlags(ALUFlagsE)
    );

    MCycle MCycle1 (
    .CLK(CLK), 
    .RESET(Reset), 
    .Start(M_StartE), 
    .MCycleOp(MCycleOpE), 
    .Operand1(SrcAE), 
    .Operand2(WriteDataE), 
    .Result(MCycleResultE), 
    .Busy(M_BusyE)
    );   

    // MCycleResultE is NOT used here for OpResultE because it is written later asynchronously.
    // The MUL instruction continues as a Bubble, so we pass ALUResultE (which is garbage, but RegWrite will be masked).
    assign OpResultE = ALUResultE; 

    // EX/MEM Register
    always @(posedge CLK) begin
        /*if (FlushM) begin
            InstrM <= 0;
            RegWriteM <= 0; MemWriteM <= 0; MemtoRegM <= 0;
            OpResultM <= 0; WriteDataM <= 0; RA2M <= 0; WA3M <= 0;
        end
        else*/ if (Real_StallM) begin
            // Hold State during Structural Stall
            InstrM <= InstrM; RegWriteM <= RegWriteM; MemWriteM <= MemWriteM; MemtoRegM <= MemtoRegM;
            OpResultM <= OpResultM; WriteDataM <= WriteDataM; RA2M <= RA2M; WA3M <= WA3M;
        end
        else begin
            InstrM <= InstrE;
            // GHOSTING LOGIC: If this was a MUL start, force RegWrite to 0 for the main pipeline.
            // The real write happens later via the Port Stealing logic.
            RegWriteM <= (M_StartE) ? 1'b0 : RegWriteE; 
            
            MemWriteM <= MemWriteE; MemtoRegM <= MemtoRegE;
            OpResultM <= OpResultE; WriteDataM <= WriteDataE;
            RA2M <= RA2E; WA3M <= WA3E;
        end
    end

    // --- MEMORY ---
    assign MemWrite = MemWriteM;
    assign OpResult = OpResultM;
    assign WriteData = ForwardM? ResultW: WriteDataM;
    assign ReadDataM = ReadData;

    // MEM/WB Register
    always @(posedge CLK) begin
        if (Real_StallW) begin
            // Hold State
            InstrW <= InstrW; RegWriteW <= RegWriteW; MemtoRegW <= MemtoRegW;
            ReadDataW <= ReadDataW; OpResultW <= OpResultW; WA3W <= WA3W;
        end else begin
            InstrW <= InstrM;
            RegWriteW <= RegWriteM; MemtoRegW <= MemtoRegM;
            ReadDataW <= ReadDataM; OpResultW <= OpResultM;
            WA3W <= WA3M;
        end
    end

    // --- WRITEBACK ---
    assign ResultW = MemtoRegW? ReadDataW: OpResultW;

    // --- HAZARD UNIT ---
    HazardUnit HazardUnit1 (
        .RA1D(RA1D), 
        .RA2D(RA2D),
        .RA1E(RA1E), 
        .RA2E(RA2E), 
        
        .WA3E(WA3E),
        .MemtoRegE(MemtoRegE), 
        .RegWriteE(RegWriteE),
        .PCSrcD(BranchTakenD), 
        .PCSrcE(PCSrcE),
        
        .MemWriteD(MemWD), 
        .ALUSrcD(ALUSrcD), 

        
        // Parallel MCycle Inputs
        .M_BusyE(M_BusyE),
        .M_WA3E(M_WA3E), // Pass the tracked register
        .M_StartE(M_StartE), 

        
        .WA3M(WA3M), 
        .RegWriteM(RegWriteM), 
        .RA2M(RA2M), 
        .MemWriteM(MemWriteM),
        .WA3W(WA3W), 
        .MemtoRegW(MemtoRegW), 
        .RegWriteW(RegWriteW),

        .StallF(StallF), 
        .StallD(StallD), 
        .FlushD(FlushD),
        //.StallE(StallE), 
        .FlushE(FlushE),
        .ForwardAE(ForwardAE), 
        .ForwardBE(ForwardBE),
      //  .FlushM(FlushM), 
        .ForwardM(ForwardM)
    );

endmodule

