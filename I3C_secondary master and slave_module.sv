module I3C_Integrated #(parameter ADDR_WIDTH = 7) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         bus_grant,
    input  logic [ADDR_WIDTH-1:0] master_addr,  // Secondary Master's address
    input  logic [ADDR_WIDTH-1:0] slave_addr,   // Slave's address
    input  logic         data_in,              // Input data
    input  logic         write_enable,         // Write enable for Slave
    output logic [7:0]   data_out_master,      // Output data from Master
    output logic [7:0]   data_out_slave,       // Output data from Slave
    output logic         request_mastership    // Request Mastership signal
);

    typedef enum logic [1:0] {SLAVE_MODE, REQUEST_MASTER, MASTER_MODE} master_state_t;
    master_state_t current_state, next_state;

    logic [7:0] memory [0:127];  // Slave's memory

    // Master State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= SLAVE_MODE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        request_mastership = 1'b0;

        case (current_state)
            SLAVE_MODE: if (bus_grant) next_state = REQUEST_MASTER;
            REQUEST_MASTER: begin
                request_mastership = 1'b1;
                if (bus_grant) next_state = MASTER_MODE;
            end
            MASTER_MODE: if (!bus_grant) next_state = SLAVE_MODE;
        endcase
    end

    assign data_out_master = (current_state == MASTER_MODE) ? {7'b0, data_in} : 8'b0;

    // Slave Memory Read/Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 128; i++) memory[i] <= 8'b0;
        end else if (write_enable) begin
            memory[slave_addr] <= {7'b0, data_in};
        end
    end

    always_ff @(posedge clk) begin
        data_out_slave <= memory[slave_addr];
    end

endmodule
