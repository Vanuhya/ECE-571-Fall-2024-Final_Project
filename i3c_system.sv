// This is the first version of the top level system I3C bus.The port connections are not matching 
//some control signals in the i3c_system module have to be added and integrated properly.
module i3c_system (
    input  logic        clk,           // System clock
    input  logic        reset_n        // Active-low reset
);

    // ----------------------------------------
    // Shared I3C/I2C Bus Signals
    // ----------------------------------------
    logic sda;   // Serial Data Line (shared bus)
    logic scl;   // Serial Clock Line (shared bus)

    // ----------------------------------------
    // Instantiating I3C Primary Master
    // ----------------------------------------
    i3c_primary_master #(
        .MAX_DEVICES(8)  // Specify the maximum number of devices
    ) primary_master (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .ibi_flag(),      // Connect to an external signal if needed
        .ibi_ack(1'b1)    // Acknowledge all IBIs (could be connected to a control signal)
    );

    // ----------------------------------------
    // Instantiating I3C Secondary Masters/Slaves
    // ----------------------------------------
    i3c_secondary_master_slave secondary_master_1 (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .request_mastership(1'b0),  // Mastership request controlled externally
        .master_granted(),          // Monitored externally
        .ibi_request(),             // IBI requests managed internally
        .ibi_ack(1'b1),             // Acknowledge all IBIs
        .slave_address(7'h20)       // Pre-assigned static address
    );

    i3c_secondary_master_slave secondary_master_2 (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .request_mastership(1'b0),  // Mastership request controlled externally
        .master_granted(),          // Monitored externally
        .ibi_request(),             // IBI requests managed internally
        .ibi_ack(1'b1),             // Acknowledge all IBIs
        .slave_address(7'h21)       // Pre-assigned static address
    );

    // ----------------------------------------
    // Instantiating I3C Slaves
    // ----------------------------------------
    i3c_slave i3c_slave_1 (
        .clk(clk),
        .rst_n(reset_n),
        .scl(scl),
        .sda_in(sda),                // Connect to shared SDA line
        .sda_out(),                  // SDA output (driven by slave)
        .static_addr(8'h30),         // Pre-assigned static address
        .dynamic_addr(),             // Dynamic address assigned by master
        .daa_request(),              // DAA request signal from master
        .daa_addr(),                 // Dynamic address assigned by master
        .daa_complete(),             // DAA completion flag
        .ibi_request(),              // IBI request from master
        .ibi_ack(),                  // IBI acknowledgment
        .ibi_data(8'h00),            // Data for IBI transfer (example)
        .command(8'h00),             // Command for directed or global CCCs
        .tx_data(8'h00),             // Data to be transmitted (for directed transfer)
        .rx_data(),                  // Data received (for directed transfer)
        .bcr(),                      // Bus Characteristic Register
        .dcr(),                      // Device Characteristic Register
        .hot_join_request(),         // Hot join request signal from slave
        .hot_join_ack(1'b0)          // Hot join acknowledgment to master (example)
    );

    i3c_slave i3c_slave_2 (
        .clk(clk),
        .rst_n(reset_n),
        .scl(scl),
        .sda_in(sda),                // Connect to shared SDA line
        .sda_out(),                  // SDA output (driven by slave)
        .static_addr(8'h31),         // Pre-assigned static address
        .dynamic_addr(),             // Dynamic address assigned by master
        .daa_request(),              // DAA request signal from master
        .daa_addr(),                 // Dynamic address assigned by master
        .daa_complete(),             // DAA completion flag
        .ibi_request(),              // IBI request from master
        .ibi_ack(),                  // IBI acknowledgment
        .ibi_data(8'h00),            // Data for IBI transfer (example)
        .command(8'h00),             // Command for directed or global CCCs
        .tx_data(8'h00),             // Data to be transmitted (for directed transfer)
        .rx_data(),                  // Data received (for directed transfer)
        .bcr(),                      // Bus Characteristic Register
        .dcr(),                      // Device Characteristic Register
        .hot_join_request(),         // Hot join request signal from slave
        .hot_join_ack(1'b0)          // Hot join acknowledgment to master (example)
    );

    i3c_slave i3c_slave_3 (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .slave_address(7'h32)       // Pre-assigned static address
    );

    // ----------------------------------------
    // Instantiating I2C Slave
    // ----------------------------------------
    i2c_slave i2c_slave_inst (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .slave_address(7'h40)       // Pre-assigned static address
    );

endmodule
