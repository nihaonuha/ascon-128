// ascon_data_process.sv
// ---------------------------------------------------------------------------
// Merged Ascon-128 plaintext/ciphertext processing. Replaces the separate
// ascon_pt_process and ascon_ct_process modules -- encrypt and decrypt turn
// out to share one per-byte formula, so mode_decrypt selects between them
// rather than duplicating the whole FSM+datapath in two modules.
//
// UNIFIED PER-BYTE FORMULA (derived by comparing the two original modules):
// For each byte position j of a block, define:
//   effective_input[j] = block_data byte j          if this is a "real" byte
//                         (i.e. !block_is_last, OR j < block_bytes)
//                       = 8'h80                      if block_is_last && j == block_bytes
//                                                     (the pad-marker byte)
//                       = 8'h00                      if block_is_last && j > block_bytes
//                                                     (zero-fill beyond padding)
// Then, for EVERY byte, regardless of mode:
//   emit_byte[j]    = cur_x0_byte[j] ^ effective_input[j]   -- the same XOR
//                      works in both directions (PT^X0=CT, and CT^X0=PT)
//   next_x0_byte[j] = (mode_decrypt && is_real_byte[j]) ? effective_input[j]
//                                                        : emit_byte[j]
// Intuition for the next_x0 rule: on a real byte, decrypt must adopt the
// RECEIVED ciphertext byte as the new state (that's what encrypt's side
// actually produced); on a non-real byte (padding), there's nothing
// received, so both directions independently reconstruct the same value
// from cur_x0 itself, and encrypt always adopts its own computed result.
//
// No permutation runs after the final block (state is used as-is for
// finalization). This stage is never skipped, even for empty data.
//
// PERMUTATION INTERFACE: this module does NOT instantiate its own
// ascon_permutation -- unlike earlier per-stage modules, it exposes a
// permutation-REQUEST interface (perm_start/perm_num_rounds/perm_x*_in,
// perm_busy/perm_done/perm_x*_out) so the top level can wire ONE shared
// permutation instance to whichever stage is currently active. See
// DESIGN_LOG.md for why: each stage previously owned its own permutation
// (a full round + serial S-box + hold registers each), and since the
// top-level FSM only ever runs one stage at a time, that was 4-5x more
// permutation hardware than necessary.
// ---------------------------------------------------------------------------

module ascon_data_process (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        mode_decrypt, // 0 = encrypt (PT in, CT out), 1 = decrypt (CT in, PT out)
    input  logic [63:0] x0_in,
    input  logic [63:0] x1_in,
    input  logic [63:0] x2_in,
    input  logic [63:0] x3_in,
    input  logic [63:0] x4_in,

    output logic        block_req,
    input  logic [63:0] block_data,
    input  logic        block_is_last,
    input  logic [3:0]  block_bytes,   // 0..7, valid only when block_is_last
    input  logic        block_valid,

    output logic        out_valid,
    output logic [63:0] out_data,      // ciphertext (encrypt) or plaintext (decrypt)
    output logic [3:0]  out_bytes,     // mirrors block_bytes; 8 when not last

    // ---- Shared permutation request interface (see header note) ----
    output logic        perm_start,
    output logic [3:0]  perm_num_rounds,
    output logic [63:0] perm_x0_in,
    output logic [63:0] perm_x1_in,
    output logic [63:0] perm_x2_in,
    output logic [63:0] perm_x3_in,
    output logic [63:0] perm_x4_in,
    input  logic        perm_busy,
    input  logic        perm_done,
    input  logic [63:0] perm_x0_out,
    input  logic [63:0] perm_x1_out,
    input  logic [63:0] perm_x2_out,
    input  logic [63:0] perm_x3_out,
    input  logic [63:0] perm_x4_out,

    output logic        busy,
    output logic        done,
    output logic [63:0] x0_out,
    output logic [63:0] x1_out,
    output logic [63:0] x2_out,
    output logic [63:0] x3_out,
    output logic [63:0] x4_out
);

    typedef enum logic [2:0] { IDLE, WAIT_BLOCK, EMIT_OUT, PERM_KICK, PERM_WAIT, FINISH } state_t;
    state_t state, next_state;

    logic [63:0] cur_x0, cur_x1, cur_x2, cur_x3, cur_x4;
    logic        last_seen;

    // ---- Unified per-byte combinational logic (see header derivation) ----
    logic [63:0] emit_result;   // ciphertext (encrypt) or plaintext (decrypt), all 8 bytes
    logic [63:0] next_x0_val;   // what cur_x0 becomes after this block
    always_comb begin
        emit_result = 64'd0;
        next_x0_val = 64'd0;
        for (int j = 0; j < 8; j++) begin
            logic [7:0] eff_input;
            logic       is_real;
            logic [7:0] cur_byte, emit_byte;

            cur_byte = cur_x0[63 - 8*j -: 8];

            if (!block_is_last || (j < block_bytes)) begin
                eff_input = block_data[63 - 8*j -: 8];
                is_real   = 1'b1;
            end else if (j == block_bytes) begin
                eff_input = 8'h80;
                is_real   = 1'b0;
            end else begin
                eff_input = 8'h00;
                is_real   = 1'b0;
            end

            emit_byte = cur_byte ^ eff_input;
            emit_result[63 - 8*j -: 8] = emit_byte;

            if (mode_decrypt && is_real)
                next_x0_val[63 - 8*j -: 8] = eff_input;
            else
                next_x0_val[63 - 8*j -: 8] = emit_byte;
        end
    end

    // ---- State register ----
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ---- Next-state logic ----
    always_comb begin
        next_state  = state;
        perm_start  = 1'b0;
        block_req   = 1'b0;
        out_valid   = 1'b0;

        case (state)
            IDLE: begin
                if (start)
                    next_state = WAIT_BLOCK;
                else
                    next_state = IDLE;
            end

            WAIT_BLOCK: begin
                block_req = 1'b1;
                if (block_valid)
                    next_state = EMIT_OUT;
                else
                    next_state = WAIT_BLOCK;
            end

            EMIT_OUT: begin
                // out_data/cur_x already latched correctly from the block
                // just accepted (same "compute at the edge" discipline as
                // every earlier stage -- see DESIGN_LOG.md entry 8).
                out_valid = 1'b1;
                if (last_seen)
                    next_state = FINISH; // no permutation after the last block
                else
                    next_state = PERM_KICK;
            end

            PERM_KICK: begin
                perm_start = 1'b1;
                next_state = PERM_WAIT;
            end

            PERM_WAIT: begin
                if (perm_done)
                    next_state = WAIT_BLOCK;
                else
                    next_state = PERM_WAIT;
            end

            FINISH: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // ---- Datapath ----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cur_x0 <= 64'd0; cur_x1 <= 64'd0; cur_x2 <= 64'd0;
            cur_x3 <= 64'd0; cur_x4 <= 64'd0;
            last_seen <= 1'b0;
            out_data <= 64'd0;
            out_bytes <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        cur_x0 <= x0_in;
                        cur_x1 <= x1_in;
                        cur_x2 <= x2_in;
                        cur_x3 <= x3_in;
                        cur_x4 <= x4_in;
                    end
                end

                WAIT_BLOCK: begin
                    if (block_valid) begin
                        last_seen <= block_is_last;
                        cur_x0    <= next_x0_val;
                        out_data  <= emit_result;
                        out_bytes <= block_is_last ? block_bytes : 4'd8;
                    end
                end

                PERM_WAIT: begin
                    if (perm_done) begin
                        cur_x0 <= perm_x0_out;
                        cur_x1 <= perm_x1_out;
                        cur_x2 <= perm_x2_out;
                        cur_x3 <= perm_x3_out;
                        cur_x4 <= perm_x4_out;
                    end
                end

                default: ; // EMIT_OUT / PERM_KICK / FINISH: no action
            endcase
        end
    end

    assign perm_num_rounds = 4'd6;
    assign perm_x0_in = cur_x0;
    assign perm_x1_in = cur_x1;
    assign perm_x2_in = cur_x2;
    assign perm_x3_in = cur_x3;
    assign perm_x4_in = cur_x4;

    assign busy   = (state != IDLE) && (state != FINISH);
    assign done   = (state == FINISH);
    assign x0_out = cur_x0;
    assign x1_out = cur_x1;
    assign x2_out = cur_x2;
    assign x3_out = cur_x3;
    assign x4_out = cur_x4;

endmodule
