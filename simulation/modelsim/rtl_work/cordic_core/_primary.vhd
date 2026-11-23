library verilog;
use verilog.vl_types.all;
entity cordic_core is
    generic(
        N               : integer := 32;
        ITER            : integer := 20
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        mode            : in     vl_logic;
        valid_in        : in     vl_logic;
        x_in            : in     vl_logic_vector;
        y_in            : in     vl_logic_vector;
        z_in            : in     vl_logic_vector;
        valid_out       : out    vl_logic;
        x_out           : out    vl_logic_vector;
        y_out           : out    vl_logic_vector;
        z_out           : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of N : constant is 1;
    attribute mti_svvh_generic_type of ITER : constant is 1;
end cordic_core;
