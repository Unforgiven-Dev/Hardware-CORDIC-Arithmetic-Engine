// =============================================================================
//  Module     : cordic_core
//  Description: CORDIC pipeline core, 32-bit Q2.29, 20 iterations
//
//  Supports ROTATION mode  : x_in = An (~0.6073), y_in = 0
//                            -> x_out = cos(z_in), y_out = sin(z_in)
//  Supports VECTORING mode : z_in = 0
//                            -> x_out = hypot(x,y)*(1/An), z_out = atan2(y,x)
//
//  Architecture  : Fully pipelined, 1 result per clock after ITER+2 cycle latency
//  Target        : >= 100 MHz on Intel/Xilinx FPGA (shift + add, no multiplier)
//
//  Q2.29 fixed-point format:
//    bit[31]     = sign
//    bits[30:29] = integer part
//    bits[28:0]  = fractional part
//    Range: -4.0 to +3.9999...
//
//  CORDIC micro-rotation (per stage i = 0..ITER-1):
//    sigma  = sign(z)  [ROTATION]  or  -sign(y)  [VECTORING]
//    x_next = x - sigma * (y >>> i)
//    y_next = y + sigma * (x >>> i)
//    z_next = z - sigma * atan(2^-i)
//
//  CORDIC gain: product of sqrt(1 + 2^-2i) for i=0..ITER-1 = 1/An ~ 1.6468
//  Caller pre-multiplies x_init by An to cancel the gain at output.
//
//  [FIX] Comment sigma convention clarified to match update equations below.
// =============================================================================

`timescale 1ns / 1ps

module cordic_core #(
    parameter N    = 32,   // word width (bits)
    parameter ITER = 20    // number of CORDIC iterations = pipeline stages
)(
    input  wire             clk,
    input  wire             rst_n,      // active-low synchronous reset
    input  wire             mode,       // 0 = ROTATION, 1 = VECTORING
    input  wire             valid_in,
    input  wire signed [N-1:0] x_in,
    input  wire signed [N-1:0] y_in,
    input  wire signed [N-1:0] z_in,
    output reg              valid_out,
    output reg  signed [N-1:0] x_out,  // cos (ROT) or magnitude*(1/An) (VEC)
    output reg  signed [N-1:0] y_out,  // sin (ROT) or ~0 (VEC)
    output reg  signed [N-1:0] z_out   // ~0 (ROT) or atan2(y,x) (VEC)
);

    // -------------------------------------------------------------------------
    // Arctangent look-up table: atan(2^-i) in Q2.29
    // Computed as: round(atan(2^-i) * 2^29), verified against Python/numpy
    // -------------------------------------------------------------------------
    function [N-1:0] atan_lut;
        input integer i;
        case (i)
            0:  atan_lut = 32'h1921FB54; // 0.78539816 rad  (pi/4)
            1:  atan_lut = 32'h0ED63383; // 0.46364761 rad
            2:  atan_lut = 32'h07D6DD7E; // 0.24497866 rad
            3:  atan_lut = 32'h03FAB753; // 0.12435499 rad
            4:  atan_lut = 32'h01FF55BB; // 0.06241881 rad
            5:  atan_lut = 32'h00FFEAAE; // 0.03123983 rad
            6:  atan_lut = 32'h007FFD55; // 0.01562373 rad
            7:  atan_lut = 32'h003FFFAB; // 0.00781234 rad
            8:  atan_lut = 32'h001FFFF5; // 0.00390623 rad
            9:  atan_lut = 32'h000FFFFF; // 0.00195312 rad
            10: atan_lut = 32'h00080000; // 0.00097656 rad
            11: atan_lut = 32'h00040000; // 0.00048828 rad
            12: atan_lut = 32'h00020000; // 0.00024414 rad
            13: atan_lut = 32'h00010000; // 0.00012207 rad
            14: atan_lut = 32'h00008000; // 0.00006104 rad
            15: atan_lut = 32'h00004000; // 0.00003052 rad
            16: atan_lut = 32'h00002000; // 0.00001526 rad
            17: atan_lut = 32'h00001000; // 0.00000763 rad
            18: atan_lut = 32'h00000800; // 0.00000381 rad
            19: atan_lut = 32'h00000400; // 0.00000191 rad
            default: atan_lut = {N{1'b0}};
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Pipeline stage registers  [0] = input capture, [ITER] = last iteration
    // -------------------------------------------------------------------------
    reg signed [N-1:0] xp [0:ITER];
    reg signed [N-1:0] yp [0:ITER];
    reg signed [N-1:0] zp [0:ITER];
    reg                mp [0:ITER];  // mode pipeline
    reg                vp [0:ITER];  // valid pipeline

    // Stage 0: capture inputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xp[0] <= {N{1'b0}};
            yp[0] <= {N{1'b0}};
            zp[0] <= {N{1'b0}};
            mp[0] <= 1'b0;
            vp[0] <= 1'b0;
        end else begin
            xp[0] <= x_in;
            yp[0] <= y_in;
            zp[0] <= z_in;
            mp[0] <= mode;
            vp[0] <= valid_in;
        end
    end

    // Stages 1..ITER: CORDIC micro-rotation (generate unrolls into flip-flops)
    genvar gi;
    generate
        for (gi = 0; gi < ITER; gi = gi + 1) begin : STAGE
            wire sigma;
            wire signed [N-1:0] x_sh, y_sh;
            wire signed [N-1:0] x_nxt, y_nxt, z_nxt;
            wire [N-1:0]        lut_val;

            // [FIX] Sigma convention (consistent with update equations below):
            //   ROTATION  : sigma = zp[gi][N-1]  (sign bit of z)
            //                 z >= 0 (MSB=0) -> sigma=0 -> x-=y>>i, y+=x>>i, z-=lut (CCW)
            //                 z <  0 (MSB=1) -> sigma=1 -> x+=y>>i, y-=x>>i, z+=lut (CW)
            //   VECTORING : sigma = ~yp[gi][N-1]  (-sign(y))
            //                 y >= 0 (MSB=0) -> sigma=1 -> x+=y>>i, y-=x>>i (drives y toward 0)
            //                 y <  0 (MSB=1) -> sigma=0 -> x-=y>>i, y+=x>>i
            assign sigma = mp[gi] ? (~yp[gi][N-1]) : (zp[gi][N-1]);

            // Arithmetic right shift (sign-extending) by i positions
            assign x_sh  = $signed(xp[gi]) >>> gi;
            assign y_sh  = $signed(yp[gi]) >>> gi;

            assign lut_val = atan_lut(gi);

            // Rotation update equations:
            //   sigma=0: x -= y>>i,  y += x>>i,  z -= lut  (CCW rotation)
            //   sigma=1: x += y>>i,  y -= x>>i,  z += lut  (CW  rotation)
            assign x_nxt = sigma ? ($signed(xp[gi]) + $signed(y_sh))
                                 : ($signed(xp[gi]) - $signed(y_sh));
            assign y_nxt = sigma ? ($signed(yp[gi]) - $signed(x_sh))
                                 : ($signed(yp[gi]) + $signed(x_sh));
            assign z_nxt = sigma ? ($signed(zp[gi]) + $signed(lut_val))
                                 : ($signed(zp[gi]) - $signed(lut_val));

            // Register stage output
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    xp[gi+1] <= {N{1'b0}};
                    yp[gi+1] <= {N{1'b0}};
                    zp[gi+1] <= {N{1'b0}};
                    mp[gi+1] <= 1'b0;
                    vp[gi+1] <= 1'b0;
                end else begin
                    xp[gi+1] <= x_nxt;
                    yp[gi+1] <= y_nxt;
                    zp[gi+1] <= z_nxt;
                    mp[gi+1] <= mp[gi];
                    vp[gi+1] <= vp[gi];
                end
            end
        end
    endgenerate

    // Output register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out     <= {N{1'b0}};
            y_out     <= {N{1'b0}};
            z_out     <= {N{1'b0}};
            valid_out <= 1'b0;
        end else begin
            x_out     <= xp[ITER];
            y_out     <= yp[ITER];
            z_out     <= zp[ITER];
            valid_out <= vp[ITER];
        end
    end

endmodule
