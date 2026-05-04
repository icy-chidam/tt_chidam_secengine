/*
 * TinyTapeout Sky130 Submission
 * Project   : Tiny Secure Telemetry Engine
 * Module    : tt_um_chidam_secengine
 * Author    : Chidam
 * License   : Apache-2.0
 *
 * ASIC-worthy 8-input / 8-output security and integrity engine.
 *
 * ui_in[7:6] mode
 *   00: absorb sample into nonlinear telemetry state
 *   01: stream-cipher / PRNG byte
 *   10: CRC-8 integrity update
 *   11: key/configuration stir
 *
 * ui_in[5:0] payload/control bits
 * uo_out[7:0] registered result byte
 *
 * uio pins are unused and held as inputs, so the application exposes only
 * 8 dedicated inputs and 8 dedicated outputs.
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

    reg [31:0] state_reg;
    reg [15:0] key_reg;
    reg [7:0]  crc_reg;
    reg [7:0]  ctr_reg;
    reg [7:0]  out_reg;

    wire [1:0] mode = ui_in[7:6];
    wire [7:0] din  = {ui_in[5:0], ui_in[7:6]};

    wire [31:0] mix_a = state_reg ^ {key_reg, ~key_reg} ^ {4{din ^ ctr_reg}};
    wire [31:0] mix_b = sub32(mix_a);
    wire [31:0] mix_c = {mix_b[18:0], mix_b[31:19]} ^
                        {mix_b[27:0], mix_b[31:28]};
    wire [31:0] round = mix_c ^ {key_reg, crc_reg, din} ^ 32'h9e37_79b9;
    wire [7:0]  crc_next = crc_step(crc_reg, din ^ state_reg[7:0]);

    assign uo_out  = out_reg;
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_reg <= 32'h6a09_e667;
            key_reg   <= 16'h243f;
            crc_reg   <= 8'h5a;
            ctr_reg   <= 8'h00;
            out_reg   <= 8'h00;
        end else if (ena) begin
            ctr_reg <= ctr_reg + 8'h01;

            case (mode)
                2'b00: begin
                    state_reg <= round ^ {crc_next, din, key_reg};
                    key_reg   <= key_reg ^ round[23:8] ^ {din, ctr_reg};
                    crc_reg   <= crc_next;
                    out_reg   <= round[7:0] ^ round[23:16] ^ crc_reg;
                end

                2'b01: begin
                    state_reg <= {round[23:0], round[31:24] ^ din};
                    key_reg   <= {key_reg[7:0], key_reg[15:8] ^ round[7:0] ^ din};
                    crc_reg   <= crc_step(crc_reg ^ round[15:8], din);
                    out_reg   <= round[15:8] ^ round[31:24] ^ din;
                end

                2'b10: begin
                    state_reg <= state_reg ^ {round[15:0], crc_next, din};
                    key_reg   <= key_reg ^ {crc_next, din};
                    crc_reg   <= crc_next;
                    out_reg   <= crc_next ^ state_reg[15:8] ^ key_reg[7:0];
                end

                default: begin
                    state_reg <= {state_reg[24:0], state_reg[31:25]} ^ {din, crc_reg, key_reg};
                    key_reg   <= {key_reg[10:0], key_reg[15:11]} ^ {din, ctr_reg};
                    crc_reg   <= 8'ha5 ^ din ^ ctr_reg;
                    out_reg   <= key_reg[15:8] ^ state_reg[31:24] ^ crc_reg;
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

    function [31:0] sub32;
        input [31:0] x;
        begin
            sub32 = {
                x[31:28],        sbox4(x[27:24]),
                sbox4(x[23:20]), sbox4(x[19:16]),
                sbox4(x[15:12]), sbox4(x[11:8]),
                sbox4(x[7:4]),   sbox4(x[3:0])
            };
        end
    endfunction

    function [7:0] crc_step;
        input [7:0] crc;
        input [7:0] data;
        reg fb0;
        reg fb1;
        reg fb2;
        begin
            fb0 = crc[7] ^ data[0] ^ data[5];
            fb1 = crc[5] ^ data[2] ^ data[7];
            fb2 = crc[3] ^ data[1] ^ data[4];
            crc_step = {
                crc[6] ^ data[6],
                crc[5] ^ fb0,
                crc[4] ^ data[3],
                crc[3] ^ fb1,
                crc[2] ^ data[2] ^ fb0,
                crc[1] ^ fb2,
                crc[0] ^ data[0],
                fb0 ^ fb1 ^ fb2
            };
        end
    endfunction

    wire _unused = &{uio_in, 1'b0};

endmodule

`default_nettype wire
