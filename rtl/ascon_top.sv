// ascon_top.sv
// ---------------------------------------------------------------------------
// Ascon-128 top-level datapath. Wires the four stage modules together behind
// a single external handshake:
//
//   ascon_init -> ascon_ad_absorb -> ascon_data_process -> ascon_finalize
//
// One mode bit (mode_decrypt) is passed straight through to ascon_data_process,
// which handles both directions (encrypt: plaintext in, ciphertext out;
// decrypt: ciphertext in, plaintext out) in one merged module -- see
// ascon_data_process.sv for the derivation of why encrypt/decrypt share one
// per-byte formula. In decrypt mode the computed tag is also compared
// against a caller-supplied expected tag, and tag_match reports whether
// they agree.
//
// SHARED PERMUTATION: unlike the earlier per-stage design (where each of
// init/ad_absorb/pt_process/ct_process/finalize owned its own
// ascon_permutation instance), this version instantiates exactly ONE
// ascon_permutation and muxes its request/response interface to whichever
// stage is currently active, based on the top-level FSM's own state. This
// is safe because the top-level FSM already guarantees the four stages run
// strictly sequentially, never concurrently -- so at most one stage's own
// perm_start is ever meaningfully asserted at a time; the mux just makes
// that routing explicit rather than relying on inactive stages happening
// to hold their outputs at 0. See DESIGN_LOG.md for the area rationale
// (this removed 3 of the original 4 redundant permutation copies).
//
// STATE CHAINING: a single set of top-level registers (state_x0..state_x4)
// holds "the state as of the end of the last completed stage". Each stage
// module's x*_in ports are wired directly to these registers; state_x* is
// overwritten with that stage's x*_out only once its `done` pulses.
//
// BLOCK ROUTING: AD blocks and PT/CT data blocks share one external data
// bus (block_data/block_is_last/block_bytes/block_valid) but have SEPARATE
// request lines (ad_block_req, data_block_req) -- only one is ever high at
// a time, so the caller always knows unambiguously which stream is being
// asked for.
//
// PROTOCOL: hold key, nonce, has_ad, mode_decrypt, and (in decrypt mode)
// tag_expected stable from the cycle `start` is asserted until `done`
// pulses. Assert `start` for one cycle to begin; respond to
// ad_block_req/data_block_req with the block bus; consume out_data/out_bytes
// whenever out_valid pulses; `done` pulses once tag_out (and, in decrypt
// mode, tag_match) are valid.
// ---------------------------------------------------------------------------

module ascon_top (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic         mode_decrypt,  // 0 = encrypt (PT in, CT out), 1 = decrypt (CT in, PT out)
    input  logic [127:0] key,
    input  logic [127:0] nonce,
    input  logic         has_ad,

    // Shared block bus -- feeds whichever of ad_block_req / data_block_req
    // is currently asserted.
    output logic         ad_block_req,
    output logic         data_block_req,
    input  logic [63:0]  block_data,
    input  logic         block_is_last,
    input  logic [3:0]   block_bytes,   // 0..7, valid only when block_is_last
    input  logic         block_valid,

    // Output stream: ciphertext (encrypt) or recovered plaintext (decrypt)
    output logic         out_valid,
    output logic [63:0]  out_data,
    output logic [3:0]   out_bytes,     // mirrors block_bytes; 8 when not last

    output logic [127:0] tag_out,       // computed tag, valid when done
    input  logic [127:0] tag_expected,  // decrypt mode only: tag to verify against
    output logic         tag_match,     // decrypt mode only: valid when done

    output logic         busy,
    output logic         done
);

    typedef enum logic [3:0] {
        S_IDLE, S_INIT_KICK, S_INIT_WAIT, S_AD_KICK, S_AD_WAIT,
        S_DATA_KICK, S_DATA_WAIT, S_FINAL_KICK, S_FINAL_WAIT, S_DONE
    } state_t;
    state_t state, next_state;

    // ---- Persistent state chain: "state as of end of last completed stage" ----
    logic [63:0] state_x0, state_x1, state_x2, state_x3, state_x4;

    // ==== Shared permutation instance ====
    logic        perm_start, perm_busy, perm_done;
    logic [3:0]  perm_num_rounds;
    logic [63:0] perm_x0_in, perm_x1_in, perm_x2_in, perm_x3_in, perm_x4_in;
    logic [63:0] perm_x0_out, perm_x1_out, perm_x2_out, perm_x3_out, perm_x4_out;

    ascon_permutation perm_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (perm_start),
        .num_rounds (perm_num_rounds),
        .x0_in      (perm_x0_in), .x1_in (perm_x1_in), .x2_in (perm_x2_in),
        .x3_in      (perm_x3_in), .x4_in (perm_x4_in),
        .busy       (perm_busy),
        .done       (perm_done),
        .x0_out     (perm_x0_out), .x1_out (perm_x1_out), .x2_out (perm_x2_out),
        .x3_out     (perm_x3_out), .x4_out (perm_x4_out)
    );

    // ==== ascon_init ====
    logic        init_start, init_busy, init_done;
    logic [63:0] init_x0, init_x1, init_x2, init_x3, init_x4;
    logic        init_perm_start;
    logic [3:0]  init_perm_num_rounds;
    logic [63:0] init_perm_x0_in, init_perm_x1_in, init_perm_x2_in, init_perm_x3_in, init_perm_x4_in;
    ascon_init init_inst (
        .clk(clk), .rst_n(rst_n), .start(init_start),
        .key(key), .nonce(nonce),
        .perm_start(init_perm_start), .perm_num_rounds(init_perm_num_rounds),
        .perm_x0_in(init_perm_x0_in), .perm_x1_in(init_perm_x1_in), .perm_x2_in(init_perm_x2_in),
        .perm_x3_in(init_perm_x3_in), .perm_x4_in(init_perm_x4_in),
        .perm_busy(perm_busy), .perm_done(perm_done),
        .perm_x0_out(perm_x0_out), .perm_x1_out(perm_x1_out), .perm_x2_out(perm_x2_out),
        .perm_x3_out(perm_x3_out), .perm_x4_out(perm_x4_out),
        .busy(init_busy), .done(init_done),
        .x0_out(init_x0), .x1_out(init_x1), .x2_out(init_x2), .x3_out(init_x3), .x4_out(init_x4)
    );

    // ==== ascon_ad_absorb ====
    logic        ad_start, ad_busy, ad_done;
    logic [63:0] ad_x0, ad_x1, ad_x2, ad_x3, ad_x4;
    logic        ad_perm_start;
    logic [3:0]  ad_perm_num_rounds;
    logic [63:0] ad_perm_x0_in, ad_perm_x1_in, ad_perm_x2_in, ad_perm_x3_in, ad_perm_x4_in;
    ascon_ad_absorb ad_inst (
        .clk(clk), .rst_n(rst_n), .start(ad_start), .has_ad(has_ad),
        .x0_in(state_x0), .x1_in(state_x1), .x2_in(state_x2), .x3_in(state_x3), .x4_in(state_x4),
        .block_req(ad_block_req),
        .block_data(block_data), .block_is_last(block_is_last),
        .block_bytes(block_bytes), .block_valid(block_valid),
        .perm_start(ad_perm_start), .perm_num_rounds(ad_perm_num_rounds),
        .perm_x0_in(ad_perm_x0_in), .perm_x1_in(ad_perm_x1_in), .perm_x2_in(ad_perm_x2_in),
        .perm_x3_in(ad_perm_x3_in), .perm_x4_in(ad_perm_x4_in),
        .perm_busy(perm_busy), .perm_done(perm_done),
        .perm_x0_out(perm_x0_out), .perm_x1_out(perm_x1_out), .perm_x2_out(perm_x2_out),
        .perm_x3_out(perm_x3_out), .perm_x4_out(perm_x4_out),
        .busy(ad_busy), .done(ad_done),
        .x0_out(ad_x0), .x1_out(ad_x1), .x2_out(ad_x2), .x3_out(ad_x3), .x4_out(ad_x4)
    );

    // ==== ascon_data_process (merged encrypt/decrypt) ====
    logic        data_start, data_busy, data_done, data_block_req_i;
    logic        data_out_valid;
    logic [63:0] data_out_data;
    logic [3:0]  data_out_bytes;
    logic [63:0] data_x0, data_x1, data_x2, data_x3, data_x4;
    logic        data_perm_start;
    logic [3:0]  data_perm_num_rounds;
    logic [63:0] data_perm_x0_in, data_perm_x1_in, data_perm_x2_in, data_perm_x3_in, data_perm_x4_in;
    ascon_data_process data_inst (
        .clk(clk), .rst_n(rst_n), .start(data_start), .mode_decrypt(mode_decrypt),
        .x0_in(state_x0), .x1_in(state_x1), .x2_in(state_x2), .x3_in(state_x3), .x4_in(state_x4),
        .block_req(data_block_req_i),
        .block_data(block_data), .block_is_last(block_is_last),
        .block_bytes(block_bytes), .block_valid(block_valid),
        .out_valid(data_out_valid), .out_data(data_out_data), .out_bytes(data_out_bytes),
        .perm_start(data_perm_start), .perm_num_rounds(data_perm_num_rounds),
        .perm_x0_in(data_perm_x0_in), .perm_x1_in(data_perm_x1_in), .perm_x2_in(data_perm_x2_in),
        .perm_x3_in(data_perm_x3_in), .perm_x4_in(data_perm_x4_in),
        .perm_busy(perm_busy), .perm_done(perm_done),
        .perm_x0_out(perm_x0_out), .perm_x1_out(perm_x1_out), .perm_x2_out(perm_x2_out),
        .perm_x3_out(perm_x3_out), .perm_x4_out(perm_x4_out),
        .busy(data_busy), .done(data_done),
        .x0_out(data_x0), .x1_out(data_x1), .x2_out(data_x2), .x3_out(data_x3), .x4_out(data_x4)
    );
    assign data_block_req = data_block_req_i;
    assign out_valid = data_out_valid;
    assign out_data  = data_out_data;
    assign out_bytes = data_out_bytes;

    // ==== ascon_finalize ====
    logic         final_start, final_busy, final_done;
    logic [63:0]  final_x0, final_x1, final_x2, final_x3, final_x4;
    logic [127:0] final_tag;
    logic         final_perm_start;
    logic [3:0]   final_perm_num_rounds;
    logic [63:0]  final_perm_x0_in, final_perm_x1_in, final_perm_x2_in, final_perm_x3_in, final_perm_x4_in;
    ascon_finalize final_inst (
        .clk(clk), .rst_n(rst_n), .start(final_start),
        .x0_in(state_x0), .x1_in(state_x1), .x2_in(state_x2), .x3_in(state_x3), .x4_in(state_x4),
        .key(key),
        .perm_start(final_perm_start), .perm_num_rounds(final_perm_num_rounds),
        .perm_x0_in(final_perm_x0_in), .perm_x1_in(final_perm_x1_in), .perm_x2_in(final_perm_x2_in),
        .perm_x3_in(final_perm_x3_in), .perm_x4_in(final_perm_x4_in),
        .perm_busy(perm_busy), .perm_done(perm_done),
        .perm_x0_out(perm_x0_out), .perm_x1_out(perm_x1_out), .perm_x2_out(perm_x2_out),
        .perm_x3_out(perm_x3_out), .perm_x4_out(perm_x4_out),
        .busy(final_busy), .done(final_done),
        .x0_out(final_x0), .x1_out(final_x1), .x2_out(final_x2), .x3_out(final_x3), .x4_out(final_x4),
        .tag_out(final_tag)
    );

    // ---- Shared permutation mux: route to whichever stage is active ----
    // Only one of these four sub-modules is ever mid-operation at a time
    // (the top-level FSM below runs them strictly sequentially), so this
    // mux -- keyed off the top-level's OWN state, not each sub-module's
    // internal state -- unambiguously picks the right one.
    always_comb begin
        case (state)
            S_INIT_KICK, S_INIT_WAIT: begin
                perm_start      = init_perm_start;
                perm_num_rounds = init_perm_num_rounds;
                perm_x0_in = init_perm_x0_in; perm_x1_in = init_perm_x1_in;
                perm_x2_in = init_perm_x2_in; perm_x3_in = init_perm_x3_in;
                perm_x4_in = init_perm_x4_in;
            end
            S_AD_KICK, S_AD_WAIT: begin
                perm_start      = ad_perm_start;
                perm_num_rounds = ad_perm_num_rounds;
                perm_x0_in = ad_perm_x0_in; perm_x1_in = ad_perm_x1_in;
                perm_x2_in = ad_perm_x2_in; perm_x3_in = ad_perm_x3_in;
                perm_x4_in = ad_perm_x4_in;
            end
            S_DATA_KICK, S_DATA_WAIT: begin
                perm_start      = data_perm_start;
                perm_num_rounds = data_perm_num_rounds;
                perm_x0_in = data_perm_x0_in; perm_x1_in = data_perm_x1_in;
                perm_x2_in = data_perm_x2_in; perm_x3_in = data_perm_x3_in;
                perm_x4_in = data_perm_x4_in;
            end
            S_FINAL_KICK, S_FINAL_WAIT: begin
                perm_start      = final_perm_start;
                perm_num_rounds = final_perm_num_rounds;
                perm_x0_in = final_perm_x0_in; perm_x1_in = final_perm_x1_in;
                perm_x2_in = final_perm_x2_in; perm_x3_in = final_perm_x3_in;
                perm_x4_in = final_perm_x4_in;
            end
            default: begin
                perm_start      = 1'b0;
                perm_num_rounds = 4'd0;
                perm_x0_in = 64'd0; perm_x1_in = 64'd0; perm_x2_in = 64'd0;
                perm_x3_in = 64'd0; perm_x4_in = 64'd0;
            end
        endcase
    end

    // ---- State register ----
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ---- Next-state logic ----
    always_comb begin
        next_state  = state;
        init_start  = 1'b0;
        ad_start    = 1'b0;
        data_start  = 1'b0;
        final_start = 1'b0;

        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_INIT_KICK;
                else
                    next_state = S_IDLE;
            end

            S_INIT_KICK: begin
                init_start = 1'b1;
                next_state = S_INIT_WAIT;
            end

            S_INIT_WAIT: begin
                if (init_done)
                    next_state = S_AD_KICK;
                else
                    next_state = S_INIT_WAIT;
            end

            S_AD_KICK: begin
                ad_start = 1'b1;
                next_state = S_AD_WAIT;
            end

            S_AD_WAIT: begin
                if (ad_done)
                    next_state = S_DATA_KICK;
                else
                    next_state = S_AD_WAIT;
            end

            S_DATA_KICK: begin
                data_start = 1'b1;
                next_state = S_DATA_WAIT;
            end

            S_DATA_WAIT: begin
                if (data_done)
                    next_state = S_FINAL_KICK;
                else
                    next_state = S_DATA_WAIT;
            end

            S_FINAL_KICK: begin
                final_start = 1'b1;
                next_state = S_FINAL_WAIT;
            end

            S_FINAL_WAIT: begin
                if (final_done)
                    next_state = S_DONE;
                else
                    next_state = S_FINAL_WAIT;
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ---- Datapath: latch state_x* and tag/match at each stage boundary ----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_x0 <= 64'd0; state_x1 <= 64'd0; state_x2 <= 64'd0;
            state_x3 <= 64'd0; state_x4 <= 64'd0;
            tag_out   <= 128'd0;
            tag_match <= 1'b0;
        end else begin
            case (state)
                S_INIT_WAIT: begin
                    if (init_done) begin
                        state_x0 <= init_x0; state_x1 <= init_x1; state_x2 <= init_x2;
                        state_x3 <= init_x3; state_x4 <= init_x4;
                    end
                end

                S_AD_WAIT: begin
                    if (ad_done) begin
                        state_x0 <= ad_x0; state_x1 <= ad_x1; state_x2 <= ad_x2;
                        state_x3 <= ad_x3; state_x4 <= ad_x4;
                    end
                end

                S_DATA_WAIT: begin
                    if (data_done) begin
                        state_x0 <= data_x0; state_x1 <= data_x1; state_x2 <= data_x2;
                        state_x3 <= data_x3; state_x4 <= data_x4;
                    end
                end

                S_FINAL_WAIT: begin
                    if (final_done) begin
                        tag_out   <= final_tag;
                        tag_match <= (final_tag == tag_expected);
                    end
                end

                default: ; // IDLE / *_KICK / DONE: no action
            endcase
        end
    end

    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign done = (state == S_DONE);

endmodule
