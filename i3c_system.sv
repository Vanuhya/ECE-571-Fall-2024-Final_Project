module i3c_system (
    input  logic        clk,       // System clock
    input  logic        reset_n    // Active-low reset
);

    // ----------------------------------------
    // Shared I3C/I2C Bus Signals
    // ----------------------------------------
    tri logic sda;   // Serial Data Line (tri-state for shared bus)
    tri logic scl;   // Serial Clock Line (tri-state for shared bus)

    // ----------------------------------------
    // Internal Signals
    // ----------------------------------------
    logic ibi_ack_master;
    logic ibi_ack_slave_1, ibi_ack_slave_2;
    logic ibi_ack_signal;  // Combined IBI acknowledgment signal

    // ----------------------------------------
    // Instantiating I3C Primary Master
    // ----------------------------------------
    i3c_primary_master #(
        .MAX_DEVICES(8)  // Specify the maximum number of devices
    ) primary_master (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),           // Use tri-state shared bus
        .scl(scl),           // Use tri-state shared bus
        .ibi_flag(),         // Connect to an external signal if needed
        .ibi_ack(ibi_ack_master)  // Connect to the internal master signal
    );

    // ----------------------------------------
    // Instantiating I3C Secondary Master/Slave Instances
    // ----------------------------------------
    i3c_secondary_master_slave secondary_master_1 (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),           // Use tri-state shared bus
        .scl(scl),           // Use tri-state shared bus
        .request_mastership(1'b0),  // Mastership request controlled externally
        .master_granted(),          // Monitored externally
        .ibi_request(),             // IBI requests managed internally
        .ibi_ack(ibi_ack_slave_1),  // Directly drive the slave-specific signal
        .slave_address(7'h20)       // Pre-assigned static address
    );

    i3c_secondary_master_slave secondary_master_2 (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),           // Use tri-state shared bus
        .scl(scl),           // Use tri-state shared bus
        .request_mastership(1'b0),  // Mastership request controlled externally
        .master_granted(),          // Monitored externally
        .ibi_request(),             // IBI requests managed internally
        .ibi_ack(ibi_ack_slave_2),  // Directly drive the slave-specific signal
        .slave_address(7'h21)       // Pre-assigned static address
    );

    // ----------------------------------------
    // Instantiating I3C and I2C Slaves
    // ----------------------------------------
    i3c_slave i3c_slave_1 (
        .clk(clk),
        .rst_n(reset_n),
        .scl(scl),
        .sda_in(sda),         // Connect to shared SDA line
        .sda_out(),           // SDA output (driven by slave)
        .static_addr(8'h30),  // Pre-assigned static address
        .dynamic_addr(),      // Dynamic address assigned by master
        .daa_request(),       // DAA request signal from master
        .daa_addr(),          // Dynamic address assigned by master
        .daa_complete(),      // DAA completion flag
        .ibi_request(),       // IBI request from master
        .ibi_ack(ibi_ack_slave_1), // Directly drive the slave acknowledgment signal
        .ibi_data(8'h00),     // IBI data register (dummy for this example)
        .command(8'h00),      // CCC command
        .tx_data(8'h00),      // Data to transmit
        .rx_data(),           // Data received
        .bcr(),               // Bus control register
        .dcr(),               // Device control register
        .hot_join_request(),  // Hot join request
        .hot_join_ack(1'b0)   // Hot join acknowledgment (default)
    );

    i3c_slave i3c_slave_2 (
        .clk(clk),
        .rst_n(reset_n),
        .scl(scl),
        .sda_in(sda),         // Connect to shared SDA line
        .sda_out(),           // SDA output (driven by slave)
        .static_addr(8'h31),  // Pre-assigned static address
        .dynamic_addr(),      // Dynamic address assigned by master
        .daa_request(),       // DAA request signal from master
        .daa_addr(),          // Dynamic address assigned by master
        .daa_complete(),      // DAA completion flag
        .ibi_request(),       // IBI request from master
        .ibi_ack(ibi_ack_slave_2), // Directly drive the slave acknowledgment signal
        .ibi_data(8'h00),     // IBI data register (dummy for this example)
        .command(8'h00),      // CCC command
        .tx_data(8'h00),      // Data to transmit
        .rx_data(),           // Data received
        .bcr(),               // Bus control register
        .dcr(),               // Device control register
        .hot_join_request(),  // Hot join request
        .hot_join_ack(1'b0)   // Hot join acknowledgment (default)
    );

    // ----------------------------------------
    // Combine Acknowledgment Signals
    // ----------------------------------------
    assign ibi_ack_signal = ibi_ack_master | ibi_ack_slave_1 | ibi_ack_slave_2;

endmodule   // This is the top-level system instantiation for I3C bus
