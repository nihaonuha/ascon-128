// ascon_init.sv
// ---------------------------------------------------------------------------
// Ascon-128 initialization: loads the 320-bit state with the fixed IV
// constant, the 128-bit key, and the 128-bit nonce, runs the full 12-round
// permutation (p^a) once, then XORs the key back into the last two words
// (x3, x4). This "locks in" the key/nonce before any real data is absorbed.
//
// State layout going into the permutation:
//   x0 = IV constant (0x80400c0600000000 for Ascon-128: a=12, b=6, rate=64,
//        key=128, tag=128)
//   x1 = key[127:64]
//   x2 = key[63:0]
//   x3 = nonce[127:64]
//   x4 = nonce[63:0]
//
// PERMUTATION INTERFACE: does not instantiate its own ascon_permutation --
// exposes a request interface (perm_start/perm_num_rounds/perm_x*_in,
// perm_busy/perm_done/perm_x*_out) so the top level can wire ONE shared
// permutation instance across all stages. See DESIGN_LOG.md.
//
// Protocol: assert `start` for one cycle with key/nonce valid; `busy` stays
// high while processing; `done` pulses for one cycle once x0_out..x4_out
// hold the initialized state, ready for associated-data absorption.
// ---------------------------------------------------------------------------

module ascon_init (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] key,     // key[127:64] = K0 (upper), key[63:0] = K1 (lower)
    input  logic [127:0] nonce,   // nonce[127:64] = N0, nonce[63:0] = N1

    // ---- Shared permutation request interface ----
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

    output logic         busy,
    output logic         done,
    output logic [63:0]  x0_out,
    output logic [63:0]  x1_out,
    output logic [63:0]  x2_out,
    output logic [63:0]  x3_out,
    output logic [63:0]  x4_out
);

    // Fixed IV constant for Ascon-128 (a=12, b=6, rate=64, key=128, tag=128)
    localparam logic [63:0] ASCON128_IV = 64'h80400c0600000000;

    typedef enum logic [1:0] { IDLE, PERM_WAIT, FINISH } state_t;
    state_t state, next_state;

    logic [127:0] key_latched;
    logic [63:0]  cur_x0, cur_x1, cur_x2, cur_x3, cur_x4;

    // ---- State register ----
    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ---- Next-state logic ----
    always_comb begin
        next_state = state;
        perm_start = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    perm_start = 1'b1; // fed live from key/nonce ports directly (see below)
                    next_state = PERM_WAIT;
                end else begin
                    next_state = IDLE;
                end
            end

            PERM_WAIT: begin
                if (perm_done)
                    next_state = FINISH;
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
            key_latched <= 128'd0;
            cur_x0 <= 64'd0; cur_x1 <= 64'd0; cur_x2 <= 64'd0;
            cur_x3 <= 64'd0; cur_x4 <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start)
                        key_latched <= key; // held stable for the post-perm XOR later
                end

                PERM_WAIT: begin
                    if (perm_done) begin
                        cur_x0 <= perm_x0_out;
                        cur_x1 <= perm_x1_out;
                        cur_x2 <= perm_x2_out;
                        cur_x3 <= perm_x3_out ^ key_latched[127:64];
                        cur_x4 <= perm_x4_out ^ key_latched[63:0];
                    end
                end

                default: ; // FINISH: no action, cur_x3/cur_x4 already final
            endcase
        end
    end

    // Permutation request inputs, fed live/combinationally when perm_start
    // fires (in the same IDLE cycle as `start`) -- safe because `key` and
    // `nonce` are top-level ports the caller holds stable during that one
    // cycle, same convention as every other module's `start` pulse.
    assign perm_num_rounds = 4'd12;
    assign perm_x0_in = ASCON128_IV;
    assign perm_x1_in = key[127:64];
    assign perm_x2_in = key[63:0];
    assign perm_x3_in = nonce[127:64];
    assign perm_x4_in = nonce[63:0];

    assign x0_out = cur_x0;
    assign x1_out = cur_x1;
    assign x2_out = cur_x2;
    assign x3_out = cur_x3;
    assign x4_out = cur_x4;

    assign busy = (state != IDLE) && (state != FINISH);
    assign done = (state == FINISH);

endmodule
