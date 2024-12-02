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
    i3c_master primary_master (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl)
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
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .slave_address(7'h30)       // Pre-assigned static address
    );

    i3c_slave i3c_slave_2 (
        .clk(clk),
        .reset_n(reset_n),
        .sda(sda),
        .scl(scl),
        .slave_address(7'h31)       // Pre-assigned static address
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

// Define Primary Master (Simplified)
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
        logic [6:0] dynamic_addr = 7'h10; // Start dynamic address assignment
        for (i = 0; i < device_count; i++) begin
            // Send ENTDAA (Enter DAA) CCC command
            send_ccc_command(8'h07); // 0x07: ENTDAA
            wait_ack();

            // Capture device response (BCR, DCR, LVR, and static address)
            devices[i].bcr = receive_data();
            devices[i].dcr = receive_data();
            devices[i].lvr = receive_data();
            devices[i].static_address = receive_data();

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
        for (i = 0; i < device_count; i++) begin
            // Use GETCAPS (Get Device Capabilities) CCC to query each device
            send_ccc_command(8'h08);  // 0x08: GETCAPS
            send_address(devices[i].dynamic_address, 1'b0); // Write
            wait_ack();

            devices[i].bcr = receive_data();
            devices[i].dcr = receive_data();
            devices[i].lvr = receive_data();
        end
    endtask

    // ----------------------------------------
    // Handle In-Band Interrupt (IBI)
    // ----------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ibi_flag <= 1'b0;
        end else begin
            if (detect_ibi()) begin
                ibi_flag <= 1'b1;  // Signal an IBI has been received
                wait(ibi_ack);     // Wait for host to acknowledge IBI
                ibi_flag <= 1'b0;
            end
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

    function logic [7:0] receive_data();
        logic [7:0] data;
        integer i;
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            data[i] <= sda;
        end
        return data;
    endfunction

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

// Define Secondary Master (Simplified)
module i3c_secondary_master #(
    parameter MAX_DEVICES = 8  // Maximum number of devices on the I3C bus
) (
    input  logic        clk,          // System clock
    input  logic        reset_n,      // Active-low reset
    inout  logic        sda,          // Serial Data Line
    output logic        scl,          // Serial Clock Line

    // Mastership Request Signals
    input  logic        request_mastership,  // Signal to request mastership
    output logic        master_granted,      // Signal indicating mastership granted

    // In-Band Interrupt (IBI) Signals
    input  logic        ibi_request,         // IBI request from a device
    output logic        ibi_ack,             // IBI acknowledgment

    // Slave Mode Address
    input  logic [6:0]  slave_address        // Assigned dynamic address
);

    // ----------------------------------------
    // Internal Signals
    // ----------------------------------------
    typedef enum logic [1:0] {
        SLAVE_MODE,
        MASTER_REQUEST,
        MASTER_MODE
    } state_t;

    state_t current_state, next_state;

    logic sda_out_en;        // Enable SDA driving
    logic sda_drive;         // Value to drive on SDA
    assign sda = sda_out_en ? sda_drive : 1'bz;

    logic scl_drive;         // Clock signal
    assign scl = scl_drive;

    typedef struct packed {
        logic [7:0] bcr;         // Bus Characteristics Register
        logic [7:0] dcr;         // Device Characteristics Register
        logic [7:0] lvr;         // Legacy Virtual Register
    } device_info_t;

    device_info_t devices[MAX_DEVICES];  // Device information array
    int device_count;                    // Number of devices on the bus

    // ----------------------------------------
    // State Machine
    // ----------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= SLAVE_MODE;
        end else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        case (current_state)
            SLAVE_MODE: begin
                if (request_mastership)
                    next_state = MASTER_REQUEST;
                else
                    next_state = SLAVE_MODE;
            end

            MASTER_REQUEST: begin
                if (master_granted)
                    next_state = MASTER_MODE;
                else
                    next_state = MASTER_REQUEST;
            end

            MASTER_MODE: begin
                if (!request_mastership)
                    next_state = SLAVE_MODE;
                else
                    next_state = MASTER_MODE;
            end

            default: next_state = SLAVE_MODE;
        endcase
    end

    // ----------------------------------------
    // Slave Mode Operation
    // ----------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset logic for slave mode
            ibi_ack <= 1'b0;
        end else if (current_state == SLAVE_MODE) begin
            if (detect_ibi()) begin
                ibi_ack <= 1'b1;  // Acknowledge IBI
            end else begin
                ibi_ack <= 1'b0;
            end
        end
    end

    function logic detect_ibi();
        // Check for IBI on the bus (SDA held low during idle by another device)
        return (sda == 1'b0 && scl == 1'b1);
    endfunction

    // ----------------------------------------
    // Request Mastership
    // ----------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            master_granted <= 1'b0;
        end else if (current_state == MASTER_REQUEST) begin
            // Send mastership request and wait for grant
            send_ccc_command(8'h06);  // MR (Mastership Request)
            wait_ack();
            master_granted <= 1'b1;
        end else begin
            master_granted <= 1'b0;
        end
    end

    // ----------------------------------------
    // Master Mode Operation
    // ----------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            device_count <= 0;  // Reset device count
        end else if (current_state == MASTER_MODE) begin
            // Assign dynamic addresses and collect device info
            assign_dynamic_addresses();
            collect_device_info();
        end
    end

    // Dynamic Address Assignment
    task assign_dynamic_addresses();
        int i;
        logic [6:0] dynamic_addr = 7'h10;
        for (i = 0; i < MAX_DEVICES; i++) begin
            // Simulate address assignment
            devices[i].bcr = receive_data();
            devices[i].dcr = receive_data();
            devices[i].lvr = receive_data();
            devices[i].dynamic_address = dynamic_addr;
            dynamic_addr++;
        end
    endtask

    // Collect Device Information
    task collect_device_info();
        int i;
        for (i = 0; i < device_count; i++) begin
            devices[i].bcr = receive_data();
            devices[i].dcr = receive_data();
            devices[i].lvr = receive_data();
        end
    endtask

    // ----------------------------------------
    // Data Transfer Tasks
    // ----------------------------------------
    task send_ccc_command(input logic [7:0] ccc_command);
        // Send a Common Command Code (CCC)
        send_data(ccc_command);
    endtask

    task send_data(input logic [7:0] data);
        integer i;
        for (i = 7; i >= 0; i--) begin
            sda_drive <= data[i];
            sda_out_en <= 1'b1;
            @(posedge scl);
        end
        sda_out_en <= 1'b0;
    endtask

    function logic [7:0] receive_data();
        logic [7:0] data;
        integer i;
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            data[i] <= sda;
        end
        return data;
    endfunction

    task wait_ack();
        @(negedge scl);
        if (sda != 1'b0) $fatal("ACK not received!");
    endtask

endmodule
// Define I3C Slave (Simplified)
module i3c_slave (
    input logic clk,                      // System clock
    input logic rst_n,                    // Active low reset
    input logic scl,                      // Serial clock (I3C clock)
    input logic sda_in,                   // Serial data input
    output logic sda_out,                 // Serial data output
    input logic [7:0] static_addr,        // Static address (if any)
    input logic [7:0] dynamic_addr,       // Dynamic address assigned by master
    input logic daa_request,              // DAA request signal from master
    input logic [7:0] daa_addr,           // Dynamic address assigned by master
    output logic daa_complete,            // DAA completion flag
    input logic ibi_request,              // In-Band Interrupt request from master
    output logic ibi_ack,                 // In-Band Interrupt acknowledgment
    input logic [7:0] ibi_data,           // Data for IBI transfer
    input logic [7:0] command,            // Command for directed or global CCCs
    input logic [7:0] tx_data,            // Data to be transmitted (for directed transfer)
    output logic [7:0] rx_data,           // Data received (for directed transfer)
    output logic [7:0] bcr,               // Bus Characteristic Register
    output logic [7:0] dcr,               // Device Characteristic Register
    output logic hot_join_request,        // Hot join request signal from slave (output)
    input logic hot_join_ack             // Hot join acknowledgment to master (input)
);

    // Internal state machine states
    typedef enum logic [3:0] {
        IDLE,                             // Idle state
        ADDR_MATCH,                       // Address match state
        DAA_ASSIGN,                       // Dynamic Address Assignment state
        DATA_TRANSFER,                    // Data transfer state
        IBI_WAIT,                         // Waiting for IBI handling
        CCC_EXEC,                         // Common Command Code execution
        HOT_JOIN_ACK_STATE,               // Hot Join Acknowledgment state
        HOT_JOIN_WAIT                     // Hot Join Wait state
    } state_t;

    state_t state;                        // Current state of the slave
    logic [7:0] rx_buffer;                // Receive buffer for address/data
    logic [7:0] tx_buffer;                // Transmit buffer for data
    logic sda_dir;                        // SDA direction control (input/output)
    logic [3:0] bit_counter;              // Bit counter for serial communication
    logic [7:0] internal_addr;            // Internal address (static or dynamic)
    logic [7:0] command_buffer;           // Store CCC command

    // Declare dynamic_addr as logic
    logic [7:0] dynamic_addr_reg;         // Use dynamic_addr_reg to store dynamic address internally

    // SDA Output Logic (when slave is driving SDA)
    assign sda_out = (sda_dir) ? tx_buffer[7] : 1'bz;

    // Default Register Values
    assign bcr = 8'h42;                     // Example BCR value
    assign dcr = 8'h10;                     // Example DCR value

    // Hot join request logic (send hot join request when slave needs to join)
    assign hot_join_request = (state == HOT_JOIN_ACK_STATE) ? 1'b1 : 1'b0;

    // Hot join acknowledge logic
    assign hot_join_ack = (state == HOT_JOIN_ACK_STATE) ? 1'b1 : 1'b0;

    // State Machine for I3C Slave
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            dynamic_addr_reg <= 8'h00;     // Initialize the internal register
            internal_addr <= 8'h00;
            daa_complete <= 1'b0;
            ibi_ack <= 1'b0;
            command_buffer <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    if (hot_join_ack) begin
                        // If hot join acknowledgment received, begin Hot Join process
                        state <= HOT_JOIN_ACK_STATE; // Move to hot join acknowledgment state
                        bit_counter <= 4'd0;
                    end else if (daa_request) begin
                        // If DAA request received, begin DAA process
                        state <= DAA_ASSIGN;
                        bit_counter <= 4'd0;
                    end else if (sda_in == 0) begin
                        // Start condition detected (address phase)
                        state <= ADDR_MATCH;
                        bit_counter <= 4'd0;
                    end
                end

                HOT_JOIN_ACK_STATE: begin
                    // Acknowledge the hot join request
                    sda_dir <= 1;               // Set SDA direction for ACK
                    tx_buffer <= 8'h00;         // Send ACK (address acknowledged)
                    state <= HOT_JOIN_WAIT;     // Wait after hot join acknowledgment
                end

                HOT_JOIN_WAIT: begin
                    // Wait for master to process hot join and continue communication
                    state <= IDLE;
                end

                DAA_ASSIGN: begin
                    if (bit_counter < 4'd8) begin
                        // Receive DAA address from master
                        rx_buffer <= {rx_buffer[6:0], sda_in};
                        bit_counter <= bit_counter + 1;
                    end else begin
                        // DAA completed, assign dynamic address
                        dynamic_addr_reg <= daa_addr;  // Address assigned by master
                        internal_addr <= dynamic_addr_reg;  // Set internal address to dynamic address
                        daa_complete <= 1'b1;  // Set DAA complete flag
                        state <= IDLE;  // Return to IDLE after DAA
                    end
                end

                ADDR_MATCH: begin
                    if (bit_counter < 4'd8) begin
                        // Shift in address bits
                        rx_buffer <= {rx_buffer[6:0], sda_in};
                        bit_counter <= bit_counter + 1;
                    end else begin
                        // Check if the received address matches static or dynamic address
                        if (rx_buffer == static_addr || rx_buffer == dynamic_addr_reg) begin
                            state <= DATA_TRANSFER;  // Address matched, proceed to data transfer
                            sda_dir <= 1;            // Prepare to transmit ACK
                            tx_buffer <= 8'h00;      // Send ACK (address acknowledged)
                        end else begin
                            state <= IDLE;  // Invalid address, go to IDLE
                        end
                    end
                end

                DATA_TRANSFER: begin
                    // Handle data transfer (read/write)
                    if (ibi_request) begin
                        // Handle IBI if requested
                        sda_dir <= 1;  // Set SDA direction for IBI response
                        tx_buffer <= ibi_data;  // Send IBI data
                        ibi_ack <= 1;  // Send IBI acknowledgment
                        state <= IBI_WAIT;  // Go to IBI_WAIT state after sending IBI response
                    end else if (command != 8'h00) begin
                        // Execute CCC command (directed or global)
                        state <= CCC_EXEC;
                    end else begin
                        // Normal data transfer (e.g., read/write)
                        rx_data <= rx_buffer;  // Store received data
                        state <= IDLE;  // End data transfer and return to IDLE
                    end
                end

                IBI_WAIT: begin
                    // Wait for master to process IBI response and transition back to IDLE
                    state <= IDLE;
                end

                CCC_EXEC: begin
                    // Handle Directed or Global CCCs (Common Command Codes)
                    command_buffer <= command;  // Store CCC command for processing
                    // Implement CCC-specific behavior here (directed or global)
                    state <= IDLE;  // After processing, return to IDLE
                end
            endcase
        end
    end
endmodule

// Define I2C Slave (Simplified)
module i2c_slave (
    input  logic        clk,            // Clock input
    input  logic        reset_n,        // Reset signal (active low)
    inout  logic        sda,            // Serial Data Line (bidirectional)
    input  logic        scl,            // Serial Clock Line
    input  logic [6:0]  slave_addr,     // Static slave address (I2C device)
    output logic        ibi_request,    // In-Band Interrupt Request
    input  logic [7:0]  ibi_data_in,    // Data for IBI
    output logic [7:0]  lvr_data_out,   // Legacy Virtual Register Data
    output logic        arbitration_lost // Flag indicating arbitration loss
);

    // Internal Signals
    logic sda_out_en;       // Enable SDA driving
    logic sda_drive;        // Value to drive on SDA
    logic scl_filtered;     // Filtered SCL signal
    logic ibi_active;       // Indicates active IBI
    logic addr_match;       // Address match signal
    logic [7:0] data_reg;   // Data register for received data
    logic [7:0] lvr_register; // Legacy Virtual Register storage
    logic arbitration_flag; // Internal arbitration flag

    assign sda = sda_out_en ? sda_drive : 1'bz;

    // Spike Filter: Filter out clock pulses < 50ns
    spike_filter #(50) scl_filter_inst (
        .clk(clk),
        .reset_n(reset_n),
        .raw_signal(scl),
        .filtered_signal(scl_filtered)
    );

    // Address Matching
    always_ff @(posedge scl_filtered or negedge reset_n) begin
        if (!reset_n) begin
            addr_match <= 1'b0;
        end else begin
            // Use local variable to store task output
            logic [6:0] captured_address;
            get_address(captured_address);
            if (is_address_phase() && (captured_address == slave_addr)) begin
                addr_match <= 1'b1;
            end else begin
                addr_match <= 1'b0;
            end
        end
    end

    // In-Band Interrupt (IBI) Management
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ibi_active <= 1'b0;
        end else if (ibi_request) begin
            ibi_active <= 1'b1;
        end else begin
            // Use local variable to store task output
            logic ibi_ack;
            ibi_acknowledged(ibi_ack);
            if (ibi_ack) begin
                ibi_active <= 1'b0;
            end
        end
    end

    // Legacy Virtual Register (LVR) Implementation
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lvr_register <= 8'h00; // Default LVR value
        end else if (addr_match) begin
            logic is_write, is_read;
            is_write_operation(is_write);
            is_read_operation(is_read);

            if (is_write) begin
                lvr_register <= get_data(); // Store data into LVR
            end else if (is_read) begin
                lvr_data_out <= lvr_register; // Output data from LVR
            end
        end
    end

    // Arbitration Management
    always_ff @(posedge scl_filtered or negedge reset_n) begin
        if (!reset_n) begin
            arbitration_flag <= 1'b0;
            arbitration_lost <= 1'b0;
        end else begin
            if (detect_arbitration_loss()) begin
                arbitration_flag <= 1'b1;
                arbitration_lost <= 1'b1;
            end else begin
                arbitration_flag <= 1'b0;
                arbitration_lost <= 1'b0;
            end
        end
    end

    // Basic I2C Slave Logic
    always_ff @(posedge scl_filtered or negedge reset_n) begin
        if (!reset_n) begin
            data_reg <= 8'h00;
        end else if (addr_match) begin
            logic is_write, is_read;
            is_write_operation(is_write);
            is_read_operation(is_read);

            if (is_write) begin
                data_reg <= get_data(); // Store received data
            end else if (is_read) begin
                send_data(data_reg); // Send data to master
            end
        end
    end

    // Function: Detect Arbitration Loss
    function logic detect_arbitration_loss();
        return (sda_out_en && sda != sda_drive);
    endfunction

    // Task: Get Data from SDA Line
    function [7:0] get_data();
        // Simplified for demonstration purposes
        return 8'hA5; // Placeholder for actual implementation
    endfunction

    // Task: Send Data on SDA Line
    task send_data(input [7:0] data);
        integer i;
        for (i = 7; i >= 0; i--) begin
            sda_drive <= data[i];
            sda_out_en <= 1'b1;
            @(posedge scl_filtered);
        end
        sda_out_en <= 1'b0; // Release SDA after transmission
    endtask

    // Task: Check if it's an Address Phase
    function logic is_address_phase();
        return (scl_filtered && !sda_out_en);
    endfunction

    // Task: Get Address from SDA Line
    task get_address(output logic [6:0] address);
        integer bit_count;
        address = 7'b0;
        bit_count = 0;

        while (bit_count < 7) begin
            @(negedge scl_filtered);
            address = {address[5:0], sda};
            bit_count++;
        end
    endtask

    // Task: Check Write Operation
    task is_write_operation(output logic is_write);
        logic rw_bit;
        @(negedge scl_filtered);
        rw_bit = sda;
        is_write = (rw_bit == 1'b0);
    endtask

    // Task: Check Read Operation
    task is_read_operation(output logic is_read);
        logic rw_bit;
        @(negedge scl_filtered);
        rw_bit = sda;
        is_read = (rw_bit == 1'b1);
    endtask

    // Task: IBI Acknowledgment
    task ibi_acknowledged(output logic acknowledged);
        @(negedge scl_filtered);
        acknowledged = (sda == 1'b0);
    endtask

endmodule

// Spike Filter Module
module spike_filter #(parameter THRESHOLD_NS = 50) (
    input  logic clk,
    input  logic reset_n,
    input  logic raw_signal,
    output logic filtered_signal
);
    logic [15:0] clk_counter;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_counter <= 0;
            filtered_signal <= 1'b0;
        end else if (raw_signal) begin
            if (clk_counter < THRESHOLD_NS) begin
                clk_counter <= clk_counter + 1;
            end else begin
                filtered_signal <= 1'b1;
            end
        end else begin
            clk_counter <= 0;
            filtered_signal <= 1'b0;
        end
    end
endmodule

/* module i3c_system (
    input logic clk,
    input logic rst_n
);
    // I3C Bus
    tri logic scl, sda;

    // Primary Master Control Signals
    logic start_transfer_primary;
    logic [7:0] data_in_primary, data_out_primary;
    logic busy_primary, ibi_detected_primary;

    // Secondary Master Control Signals
    logic [6:0] static_address_secondary;
    logic request_mastership, write_enable_secondary;
    logic [7:0] data_in_secondary, data_out_secondary;
    logic busy_secondary;

    // I3C Slave Control Signals
    logic [7:0] static_addr_slave, dynamic_addr_slave, rx_data_slave, tx_data_slave;
    logic daa_request_slave, daa_complete_slave, ibi_request_slave, ibi_ack_slave;
    logic [7:0] ibi_data_slave, command_slave;
    logic [7:0] bcr_slave, dcr_slave;
    logic hot_join_request_slave, hot_join_ack_slave;

    // I2C Slave Control Signals
    logic ibi_request_i2c;
    logic [6:0] slave_addr_i2c;
    logic [7:0] ibi_data_i2c, lvr_data_out_i2c;
    logic arbitration_lost_i2c;

    // Primary Master Instance
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

    // Secondary Master Instance
    i3c_secondary_master secondary_master (
        .clk(clk),
        .rst_n(rst_n),
        .scl(scl),
        .sda(sda),
        .static_address(static_address_secondary),
        .dynamic_address(dynamic_addr_slave),
        .request_mastership(request_mastership),
        .write_enable(write_enable_secondary),
        .data_in(data_in_secondary),
        .data_out(data_out_secondary),
        .busy(busy_secondary)
    );

    // I3C Slave Instance
    i3c_slave i3c_slave_inst (
        .clk(clk),
        .rst_n(rst_n),
        .scl(scl),
        .sda_in(sda),
        .sda_out(sda),
        .static_addr(static_addr_slave),
        .dynamic_addr(dynamic_addr_slave),
        .daa_request(daa_request_slave),
        .daa_addr(dynamic_addr_slave),
        .daa_complete(daa_complete_slave),
        .ibi_request(ibi_request_slave),
        .ibi_ack(ibi_ack_slave),
        .ibi_data(ibi_data_slave),
        .command(command_slave),
        .tx_data(tx_data_slave),
        .rx_data(rx_data_slave),
        .bcr(bcr_slave),
        .dcr(dcr_slave),
        .hot_join_request(hot_join_request_slave),
        .hot_join_ack(hot_join_ack_slave)
    );

    // I2C Slave Instance
    i2c_slave i2c_slave_inst (
        .clk(clk),
        .reset_n(rst_n),
        .sda(sda),
        .scl(scl),
        .slave_addr(slave_addr_i2c),
        .ibi_request(ibi_request_i2c),
        .ibi_data_in(ibi_data_i2c),
        .lvr_data_out(lvr_data_out_i2c),
        .arbitration_lost(arbitration_lost_i2c)
    );

endmodule

// Define Primary Master (Simplified)
module i3c_primary_master (
    input logic clk,
    input logic rst_n,
    inout tri logic scl,
    inout tri logic sda,
    input logic start_transfer,
    input logic [7:0] data_in,
    output logic [7:0] data_out,
    output logic busy,
    output logic ibi_detected
);
    // Placeholder behavior
    assign busy = 0;
    assign ibi_detected = 0;
endmodule

// Define Secondary Master (Simplified)
module i3c_secondary_master (
    input logic clk,
    input logic rst_n,
    inout tri logic scl,
    inout tri logic sda,
    input logic [6:0] static_address,
    output logic [7:0] dynamic_address, // Updated to 8 bits
    input logic request_mastership,
    input logic write_enable,
    input logic [7:0] data_in,
    output logic [7:0] data_out,
    output logic busy
);
    // Placeholder behavior
    assign busy = 0;
    assign dynamic_address = static_address;
    assign data_out = 0;
endmodule

// Define I3C Slave (Simplified)
module i3c_slave (
    input logic clk,
    input logic rst_n,
    input logic scl,
    input logic sda_in,
    output logic sda_out,
    input logic [7:0] static_addr,
    input logic [7:0] dynamic_addr,
    input logic daa_request,
    input logic [7:0] daa_addr,
    output logic daa_complete,
    output logic ibi_request, // Changed from input to output
    output logic ibi_ack,
    input logic [7:0] ibi_data,
    input logic [7:0] command,
    input logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic [7:0] bcr,
    output logic [7:0] dcr,
    output logic hot_join_request,
    input logic hot_join_ack
);
    // Placeholder behavior
    assign daa_complete = 0;
    assign ibi_ack = 0;
    assign rx_data = 0;
    assign bcr = 0;
    assign dcr = 0;
endmodule

// Define I2C Slave (Simplified)
module i2c_slave (
    input logic clk,
    input logic reset_n,
    inout logic sda,
    input logic scl,
    input logic [6:0] slave_addr,
    output logic ibi_request,
    input logic [7:0] ibi_data_in,
    output logic [7:0] lvr_data_out,
    output logic arbitration_lost
);
    // Placeholder behavior
    assign ibi_request = 0;
    assign lvr_data_out = 0;
    assign arbitration_lost = 0;
endmodule */
