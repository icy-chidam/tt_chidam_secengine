/*
 * TinyTapeout Sky130 Submission
 * Project   : Tiny Secure Telemetry Engine
 * Module    : tt_um_chidam_secengine
 * Author    : Chidam
 * License   : Apache-2.0
 *
 * 8 dedicated inputs, 8 dedicated outputs.
 *
 * ui_in[7:6] mode
 *   00: absorb byte into nonlinear state and CRC
 *   01: keystream / lightweight stream-cipher step
 *   10: CRC-16/CCITT integrity update
 *   11: key/config stir step
 *
 * ui_in[5:0] payload/control bits
 * uo_out[7:0] registered result byte
 *
 * The bidirectional pins are intentionally not used as application IO.
 */

`default_nettype none

module tt_um_chidam_secengine (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    reg [63:0] state_reg;
    reg [31:0] key_reg;
    reg [15:0] crc_reg;
    reg [7:0]  ctr_reg;
    reg [7:0]  out_reg;

    wire [1:0] mode = ui_in[7:6];
    wire [7:0] din  = {ui_in[5:0], ui_in[7:6]};

    wire [63:0] round_0 = perm_round(state_reg, key_reg, din, ctr_reg);
    wire [63:0] round_1 = perm_round(round_0, {key_reg[18:0], key_reg[31:19]}, din ^ 8'h3c, ctr_reg + 8'h29);
    wire [63:0] round_2 = perm_round(round_1, {key_reg[10:0], key_reg[31:11]}, din ^ 8'ha7, ctr_reg + 8'h51);
    wire [63:0] round_3 = perm_round(round_2, {key_reg[26:0], key_reg[31:27]}, din ^ 8'h5e, ctr_reg + 8'h8d);
    wire [15:0] crc_next = crc16_ccitt(crc_reg, din ^ state_reg[7:0]);

    assign uo_out  = out_reg;
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_reg <= 64'h6a09_e667_f3bc_c908;
            key_reg   <= 32'h243f_6a88;
            crc_reg   <= 16'h1d0f;
            ctr_reg   <= 8'h00;
            out_reg   <= 8'h00;
        end else if (ena) begin
            ctr_reg <= ctr_reg + 8'h01;

            case (mode)
                2'b00: begin
                    state_reg <= round_3 ^ {crc_next, key_reg, din, ctr_reg};
                    key_reg   <= key_reg ^ round_3[47:16] ^ {24'h0, din};
                    crc_reg   <= crc_next;
                    out_reg   <= round_3[7:0] ^ round_3[39:32] ^ crc_reg[15:8];
                end

                2'b01: begin
                    state_reg <= {round_3[55:0], round_3[63:56]} ^ {8{din}};
                    key_reg   <= {key_reg[23:0], key_reg[31:24] ^ din ^ round_3[7:0]};
                    crc_reg   <= crc16_ccitt(crc_reg ^ round_3[31:16], din);
                    out_reg   <= round_3[15:8] ^ round_3[55:48] ^ din;
                end

                2'b10: begin
                    state_reg <= state_reg ^ {crc_next, round_2[47:0]};
                    key_reg   <= key_reg + {crc_next, din, ctr_reg};
                    crc_reg   <= crc_next;
                    out_reg   <= crc_next[15:8] ^ crc_next[7:0] ^ state_reg[23:16];
                end

                default: begin
                    state_reg <= {state_reg[55:0], state_reg[63:56] ^ din ^ key_reg[7:0]};
                    key_reg   <= {key_reg[22:0], key_reg[31:23]} ^ {din, ctr_reg, crc_reg[7:0], crc_reg[15:8]};
                    crc_reg   <= 16'hace1 ^ {din, ctr_reg};
                    out_reg   <= key_reg[7:0] ^ state_reg[63:56] ^ crc_reg[7:0];
                end
            endcase
        end
    end

    function [3:0] sbox4;
        input [3:0] x;
        begin
            case (x)
                4'h0: sbox4 = 4'hc;
                4'h1: sbox4 = 4'h5;
                4'h2: sbox4 = 4'h6;
                4'h3: sbox4 = 4'hb;
                4'h4: sbox4 = 4'h9;
                4'h5: sbox4 = 4'h0;
                4'h6: sbox4 = 4'ha;
                4'h7: sbox4 = 4'hd;
                4'h8: sbox4 = 4'h3;
                4'h9: sbox4 = 4'he;
                4'ha: sbox4 = 4'hf;
                4'hb: sbox4 = 4'h8;
                4'hc: sbox4 = 4'h4;
                4'hd: sbox4 = 4'h7;
                4'he: sbox4 = 4'h1;
                default: sbox4 = 4'h2;
            endcase
        end
    endfunction

    function [63:0] sub64;
        input [63:0] x;
        begin
            sub64 = {
                sbox4(x[63:60]), sbox4(x[59:56]),
                sbox4(x[55:52]), sbox4(x[51:48]),
                sbox4(x[47:44]), sbox4(x[43:40]),
                sbox4(x[39:36]), sbox4(x[35:32]),
                sbox4(x[31:28]), sbox4(x[27:24]),
                sbox4(x[23:20]), sbox4(x[19:16]),
                sbox4(x[15:12]), sbox4(x[11:8]),
                sbox4(x[7:4]),   sbox4(x[3:0])
            };
        end
    endfunction

    function [63:0] perm_round;
        input [63:0] s;
        input [31:0] k;
        input [7:0]  d;
        input [7:0]  c;
        reg   [63:0] a;
        reg   [63:0] b;
        begin
            a = sub64(s ^ {k, ~k} ^ {8{d ^ c}});
            b = {a[50:0], a[63:51]} ^ {a[22:0], a[63:23]} ^ {a[7:0], a[63:8]};
            perm_round = b + {k, ~k} + {24'h9e3779, d, 24'h7f4a7c, c};
        end
    endfunction

    function [15:0] crc16_ccitt;
        input [15:0] crc;
        input [7:0]  data;
        integer i;
        reg [15:0] c;
        begin
            c = crc ^ {data, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[15])
                    c = (c << 1) ^ 16'h1021;
                else
                    c = c << 1;
            end
            crc16_ccitt = c;
        end
    endfunction

    wire _unused = &{uio_in, 1'b0};

endmodule

`default_nettype wire
