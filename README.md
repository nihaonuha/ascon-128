# ascon-128 hardware core

serial, area/power-optimized systemverilog implementation of ascon-128 (nist's lightweight aead cipher), verified against an independent c++ golden model and synthesized through openroad (sky130hd).

## status

functionally complete. all 11 testbenches pass against golden vectors (`./run_all_tests.sh`). synthesized, placed, and routed clean — 0 drc violations, 16.1 mW total power, 178,679 µm² die area, fmax 154.75 MHz against a 50 MHz target. see `docs/design_log.md` for the full history of decisions and results.

## structure

```
rtl/     — systemverilog implementation (10 modules)
tb/      — one testbench per module, golden vectors from model/
model/   — independent c++ reference implementation
docs/
  design_log.md    — implementation decisions, synthesis results, signoff status
  algo_overview.md — the ascon-128 algorithm itself, notes form
run_all_tests.sh    — runs all testbenches via icarus verilog
```

## running the tests

```bash
./run_all_tests.sh
```

requires icarus verilog (`iverilog`/`vvp`).

## rtl modules

- `ascon_sbox.sv` / `ascon_sbox_serial.sv` — 5-bit s-box, combinational + serial (bit-counter driven)
- `ascon_diffusion.sv` — linear diffusion layer
- `ascon_add_rc.sv` — round-constant addition
- `ascon_round.sv` — one round (add-rc → s-box → diffusion)
- `ascon_permutation.sv` — chains rounds (12 for p^a, 6 for p^b)
- `ascon_init.sv` — loads iv+key+nonce, runs p^a, xors key back in
- `ascon_ad_absorb.sv` — absorbs associated data
- `ascon_data_process.sv` — plaintext/ciphertext processing, both directions (`mode_decrypt` selects)
- `ascon_finalize.sv` — final p^a, produces 128-bit tag
- `ascon_top.sv` — wires everything together; one shared permutation instance across all stages, muxed by the top-level fsm

## synthesis

synthesized through openroad-flow-scripts, sky130hd pdk. the orfs-side config (`config.mk`, `constraint.sdc`) lives in the orfs checkout, not this repo — `designs/src/ascon_top/` for the rtl copy and `designs/sky130hd/ascon_top/` for the config. see `docs/design_log.md` decisions 6–8 for the synthesis/ppa work and signoff results.

## known limitation

lvs isn't fully clean — diagnosed to known upstream tooling issues (openroad's cdl writer dropping power-net connectivity; magic's basic power-mesh extraction reporting fragmented nets), not a connectivity defect in the design. drc is clean and independently confirmed. full writeup in `docs/design_log.md` decision 8.
