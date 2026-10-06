// tb_ascon_add_rc.sv
// ---------------------------------------------------------------------------
// Self-checking testbench for ascon_add_rc.
// Golden vectors generated from the independent C++ reference model
// (model/ascon_diffusion_ref.cpp), one per round (0-11), each combined with
// a sample x2 pattern.
// ---------------------------------------------------------------------------

module tb_ascon_add_rc;

    logic [3:0]  round;
    logic [63:0] x2_in;
    logic [63:0] x2_out;
    int errors;

    ascon_add_rc dut (
        .round(round),
        .x2_in(x2_in),
        .x2_out(x2_out)
    );

    task automatic check_add_rc_vector(
        input logic [3:0]  r,
        input logic [63:0] i,
        input logic [63:0] e,
        input string label
    );
        round = r;
        x2_in = i;
        #1;
        if (x2_out !== e) begin
            errors++;
            $display("FAIL [%s]: round=%0d in=%016h got=%016h want=%016h",
                      label, r, i, x2_out, e);
        end else begin
            $display("PASS [%s]", label);
        end
    endtask

    initial begin
        errors = 0;

        check_add_rc_vector(4'd0 , 64'h0000000000000000, 64'h00000000000000F0, "round-0");
        check_add_rc_vector(4'd1 , 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFF1E, "round-1");
        check_add_rc_vector(4'd2 , 64'h123456789ABCDEF0, 64'h123456789ABCDE22, "round-2");
        check_add_rc_vector(4'd3 , 64'h0000000000000000, 64'h00000000000000C3, "round-3");
        check_add_rc_vector(4'd4 , 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFF4B, "round-4");
        check_add_rc_vector(4'd5 , 64'h123456789ABCDEF0, 64'h123456789ABCDE55, "round-5");
        check_add_rc_vector(4'd6 , 64'h0000000000000000, 64'h0000000000000096, "round-6");
        check_add_rc_vector(4'd7 , 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFF78, "round-7");
        check_add_rc_vector(4'd8 , 64'h123456789ABCDEF0, 64'h123456789ABCDE88, "round-8");
        check_add_rc_vector(4'd9 , 64'h0000000000000000, 64'h0000000000000069, "round-9");
        check_add_rc_vector(4'd10, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFA5, "round-10");
        check_add_rc_vector(4'd11, 64'h123456789ABCDEF0, 64'h123456789ABCDEBB, "round-11");

        if (errors == 0)
            $display("\n*** ALL ADD_RC VECTORS MATCH THE GOLDEN MODEL ***");
        else
            $display("\n*** %0d MISMATCH(ES) FOUND ***", errors);

        $finish;
    end

endmodule
