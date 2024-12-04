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
