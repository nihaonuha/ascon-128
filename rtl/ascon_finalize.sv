// ascon_finalize.sv
// ---------------------------------------------------------------------------
// Ascon-128 finalization: the last stage after plaintext processing. XORs
// the 128-bit key into x1/x2, runs the full 12-round permutation (p^a)
// once, then XORs the key into x3/x4. The tag is the resulting {x3, x4}
// (128 bits), sent alongside the ciphertext so the receiver can verify
// nothing was tampered with.
//
// Same shape as ascon_init.sv (single p^a call, key latched and XORed in
// around it) except the key goes into x1/x2 going IN (not x0/x1/x2 as the
// IV), and comes back out on x3/x4 as the tag rather than just x3/x4 of
// state. State-in here is whatever ascon_pt_process left behind (x0_out..
// x4_out), not a fresh IV/key/nonce load like ascon_init.
//
// Protocol: assert `start` for one cycle with state_in/key valid; `busy`
// stays high while processing; `done` pulses for one cycle once
// x0_out..x4_out hold the final state and tag_out holds the 128-bit tag.
// ---------------------------------------------------------------------------

module ascon_finalize (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [63:0]  x0_in,
    input  logic [63:0]  x1_in,
    input  logic [63:0]  x2_in,
    input  logic [63:0]  x3_in,
    input  logic [63:0]  x4_in,
    input  logic [127:0] key,       // key[127:64] = K0 (upper), key[63:0] = K1 (lower)

    // ---- Shared permutation request interface ----
    output logic         perm_start,
    output logic [3:0]   perm_num_rounds,
    output logic [63:0]  perm_x0_in,
    output logic [63:0]  perm_x1_in,
    output logic [63:0]  perm_x2_in,
    output logic [63:0]  perm_x3_in,
    output logic [63:0]  perm_x4_in,
    input  logic         perm_busy,
    input  logic         perm_done,
    input  logic [63:0]  perm_x0_out,
    input  logic [63:0]  perm_x1_out,
    input  logic [63:0]  perm_x2_out,
    input  logic [63:0]  perm_x3_out,
    input  logic [63:0]  perm_x4_out,

    output logic         busy,
    output logic         done,
    output logic [63:0]  x0_out,
    output logic [63:0]  x1_out,
    output logic [63:0]  x2_out,
    output logic [63:0]  x3_out,
    output logic [63:0]  x4_out,
    output logic [127:0] tag_out    // = {x3_out, x4_out}, valid when done
);

    typedef enum logic [1:0] { IDLE, PERM_WAIT, FINISH } state_t;
    state_t state, next_state;

    logic [127:0] key_latched;

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
                    perm_start = 1'b1; // kick off the permutation immediately
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
    logic [63:0] cur_x0, cur_x1, cur_x2, cur_x3, cur_x4;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            key_latched <= 128'd0;
            cur_x0 <= 64'd0; cur_x1 <= 64'd0; cur_x2 <= 64'd0;
            cur_x3 <= 64'd0; cur_x4 <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start)
                        key_latched <= key; // latch key for the later XOR step
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

                default: ; // FINISH: no datapath action, cur_x already final
            endcase
        end
    end

    assign perm_num_rounds = 4'd12;
    assign perm_x0_in = x0_in;
    assign perm_x1_in = x1_in ^ key[127:64]; // key XORed in BEFORE the permutation
    assign perm_x2_in = x2_in ^ key[63:0];
    assign perm_x3_in = x3_in;
    assign perm_x4_in = x4_in;

    assign busy    = (state != IDLE) && (state != FINISH);
    assign done    = (state == FINISH);
    assign x0_out  = cur_x0;
    assign x1_out  = cur_x1;
    assign x2_out  = cur_x2;
    assign x3_out  = cur_x3;
    assign x4_out  = cur_x4;
    assign tag_out = {cur_x3, cur_x4};

endmodule
