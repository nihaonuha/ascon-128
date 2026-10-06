// tb_ascon_sbox_serial.sv
// ---------------------------------------------------------------------------
// Testbench for ascon_sbox_serial.
//
// Verification approach: this module should produce EXACTLY the same result
// as applying the combinational ascon_sbox independently to all 64 bit
// positions (i.e. the "parallel" version) -- it's the same S-box, just
// applied serially over time instead of in parallel. So the golden model
// here is a SystemVerilog function that does the parallel version, computed
// right in the testbench, rather than a separate external table (that
// already got verified in tb_ascon_sbox.sv).
// ---------------------------------------------------------------------------

module tb_ascon_sbox_serial;

    logic clk, rst_n, start, busy, done;
    logic [63:0] x0_in, x1_in, x2_in, x3_in, x4_in;
    logic [63:0] x0_out, x1_out, x2_out, x3_out, x4_out;
    int errors;

    ascon_sbox_serial dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .x0_in(x0_in), .x1_in(x1_in), .x2_in(x2_in), .x3_in(x3_in), .x4_in(x4_in),
        .busy(busy), .done(done),
        .x0_out(x0_out), .x1_out(x1_out), .x2_out(x2_out), .x3_out(x3_out), .x4_out(x4_out)
    );

    // Clock generation: 10-unit period
    initial clk = 0;
    always #5 clk = ~clk;

    // Reference S-box table (same golden table as tb_ascon_sbox.sv),
    // used here to compute the expected PARALLEL result for comparison.
    function automatic [4:0] sbox_ref(input [4:0] x);
        logic [4:0] table_ [0:31];
        table_[0]=5'h04; table_[1]=5'h0b; table_[2]=5'h1f; table_[3]=5'h14;
        table_[4]=5'h1a; table_[5]=5'h15; table_[6]=5'h09; table_[7]=5'h02;
        table_[8]=5'h1b; table_[9]=5'h05; table_[10]=5'h08; table_[11]=5'h12;
        table_[12]=5'h1d; table_[13]=5'h03; table_[14]=5'h06; table_[15]=5'h1c;
        table_[16]=5'h1e; table_[17]=5'h13; table_[18]=5'h07; table_[19]=5'h0e;
        table_[20]=5'h00; table_[21]=5'h0d; table_[22]=5'h11; table_[23]=5'h18;
        table_[24]=5'h10; table_[25]=5'h0c; table_[26]=5'h01; table_[27]=5'h19;
        table_[28]=5'h16; table_[29]=5'h0a; table_[30]=5'h0f; table_[31]=5'h17;
        sbox_ref = table_[x];
    endfunction

    // Compute the expected fully-substituted 5 words by applying sbox_ref
    // to every one of the 64 bit positions -- the "parallel" reference.
    task automatic compute_expected(
        input  logic [63:0] i0, i1, i2, i3, i4,
        output logic [63:0] e0, e1, e2, e3, e4
    );
        logic [4:0] in_bits, out_bits;
        e0 = 64'd0; e1 = 64'd0; e2 = 64'd0; e3 = 64'd0; e4 = 64'd0;
        for (int b = 0; b < 64; b++) begin
            in_bits = { i0[b], i1[b], i2[b], i3[b], i4[b] };
            out_bits = sbox_ref(in_bits);
            e0[b] = out_bits[4];
            e1[b] = out_bits[3];
            e2[b] = out_bits[2];
            e3[b] = out_bits[1];
            e4[b] = out_bits[0];
        end
    endtask

    task automatic run_case(
        input logic [63:0] i0, i1, i2, i3, i4,
        input string label
    );
        logic [63:0] e0, e1, e2, e3, e4;
        compute_expected(i0, i1, i2, i3, i4, e0, e1, e2, e3, e4);

        x0_in = i0; x1_in = i1; x2_in = i2; x3_in = i3; x4_in = i4;
        start = 1;
        @(posedge clk); #1;
        start = 0;

        // Wait until done pulses (bounded wait to avoid a hang on failure)
        for (int cyc = 0; cyc < 100 && !done; cyc++) begin
            @(posedge clk); #1;
        end

        if (!done) begin
            errors++;
            $display("FAIL [%s]: never asserted done", label);
        end else if (x0_out !== e0 || x1_out !== e1 || x2_out !== e2 ||
                     x3_out !== e3 || x4_out !== e4) begin
            errors++;
            $display("FAIL [%s]", label);
            $display("  got : %016h %016h %016h %016h %016h",
                      x0_out, x1_out, x2_out, x3_out, x4_out);
            $display("  want: %016h %016h %016h %016h %016h", e0, e1, e2, e3, e4);
        end else begin
            $display("PASS [%s]", label);
        end

        @(posedge clk); #1; // let FINISH state clear back to IDLE, settled
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        start = 0;
        x0_in = 0; x1_in = 0; x2_in = 0; x3_in = 0; x4_in = 0;

        repeat (2) @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        run_case(64'h0000000000000000, 64'h0000000000000000, 64'h0000000000000000,
                  64'h0000000000000000, 64'h0000000000000000, "all-zero");

        run_case(64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
                  64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF, "all-ones");

        run_case(64'h0123456789ABCDEF, 64'hFEDCBA9876543210, 64'h1111111111111111,
                  64'hAAAAAAAAAAAAAAAA, 64'h5555555555555555, "mixed-pattern-1");

        run_case(64'h8000000000000000, 64'h0000000000000001, 64'hDEADBEEFCAFEBABE,
                  64'h0F0F0F0F0F0F0F0F, 64'hF0F0F0F0F0F0F0F0, "mixed-pattern-2");

        if (errors == 0)
            $display("\n*** ALL SERIAL S-BOX VECTORS MATCH THE PARALLEL REFERENCE ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
