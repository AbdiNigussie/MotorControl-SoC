`timescale 1ns / 1ps

module PWM_Generator(
    input wire clk,
    input wire reset,
    
    // Memory-Mapped Bus Interface
    input wire we,              // Write Enable
    input wire[31:0] addr,     // Address (from ALUResult)
    input wire [31:0] wdata,    // Write Data
    
    // 3-Phase PWM Outputs for Motor Driver
    output wire pwm_u,
    output wire pwm_v,
    output wire pwm_w
);

    // Motor Control Registers
    reg [31:0] period_reg;      // Sets the PWM frequency
    reg [31:0] cmp_u;           // Duty cycle compare for Phase U
    reg [31:0] cmp_v;           // Duty cycle compare for Phase V
    reg [31:0] cmp_w;           // Duty cycle compare for Phase W
    
    // Center-aligned counter (Up/Down)
    reg [31:0] counter;
    reg count_up; // 1 = counting up, 0 = counting down

    // Register Write Logic (Memory Mapped IO)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            period_reg <= 32'd1000; // Default period
            cmp_u      <= 32'd0;
            cmp_v      <= 32'd0;
            cmp_w      <= 32'd0;
        end else if (we) begin
            // Base address assumed to be stripped/handled by wrapper, 
            // checking lower bits for register offset
            case (addr[3:0])
                4'h0: period_reg <= wdata; // Offset 0x0: Period
                4'h4: cmp_u      <= wdata; // Offset 0x4: Phase U Duty
                4'h8: cmp_v      <= wdata; // Offset 0x8: Phase V Duty
                4'hC: cmp_w      <= wdata; // Offset 0xC: Phase W Duty
            endcase
        end
    end

    // Center-Aligned Counter Logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 32'b0;
            count_up <= 1'b1;
        end else begin
            if (count_up) begin
                if (counter >= period_reg) begin
                    count_up <= 1'b0;
                    counter <= counter - 1;
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                if (counter == 32'b0) begin
                    count_up <= 1'b1;
                    counter <= counter + 1;
                end else begin
                    counter <= counter - 1;
                end
            end
        end
    end

    // PWM Output Generation (High when counter is less than compare value)
    assign pwm_u = (counter < cmp_u) ? 1'b1 : 1'b0;
    assign pwm_v = (counter < cmp_v) ? 1'b1 : 1'b0;
    assign pwm_w = (counter < cmp_w) ? 1'b1 : 1'b0;

endmodule