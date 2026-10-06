// ascon_permutation.sv
// ---------------------------------------------------------------------------
// Ascon permutation: chains ascon_round either 12 times (p^a, used at
// initialization and finalization) or 6 times (p^b, used between blocks of
// associated data / plaintext).
//
// Key structural fact: p^b's 6 rounds are exactly the LAST 6 rounds of p^a
// (round-constant indices 6 through 11), so a single `num_rounds` input
// selects between them -- the starting round index is simply
// (12 - num_rounds): 0 for a 12-round run, 6 for a 6-round run.
//
// Protocol: assert `start` for one cycle with x0_in..x4_in and num_rounds
// (4'd12 or 4'd6) valid; `busy` stays high while processing; `done` pulses
// for one cycle once x0_out..x4_out hold the fully permuted state.
// ---------------------------------------------------------------------------

module ascon_permutation (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [3:0]  num_rounds,   // 4'd12 for p^a, 4'd6 for p^b
    input  logic [63:0] x0_in,
    input  logic [63:0] x1_in,
    input  logic [63:0] x2_in,
    input  logic [63:0] x3_in,
    input  logic [63:0] x4_in,
    output logic        busy,
    output logic        done,
    output logic [63:0] x0_out,
    output logic [63:0] x1_out,
    output logic [63:0] x2_out,
    output logic [63:0] x3_out,
    output logic [63:0] x4_out
);
    typedef enum logic [1:0] { IDLE, ROUND_START, ROUND_WAIT, FINISH } state_t;
    state_t state, next_state;

    logic [3:0] round_idx;     // current round-constant index (0..11)
    logic [3:0] rounds_done;   // how many rounds completed so far
    logic [3:0] rounds_target; // latched copy of num_rounds
    logic [3:0] start_round;   // 12 - num_rounds

    // Working state words, fed back into ascon_round each iteration
    logic [63:0] cur_x0, cur_x1, cur_x2, cur_x3, cur_x4;

    logic        r_start, r_busy, r_done;
    logic [63:0] r_x0_out, r_x1_out, r_x2_out, r_x3_out, r_x4_out;

    assign start_round = 4'd12 - num_rounds;

    ascon_round round_inst (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (r_start),
        .round  (round_idx),
        .x0_in  (cur_x0), .x1_in (cur_x1), .x2_in (cur_x2),
        .x3_in  (cur_x3), .x4_in (cur_x4),
        .busy   (r_busy),
        .done   (r_done),
        .x0_out (r_x0_out), .x1_out (r_x1_out), .x2_out (r_x2_out),
        .x3_out (r_x3_out), .x4_out (r_x4_out)
    );

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
        r_start = 1'b0;

        case (state)
            IDLE: begin
                if (start)
                    next_state = ROUND_START;
                else
                    next_state = IDLE;
            end

            ROUND_START: begin
                r_start = 1'b1; // pulse start into ascon_round for 1 cycle
                next_state = ROUND_WAIT;
            end

            ROUND_WAIT: begin
                if (r_done) begin
                    if (rounds_done == rounds_target - 4'd1)
                        next_state = FINISH;
                    else
                        next_state = ROUND_START;
                end else begin
                    next_state = ROUND_WAIT;
                end
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
            round_idx     <= 4'd0;
            rounds_done   <= 4'd0;
            rounds_target <= 4'd0;
            cur_x0 <= 64'd0; cur_x1 <= 64'd0; cur_x2 <= 64'd0;
            cur_x3 <= 64'd0; cur_x4 <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        cur_x0        <= x0_in;
                        cur_x1        <= x1_in;
                        cur_x2        <= x2_in;
                        cur_x3        <= x3_in;
                        cur_x4        <= x4_in;
                        round_idx     <= start_round;
                        rounds_done   <= 4'd0;
                        rounds_target <= num_rounds;
                    end
                end

                ROUND_WAIT: begin
                    if (r_done) begin
                        // Feed this round's output into the next round's input
                        cur_x0 <= r_x0_out;
                        cur_x1 <= r_x1_out;
                        cur_x2 <= r_x2_out;
                        cur_x3 <= r_x3_out;
                        cur_x4 <= r_x4_out;
                        round_idx   <= round_idx + 4'd1;
                        rounds_done <= rounds_done + 4'd1;
                    end
                end

                FINISH: begin
                    // No datapath action needed -- x_out is driven directly
                    // from cur_x via continuous assignment below, so it's
                    // already correct the moment we enter this state (no
                    // extra one-cycle lag behind `done`).
                end

                default: ;
            endcase
        end
    end

    assign busy   = (state != IDLE) && (state != FINISH);
    assign done   = (state == FINISH);
    assign x0_out = cur_x0;
    assign x1_out = cur_x1;
    assign x2_out = cur_x2;
    assign x3_out = cur_x3;
    assign x4_out = cur_x4;

endmodule
