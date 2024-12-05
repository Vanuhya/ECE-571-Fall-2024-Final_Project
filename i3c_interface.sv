// Import the package outside the interface declaration
import i3c_pkg::*; // Import the package defining MAX_DEVICES

interface i3c_interface (
    input logic clk,
    input logic reset_n
);

    // Shared Bus Signals
    tri logic sda;  // Serial Data Line (tri-state for shared bus)
    tri logic scl;  // Serial Clock Line (tri-state for shared bus)

    // Modports for Specific Roles
    modport master (
        input clk, reset_n,
        inout sda, scl
    );

    modport slave (
        input clk, reset_n,
        inout sda, scl
    );

endinterface : i3c_interface

