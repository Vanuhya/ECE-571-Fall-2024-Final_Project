module tb_I3C_Integrated;

    // DUT signals
    logic clk, rst_n, bus_grant, data_in, write_enable;
    logic [6:0] master_addr, slave_addr;
    logic [7:0] data_out_master, data_out_slave;
    logic request_mastership;

    // Instantiate the DUT
    I3C_Integrated #(.ADDR_WIDTH(7)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .bus_grant(bus_grant),
        .master_addr(master_addr),
        .slave_addr(slave_addr),
        .data_in(data_in),
        .write_enable(write_enable),
        .data_out_master(data_out_master),
        .data_out_slave(data_out_slave),
        .request_mastership(request_mastership)
    );

    // Clock generator
    always #5 clk = ~clk;

    // Random Transaction Class
    class Transaction;
        rand logic [6:0] addr;
        rand logic data_in;
        constraint addr_range { addr inside {[0:127]}; }
    endclass

    Transaction trans;

    // Functional Coverage
    covergroup coverage @(posedge clk);
        coverpoint slave_addr {
            bins addr_bins[] = {[0:127]};
        }
        coverpoint write_enable {
            bins enabled = {1};
            bins disabled = {0};
        }
        coverpoint request_mastership {
            bins request = {1};
            bins no_request = {0};
        }
    endgroup

    coverage cov_inst; // Define a covergroup instance

    initial begin
        cov_inst = new(); // Instantiate the covergroup
    end

    // Test Sequence
initial begin
    // Initialize signals
    clk = 0;
    rst_n = 0;
    bus_grant = 0;
    master_addr = 7'h01;
    slave_addr = 7'h00;
    data_in = 0;
    write_enable = 0;

    // Reset sequence
    #10 rst_n = 1;

    // Start transactions
   
    for (int i = 0; i < 200; i++) begin
    trans = new();
    assert(trans.randomize()); // Generate constrained random transaction
    slave_addr = trans.addr;
    data_in = trans.data_in;
    write_enable = 1; // Set write_enable to 1 at the start of the transaction

    // Display the transaction details with a timestamp
    $display("Time: %0t | Transaction %0d: slave_addr = %0h, data_in = %b, write_enable = %b", 
             $time, i, slave_addr, data_in, write_enable);

    // Hold write_enable as 1 for a sufficient duration before clearing it
    #10; // Hold the write_enable for 10 time units while the transaction is active
    write_enable = 0; // Set write_enable to 0 after the hold period

    // Alternate bus grant to simulate Mastership request
    bus_grant = (i % 2 == 0);
    #20;
    end


    // Display functional coverage
    $display("Functional Coverage: %0.2f%%", $get_coverage());

    $finish;
end


endmodule
