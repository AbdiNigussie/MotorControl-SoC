`timescale 1ns / 1ps

/* MCycle: Sequential Multiplier and Divider */
module MCycle #(
    parameter width = 32
)(
    input CLK,
    input RESET,
    input Start,        // Asserted when MUL/DIV is decoded
    input MCycleOp,     // 0=MUL, 1=DIV
    input [width-1:0] Operand1,  // Rs for MUL, Rn for DIV (Dividend)
    input [width-1:0] Operand2,  // Rm for both (Divisor)
    
    output [width-1:0] Result,   // 32-bit result (Lower 32bits for MUL, Quotient for DIV)
    output reg Busy              // Stalls CPU when high
);

    localparam IDLE = 1'b0;
    localparam COMPUTING = 1'b1;
    
    reg state, n_state;
    reg [5:0] count;              // Counts cycles (0 to 32)
    reg [2*width-1:0] product;    // 64-bit register 
                                  // MUL: Stores {High, Low} product
                                  // DIV: Stores {Remainder, Quotient}
    reg [width-1:0] multiplicand; // Multiplicand (Operand1)
    reg [width-1:0] divisor;      // Divisor (Operand2)
    
    // Temporary variable for combinatorial logic in Division
    reg [2*width-1:0] div_temp; 

    // ====================================================
    //              State Machine Logic
    // ====================================================
    always @(posedge CLK or posedge RESET) begin
        if (RESET) state <= IDLE;
        else state <= n_state;
    end
    
    always @(*) begin
        case (state)
            IDLE: begin
                if (Start) begin
                    n_state = COMPUTING;
                    Busy = 1'b1;
                end else begin
                    n_state = IDLE;
                    Busy = 1'b0;
                end
            end
            COMPUTING: begin
                // Run for 'width' cycles (32). 
                // Note: The count update happens at posedge, so we check if we are about to hit 32.
                if (count == width) begin
                    n_state = IDLE;
                    Busy = 1'b0;
                end else begin
                    n_state = COMPUTING;
                    Busy = 1'b1;
                end
            end
            default: begin
                n_state = IDLE;
                Busy = 1'b0;
            end
        endcase
    end

    // ====================================================
    //              Arithmetic Datapath
    // ====================================================
    always @(posedge CLK) begin
        if (state == IDLE && n_state == COMPUTING) begin
            // --- Initialization Phase (Cycle 0) ---
            count <= 0;
            multiplicand <= Operand1;
            divisor <= Operand2;
            
            if (!MCycleOp) begin 
                // MUL: Load Multiplier (Op2) into lower half. Clear upper half.
                product <= {{width{1'b0}}, Operand2}; 
            end else begin 
                // DIV: Load Dividend (Op1) into lower half. Clear upper half.
                product <= {{width{1'b0}}, Operand1};
            end

        end else if (n_state == COMPUTING) begin
            // --- Computation Phase (Cycles 1 to 32) ---
            count <= count + 1;
            
            if (!MCycleOp) begin 
                // --- MULTIPLIER LOGIC (Shift-Add) ---
                // If LSB (Multiplier bit) is 1, add Multiplicand to Upper Half.
                // Then Shift Right entire 64-bit register.
                if (product[0]) begin
                    product <= (product + {multiplicand, {width{1'b0}}}) >> 1;
                end else begin
                    product <= product >> 1;
                end

            end else begin 
                // --- DIVIDER LOGIC (Shift-Subtract / Restoring) ---
                // 1. Shift Left
                div_temp = product << 1; 
                
                // 2. Try to subtract Divisor from Upper Half (Remainder)
                if (div_temp[2*width-1:width] >= divisor) begin
                    // Subtraction possible: Update Remainder, Set Quotient Bit (LSB) to 1
                    div_temp[2*width-1:width] = div_temp[2*width-1:width] - divisor;
                    div_temp[0] = 1'b1;
                end else begin
                    // Subtraction impossible: Remainder unchanged, Quotient Bit (LSB) is 0
                    div_temp[0] = 1'b0;
                end

                product <= div_temp;
            end
        end
    end
    
    // Result Mux:
    // MUL: The standard algorithm produces the 64-bit product. We want lower 32.
    // DIV: The algorithm leaves Quotient in Lower 32, Remainder in Upper 32.
    assign Result = product[width-1:0];

endmodule