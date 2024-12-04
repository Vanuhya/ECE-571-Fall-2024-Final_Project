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
      // Declare txn as a static variable outside initial block
// Temporary variables for force/release
        logic [7:0] command_tmp;
        logic ibi_request_tmp;
        logic [7:0] data_tmp;


initial begin
    repeat (300) begin
        txn = new();  // Create a new transaction
        assert(txn.randomize()) else $fatal("Transaction randomization failed!");

        // Display the transaction
        display_transaction(txn);

        // Iterate over all devices
        for (int device_id = 1; device_id <= 4; device_id++) begin
            // Assign transaction fields to temporary variables
            command_tmp = txn.command;
            ibi_request_tmp = txn.ibi_request;
            data_tmp = txn.data;

            case (device_id)
                1: begin  // I3C Slave 1
                    $display("Testing I3C Slave 1...");
                    // Apply CCC Command using force/release
                    force dut.i3c_slave_1.command = command_tmp;
                    #10 release dut.i3c_slave_1.command;

                    // Handle IBI
                    if (ibi_request_tmp) begin
                        $display("Time: %0t | IBI requested by I3C Slave 1.", $time);
                        force dut.i3c_slave_1.ibi_request = 1;
                        #10 release dut.i3c_slave_1.ibi_request;
                    end

                    // Write/Read Transactions
                    if (txn.write_enable) begin
                        force dut.i3c_slave_1.tx_data = data_tmp;
                        $display("Time: %0t | Writing Data: 0x%0h to I3C Slave 1.", $time, data_tmp);
                        #10 release dut.i3c_slave_1.tx_data;
                    end else begin
                        $display("Time: %0t | Reading Data: 0x%0h from I3C Slave 1.", $time, dut.i3c_slave_1.rx_data);
                    end
                end

                2: begin  // I3C Slave 2
                    $display("Testing I3C Slave 2...");
                    force dut.i3c_slave_2.command = command_tmp;
                    #10 release dut.i3c_slave_2.command;

                    if (ibi_request_tmp) begin
                        $display("Time: %0t | IBI requested by I3C Slave 2.", $time);
                        force dut.i3c_slave_2.ibi_request = 1;
                        #10 release dut.i3c_slave_2.ibi_request;
                    end

                    if (txn.write_enable) begin
                        force dut.i3c_slave_2.tx_data = data_tmp;
                        $display("Time: %0t | Writing Data: 0x%0h to I3C Slave 2.", $time, data_tmp);
                        #10 release dut.i3c_slave_2.tx_data;
                    end else begin
                        $display("Time: %0t | Reading Data: 0x%0h from I3C Slave 2.", $time, dut.i3c_slave_2.rx_data);
                    end
                end

                3: begin  // I2C Slave
                    $display("Testing I2C Slave...");
                    // I2C Slave does not use command or IBI
                    if (txn.write_enable) begin
                        force dut.i2c_slave_1.data_reg = data_tmp;
                        $display("Time: %0t | Writing Data: 0x%0h to I2C Slave.", $time, data_tmp);
                        #10 release dut.i2c_slave_1.data_reg;
                    end else begin
                        $display("Time: %0t | Reading Data: 0x%0h from I2C Slave.", $time, dut.i2c_slave_1.data_reg);
                    end
                end
            endcase
        end
    end



           //Sample Functional Coverage
            dynamic_address_cov.sample();
            ibi_handling_cov.sample();
            ccc_handling_cov.sample();

            #20;
    

        // Display Coverage Results
        $display("Dynamic Address Coverage: %0.2f%%", dynamic_address_cov.get_coverage());
        $display("IBI Handling Coverage: %0.2f%%", ibi_handling_cov.get_coverage());
        $display("CCC Handling Coverage: %0.2f%%", ccc_handling_cov.get_coverage());

        $finish;
end
endmodule
