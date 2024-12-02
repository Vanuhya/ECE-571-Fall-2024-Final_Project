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
        constraint valid_static_address { static_address inside {[7'h10:7'h7F]}; }
    endclass

    i3c_transaction txn;

    // Functional Coverage
    covergroup cg_dynamic_address @(posedge clk);
        coverpoint dut.i3c_slave_inst.dynamic_addr; // Ensure `dynamic_addr` exists and is connected in `i3c_system`
    endgroup
    cg_dynamic_address dynamic_address_cov;

    covergroup cg_ibi_handling @(posedge clk);
        coverpoint dut.primary_master.ibi_detected; // Ensure `ibi_detected` exists and is connected in `i3c_system`
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
    end

    // Main Test Logic
    initial begin
        repeat (100) begin
            // Create and randomize transaction object
            txn = new();
            assert(txn.randomize()) else $fatal("Transaction randomization failed!");

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
                dut.i3c_slave_inst.ibi_request = 1; // Ensure `ibi_request` exists and is connected in `i3c_system`
                #10 dut.i3c_slave_inst.ibi_request = 0;
                ibi_handling_cov.sample(); // Properly sample the `ibi_handling_cov` covergroup
            end

            // Coverage Sampling
            dynamic_address_cov.sample(); // Properly sample the `dynamic_address_cov` covergroup
            #20;
        end

        // Display Coverage
        $display("Dynamic Address Coverage: %0.2f%%", dynamic_address_cov.get_coverage());
        $display("IBI Handling Coverage: %0.2f%%", ibi_handling_cov.get_coverage());
        $finish;
    end
endmodule
