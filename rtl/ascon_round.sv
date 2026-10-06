// ascon_round.sv
// ---------------------------------------------------------------------------
// One full Ascon permutation round: add-round-constant -> substitute (serial
// S-box) -> diffuse. Chains the three already-verified sub-modules together
// under a single FSM.
//
// Only the S-box stage takes multiple cycles (64, via ascon_sbox_serial).
// add_rc and diffusion are purely combinational, so each just takes 1 cycle
// to latch through.
//
// Protocol: same as ascon_sbox_serial -- assert `start` for one cycle with
// x0_in..x4_in and `round` valid; `busy` stays high while processing; `done`
// pulses for one cycle once x0_out..x4_out hold the completed round's result.
// ---------------------------------------------------------------------------

module ascon_round (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [3:0]  round,
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

    typedef enum logic [2:0] { IDLE, ADD_RC, SBOX_START, SBOX_WAIT, DIFFUSE, FINISH } state_t;
    state_t state, next_state;

    // Latched copies of the words as they move through each stage
    logic [63:0] hold_x0, hold_x1, hold_x2_latched, hold_x3, hold_x4;
    logic [63:0] rc_x2;                              // x2 after add_rc

    logic [63:0] sbox_x0, sbox_x1, sbox_x2, sbox_x3, sbox_x4; // after S-box
    logic [63:0] diff_x0, diff_x1, diff_x2, diff_x3, diff_x4; // after diffusion

    // ---- Sub-module: add round constant (combinational) ----
    ascon_add_rc add_rc_inst (
        .round  (round),
        .x2_in  (hold_x2_latched),
        .x2_out (rc_x2)
    );

    // ---- Sub-module: serial S-box ----
    logic sbox_start, sbox_busy, sbox_done;
    ascon_sbox_serial sbox_inst (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (sbox_start),
        .x0_in  (hold_x0),
        .x1_in  (hold_x1),
        .x2_in  (rc_x2),
        .x3_in  (hold_x3),
        .x4_in  (hold_x4),
        .busy   (sbox_busy),
        .done   (sbox_done),
        .x0_out (sbox_x0),
        .x1_out (sbox_x1),
        .x2_out (sbox_x2),
        .x3_out (sbox_x3),
        .x4_out (sbox_x4)
    );

    // ---- Sub-module: diffusion (combinational) ----
    ascon_diffusion diff_inst (
        .x0_in (sbox_x0), .x1_in (sbox_x1), .x2_in (sbox_x2),
        .x3_in (sbox_x3), .x4_in (sbox_x4),
        .x0_out(diff_x0), .x1_out(diff_x1), .x2_out(diff_x2),
        .x3_out(diff_x3), .x4_out(diff_x4)
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
        sbox_start = 1'b0;

        case (state)
            IDLE: begin
                if (start)
                    next_state = ADD_RC;
                else
                    next_state = IDLE;
            end

            ADD_RC: begin
                next_state = SBOX_START;
            end

            SBOX_START: begin
                sbox_start = 1'b1;   // pulse start into the S-box for 1 cycle
                next_state = SBOX_WAIT;
            end

            SBOX_WAIT: begin
                if (sbox_done)
                    next_state = DIFFUSE;
                else
                    next_state = SBOX_WAIT;
            end

            DIFFUSE: begin
                next_state = FINISH;
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
            hold_x0 <= 64'd0; hold_x1 <= 64'd0; hold_x2_latched <= 64'd0;
            hold_x3 <= 64'd0; hold_x4 <= 64'd0;
            x0_out  <= 64'd0; x1_out  <= 64'd0; x2_out  <= 64'd0;
            x3_out  <= 64'd0; x4_out  <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        // Latch the round's inputs before add_rc touches x2
                        hold_x0         <= x0_in;
                        hold_x1         <= x1_in;
                        hold_x2_latched <= x2_in;
                        hold_x3         <= x3_in;
                        hold_x4         <= x4_in;
                    end
                end

                DIFFUSE: begin
                    // Latch the final diffused result as this round's output
                    x0_out <= diff_x0;
                    x1_out <= diff_x1;
                    x2_out <= diff_x2;
                    x3_out <= diff_x3;
                    x4_out <= diff_x4;
                end

                default: ; // ADD_RC / SBOX_START / SBOX_WAIT / FINISH: no datapath action
            endcase
        end
    end

    assign busy = (state != IDLE) && (state != FINISH);
    assign done = (state == FINISH);

endmodule
