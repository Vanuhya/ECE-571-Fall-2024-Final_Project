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
        constraint valid_static_address { static_address inside {[7'h00:7'h7F]}; }
        constraint ibi_request_prob { ibi_request dist {1 := 70, 0 := 30}; } // Increase IBI probability
    endclass

    i3c_transaction txn;
    int txn_num = 0; // Transaction counter

    // Functional Coverage
    covergroup cg_dynamic_address @(posedge clk);
        coverpoint dut.i3c_slave_inst.dynamic_addr;
    endgroup
    cg_dynamic_address dynamic_address_cov;

    covergroup cg_ibi_handling @(posedge clk);
        coverpoint dut.primary_master.ibi_detected;
    endgroup
    cg_ibi_handling ibi_handling_cov;

    covergroup cg_transaction @(posedge clk);
        coverpoint dut.data_in_primary {
            bins low = {[8'h00:8'h3F]};
            bins mid = {[8'h40:8'h7F]};
            bins high = {[8'h80:8'hFF]};
        }
        coverpoint dut.static_address_secondary;
    endgroup
    cg_transaction transaction_cov;

    // Test Initialization
    initial begin
        clk = 0;
        rst_n = 0;

        // Construct Covergroups
        dynamic_address_cov = new();
        ibi_handling_cov = new();
        transaction_cov = new();

        // Release Reset
        #20 rst_n = 1;
    end

    // Main Test Logic
    initial begin
        repeat (500) begin
            txn_num++;
            // Create and randomize transaction object
            txn = new();
            assert(txn.randomize()) else $fatal("Transaction randomization failed!");

            // Display transaction details
            $display("Transaction #%0d: Data: 0x%0h, Static Address: 0x%0h, Request Mastership: %0b, Write Enable: %0b, IBI Request: %0b",
                     txn_num, txn.data, txn.static_address, txn.request_mastership, txn.write_enable, txn.ibi_request);

            // Simulate Primary Master Transactions
            dut.start_transfer_primary = 1;
            dut.data_in_primary = txn.data;
            #10 dut.start_transfer_primary = 0;

            // Simulate Secondary Master Transactions
            dut.static_address_secondary = txn.static_address;
            dut.write_enable_secondary = txn.write_enable;
            dut.request_mastership = txn.request_mastership;
            #20;

            // Handle IBI
            if (txn.ibi_request) begin
                dut.i3c_slave_inst.ibi_request = 1;
                #10 dut.i3c_slave_inst.ibi_request = 0;
                ibi_handling_cov.sample();
            end

            // Coverage Sampling
            dynamic_address_cov.sample();
            transaction_cov.sample();
            #20;
        end

        // Display Coverage
        $display("Dynamic Address Coverage: %0.2f%%", dynamic_address_cov.get_coverage());
        $display("IBI Handling Coverage: %0.2f%%", ibi_handling_cov.get_coverage());
        $display("Transaction Coverage: %0.2f%%", transaction_cov.get_coverage());
        $finish;
    end

    // Monitor Signals
    initial begin
        $monitor("Time: %0t | clk: %b | rst_n: %b | Dynamic Address: %0h | IBI Detected: %b",
                 $time, clk, rst_n, dut.i3c_slave_inst.dynamic_addr, dut.primary_master.ibi_detected);
    end
endmodule
