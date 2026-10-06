// tb_ascon_diffusion.sv
// ---------------------------------------------------------------------------
// Self-checking testbench for ascon_diffusion.
// Golden vectors were generated from an independent Python model of the same
// Sigma function (x ^ ROTR(x,a) ^ ROTR(x,b) per word), NOT copied from the
// RTL, so this is a true independent cross-check rather than a tautology.
// ---------------------------------------------------------------------------

module tb_ascon_diffusion;

    logic [63:0] x0_in, x1_in, x2_in, x3_in, x4_in;
    logic [63:0] x0_out, x1_out, x2_out, x3_out, x4_out;
    int errors;

    ascon_diffusion dut (
        .x0_in(x0_in), .x1_in(x1_in), .x2_in(x2_in), .x3_in(x3_in), .x4_in(x4_in),
        .x0_out(x0_out), .x1_out(x1_out), .x2_out(x2_out), .x3_out(x3_out), .x4_out(x4_out)
    );

    task automatic check_vector(
        input logic [63:0] i0, i1, i2, i3, i4,
        input logic [63:0] e0, e1, e2, e3, e4,
        input string label
    );
        x0_in = i0; x1_in = i1; x2_in = i2; x3_in = i3; x4_in = i4;
        #1;
        if (x0_out !== e0 || x1_out !== e1 || x2_out !== e2 ||
            x3_out !== e3 || x4_out !== e4) begin
            errors++;
            $display("FAIL [%s]", label);
            $display("  got : %016h %016h %016h %016h %016h",
                      x0_out, x1_out, x2_out, x3_out, x4_out);
            $display("  want: %016h %016h %016h %016h %016h", e0, e1, e2, e3, e4);
        end else begin
            $display("PASS [%s]", label);
        end
    endtask

    initial begin
        errors = 0;

        check_vector(
            64'h0000000000000000, 64'h0000000000000000, 64'h0000000000000000,
            64'h0000000000000000, 64'h0000000000000000,
            64'h0000000000000000, 64'h0000000000000000, 64'h0000000000000000,
            64'h0000000000000000, 64'h0000000000000000,
            "all-zero"
        );

        check_vector(
            64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
            64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
            64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
            64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
            "all-ones"
        );

        check_vector(
            64'h0123456789ABCDEF, 64'hFEDCBA9876543210, 64'h1111111111111111,
            64'hAAAAAAAAAAAAAAAA, 64'h5555555555555555,
            64'hE2227BB3F3336AA2, 64'h38D5C63FE5081BE2, 64'hDDDDDDDDDDDDDDDD,
            64'h5555555555555555, 64'h5555555555555555,
            "mixed-pattern-1"
        );

        check_vector(
            64'h8000000000000000, 64'h0000000000000001, 64'hDEADBEEFCAFEBABE,
            64'h0F0F0F0F0F0F0F0F, 64'hF0F0F0F0F0F0F0F0,
            64'h8000100800000000, 64'h0000000002000009, 64'h4A81D76390AA1D0B,
            64'h4B4B4B4B4B4B4B4B, 64'h6969696969696969,
            "mixed-pattern-2"
        );

        check_vector(
            64'h0102030405060708, 64'h1122334455667788, 64'h9988776655443322,
            64'hA5A5A5A5A5A5A5A5, 64'h5A5A5A5A5A5A5A5A,
            64'h918373A45546B7E8, 64'h10996589EE778FAE, 64'h5F2A6D08E6B33A7F,
            64'h1E1E1E1E1E1E1E1E, 64'hC3C3C3C3C3C3C3C3,
            "mixed-pattern-3"
        );

        if (errors == 0)
            $display("\n*** ALL DIFFUSION VECTORS MATCH THE GOLDEN MODEL ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
