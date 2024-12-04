module i3c_primary_master #(
    parameter MAX_DEVICES = 8  // Maximum number of devices on the I3C bus
) (
    input  logic        clk,         // System clock
    input  logic        reset_n,     // Active-low reset
    inout  logic        sda,         // Serial Data Line
    output logic        scl,         // Serial Clock Line

    output logic        ibi_flag,    // Indicates IBI request received
    input  logic        ibi_ack      // Acknowledge for IBI
);

    // ----------------------------------------
    // Internal Signals
    // ----------------------------------------
    typedef struct packed {
        logic [7:0] static_address;   // Static address
        logic [6:0] dynamic_address;  // Dynamic address assigned by master
        logic [7:0] bcr;              // Bus Characteristics Register
        logic [7:0] dcr;              // Device Characteristics Register
        logic [7:0] lvr;              // Legacy Virtual Register
        logic       ibi_requested;    // IBI request flag
    } device_info_t;

    device_info_t devices[MAX_DEVICES];  // Device information array
    int device_count;                    // Number of devices on the bus

    logic sda_out_en;   // Enable SDA driving
    logic sda_drive;    // Value to drive on SDA
    assign sda = sda_out_en ? sda_drive : 1'bz;

    logic scl_drive;    // Clock signal
    assign scl = scl_drive;

    // ----------------------------------------
    // Dynamic Address Assignment (DAA)
    // ----------------------------------------
    task assign_dynamic_addresses();
        int i;
        automatic logic [6:0] dynamic_addr = 7'h10; // Start dynamic address assignment
        logic [7:0] temp_data;                      // Temporary variable for receive_data
        for (i = 0; i < device_count; i++) begin
            // Send ENTDAA (Enter DAA) CCC command
            send_ccc_command(8'h07); // 0x07: ENTDAA
            wait_ack();

            // Capture device response (BCR, DCR, LVR, and static address)
            receive_data(temp_data); devices[i].bcr = temp_data;
            receive_data(temp_data); devices[i].dcr = temp_data;
            receive_data(temp_data); devices[i].lvr = temp_data;
            receive_data(temp_data); devices[i].static_address = temp_data;

            // Assign a dynamic address to the device
            send_data(dynamic_addr);
            wait_ack();
            devices[i].dynamic_address = dynamic_addr;
            dynamic_addr++;
        end
    endtask

    // ----------------------------------------
    // Collect BCR, DCR, and LVR
    // ----------------------------------------
    task collect_device_info();
        int i;
        logic [7:0] temp_data;  // Temporary variable for receive_data
        for (i = 0; i < device_count; i++) begin
            // Use GETCAPS (Get Device Capabilities) CCC to query each device
            send_ccc_command(8'h08);  // 0x08: GETCAPS
            send_address(devices[i].dynamic_address, 1'b0); // Write
            wait_ack();

            receive_data(temp_data); devices[i].bcr = temp_data;
            receive_data(temp_data); devices[i].dcr = temp_data;
            receive_data(temp_data); devices[i].lvr = temp_data;
        end
    endtask

    // ----------------------------------------
    // Handle In-Band Interrupt (IBI)
    // ----------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ibi_flag <= 1'b0;
        end else if (detect_ibi()) begin
            ibi_flag <= 1'b1;
        end else if (ibi_ack) begin
            ibi_flag <= 1'b0; // Clear IBI flag after acknowledgment
        end
    end

    function logic detect_ibi();
        // Detect IBI request (SDA held low by slave during idle)
        return (sda == 1'b0 && scl == 1'b1);
    endfunction

    // ----------------------------------------
    // Send and Receive Data
    // ----------------------------------------
    task send_data(input logic [7:0] data);
        integer i;
        for (i = 7; i >= 0; i--) begin
            sda_drive <= data[i];
            sda_out_en <= 1'b1;
            @(posedge scl);
        end
        sda_out_en <= 1'b0;
    endtask

    task automatic receive_data(output logic [7:0] data);
        integer i;
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            data[i] = sda;
        end
    endtask

    task send_address(input logic [6:0] address, input logic rw);
        logic [7:0] address_byte;
        address_byte = {address, rw};
        send_data(address_byte);
    endtask

    task send_ccc_command(input logic [7:0] command);
        // Send broadcast or directed CCC
        send_data(command);
    endtask

    // ----------------------------------------
    // Communicate with All Devices (Global CCC)
    // ----------------------------------------
    task send_global_ccc(input logic [7:0] ccc_command);
        send_ccc_command(ccc_command);
        wait_ack();
    endtask

    // ----------------------------------------
    // Communicate with Specific Device (Directed CCC)
    // ----------------------------------------
    task send_directed_ccc(input logic [7:0] ccc_command, input logic [6:0] device_addr);
        send_ccc_command(ccc_command);
        send_address(device_addr, 1'b0);  // Write
        wait_ack();
    endtask

    // ----------------------------------------
    // Wait for Acknowledge
    // ----------------------------------------
    task wait_ack();
        @(negedge scl); // Wait for ACK bit
        if (sda != 1'b0) $fatal("ACK not received!");
    endtask

    // ----------------------------------------
    // Initialization
    // ----------------------------------------
    initial begin
        device_count = 0;  // Initialize device count
        @(negedge reset_n);
        // Assign dynamic addresses and collect device info
        assign_dynamic_addresses();
        collect_device_info();
    end

endmodule
