// tb_ascon_sbox.sv
// ---------------------------------------------------------------------------
// Self-checking testbench for ascon_sbox.
// Sweeps all 32 possible 5-bit inputs and compares against the golden
// Ascon S-box table (the same values published in the Ascon spec).
// ---------------------------------------------------------------------------

module tb_ascon_sbox;

    logic [4:0] x;
    logic [4:0] y;
    int errors;

    // Golden table: golden[i] = S-box output for input i (i = x0..x4, x0 MSB)
    logic [4:0] golden [0:31];

    ascon_sbox dut (
        .x(x),
        .y(y)
    );

    initial begin
        golden[0]  = 5'h04; golden[1]  = 5'h0b; golden[2]  = 5'h1f; golden[3]  = 5'h14;
        golden[4]  = 5'h1a; golden[5]  = 5'h15; golden[6]  = 5'h09; golden[7]  = 5'h02;
        golden[8]  = 5'h1b; golden[9]  = 5'h05; golden[10] = 5'h08; golden[11] = 5'h12;
        golden[12] = 5'h1d; golden[13] = 5'h03; golden[14] = 5'h06; golden[15] = 5'h1c;
        golden[16] = 5'h1e; golden[17] = 5'h13; golden[18] = 5'h07; golden[19] = 5'h0e;
        golden[20] = 5'h00; golden[21] = 5'h0d; golden[22] = 5'h11; golden[23] = 5'h18;
        golden[24] = 5'h10; golden[25] = 5'h0c; golden[26] = 5'h01; golden[27] = 5'h19;
        golden[28] = 5'h16; golden[29] = 5'h0a; golden[30] = 5'h0f; golden[31] = 5'h17;

        errors = 0;

        for (int i = 0; i < 32; i++) begin
            x = i[4:0];
            #1; // let combinational logic settle

            if (y !== golden[i]) begin
                errors++;
                $display("FAIL: x=%0d (5'b%05b) -> y=5'b%05b, expected 5'b%05b",
                          i, x, y, golden[i]);
            end else begin
                $display("PASS: x=%0d (5'b%05b) -> y=5'b%05b", i, x, y);
            end
        end

        if (errors == 0)
            $display("\n*** ALL 32 S-BOX VECTORS MATCH THE GOLDEN TABLE ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
