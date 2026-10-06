// tb_ascon_top.sv
// ---------------------------------------------------------------------------
// Testbench for ascon_top. Runs a full encrypt (init -> AD -> PT -> tag),
// then a full decrypt of that exact ciphertext (init -> AD -> CT -> tag
// compare) with the same key/nonce/AD, and checks the recovered plaintext
// and the tag all match. A third run repeats the decrypt with a corrupted
// expected tag to confirm tag_match correctly reports a mismatch.
//
// Every intermediate value here is NOT freshly invented -- it's the same
// key/nonce/AD/plaintext already independently verified end-to-end across
// tb_ascon_init ("placeholder-key-nonce-1"), tb_ascon_ad_absorb
// ("single-partial-block-3bytes"), tb_ascon_pt_process ("case-C"), and
// tb_ascon_finalize ("case-1-chained-off-pt"). This testbench is checking
// WIRING correctness (that ascon_top drives the sub-modules in the right
// order with the right handshakes), not the underlying arithmetic again --
// that's already covered stage by stage.
// ---------------------------------------------------------------------------

module tb_ascon_top;

    logic clk, rst_n, start, mode_decrypt, has_ad;
    logic [127:0] key, nonce, tag_expected;
    logic ad_block_req, data_block_req;
    logic [63:0] block_data;
    logic block_is_last;
    logic [3:0] block_bytes;
    logic block_valid;
    logic out_valid;
    logic [63:0] out_data;
    logic [3:0] out_bytes;
    logic [127:0] tag_out;
    logic tag_match, busy, done;

    int errors;

    ascon_top dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .mode_decrypt(mode_decrypt), .key(key), .nonce(nonce), .has_ad(has_ad),
        .ad_block_req(ad_block_req), .data_block_req(data_block_req),
        .block_data(block_data), .block_is_last(block_is_last),
        .block_bytes(block_bytes), .block_valid(block_valid),
        .out_valid(out_valid), .out_data(out_data), .out_bytes(out_bytes),
        .tag_out(tag_out), .tag_expected(tag_expected), .tag_match(tag_match),
        .busy(busy), .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Same key/nonce as tb_ascon_init's "placeholder-key-nonce-1" case.
    localparam logic [127:0] TEST_KEY   = {64'h0001020304050607, 64'h08090A0B0C0D0E0F};
    localparam logic [127:0] TEST_NONCE = {64'h0102030405060708, 64'h090A0B0C0D0E0F00};

    // Captured output stream (ciphertext on encrypt runs, plaintext on decrypt runs)
    logic [63:0] captured_out [0:3];
    logic [3:0]  captured_out_bytes [0:3];
    int          out_count;

    // Feed one block to whichever request line is currently active
    // (ad_block_req during the AD phase, data_block_req during PT/CT).
    task automatic feed_block(
        input logic [63:0] data,
        input logic        is_last,
        input logic [3:0]  bytes
    );
        int wait_cyc;
        wait_cyc = 0;
        while (!(ad_block_req || data_block_req) && wait_cyc < 2000) begin
            @(posedge clk); #1;
            wait_cyc++;
        end
        if (!(ad_block_req || data_block_req))
            $display("WARNING: neither block_req asserted, timed out waiting");

        block_data    = data;
        block_is_last = is_last;
        block_bytes   = bytes;
        block_valid   = 1;
        @(posedge clk); #1;
        block_valid   = 0;

        // out_valid pulses one cycle later IF this was a data-stage block
        // (AD blocks produce no out_valid pulse at all).
        wait_cyc = 0;
        while (!out_valid && wait_cyc < 10) begin
            @(posedge clk); #1;
            wait_cyc++;
        end
        if (out_valid) begin
            captured_out[out_count]       = out_data;
            captured_out_bytes[out_count] = out_bytes;
            out_count++;
        end
    endtask

    task automatic wait_done(int max_cycles);
        for (int cyc = 0; cyc < max_cycles && !done; cyc++) begin
            @(posedge clk); #1;
        end
    endtask

    task automatic check_out(input int idx, input logic [63:0] expected, input string label);
        if (captured_out[idx] !== expected) begin
            errors++;
            $display("FAIL [%s] out[%0d]: got %016h want %016h", label, idx, captured_out[idx], expected);
        end else begin
            $display("PASS [%s] out[%0d]", label, idx);
        end
    endtask

    // Data at a byte position beyond out_bytes is explicitly don't-care per
    // both ascon_pt_process's and ascon_ct_process's documented contract --
    // check the metadata (how many bytes are real) rather than the garbage
    // pattern in the unused bits, which differed even between the two
    // original (pre-merge) modules without either being wrong.
    task automatic check_out_bytes(input int idx, input logic [3:0] expected, input string label);
        if (captured_out_bytes[idx] !== expected) begin
            errors++;
            $display("FAIL [%s] out_bytes[%0d]: got %0d want %0d", label, idx, captured_out_bytes[idx], expected);
        end else begin
            $display("PASS [%s] out_bytes[%0d]", label, idx);
        end
    endtask

    task automatic check_tag(input logic [127:0] expected, input string label);
        if (!done) begin
            errors++;
            $display("FAIL [%s]: never asserted done", label);
        end else if (tag_out !== expected) begin
            errors++;
            $display("FAIL [%s] tag: got %032h want %032h", label, tag_out, expected);
        end else begin
            $display("PASS [%s] tag", label);
        end
    endtask

    task automatic check_match(input logic expected, input string label);
        if (tag_match !== expected) begin
            errors++;
            $display("FAIL [%s] tag_match: got %0b want %0b", label, tag_match, expected);
        end else begin
            $display("PASS [%s] tag_match=%0b", label, tag_match);
        end
    endtask

    // Golden expected tag from this key/nonce/AD/PT combo (matches
    // tb_ascon_finalize's "case-1-chained-off-pt" exactly).
    localparam logic [127:0] EXPECTED_TAG =
        {64'h700A83A53160D7AE, 64'h1474D4B69F49D92C};

    initial begin
        errors = 0;
        rst_n = 0;
        start = 0; mode_decrypt = 0; has_ad = 0;
        key = 0; nonce = 0; tag_expected = 0;
        block_data = 0; block_is_last = 0; block_bytes = 0; block_valid = 0;

        repeat (2) @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // =========================================================
        // Run 1: ENCRYPT -- init -> AD (3-byte block) -> PT (Case C)
        // =========================================================
        out_count = 0;
        key = TEST_KEY; nonce = TEST_NONCE; has_ad = 1; mode_decrypt = 0;
        start = 1;
        @(posedge clk); #1;
        start = 0;

        // AD: single partial block, 3 real bytes
        feed_block(64'h0102030000000000, 1'b1, 4'd3);
        // PT Case C: one full block, then a pure-padding empty final block
        feed_block(64'hAABBCCDDEEFF0011, 1'b0, 4'd0);
        feed_block(64'h0000000000000000, 1'b1, 4'd0);

        wait_done(3000);
        check_out(0, 64'hA10C16954709868B, "encrypt");
        check_out(1, 64'h87077F5823CDE5F5, "encrypt");
        check_tag(EXPECTED_TAG, "encrypt");
        @(posedge clk); #1; // let S_DONE clear back to IDLE

        // =========================================================
        // Run 2: DECRYPT the exact ciphertext just produced -- expect
        // the original plaintext back and tag_match = 1
        // =========================================================
        out_count = 0;
        key = TEST_KEY; nonce = TEST_NONCE; has_ad = 1; mode_decrypt = 1;
        tag_expected = EXPECTED_TAG;
        start = 1;
        @(posedge clk); #1;
        start = 0;

        feed_block(64'h0102030000000000, 1'b1, 4'd3);       // same AD
        feed_block(64'hA10C16954709868B, 1'b0, 4'd0);        // ct[0] just captured
        feed_block(64'h87077F5823CDE5F5, 1'b1, 4'd0);        // ct[1], 0 real bytes

        wait_done(3000);
        check_out(0, 64'hAABBCCDDEEFF0011, "decrypt-match");  // recovered plaintext
        check_out_bytes(1, 4'd0, "decrypt-match"); // block_bytes=0: all-padding block, no real recovered bytes -- data itself is don't-care
        check_tag(EXPECTED_TAG, "decrypt-match");
        check_match(1'b1, "decrypt-match");
        @(posedge clk); #1;

        // =========================================================
        // Run 3: DECRYPT again but with a deliberately WRONG expected
        // tag (one bit flipped) -- computed tag should be unchanged,
        // tag_match should report 0
        // =========================================================
        out_count = 0;
        key = TEST_KEY; nonce = TEST_NONCE; has_ad = 1; mode_decrypt = 1;
        tag_expected = EXPECTED_TAG ^ 128'd1; // flip the LSB
        start = 1;
        @(posedge clk); #1;
        start = 0;

        feed_block(64'h0102030000000000, 1'b1, 4'd3);
        feed_block(64'hA10C16954709868B, 1'b0, 4'd0);
        feed_block(64'h87077F5823CDE5F5, 1'b1, 4'd0);

        wait_done(3000);
        check_tag(EXPECTED_TAG, "decrypt-mismatch"); // computed tag itself still correct
        check_match(1'b0, "decrypt-mismatch");        // but doesn't match the (wrong) expected tag

        if (errors == 0)
            $display("\n*** ALL TOP-LEVEL DATAPATH VECTORS MATCH -- ENCRYPT/DECRYPT WIRING OK ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
