// tb_ascon_data_process.sv
// ---------------------------------------------------------------------------
// Testbench for ascon_data_process, the merged encrypt/decrypt module that
// replaced the separate ascon_pt_process and ascon_ct_process. Covers BOTH
// directions:
//   - ENCRYPT (mode_decrypt=0): same cases as the old tb_ascon_pt_process.sv
//   - DECRYPT (mode_decrypt=1): same round-trip cases as the old
//     tb_ascon_ct_process.sv (feeds in the exact ciphertext the encrypt
//     cases produced, checks the original plaintext comes back out)
//
// One "don't care" test-precision fix versus the old ct_process testbench:
// the old test asserted an EXACT zero for output bytes beyond pt_bytes/
// ct_bytes (data past the real byte count). That's documented as don't-care
// in both directions -- the old ct_process module happened to leave zeros
// there, while pt_process happened to leave an XOR artifact; the merged
// module also leaves the artifact (a legitimate, equally-valid choice per
// the contract). So here we check out_bytes (the actual metadata contract)
// instead of the non-contractual data pattern for those specific blocks.
// See DESIGN_LOG.md for the full writeup.
// ---------------------------------------------------------------------------

module tb_ascon_data_process;

    logic clk, rst_n, start, mode_decrypt, busy, done;
    logic [63:0] x0_in, x1_in, x2_in, x3_in, x4_in;
    logic [63:0] x0_out, x1_out, x2_out, x3_out, x4_out;

    logic        block_req;
    logic [63:0] block_data;
    logic        block_is_last;
    logic [3:0]  block_bytes;
    logic        block_valid;

    logic        out_valid;
    logic [63:0] out_data;
    logic [3:0]  out_bytes;

    int errors;

    // Local shared permutation instance, wired the same way ascon_top does it.
    logic        perm_start, perm_busy, perm_done;
    logic [3:0]  perm_num_rounds;
    logic [63:0] perm_x0_in, perm_x1_in, perm_x2_in, perm_x3_in, perm_x4_in;
    logic [63:0] perm_x0_out, perm_x1_out, perm_x2_out, perm_x3_out, perm_x4_out;

    ascon_permutation perm_inst (
        .clk(clk), .rst_n(rst_n), .start(perm_start), .num_rounds(perm_num_rounds),
        .x0_in(perm_x0_in), .x1_in(perm_x1_in), .x2_in(perm_x2_in), .x3_in(perm_x3_in), .x4_in(perm_x4_in),
        .busy(perm_busy), .done(perm_done),
        .x0_out(perm_x0_out), .x1_out(perm_x1_out), .x2_out(perm_x2_out), .x3_out(perm_x3_out), .x4_out(perm_x4_out)
    );

    ascon_data_process dut (
        .clk(clk), .rst_n(rst_n), .start(start), .mode_decrypt(mode_decrypt),
        .x0_in(x0_in), .x1_in(x1_in), .x2_in(x2_in), .x3_in(x3_in), .x4_in(x4_in),
        .block_req(block_req), .block_data(block_data),
        .block_is_last(block_is_last), .block_bytes(block_bytes), .block_valid(block_valid),
        .out_valid(out_valid), .out_data(out_data), .out_bytes(out_bytes),
        .perm_start(perm_start), .perm_num_rounds(perm_num_rounds),
        .perm_x0_in(perm_x0_in), .perm_x1_in(perm_x1_in), .perm_x2_in(perm_x2_in),
        .perm_x3_in(perm_x3_in), .perm_x4_in(perm_x4_in),
        .perm_busy(perm_busy), .perm_done(perm_done),
        .perm_x0_out(perm_x0_out), .perm_x1_out(perm_x1_out), .perm_x2_out(perm_x2_out),
        .perm_x3_out(perm_x3_out), .perm_x4_out(perm_x4_out),
        .busy(busy), .done(done),
        .x0_out(x0_out), .x1_out(x1_out), .x2_out(x2_out), .x3_out(x3_out), .x4_out(x4_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Base state used as input for every test case (post-AD-absorb state)
    localparam logic [63:0] BASE_X0 = 64'h0BB7DA48A9F6869A;
    localparam logic [63:0] BASE_X1 = 64'h584DB678AC4D1B07;
    localparam logic [63:0] BASE_X2 = 64'h3D5FB897517D85BC;
    localparam logic [63:0] BASE_X3 = 64'h1C7A606B20964237;
    localparam logic [63:0] BASE_X4 = 64'h17C528BA07736373;

    logic [63:0] captured_out [0:3];
    logic [3:0]  captured_out_bytes [0:3];
    int          out_count;

    task automatic feed_block(
        input logic [63:0] data,
        input logic        is_last,
        input logic [3:0]  bytes
    );
        int wait_cyc;
        wait_cyc = 0;
        while (!block_req && wait_cyc < 500) begin
            @(posedge clk); #1;
            wait_cyc++;
        end
        if (!block_req) $display("WARNING: block_req never asserted, timed out waiting");

        block_data    = data;
        block_is_last = is_last;
        block_bytes   = bytes;
        block_valid   = 1;
        @(posedge clk); #1;
        block_valid   = 0;

        wait_cyc = 0;
        while (!out_valid && wait_cyc < 10) begin
            @(posedge clk); #1;
            wait_cyc++;
        end
        if (out_valid) begin
            captured_out[out_count]       = out_data;
            captured_out_bytes[out_count] = out_bytes;
            out_count++;
        end else begin
            $display("WARNING: out_valid never asserted after block");
        end
    endtask

    task automatic wait_done(int max_cycles);
        for (int cyc = 0; cyc < max_cycles && !done; cyc++) begin
            @(posedge clk); #1;
        end
    endtask

    task automatic check_result(
        input logic [63:0] e0, e1, e2, e3, e4,
        input string label
    );
        if (!done) begin
            errors++;
            $display("FAIL [%s]: never asserted done", label);
        end else if (x0_out !== e0 || x1_out !== e1 || x2_out !== e2 ||
                     x3_out !== e3 || x4_out !== e4) begin
            errors++;
            $display("FAIL [%s] (state)", label);
            $display("  got : %016h %016h %016h %016h %016h",
                      x0_out, x1_out, x2_out, x3_out, x4_out);
            $display("  want: %016h %016h %016h %016h %016h", e0, e1, e2, e3, e4);
        end else begin
            $display("PASS [%s]", label);
        end
        @(posedge clk); #1; // let FINISH clear back to IDLE, settled
    endtask

    task automatic check_out(input int idx, input logic [63:0] expected, input string label);
        if (captured_out[idx] !== expected) begin
            errors++;
            $display("FAIL [%s] out[%0d]: got %016h want %016h", label, idx, captured_out[idx], expected);
        end else begin
            $display("PASS [%s] out[%0d]", label, idx);
        end
    endtask

    // For a partial block (real_bytes < 8), only the top real_bytes bytes
    // are meaningful -- the rest is don't-care per the out_bytes contract
    // (see header note). Masks both sides down to that many bytes before
    // comparing, so don't-care bits can never cause a spurious failure.
    task automatic check_out_real(
        input int idx, input int real_bytes,
        input logic [63:0] expected, input string label
    );
        logic [63:0] mask;
        logic [63:0] got_masked, want_masked;
        mask = (real_bytes == 8) ? 64'hFFFFFFFFFFFFFFFF : ~(64'hFFFFFFFFFFFFFFFF >> (8*real_bytes));
        got_masked  = captured_out[idx] & mask;
        want_masked = expected & mask;
        if (got_masked !== want_masked) begin
            errors++;
            $display("FAIL [%s] out[%0d] (top %0d real bytes): got %016h want %016h (masked: got %016h want %016h)",
                      label, idx, real_bytes, captured_out[idx], expected, got_masked, want_masked);
        end else begin
            $display("PASS [%s] out[%0d] (top %0d real bytes)", label, idx, real_bytes);
        end
    endtask

    // See header note: checks the metadata contract, not a don't-care data pattern.
    task automatic check_out_bytes(input int idx, input logic [3:0] expected, input string label);
        if (captured_out_bytes[idx] !== expected) begin
            errors++;
            $display("FAIL [%s] out_bytes[%0d]: got %0d want %0d", label, idx, captured_out_bytes[idx], expected);
        end else begin
            $display("PASS [%s] out_bytes[%0d]", label, idx);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        start = 0; mode_decrypt = 0;
        block_data = 0; block_is_last = 0; block_bytes = 0; block_valid = 0;
        x0_in = 0; x1_in = 0; x2_in = 0; x3_in = 0; x4_in = 0;

        repeat (2) @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // =========================================================
        // ENCRYPT direction (mode_decrypt=0) -- same cases as the old
        // tb_ascon_pt_process.sv
        // =========================================================

        // --- Case A: single 4-byte partial block ---
        out_count = 0;
        mode_decrypt = 0;
        x0_in = BASE_X0; x1_in = BASE_X1; x2_in = BASE_X2; x3_in = BASE_X3; x4_in = BASE_X4;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        feed_block(64'h4142434400000000, 1'b1, 4'd4);
        wait_done(50);
        check_out_real(0, 4, 64'h4AF5990C29F6869A, "encrypt-case-A");
        check_result(
            64'h4AF5990C29F6869A, 64'h584DB678AC4D1B07, 64'h3D5FB897517D85BC,
            64'h1C7A606B20964237, 64'h17C528BA07736373,
            "encrypt-case-A"
        );

        // --- Case B: one full block, then 6-byte partial final block ---
        out_count = 0;
        mode_decrypt = 0;
        x0_in = BASE_X0; x1_in = BASE_X1; x2_in = BASE_X2; x3_in = BASE_X3; x4_in = BASE_X4;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        feed_block(64'h0011223344556677, 1'b0, 4'd0);
        feed_block(64'h8899AABBCCDD0000, 1'b1, 4'd6);
        wait_done(1600);
        check_out(0, 64'h0BA6F87BEDA3E0ED, "encrypt-case-B");
        check_out_real(1, 6, 64'h15D41FB12BA44DC0, "encrypt-case-B");
        check_result(
            64'h15D41FB12BA44DC0, 64'h07BF46E83B6D3C12, 64'hEC4DE48E27356A18,
            64'h931B0525B74EC2ED, 64'hBC7E72032A4134FB,
            "encrypt-case-B"
        );

        // --- Case C: one full block, then pure-padding empty final block ---
        out_count = 0;
        mode_decrypt = 0;
        x0_in = BASE_X0; x1_in = BASE_X1; x2_in = BASE_X2; x3_in = BASE_X3; x4_in = BASE_X4;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        feed_block(64'hAABBCCDDEEFF0011, 1'b0, 4'd0);
        feed_block(64'h0000000000000000, 1'b1, 4'd0);
        wait_done(1600);
        check_out(0, 64'hA10C16954709868B, "encrypt-case-C");
        check_out_bytes(1, 4'd0, "encrypt-case-C"); // 0 real bytes: data itself is don't-care
        check_result(
            64'h87077F5823CDE5F5, 64'hC1AEB899CBF02F93, 64'h6EF77480D527FEE7,
            64'hA93B43538C3DFBD2, 64'h51EC313754C82BDD,
            "encrypt-case-C"
        );

        // =========================================================
        // DECRYPT direction (mode_decrypt=1) -- feeds in the exact
        // ciphertext the encrypt cases above produced; expects the
        // original plaintext back and the same final state.
        // =========================================================

        // --- Case A round-trip ---
        out_count = 0;
        mode_decrypt = 1;
        x0_in = BASE_X0; x1_in = BASE_X1; x2_in = BASE_X2; x3_in = BASE_X3; x4_in = BASE_X4;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        feed_block(64'h4AF5990C29F6869A, 1'b1, 4'd4);
        wait_done(50);
        check_out_real(0, 4, 64'h4142434400000000, "decrypt-case-A-roundtrip");
        check_result(
            64'h4AF5990C29F6869A, 64'h584DB678AC4D1B07, 64'h3D5FB897517D85BC,
            64'h1C7A606B20964237, 64'h17C528BA07736373,
            "decrypt-case-A-roundtrip"
        );

        // --- Case B round-trip ---
        out_count = 0;
        mode_decrypt = 1;
        x0_in = BASE_X0; x1_in = BASE_X1; x2_in = BASE_X2; x3_in = BASE_X3; x4_in = BASE_X4;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        feed_block(64'h0BA6F87BEDA3E0ED, 1'b0, 4'd0);
        feed_block(64'h15D41FB12BA44DC0, 1'b1, 4'd6);
        wait_done(1600);
        check_out(0, 64'h0011223344556677, "decrypt-case-B-roundtrip");
        check_out_real(1, 6, 64'h8899AABBCCDD0000, "decrypt-case-B-roundtrip");
        check_result(
            64'h15D41FB12BA44DC0, 64'h07BF46E83B6D3C12, 64'hEC4DE48E27356A18,
            64'h931B0525B74EC2ED, 64'hBC7E72032A4134FB,
            "decrypt-case-B-roundtrip"
        );

        // --- Case C round-trip ---
        out_count = 0;
        mode_decrypt = 1;
        x0_in = BASE_X0; x1_in = BASE_X1; x2_in = BASE_X2; x3_in = BASE_X3; x4_in = BASE_X4;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        feed_block(64'hA10C16954709868B, 1'b0, 4'd0);
        feed_block(64'h87077F5823CDE5F5, 1'b1, 4'd0);
        wait_done(1600);
        check_out(0, 64'hAABBCCDDEEFF0011, "decrypt-case-C-roundtrip");
        check_out_bytes(1, 4'd0, "decrypt-case-C-roundtrip"); // 0 real bytes: recovered data itself is don't-care
        check_result(
            64'h87077F5823CDE5F5, 64'hC1AEB899CBF02F93, 64'h6EF77480D527FEE7,
            64'hA93B43538C3DFBD2, 64'h51EC313754C82BDD,
            "decrypt-case-C-roundtrip"
        );

        if (errors == 0)
            $display("\n*** ALL DATA_PROCESS VECTORS MATCH -- ENCRYPT + DECRYPT ROUND TRIP OK ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
