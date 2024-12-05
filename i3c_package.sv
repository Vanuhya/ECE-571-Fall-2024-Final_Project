package i3c_pkg;

    // -------------------------------------------------------
    // Parameters and Constants
    // -------------------------------------------------------
    parameter int MAX_DEVICES = 8;         // Maximum number of devices on the bus
    parameter int I3C_DYNAMIC_ADDR_MIN = 7'h08;
    parameter int I3C_DYNAMIC_ADDR_MAX = 7'h7F;

    // -------------------------------------------------------
    // Enumerations
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        MASTERSHIP = 2'b01,
        DATA_TRANSFER = 2'b10
    } i3c_state_t;

    // -------------------------------------------------------
    // Structures for Transactions
    // -------------------------------------------------------
    typedef struct {
        logic [7:0] data;
        logic [6:0] static_address;
        logic [7:0] command;
        bit         request_mastership;
        bit         ibi_request;
        bit         write_enable;
    } i3c_transaction_t;

endpackage : i3c_pkg

