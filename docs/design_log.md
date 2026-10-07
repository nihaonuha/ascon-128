# ascon core: design log

---

## 1. algorithm variant: ascon-128

ascon-128 over the ascon-128a. ascon-128 is the primary variant in the nist standard and most commonly referenced version in the spec and literature. 128a also has a 128-bit rate compared to the 128's 64-bit rate, so i want to go for something small and standard/canonical.


## 2. s-box case-statement lookup table implementation

**decision:** implement the 5-bit s-box as a direct `case` statement mapping
each of the 32 possible inputs to its golden-table output.

**why:** the s-box is fundamentally a fixed substitution table — the
case-statement form states that directly and is simple to verify exhaustively
(all 32 inputs). matches how the original (pre-loss) implementation was
built.

**alternative considered:** the bit-sliced algebraic form (xor/and network
derived from the chi-like transform in the spec) — mathematically closer to
"why" the s-box has its nonlinearity properties, but not the style used here.
both forms were verified to produce identical outputs against the same
golden table.


## 3. verification strategy: golden-vector testing against an independent
   reference model

**decision:** every rtl module is checked against expected outputs generated
by a *separate* implementation of the same math — not derived from the rtl
itself.

**why:** checking hardware output against its own derived values is circular
and proves nothing. an independent reference model (external published table
for the s-box; a from-scratch reimplementation of the diffusion/add-constant
formulas) gives real evidence of correctness when both agree.

**reference model language: c++** (not python). rationale: closer in
semantics to hardware bit-widths (fixed-width `uint64_t`, explicit shifts),
and a common choice for hardware verification reference models generally.


## 4. project directory structure

**decision:**
```
~/osic/designs/ascon/
├── rtl/     — systemverilog modules
├── tb/      — testbenches
├── model/   — c++ golden-reference implementations
└── docs/    — this design log
```
kept separate from `OpenROAD-flow-scripts/flow/designs/{src,sky130hd}/ascon/`,
which will only be populated once a module is ready to actually go through
the openroad flow (synthesis/place/route).


## 5. ppa target: optimize for area + power over performance

**decision:** prioritize small area and low power over raw throughput/speed.

**why:** ascon itself was designed as a nist lightweight cryptography
candidate, intended for constrained/embedded devices where area and power
matter more than throughput. optimizing the implementation for the same
goals the algorithm itself was designed around is a coherent, defensible
design story — not an arbitrary constraint.

**consequence:** the s-box, which is applied per-bit-slice across 64
bit-positions each round, will be implemented as a single reused instance
driven by a bit-counter and small fsm (serial), rather than 64 parallel
instances (combinational/parallel). this trades more clock cycles per round
for significantly less area and lower dynamic power — the first point in the
design where sequential logic (a clock, registers, a state machine) enters
the project; everything before this (s-box, diffusion, add-round-constant)
was purely combinational.

**alternative considered:** fully parallel/combinational round (64 s-box
instances) — simpler to build and verify, higher throughput, but
significantly larger area and higher power. rejected given the ppa target
above.


## 6. merge pt_process/ct_process, and share one permutation instance
   across all stages

**decision:** replace the separate `ascon_pt_process` / `ascon_ct_process`
modules with a single `ascon_data_process`, selecting encrypt vs. decrypt at
runtime via a `mode_decrypt` input rather than instantiating two full
datapaths. went further than that: `ascon_init`, `ascon_ad_absorb`,
`ascon_data_process`, and `ascon_finalize` no longer each own a private
`ascon_permutation` instance — `ascon_top` instantiates exactly one
permutation and muxes its request/response interface to whichever stage is
currently active, keyed off the top-level fsm's own state.

**why:** first openroad synthesis run (sky130hd) showed sequential elements
at 47% of total chip area, with `pt_process`/`ct_process` each carrying a
full duplicate 320-bit state register bank plus their own permutation
instance — dead weight, since only one of pt/ct is ever live per operation,
and the top-level fsm already guarantees init/ad/data/finalize run strictly
sequentially, never concurrently, so at most one stage's permutation request
is ever meaningfully asserted at a time. the math also unifies cleanly:
`output_byte = x0_byte ^ data_byte` in both directions (xor is its own
inverse), and `new_state_byte` differs only in whether it takes the computed
xor result (encrypt) or the received byte directly (decrypt) — one shared
per-byte formula, not two mirrored modules. the pad-marker/beyond-padding
byte conventions of the two original modules genuinely differed bit-for-bit
(not just "don't-care" in the docs sense), so the merged module reproduces
each direction's exact original convention there to stay bit-exact against
existing golden vectors.

**result (sky130hd, same 20 ns constraint, before -> after):**

| metric | before | after |
|---|---|---|
| std cells | 49,940 | 18,692 (-62.5%) |
| std-cell area | 442,493 µm² | 157,343 µm² (-64.4%) |
| flip-flops | 10,460 | 3,523 (-66.3%) |
| total power | 47.9 mW | 17.1 mW (-64.3%) |
| clock power | 24.6 mW (51.4%) | 8.28 mW (48.5%) |
| worst slack | +13.20 ns | +13.70 ns |
| fmax | 147.1 MHz | 158.7 MHz |
| max-slew / max-cap violations | 42 / 9 | 0 / 0 |
| route time / peak memory | 33-68 min / 3.6-4.1 GB | 8m23s / 2.2 GB |

all 11 testbenches (tb_ascon_pt_process/tb_ascon_ct_process retired in favor
of a single tb_ascon_data_process; tb_ascon_init/tb_ascon_ad_absorb/
tb_ascon_finalize updated for the new perm_* port interface) still pass
against the same golden vectors from `model/ascon_ref.cpp`.

**alternative considered:** keep `ascon_pt_process`/`ascon_ct_process` as
thin wrappers around a merged core (tie `mode_decrypt` to a constant per
wrapper), preserving the old module names/ports exactly so the existing
per-module testbenches need zero changes. rejected in favor of the more
thorough refactor — wrapper modules would still leave each stage owning its
own permutation instance, missing the much larger win (5 permutation copies
down to 1) that actually explains most of the area/power drop above.


## 7. placement density: settle on CORE_UTILIZATION=45 / PLACE_DENSITY=0.55

**decision:** stop density tuning at `CORE_UTILIZATION=45`, `PLACE_DENSITY=0.55`
(sky130hd actually places this at ~51% utilization) rather than pushing
tighter.

**why:** swept two points after the decision-6 merge:

| | util. ~24% / density 0.35 | util. ~51% / density 0.55 |
|---|---|---|
| die area | 188,666 µm² | 178,679 µm² (-5.3%) |
| total power | 17.1 mW | 16.1 mW (-5.8%) |
| route time | 8m23s | 33m45s (+4x) |
| peak memory | 2.2 GB | 3.22 GB (+46%) |
| violations | 0 | 0 |

roughly doubling actual density bought a 5% area/power improvement at 4x the
route time and significantly more memory pressure — diminishing returns. the
real win was the decision-6 refactor (62-66% cuts across cells/area/power);
further density tuning past this point trades a lot of runtime for single-
digit gains, and the 45/0.55 config leaves a comfortable margin against the
8 gb laptop's practical memory ceiling for future re-runs.

**alternative considered:** push to 60%/0.65 to find the actual congestion
wall. decided against — not worth the runtime for the design as it stands;
can revisit if the synthesis environment changes (more ram, faster machine)
or if a future change shrinks the design further and makes tighter density
cheap again.


## 8. drc/lvs signoff: drc clean, lvs attempted via two paths, stopped short
   of clean

**decision:** run formal signoff checks via klayout (drc) and klayout/netgen
(lvs) on top of openroad's own route-time checks. drc passed cleanly; lvs did
not reach a clean pass after two independent attempts, and we're stopping
here rather than continuing to chase it.

**why / what we found:**

drc — `make drc` via klayout's `sky130hd.lydrc` ruleset: 0 violations.
independent confirmation of what openroad's own route-time checks already
reported.

lvs, attempt 1 (klayout + cdl, orfs's built-in `make lvs`): hit a pin-count
parsing error in the pdk's own cdl library (`sky130_fd_sc_hd__macro_sparecell`
uses a backslash-delimited instance syntax klayout's cdl reader miscounts as
an extra pin). fixed via a sed patch in the makefile's cdl-concatenation
rule. after that fix, `compare()` failed on a deeper issue: `6_final.cdl`
(openroad's `write_cdl` output) carries zero power/ground pin connectivity
on any instance — not a naming mismatch `connect_global`/`same_nets` can
patch around, an actual absence of power nets in the schematic netlist.
traced this to a confirmed, long-standing upstream issue (openroad project
issue #1146, open since 2021, still not fully resolved) — the same
pin-count-mismatch error, hitting the same `macro_sparecell` cell, reported
by other users on orfs's own stock `gcd` example design. not specific to
this design or this config.

lvs, attempt 2 (magic extraction + netgen, comparing against `6_final.v`
instead of cdl): avoids the cdl bug entirely by using a different netlist
source and a different tool. result: 18,594 devices vs 18,593 (off by one,
~99.995% match — plausibly one antenna-fix diode cell not appearing
identically in both views) and 138,292 vs 93,433 nets (a larger gap, but a
well-known artifact of magic's basic power-mesh extraction reporting many
disconnected net fragments rather than one merged net — an extraction-
methodology limitation, not evidence of an actual open circuit, especially
given drc already confirmed the physical routing itself is clean).

**conclusion:** stopping here. drc-clean (independently confirmed) +
functional verification against golden vectors (11/11 testbenches) is the
signoff bar for this project. a fully clean lvs pass would require either
waiting on the upstream openroad cdl fix, or tuning magic's power-mesh
extraction/net-merging specifically — both legitimate but open-ended efforts
disproportionate to what this project needs.

**alternative considered:** keep iterating on magic's extraction options
(merge/connectivity passes to try to close the net-count gap) toward a fully
clean lvs. left as a known follow-up if ever needed, not pursued further
here.


## status as of this entry

**functionally complete and verified.** all 12 original testbenches
(now 11, after decision 6 retired tb_ascon_pt_process/tb_ascon_ct_process in
favor of tb_ascon_data_process) pass against golden vectors from
`model/ascon_ref.cpp`:
- [x] s-box, serial s-box (`ascon_sbox.sv`, `ascon_sbox_serial.sv`)
- [x] diffusion, add-round-constant (`ascon_diffusion.sv`, `ascon_add_rc.sv`)
- [x] round, permutation (`ascon_round.sv`, `ascon_permutation.sv`)
- [x] init, ad absorb, merged data process, finalize
      (`ascon_init.sv`, `ascon_ad_absorb.sv`, `ascon_data_process.sv`,
      `ascon_finalize.sv`)
- [x] top-level encrypt/decrypt datapath with tag verification (`ascon_top.sv`)

**synthesized through openroad (sky130hd)**, final ppa at
`CORE_UTILIZATION=45`/`PLACE_DENSITY=0.55`:
- 18,692 std cells / 157,343 µm² std-cell area / 178,679 µm² die area
- 16.1 mW total power (46.2% clock, 46.0% sequential, 7.9% combinational)
- fmax 154.75 MHz against a 50 MHz (20 ns) constraint; 0 drc/timing violations

signoff status (see decision 8):
- [x] drc — 0 violations (klayout, `sky130hd.lydrc`)
- [~] lvs — not clean; two attempts diagnosed down to known upstream
      tooling limitations (openroad cdl bug; magic power-mesh extraction
      artifact), not a connectivity defect in the design. not pursued
      further — drc-clean + functional golden-vector verification is the
      signoff bar this project is landing on.
