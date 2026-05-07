`timescale 1ns / 1ps

module RegisterFile(
    input CLK,
    input WE3,          // Write Enable
    input [3:0] A1,     // Read Address 1
    input [3:0] A2,     // Read Address 2
    input [3:0] A3,     // Write Address
    input [31:0] WD3,   // Write Data
    input [31:0] R15,   // PC input (from Fetch stage)

    output [31:0] RD1,
    output [31:0] RD2
    );
    
    // RegBank stores R0 through R14. 
    // R15 (PC) is stored externally and passed in as input.
    reg [31:0] RegBank[0:14]; 
    integer i;
    initial begin
        for ( i = 0; i < 15; i = i + 1) begin
            RegBank[i] = 32'b0;
        end
    end
    // =========================================================
    // READ OPERATION (Combinational)
    // =========================================================
    assign RD1 = (A1 == 4'b1111) ? R15 : RegBank[A1];
    assign RD2 = (A2 == 4'b1111) ? R15 : RegBank[A2];
       
    // WRITE OPERATION (Sequential)
    // This allows writing in the middle of the cycle so the read 
    // at the next posedge gets the updated data.
    always @(negedge CLK) begin    
        // Write to R0-R14 only. R15 is read-only here (updated by PC logic).
        if(WE3 && (A3 != 4'b1111)) begin
            RegBank[A3] <= WD3; 
        end
    end   
    
endmodule