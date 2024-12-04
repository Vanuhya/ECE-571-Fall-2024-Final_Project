module tb_i3c_system;

    // Clock and Reset
    logic clk, rst_n;

    // Shared Bus Signals
    tri logic sda; // Serial Data Line (shared bus)
    tri logic scl; // Serial Clock Line (shared bus)

    // DUT Instance
    i3c_system dut (
        .clk(clk),
        .reset_n(rst_n)
    );

    // Clock Generation
    always #5 clk = ~clk;

    // Randomized Transaction Class
    class i3c_transaction;
        rand logic [7:0] data;              // Data to be sent/received
        rand logic [6:0] static_address;   // Static address of I3C devices
        rand logic [7:0] command;          // CCC command
        rand bit request_mastership;       // Request for mastership
        rand bit ibi_request;              // In-band interrupt request
        rand bit write_enable;             // Write enable signal

        // Constraints for meaningful transactions
        constraint valid_data { data inside {[8'h00:8'hFF]}; }
        constraint valid_static_address { static_address inside {[7'h08:7'h7F]}; }
        constraint ibi_probability { ibi_request dist {1 := 60, 0 := 40}; } // IBI request ~60% of the time
    endclass

    i3c_transaction txn;

    // Functional Coverage
    covergroup cg_dynamic_address @(posedge clk);
        coverpoint dut.primary_master.devices[0].dynamic_address {
            bins valid_dynamic_addresses[] = {[7'h10:7'h7F]};
            bins edge_cases[] = {7'h10, 7'h7F};
        }
    endgroup
    cg_dynamic_address dynamic_address_cov;

    covergroup cg_ibi_handling @(posedge clk);
        coverpoint dut.primary_master.ibi_flag {
            bins ibi_detected = {1};
            bins ibi_not_detected = {0};
        }
    endgroup
    cg_ibi_handling ibi_handling_cov;

    covergroup cg_ccc_handling @(posedge clk);
        coverpoint dut.i3c_slave_1.command {
            bins ccc_valid_commands[] = {[8'h07:8'h0F]};
        }
    endgroup
    cg_ccc_handling ccc_handling_cov;

    // Display Transactions
    task display_transaction(i3c_transaction txn);
        $display(
            "Time: %0t | Data: 0x%0h | Static Addr: 0x%0h | Command: 0x%0h | IBI: %b | Mastership: %b | Write: %b",
            $time, txn.data, txn.static_address, txn.command, txn.ibi_request, txn.request_mastership, txn.write_enable
        );
    endtask

    // Test Initialization
    initial begin
        clk = 0;
        rst_n = 0;

        dynamic_address_cov = new();
        ibi_handling_cov = new();
        ccc_handling_cov = new();

        // Reset the DUT
        #20 rst_n = 1;
        $display("Simulation started: Reset released.");
    end

    // Randomized Testing
    initial begin
        repeat (300) begin
            txn = new();
            assert(txn.randomize()) else $fatal("Transaction randomization failed!");

            // Display the transaction
            display_transaction(txn);

            // Apply CCC Command using force/release
            force dut.i3c_slave_1.command = txn.command;
            #10 release dut.i3c_slave_1.command;

            // Handle IBI using force/release
            if (txn.ibi_request) begin
                $display("Time: %0t | IBI requested by Slave 1.", $time);
                force dut.i3c_slave_1.ibi_request = 1;
                #10 release dut.i3c_slave_1.ibi_request;
            end

            // Write/Read Transactions using force/release
            if (txn.write_enable) begin
                force dut.i3c_slave_1.tx_data = txn.data;
                $display("Time: %0t | Writing Data: 0x%0h to Slave 1.", $time, txn.data);
                #10 release dut.i3c_slave_1.tx_data;
            end else begin
                $display("Time: %0t | Reading Data: 0x%0h from Slave 1.", $time, dut.i3c_slave_1.rx_data);
            end

            // Sample Functional Coverage
            dynamic_address_cov.sample();
            ibi_handling_cov.sample();
            ccc_handling_cov.sample();

            #20;
        end

        // Display Coverage Results
        $display("Dynamic Address Coverage: %0.2f%%", dynamic_address_cov.get_coverage());
        $display("IBI Handling Coverage: %0.2f%%", ibi_handling_cov.get_coverage());
        $display("CCC Handling Coverage: %0.2f%%", ccc_handling_cov.get_coverage());

        $finish;
    end

endmodule
