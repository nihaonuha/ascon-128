// ascon_diffusion.sv
// ---------------------------------------------------------------------------
// Ascon linear diffusion layer (the Sigma / "P_L" step of one round).
//
// Operates independently on each of the 5 state words. For each 64-bit word,
// XOR it with two different rotated copies of itself. Each word has its own
// fixed pair of rotation amounts as defined by the Ascon spec.
//
//   x0' = x0 ^ ROTR(x0,19) ^ ROTR(x0,28)
//   x1' = x1 ^ ROTR(x1,61) ^ ROTR(x1,39)
//   x2' = x2 ^ ROTR(x2, 1) ^ ROTR(x2, 6)
//   x3' = x3 ^ ROTR(x3,10) ^ ROTR(x3,17)
//   x4' = x4 ^ ROTR(x4, 7) ^ ROTR(x4,41)
//
// Purely combinational, no interdependency between the five words at this
// stage (that mixing already happened in the S-box / substitution layer).
// ---------------------------------------------------------------------------

module ascon_diffusion (
    input  logic [63:0] x0_in,
    input  logic [63:0] x1_in,
    input  logic [63:0] x2_in,
    input  logic [63:0] x3_in,
    input  logic [63:0] x4_in,
    output logic [63:0] x0_out,
    output logic [63:0] x1_out,
    output logic [63:0] x2_out,
    output logic [63:0] x3_out,
    output logic [63:0] x4_out
);

    // Right-rotate a 64-bit value by n bits (n in range 1..63)
    function automatic logic [63:0] rotr(input logic [63:0] v, input int n);
        rotr = (v >> n) | (v << (64 - n));
    endfunction

    always_comb begin
        x0_out = x0_in ^ rotr(x0_in, 19) ^ rotr(x0_in, 28);
        x1_out = x1_in ^ rotr(x1_in, 61) ^ rotr(x1_in, 39);
        x2_out = x2_in ^ rotr(x2_in, 1)  ^ rotr(x2_in, 6);
        x3_out = x3_in ^ rotr(x3_in, 10) ^ rotr(x3_in, 17);
        x4_out = x4_in ^ rotr(x4_in, 7)  ^ rotr(x4_in, 41);
    end

endmodule
