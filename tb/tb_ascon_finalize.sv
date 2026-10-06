// tb_ascon_finalize.sv
// ---------------------------------------------------------------------------
// Testbench for ascon_finalize. Drives start with a state + key, waits for
// done, and checks both the final state and the 128-bit tag against golden
// vectors from model/ascon_ref.cpp's finalize() function.
// ---------------------------------------------------------------------------

module tb_ascon_finalize;

    logic clk, rst_n, start, busy, done;
    logic [63:0]  x0_in, x1_in, x2_in, x3_in, x4_in;
    logic [127:0] key;
    logic [63:0]  x0_out, x1_out, x2_out, x3_out, x4_out;
    logic [127:0] tag_out;

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

    ascon_finalize dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .x0_in(x0_in), .x1_in(x1_in), .x2_in(x2_in), .x3_in(x3_in), .x4_in(x4_in),
        .key(key),
        .perm_start(perm_start), .perm_num_rounds(perm_num_rounds),
        .perm_x0_in(perm_x0_in), .perm_x1_in(perm_x1_in), .perm_x2_in(perm_x2_in),
        .perm_x3_in(perm_x3_in), .perm_x4_in(perm_x4_in),
        .perm_busy(perm_busy), .perm_done(perm_done),
        .perm_x0_out(perm_x0_out), .perm_x1_out(perm_x1_out), .perm_x2_out(perm_x2_out),
        .perm_x3_out(perm_x3_out), .perm_x4_out(perm_x4_out),
        .busy(busy), .done(done),
        .x0_out(x0_out), .x1_out(x1_out), .x2_out(x2_out), .x3_out(x3_out), .x4_out(x4_out),
        .tag_out(tag_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic wait_done(int max_cycles);
        for (int cyc = 0; cyc < max_cycles && !done; cyc++) begin
            @(posedge clk); #1;
        end
    endtask

    task automatic check_result(
        input logic [63:0]  e0, e1, e2, e3, e4,
        input logic [127:0] etag,
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
        end else if (tag_out !== etag) begin
            errors++;
            $display("FAIL [%s] (tag): got %032h want %032h", label, tag_out, etag);
        end else begin
            $display("PASS [%s]", label);
        end
        @(posedge clk); #1; // let FINISH clear back to IDLE, settled
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        start = 0;
        x0_in = 0; x1_in = 0; x2_in = 0; x3_in = 0; x4_in = 0; key = 0;

        repeat (2) @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // --- Case 1: chained off pt_process Case C (same key as init) ---
        x0_in = 64'h87077F5823CDE5F5; x1_in = 64'hC1AEB899CBF02F93;
        x2_in = 64'h6EF77480D527FEE7; x3_in = 64'hA93B43538C3DFBD2;
        x4_in = 64'h51EC313754C82BDD;
        key   = {64'h0001020304050607, 64'h08090A0B0C0D0E0F};
        start = 1;
        @(posedge clk); #1;
        start = 0;
        wait_done(1600);
        check_result(
            64'hE0135FDE5FE4A137, 64'hBB522F16757A0013, 64'hF4B4191789593995,
            64'h700A83A53160D7AE, 64'h1474D4B69F49D92C,
            {64'h700A83A53160D7AE, 64'h1474D4B69F49D92C},
            "case-1-chained-off-pt"
        );

        // --- Case 2: all-zero state, all-zero key ---
        x0_in = 0; x1_in = 0; x2_in = 0; x3_in = 0; x4_in = 0;
        key = 0;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        wait_done(1600);
        check_result(
            64'h78EA7AE5CFEBB108, 64'h9B9BFB8513B560F7, 64'h6937F83E03D11A50,
            64'h3FE53F36F2C1178C, 64'h045D648E4DEF12C9,
            {64'h3FE53F36F2C1178C, 64'h045D648E4DEF12C9},
            "case-2-all-zero"
        );

        // --- Case 3: all-ones state, all-ones key ---
        x0_in = 64'hFFFFFFFFFFFFFFFF; x1_in = 64'hFFFFFFFFFFFFFFFF;
        x2_in = 64'hFFFFFFFFFFFFFFFF; x3_in = 64'hFFFFFFFFFFFFFFFF;
        x4_in = 64'hFFFFFFFFFFFFFFFF;
        key   = {64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF};
        start = 1;
        @(posedge clk); #1;
        start = 0;
        wait_done(1600);
        check_result(
            64'h009462EA815456BA, 64'hE994557A5A1D1765, 64'h944AAD0F97E92CCC,
            64'hA34D6CE14ED7C6F9, 64'hBFF11716B126F87C,
            {64'hA34D6CE14ED7C6F9, 64'hBFF11716B126F87C},
            "case-3-all-ones"
        );

        // --- Case 4: mixed pattern state, different key than reached it ---
        x0_in = 64'h0BA6F87BEDA3E0ED; x1_in = 64'h07BF46E83B6D3C12;
        x2_in = 64'hEC4DE48E27356A18; x3_in = 64'h931B0525B74EC2ED;
        x4_in = 64'hBC7E72032A4134FB;
        key   = {64'hDEADBEEFCAFEBABE, 64'h1122334455667788};
        start = 1;
        @(posedge clk); #1;
        start = 0;
        wait_done(1600);
        check_result(
            64'h836C7D340CA59018, 64'h96F1CE66EA1CC306, 64'h2686F3722D9FB2FC,
            64'h7F9EFAC391FE0A25, 64'hFE28879EC7E82152,
            {64'h7F9EFAC391FE0A25, 64'hFE28879EC7E82152},
            "case-4-mixed-pattern"
        );

        if (errors == 0)
            $display("\n*** ALL FINALIZATION VECTORS MATCH THE C++ REFERENCE MODEL ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
