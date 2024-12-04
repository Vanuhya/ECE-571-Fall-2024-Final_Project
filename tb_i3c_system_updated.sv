
`include "i2c_slave.sv"
`include "i3c_secondary_master.sv"
`include "i3c_slave1.sv"
`include "i3c_system.sv"

module i3c_testbench;

    // Clock and Reset
    logic clk;
    logic reset_n;

    // Bus signals
    logic sda;
    logic scl;

    // IBI signals
    logic ibi_flag;
    logic ibi_ack;

    // DUT: I3C Primary Master
    i3c_primary_master #(.MAX_DEVICES(8)) dut (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .ibi_flag(ibi_flag),
        .ibi_ack(ibi_ack)
    );

    // Testbench Components
    i3c_driver driver;            // Driver object
    i3c_monitor monitor;          // Monitor object
    i3c_scoreboard scoreboard;    // Scoreboard object
    i3c_transaction tr;           // Transaction object

    // Covergroup for Functional Coverage
    covergroup cg_transaction;
        coverpoint tr.device_address;
        coverpoint tr.data;
        coverpoint tr.write;
        coverpoint tr.ccc;
    endgroup

    cg_transaction cg;

    // Clock Generator
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Reset Generator
    initial begin
        reset_n = 0;
        #50 reset_n = 1;
    end

    // Main Test Sequence
    initial begin
        // Instantiate Testbench Components using `new`
        $display("Instantiating Testbench Components...");
        i3c_driver = new();          // Initialize driver
        i3c_monitor = new();         // Initialize monitor
        i3c_scoreboard = new();      // Initialize scoreboard
        tr = new();              // Initialize transaction object
        cg = new();              // Initialize covergroup

        // Wait for reset
        @(posedge reset_n);
        $display("Reset Released. Starting Test...");

        // Generate Transactions
        for (int i = 0; i < 100; i++) begin
            assert(tr.randomize()) else $fatal("Transaction randomization failed!");

            // Log generated transaction
            $display("Generated Transaction: Addr=0x%0h, Data=0x%0h, Write=%0b, CCC=%0b",
                     tr.device_address, tr.data, tr.write, tr.ccc);

            // Drive transaction to DUT
            driver.drive_transaction(tr);

            // Sample coverage
            cg.sample();

            // Verify transaction
            scoreboard.check(tr);
        end

        // Display coverage summary (manually tracking coverage in this case)
        $display("Coverage Summary:");
        cg.display();

        // End simulation
        $display("Simulation Complete.");
        $stop;
    end

endmodule

// ----------------------------------------
// Classes
// ----------------------------------------

class i3c_transaction;
    rand logic [6:0] device_address;
    rand logic [7:0] data;
    rand bit write; // 1 for write, 0 for read
    rand bit ccc;   // Indicates if this is a CCC command

    constraint valid_address {
        device_address inside {[7'h10:7'h7F]};
    }
endclass

class i3c_driver;
    task drive_transaction(i3c_transaction tr);
        // Drive SDA and SCL for the transaction
        // Placeholder: Replace with actual bus signaling logic
        $display("Driving Transaction: Addr=0x%0h, Data=0x%0h, Write=%0b, CCC=%0b",
                 tr.device_address, tr.data, tr.write, tr.ccc);
    endtask
endclass

class i3c_monitor;
    task capture_transaction();
        // Monitor and log transactions
        // Placeholder: Replace with bus monitoring logic
        $display("Monitoring Transaction: Placeholder logic.");
    endtask
endclass

class i3c_scoreboard;
    function void check(i3c_transaction tr);
        // Verify DUT behavior matches expected results
        $display("Checking Transaction: Addr=0x%0h, Data=0x%0h, Write=%0b, CCC=%0b",
                 tr.device_address, tr.data, tr.write, tr.ccc);
    endfunction
endclass
