library verilog;
use verilog.vl_types.all;
entity cordic_top is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        mode            : in     vl_logic;
        valid_in        : in     vl_logic;
        x_in            : in     vl_logic_vector(31 downto 0);
        y_in            : in     vl_logic_vector(31 downto 0);
        z_in            : in     vl_logic_vector(31 downto 0);
        valid_out       : out    vl_logic;
        x_out           : out    vl_logic_vector(31 downto 0);
        y_out           : out    vl_logic_vector(31 downto 0);
        z_out           : out    vl_logic_vector(31 downto 0)
    );
end cordic_top;
