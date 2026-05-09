`timescale 1ns / 1ps

module CORDIC_Accelerator(
    input wire clk,
    input wire reset,
    
    // Memory-Mapped Interface
    input wire we,              // Write Enable
    input wire [31:0] addr,     // Address from ALU
    input wire [31:0] wdata,    // Data from CPU
    output reg [31:0] rdata     // Data sent back to CPU
);

    // Q16.16 Fixed Point Format
    // Constant 1/K = 0.6072529350... scaled by 2^16 = 39797
    localparam K_INV = 32'd39797; 
    
    // Registers for internal math
    reg signed [31:0] x, y, z;
    reg [4:0] iter;
    reg busy;

    // CORDIC Atan Lookup Table (Radians * 2^16)
    wire [31:0] atan_table [0:15];
    assign atan_table[0]  = 32'd51472; // atan(1)
    assign atan_table[1]  = 32'd30386; // atan(1/2)
    assign atan_table[2]  = 32'd16055; // atan(1/4)
    assign atan_table[3]  = 32'd8150;  // atan(1/8)
    assign atan_table[4]  = 32'd4091;
    assign atan_table[5]  = 32'd2047;
    assign atan_table[6]  = 32'd1024;
    assign atan_table[7]  = 32'd512;
    assign atan_table[8]  = 32'd256;
    assign atan_table[9]  = 32'd128;
    assign atan_table[10] = 32'd64;
    assign atan_table[11] = 32'd32;
    assign atan_table[12] = 32'd16;
    assign atan_table[13] = 32'd8;
    assign atan_table[14] = 32'd4;
    assign atan_table[15] = 32'd2;

    // Determine rotation direction (d_i)
    wire z_sign = z[31];
    
    // State Machine & MMIO Write Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            iter <= 0;
            busy <= 0;
            x <= 0; y <= 0; z <= 0;
        end else begin
            // Trigger calculation when CPU writes angle to Address 0x00000B00
            if (we && addr[3:0] == 4'h0 && !busy) begin
                x <= K_INV;       // Load initial X
                y <= 32'd0;       // Initial Y = 0
                z <= wdata;       // Target Angle from CPU
                iter <= 0;
                busy <= 1'b1;     // Start calculating!
            end 
            // Iterative CORDIC Math
            else if (busy) begin
                if (iter < 16) begin
                    if (z_sign == 1'b0) begin // z >= 0
                        x <= x - (y >>> iter);
                        y <= y + (x >>> iter);
                        z <= z - atan_table[iter];
                    end else begin             // z < 0
                        x <= x + (y >>> iter);
                        y <= y - (x >>> iter);
                        z <= z + atan_table[iter];
                    end
                    iter <= iter + 1;
                end else begin
                    busy <= 1'b0; // Done!
                end
            end
        end
    end

    // MMIO Read Logic (Send data back to ARM CPU)
    always @(*) begin
        case(addr[3:0])
            4'h0: rdata = {31'b0, busy}; // 0x0B00: Read Status (1=Busy, 0=Done)
            4'h4: rdata = x;             // 0x0B04: Read Cosine
            4'h8: rdata = y;             // 0x0B08: Read Sine
            default: rdata = 32'b0;
        endcase
    end

endmodule