module i3c_tb_primary;

    // Clock and reset
    logic clk, rst_n;

    // I3C Bus signals
    tri logic scl, sda;

    // Primary master control signals
    logic start_transfer_primary;
    logic [7:0] data_in_primary;
    logic [7:0] data_out_primary;
    logic busy_primary;
    logic ibi_detected_primary;

    // Clock generation
    always #5 clk = ~clk;

    // DUT: Primary Master
    i3c_primary_master primary_master (
        .clk(clk),
        .rst_n(rst_n),
        .scl(scl),
        .sda(sda),
        .start_transfer(start_transfer_primary),
        .data_in(data_in_primary),
        .data_out(data_out_primary),
        .busy(busy_primary),
        .ibi_detected(ibi_detected_primary)
    );

    // Transaction class
    class i3c_transaction;
        rand bit [7:0] data;
        rand bit error_inject;
        rand bit arbitration_test;
        rand bit ibi_request;

        constraint valid_data {
            data inside {[8'h00:8'hFF]};
        }

        constraint error_probability {
            error_inject dist {1 := 30, 0 := 70};
        }

        constraint arbitration_probability {
            arbitration_test dist {1 := 20, 0 := 80};
        }

        constraint ibi_probability {
            ibi_request dist {1 := 10, 0 := 90};
        }

        function void display();
            $display("Transaction: Data=%h, Error Inject=%b, Arbitration=%b, IBI=%b",
                     data, error_inject, arbitration_test, ibi_request);
        endfunction
    endclass

    // Coverage groups
    covergroup cg_arbitration @(posedge clk);
        coverpoint busy_primary {
            bins arbitration_attempts = {1}; // Busy during arbitration
        }
    endgroup
    cg_arbitration arbitration_cov;

    covergroup cg_error_recovery @(posedge clk);
        coverpoint data_in_primary {
            bins error_range = {[8'h80:8'hFF]}; // Specific error range
        }
    endgroup
    cg_error_recovery error_recovery_cov;

    covergroup cg_ibi @(posedge clk);
        coverpoint ibi_detected_primary {
            bins ibi_detected = {1};
            bins ibi_not_detected = {0};
        }
    endgroup
    cg_ibi ibi_cov;

    // Initialize coverage groups
    initial begin
        arbitration_cov = new();
        error_recovery_cov = new();
        ibi_cov = new();
    end

    // Main test
    initial begin
        i3c_transaction txn;

        clk = 0;
        rst_n = 0;
        start_transfer_primary = 0;
        data_in_primary = 8'h00;

        // Apply reset
        #10 rst_n = 1;

        repeat (100) begin
            txn = new();
            assert(txn.randomize()) else $fatal("Randomization failed!");

            txn.display();

            if (!busy_primary) begin
                start_transfer_primary = 1;
                data_in_primary = txn.data;

                // Simulate error
                if (txn.error_inject) force scl = 1'bz;

                // Simulate arbitration
                if (txn.arbitration_test) force sda = 1'b0;

                #10 start_transfer_primary = 0;

                // Release forced signals
                release scl;
                release sda;
            end

            // Handle IBI
            if (txn.ibi_request) begin
                force sda = 1'b0;
                #10 release sda;
                ibi_cov.sample();
            end

            arbitration_cov.sample();
            error_recovery_cov.sample();

            @(posedge clk);
        end

        $display("Coverage Results:");
        $display("Arbitration: %0.2f%%", arbitration_cov.get_coverage());
        $display("Error Recovery: %0.2f%%", error_recovery_cov.get_coverage());
        $display("IBI: %0.2f%%", ibi_cov.get_coverage());
        $finish;
    end

endmodule

