// ascon_sbox.sv
// ---------------------------------------------------------------------------
// Ascon 5-bit substitution layer (S-box), implemented as a combinational
// lookup table (case statement) directly from the golden S-box table.
//
// Bit ordering convention:
//   Input  x = {x0, x1, x2, x3, x4}   -> x0 is bit[4] (MSB), x4 is bit[0] (LSB)
//   Output y = {y0, y1, y2, y3, y4}   -> same convention
// ---------------------------------------------------------------------------

module ascon_sbox (
    input  logic [4:0] x,
    output logic [4:0] y
);

    always_comb begin
        case (x)
            5'h00: y = 5'h04;
            5'h01: y = 5'h0b;
            5'h02: y = 5'h1f;
            5'h03: y = 5'h14;
            5'h04: y = 5'h1a;
            5'h05: y = 5'h15;
            5'h06: y = 5'h09;
            5'h07: y = 5'h02;
            5'h08: y = 5'h1b;
            5'h09: y = 5'h05;
            5'h0a: y = 5'h08;
            5'h0b: y = 5'h12;
            5'h0c: y = 5'h1d;
            5'h0d: y = 5'h03;
            5'h0e: y = 5'h06;
            5'h0f: y = 5'h1c;
            5'h10: y = 5'h1e;
            5'h11: y = 5'h13;
            5'h12: y = 5'h07;
            5'h13: y = 5'h0e;
            5'h14: y = 5'h00;
            5'h15: y = 5'h0d;
            5'h16: y = 5'h11;
            5'h17: y = 5'h18;
            5'h18: y = 5'h10;
            5'h19: y = 5'h0c;
            5'h1a: y = 5'h01;
            5'h1b: y = 5'h19;
            5'h1c: y = 5'h16;
            5'h1d: y = 5'h0a;
            5'h1e: y = 5'h0f;
            5'h1f: y = 5'h17;
            default: y = 5'h00; // unreachable, x is always 5 bits
        endcase
    end

endmodule
