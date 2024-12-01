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