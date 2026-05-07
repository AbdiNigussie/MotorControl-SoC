module HazardUnit(
    input [3:0] RA1D,
    input [3:0] RA2D,
    
    input [3:0] RA1E,
    input [3:0] RA2E,
    input [3:0] WA3E,
    input MemtoRegE,
    input RegWriteE,
     // NEW INPUT to fix Store Stall
    input MemWriteD,  
    input PCSrcD, 
    input PCSrcE, // EARLY BTA   
    input ALUSrcD,
    input M_BusyE, // Is Multiplier busy?
    input M_StartE,             // <--- NEW INPUT
    input [3:0] M_WA3E,// Which register is the Multiplier writing to? (From ARM Top)
    
    input [3:0] WA3M,
    input RegWriteM,
    input [3:0] RA2M,
    input MemWriteM,
    input [3:0] WA3W,
    input MemtoRegW,
    input RegWriteW,

    output StallF,
    output StallD,
    output FlushD,
    //output StallE,
    output FlushE,
    output reg [1:0] ForwardAE,
    output reg [1:0] ForwardBE,
    //output FlushM,
    output ForwardM
    );
    
    /* ========================================================== */
    /*                    FORWARDING LOGIC                        */
    /* ========================================================== */

    // 1. ALU Forwarding (EX Hazard & MEM Hazard)
    // Data forwarding for DP
    wire Match_1E_M, Match_2E_M, Match_1E_W, Match_2E_W;
    assign Match_1E_M = (RA1E == WA3M);
    assign Match_2E_M = (RA2E == WA3M);
    assign Match_1E_W = (RA1E == WA3W);
    assign Match_2E_W = (RA2E == WA3W);
    
    always @(*) begin
           // Check MCycle First (Highest Priority for immediate usage)
         if (!M_BusyE && (M_WA3E != 0) && (RA1E == M_WA3E)) begin
              ForwardAE = 2'b11; // Forward from MCycle
         end
         // Standard Checks
         else if (Match_1E_M && RegWriteM) begin
            ForwardAE = 2'b10;
        end
        else if (Match_1E_W && RegWriteW) begin
            ForwardAE = 2'b01;
        end
        else begin
            ForwardAE = 2'b00;
        end
    end
    always @(*) begin
         // Check MCycle First
           if (!M_BusyE && (M_WA3E != 0) && (RA2E == M_WA3E)) begin
                ForwardBE = 2'b11; // Forward from MCycle
           end
           else if (Match_2E_M && RegWriteM) begin
            ForwardBE = 2'b10;
        end
        else if (Match_2E_W && RegWriteW) begin
            ForwardBE = 2'b01;
        end
        else begin
            ForwardBE = 2'b00;
        end
    end

    // 2. Memory-to-Memory Forwarding (For STR instructions)
    assign ForwardM = (RA2M == WA3W) & MemWriteM & MemtoRegW & RegWriteW;

    /* ========================================================== */
    /*                   STALL & FLUSH LOGIC                      */
    /* ========================================================== */

    // 1. Load-Use Hazard Detection
  
    wire Match_12D_E = (RA1D == WA3E) || ((RA2D == WA3E) && !MemWriteD); // make sure it wont stall mem-to-copy
    wire Ldrstall;
    assign Ldrstall = Match_12D_E & MemtoRegE & RegWriteE & !PCSrcD;
    
    // 2. Multi-Cycle RAW Hazard (Scoreboarding)
    // If the Multiplier is running (M_BusyE) AND the instruction in Decode
    // tries to READ the register that the Multiplier is going to write.
   wire MulStartHazard = M_StartE && Match_12D_E; 
        
    // Case B: MUL is running in background. We look at M_WA3E.
    wire MulBusyHazard  = (M_BusyE && !M_StartE) && ((RA1D == M_WA3E) || ((RA2D == M_WA3E)&& (ALUSrcD == 0)));
    
    // Combine them
    wire MulDependency = MulStartHazard || MulBusyHazard;

    assign StallF = Ldrstall || MulDependency;
    assign StallD = Ldrstall || MulDependency;
   // assign StallE = 0 ;
    // 1. Flush Fetch (IF/ID) if:
        //    a. Branch Taken in Decode (Early BTA)
        //    b. Branch Taken in Execute (Late BTA for Conditional)
    assign FlushD = PCSrcD || PCSrcE ;    
    assign FlushE = Ldrstall || PCSrcE || MulDependency ;
    //assign FlushM = 0;

    /* END: STALL_FLUSH SIGNAL */


endmodule