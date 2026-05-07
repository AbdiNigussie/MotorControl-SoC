`timescale 1ns / 1ps

module tb_Processor_System();

    // Inputs
    reg clk;
    reg reset;
    reg [6:0] dip_switches;

    // Outputs
    wire[15:0] led;
    wire [31:0] hex_display;
    wire pwm_u;
    wire pwm_v;
    wire pwm_w;

    // Instantiate the Wrapper (Your SoC)
    Wrapper #(
        .N_LEDs(16),
        .N_DIPs(7)
    ) uut (
        .DIP(dip_switches),
        .LED(led),
        .SEVENSEGHEX(hex_display),
        .RESET(reset),
        .CLK(clk),
        .pwm_u(pwm_u),
        .pwm_v(pwm_v),
        .pwm_w(pwm_w)
    );

    // Clock Generation (100 MHz)
    always #5 clk = ~clk;

    initial begin
        // Initialize Inputs
        clk = 0;
        reset = 1;
        dip_switches = 7'b0;

        // Hold reset for a few cycles
        #20;
        reset = 0;

        // Allow the processor 150ns to execute the 10 instructions
        // It will write the values to the PWM peripheral Memory-Mapped IO
        #150; 
        
        // Wait and observe the PWM hardware running independently!
        // A period of 100 takes 200 clock cycles (center-aligned up/down).
        // Let's run for 2000 clock cycles (20,000 ns) to see 10 full PWM waves.
        #20000;
        
        $display("Simulation Complete. Check the waveform for PWM outputs!");
        $finish;
    end

    // Optional: For Icarus Verilog / EDA Playground to generate waveforms
    // initial begin
    //    $dumpfile("dump.vcd");
    //    $dumpvars(0, tb_Processor_System);
    // end

endmodule