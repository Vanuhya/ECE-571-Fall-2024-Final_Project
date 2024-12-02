module tb_i3c_system;
    // Clock and Reset
    logic clk, rst_n;

    // DUT Instance
    i3c_system dut (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Clock Generation
    always #5 clk = ~clk;

    // Random Transaction Class
    class i3c_transaction;
        rand logic [7:0] data;
        rand logic [6:0] static_address;
        rand bit request_mastership;
        rand bit write_enable;
        rand bit ibi_request;

        // Constraints
        constraint valid_data { data inside {[8'h00:8'hFF]}; }
        constraint valid_static_address { static_address inside {[7'h08:7'h7F]}; } // Expanded range
        constraint ibi_request_probability { ibi_request dist {1 := 50, 0 := 50}; } // 50% chance of IBI
    endclass

    i3c_transaction txn;

    // Functional Coverage
    covergroup cg_dynamic_address @(posedge clk);
        coverpoint dut.i3c_slave_inst.dynamic_addr {
            bins lower_range[] = {[7'h08:7'h3F]}; // Low range
            bins upper_range[] = {[7'h40:7'h7F]}; // High range
        }
    endgroup
    cg_dynamic_address dynamic_address_cov;

    covergroup cg_ibi_handling @(posedge clk);
        coverpoint dut.primary_master.ibi_detected {
            bins ibi_detected_yes = {1};
            bins ibi_detected_no = {0};
        }
    endgroup
    cg_ibi_handling ibi_handling_cov;

    // Test Initialization
    initial begin
        clk = 0;
        rst_n = 0;

        // Construct Covergroups
        dynamic_address_cov = new();
        ibi_handling_cov = new();

        // Release Reset
        #20 rst_n = 1;
        $display("Simulation started: Reset released.");
    end

    // Display Transactions and Events
    task display_transaction(i3c_transaction txn);
        $display(
            "Time: %0t | Data: %h | Static Address: %h | Mastership: %b | Write Enable: %b | IBI Request: %b",
            $time, txn.data, txn.static_address, txn.request_mastership, txn.write_enable, txn.ibi_request
        );
    endtask

    // Main Test Logic
    initial begin
        repeat (200) begin // Increased iterations for better coverage
            // Create and randomize transaction object
            txn = new();
            assert(txn.randomize()) else $fatal("Transaction randomization failed!");

            // Display Transaction
            display_transaction(txn);

            // Simulate Primary Master Transactions
            dut.start_transfer_primary = 1;
            dut.data_in_primary = txn.data;
            #10 dut.start_transfer_primary = 0;

            // Simulate Secondary Master Transactions
            dut.static_address_secondary = txn.static_address;
            dut.write_enable_secondary = txn.write_enable;
            dut.request_mastership = txn.request_mastership;

            // Log Mastership Requests
            if (txn.request_mastership) begin
                $display("Time: %0t | Secondary Master requested bus mastership.", $time);
            end

            #20;

            // Handle IBI
            if (txn.ibi_request) begin
                $display("Time: %0t | IBI requested by I3C Slave.", $time);
                dut.i3c_slave_inst.ibi_request = 1;
                #10;
                dut.i3c_slave_inst.ibi_request = 0;
                ibi_handling_cov.sample(); // Sample the IBI coverage
                $display("Time: %0t | IBI handled successfully by Primary Master.", $time);
            end

            // Coverage Sampling
            dynamic_address_cov.sample(); // Sample the dynamic address coverage
            #20;
        end

        // Display Coverage
        $display("Dynamic Address Coverage: %0.2f%%", dynamic_address_cov.get_coverage());
        $display("IBI Handling Coverage: %0.2f%%", ibi_handling_cov.get_coverage());
        $finish;
    end
endmodule
