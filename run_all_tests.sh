#!/usr/bin/env bash
# run_all_tests.sh
# ---------------------------------------------------------------------------
# Compiles and runs every testbench in tb/ against the current rtl/, one at
# a time (each gets a fresh compile so stale .vvp files can't hide a break).
# Requires: iverilog + vvp (Icarus Verilog) on PATH.
#
# Usage:   ./run_all_tests.sh          (from the ascon/ project root)
#          bash run_all_tests.sh
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"

# All RTL files, compiled in together every time -- iverilog only pulls in
# what's actually instantiated, so it's fine (and simplest) to always pass
# every module rather than tracking per-testbench dependency lists by hand.
RTL_FILES="rtl/ascon_add_rc.sv rtl/ascon_sbox.sv rtl/ascon_diffusion.sv \
rtl/ascon_round.sv rtl/ascon_sbox_serial.sv rtl/ascon_permutation.sv \
rtl/ascon_init.sv rtl/ascon_ad_absorb.sv rtl/ascon_data_process.sv \
rtl/ascon_finalize.sv rtl/ascon_top.sv"

TESTBENCHES="tb_ascon_sbox tb_ascon_add_rc tb_ascon_diffusion tb_ascon_sbox_serial \
tb_ascon_round tb_ascon_permutation tb_ascon_init tb_ascon_ad_absorb \
tb_ascon_data_process tb_ascon_finalize tb_ascon_top"

pass_count=0
fail_count=0
fail_list=""

for tb in $TESTBENCHES; do
    echo "############################################################"
    echo "### $tb"
    echo "############################################################"

    out_vvp="/tmp/${tb}.vvp"
    if ! iverilog -g2012 -o "$out_vvp" $RTL_FILES "tb/${tb}.sv" 2>&1; then
        echo ">>> COMPILE FAILED for $tb"
        fail_count=$((fail_count+1))
        fail_list="$fail_list $tb(compile)"
        continue
    fi

    sim_out=$(vvp "$out_vvp" 2>&1)
    echo "$sim_out"

    if echo "$sim_out" | grep -q "MISMATCH(ES) FOUND\|^FAIL "; then
        fail_count=$((fail_count+1))
        fail_list="$fail_list $tb"
    else
        pass_count=$((pass_count+1))
    fi
    echo
done

echo "############################################################"
echo "SUMMARY: $pass_count/$((pass_count+fail_count)) testbenches clean"
if [ "$fail_count" -gt 0 ]; then
    echo "FAILED:$fail_list"
    exit 1
else
    echo "ALL TESTBENCHES PASS"
    exit 0
fi
