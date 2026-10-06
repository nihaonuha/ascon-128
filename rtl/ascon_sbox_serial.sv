// ascon_sbox_serial.sv
// ---------------------------------------------------------------------------
// Serial S-box wrapper for the substitution layer.
//
// Rather than instantiating 64 parallel copies of ascon_sbox (one per bit
// position across the 5 state words), this reuses a SINGLE ascon_sbox
// instance, feeding it one bit-slice per clock cycle across 64 cycles.
// This trades latency (64 extra cycles per round) for a large reduction in
// area and dynamic power, in line with Ascon's own lightweight-cipher goals
// (see DESIGN_LOG.md, entry 5).
//
// Protocol:
//   - Assert `start` for one cycle with x0_in..x4_in already valid.
//   - `busy` goes high while processing.
//   - After 64 cycles, `done` pulses for one cycle and x0_out..x4_out hold
//     the fully substituted words.
// ---------------------------------------------------------------------------

module ascon_sbox_serial (
    input  logic        clk,
    input  logic        rst_n,     // active-low synchronous reset
    input  logic        start,
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

    typedef enum logic [1:0] { IDLE, RUNNING, FINISH } state_t;
    state_t state, next_state;

    logic [5:0] bit_idx;          // 0..63, which bit-slice we're on
    logic [63:0] hold_x0, hold_x1, hold_x2, hold_x3, hold_x4; // latched inputs
    logic [63:0] res_x0, res_x1, res_x2, res_x3, res_x4;      // building results

    // Extract bit [bit_idx] from each latched input word to feed the S-box
    logic [4:0] sbox_in;
    logic [4:0] sbox_out;

    assign sbox_in = { hold_x0[bit_idx], hold_x1[bit_idx], hold_x2[bit_idx],
                        hold_x3[bit_idx], hold_x4[bit_idx] };

    ascon_sbox sbox_inst (
        .x(sbox_in),
        .y(sbox_out)
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
        case (state)
            IDLE: begin
                if (start)
                    next_state = RUNNING;
                else
                    next_state = IDLE;
            end
            RUNNING: begin
                if (bit_idx == 6'd63)
                    next_state = FINISH;
                else
                    next_state = RUNNING;
            end
            FINISH:  next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // ---- Datapath ----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bit_idx <= 6'd0;
            hold_x0 <= 64'd0; hold_x1 <= 64'd0; hold_x2 <= 64'd0;
            hold_x3 <= 64'd0; hold_x4 <= 64'd0;
            res_x0  <= 64'd0; res_x1  <= 64'd0; res_x2  <= 64'd0;
            res_x3  <= 64'd0; res_x4  <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        // Latch inputs and reset the bit counter/results
                        hold_x0 <= x0_in; hold_x1 <= x1_in; hold_x2 <= x2_in;
                        hold_x3 <= x3_in; hold_x4 <= x4_in;
                        res_x0  <= 64'd0; res_x1  <= 64'd0; res_x2  <= 64'd0;
                        res_x3  <= 64'd0; res_x4  <= 64'd0;
                        bit_idx <= 6'd0;
                    end
                end

                RUNNING: begin
                    // Place this cycle's S-box result into bit [bit_idx] of
                    // each result word.
                    res_x0[bit_idx] <= sbox_out[4];
                    res_x1[bit_idx] <= sbox_out[3];
                    res_x2[bit_idx] <= sbox_out[2];
                    res_x3[bit_idx] <= sbox_out[1];
                    res_x4[bit_idx] <= sbox_out[0];

                    if (bit_idx != 6'd63)
                        bit_idx <= bit_idx + 6'd1;
                end

                FINISH: begin
                    // one-cycle pulse state, nothing to update
                end

                default: ;
            endcase
        end
    end

    assign busy   = (state == RUNNING);
    assign done   = (state == FINISH);
    assign x0_out = res_x0;
    assign x1_out = res_x1;
    assign x2_out = res_x2;
    assign x3_out = res_x3;
    assign x4_out = res_x4;

endmodule
