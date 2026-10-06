// ascon_ad_absorb.sv
// ---------------------------------------------------------------------------
// Ascon-128 associated data (AD) absorption. Streams 64-bit AD blocks in one
// at a time via a request/valid handshake, XORs each (padded, if last) block
// into x0, and runs p^b (6 rounds) after each one. After the final block,
// XORs a domain-separator bit (1) into the LSB of x4, marking the transition
// to plaintext processing.
//
// If has_ad = 0, the entire stage is skipped (state passes through
// unchanged, no domain separator applied) -- this matches the Ascon spec's
// rule that the AD phase (including its domain separator) only happens if
// there IS associated data.
//
// PADDING: Ascon pads by appending a single 1 bit then 0 bits to fill the
// last block. If the real AD data exactly fills full 8-byte blocks with
// nothing left over, an EXTRA block consisting of pure padding (0x80 then
// seven 0x00 bytes) is required. To keep this module simple, the caller
// handles chunking real AD bytes into full 8-byte blocks (block_is_last=0,
// block_bytes ignored) and provides the final block (block_is_last=1) with
// block_bytes in 0..7:
//   block_bytes = 0        -> entire block is padding (0x80, then 7x 0x00)
//   block_bytes = 1..7     -> that many real bytes (big-endian, byte 0 =
//                              MSB), followed by 0x80, then zero-fill
// (block_bytes = 8 is never used here -- see note above: an exact multiple
// needs its own all-padding block instead.)
//
// Protocol: assert `start` for one cycle with has_ad and x0_in..x4_in valid.
// If has_ad=1, the module will then assert `block_req` when ready for the
// next block; respond with block_data/block_is_last/block_bytes and pulse
// block_valid for one cycle. Repeat until the block marked block_is_last has
// been accepted. `done` pulses once x0_out..x4_out hold the final state.
// ---------------------------------------------------------------------------

module ascon_ad_absorb (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        has_ad,
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

    output logic        busy,
    output logic        done,
    output logic [63:0] x0_out,
    output logic [63:0] x1_out,
    output logic [63:0] x2_out,
    output logic [63:0] x3_out,
    output logic [63:0] x4_out
);

    typedef enum logic [2:0] { IDLE, SKIP, WAIT_BLOCK, PERM_KICK, PERM_WAIT, FINISH } state_t;
    state_t state, next_state;

    logic [63:0] cur_x0, cur_x1, cur_x2, cur_x3, cur_x4;
    logic        last_seen; // latched: was the block just absorbed the final one?

    // ---- Padding logic (combinational): build the padded 64-bit block ----
    logic [63:0] padded_block;
    always_comb begin
        if (!block_is_last) begin
            padded_block = block_data;
        end else begin
            padded_block = 64'd0;
            for (int j = 0; j < 8; j++) begin
                if (j < block_bytes) begin
                    // Keep real byte j from block_data (byte 0 = MSB)
                    padded_block[63 - 8*j -: 8] = block_data[63 - 8*j -: 8];
                end else if (j == block_bytes) begin
                    // The pad-start byte
                    padded_block[63 - 8*j -: 8] = 8'h80;
                end
                // else: stays 0x00 (already initialized)
            end
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
        next_state = state;
        perm_start = 1'b0;
        block_req  = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    if (has_ad)
                        next_state = WAIT_BLOCK;
                    else
                        next_state = SKIP;
                end else begin
                    next_state = IDLE;
                end
            end

            SKIP: begin
                next_state = FINISH; // no AD: pass state through, no domain sep
            end

            WAIT_BLOCK: begin
                block_req = 1'b1;
                if (block_valid)
                    next_state = PERM_KICK;
                else
                    next_state = WAIT_BLOCK;
            end

            PERM_KICK: begin
                perm_start = 1'b1; // padded_block/cur_x already combinationally valid
                next_state = PERM_WAIT;
            end

            PERM_WAIT: begin
                if (perm_done) begin
                    if (last_seen)
                        next_state = FINISH;
                    else
                        next_state = WAIT_BLOCK;
                end else begin
                    next_state = PERM_WAIT;
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
            cur_x0 <= 64'd0; cur_x1 <= 64'd0; cur_x2 <= 64'd0;
            cur_x3 <= 64'd0; cur_x4 <= 64'd0;
            last_seen <= 1'b0;
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
                        cur_x0    <= cur_x0 ^ padded_block; // latch immediately -- stable for the permutation
                    end
                end

                PERM_WAIT: begin
                    if (perm_done) begin
                        cur_x0 <= perm_x0_out;
                        cur_x1 <= perm_x1_out;
                        cur_x2 <= perm_x2_out;
                        cur_x3 <= perm_x3_out;
                        // Apply domain separator here (same edge) if this
                        // was the final block -- avoids an extra latched
                        // state hop, same lesson as the permutation fix.
                        cur_x4 <= last_seen ? (perm_x4_out ^ 64'd1) : perm_x4_out;
                    end
                end

                default: ; // SKIP / PERM_KICK / FINISH: no action
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
