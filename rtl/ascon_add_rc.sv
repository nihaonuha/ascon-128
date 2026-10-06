// ascon_add_rc.sv
// ---------------------------------------------------------------------------
// Ascon round-constant addition layer (the "p_C" step of one round).
//
// XORs a fixed 8-bit round constant into the LOW BYTE of x2 only. All other
// bits of x2, and all of x0/x1/x3/x4, pass through completely unchanged.
// The constant depends only on which round (0-11 for the 12-round p^a
// permutation) is currently being executed.
//
// Constants are a fixed table from the Ascon spec (same idea as the S-box
// table — not computed, just fixed values every correct implementation
// must use).
// ---------------------------------------------------------------------------

module ascon_add_rc (
    input  logic [3:0]  round,   // 0..11
    input  logic [63:0] x2_in,
    output logic [63:0] x2_out
);

    logic [7:0] rc;

    always_comb begin
        case (round)
            4'd0:  rc = 8'hf0;
            4'd1:  rc = 8'he1;
            4'd2:  rc = 8'hd2;
            4'd3:  rc = 8'hc3;
            4'd4:  rc = 8'hb4;
            4'd5:  rc = 8'ha5;
            4'd6:  rc = 8'h96;
            4'd7:  rc = 8'h87;
            4'd8:  rc = 8'h78;
            4'd9:  rc = 8'h69;
            4'd10: rc = 8'h5a;
            4'd11: rc = 8'h4b;
            default: rc = 8'h00; // out of range, shouldn't happen
        endcase end
        assign x2_out = {x2_in[63:8], x2_in[7:0] ^ rc};
endmodule
