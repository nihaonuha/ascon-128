# ascon-128 overview

notes on the algorithm itself, not implementation decisions (see `design_log.md` for those).

---

## what it does

authenticated encryption (aead): encrypts data and produces a tag proving it wasn't tampered with. plain encryption alone (e.g. aes-cbc) doesn't catch tampering — ascon does both in one pass.

designed for lightweight/embedded use (iot, smart cards). nist's winning lightweight cryptography candidate.

---

## state and permutation

320-bit internal state, five 64-bit words (`x0`-`x4`).

core operation is the permutation — applied repeatedly, with different data xored in/out around it depending on stage. 12 rounds (`p^a`) at start and end, 6 rounds (`p^b`) in between. same round logic both times, just a different repeat count.

data gets xored into the state, the permutation mixes it, then the relevant bits get read back out (ciphertext, tag).

---

## one round = 3 steps

1. add round constant — xor one fixed byte into `x2`, different per round.
2. s-box — 5-bit nonlinear substitution, applied bit-slice across all 64 bit-positions. source of the cipher's confusion/nonlinearity.
3. diffusion — xor each word with two rotated copies of itself. spreads any single-bit change across the whole word.

---

## four stages

**init** — load state with a fixed constant + key + nonce. run `p^a` once. xor key back in.

**associated data (optional)** — xor each 64-bit ad block into the state, `p^b` after every block including the last. skipped entirely if there's no ad.

**plaintext** — for each 64-bit pt block: xor into state, result is the ct block, output it. `p^b` before the next block, skipped after the last block (no next block to prepare state for).

**finalization** — xor key into state, run `p^a` once, xor key in again. last 128 bits of state = the tag.

---

## decryption

same init/ad handling as encryption. per ct block: xor into state to recover pt, but put the ct block itself (not the recovered pt) back into the state before the next round — keeps both sides in sync regardless of direction. finalization/tag check unchanged.

---

## rtl status

all stages built and synthesized (sky130hd, via openroad). see `design_log.md` for implementation decisions, verification approach, and synthesis results — this file stays limited to the algorithm.

- [x] add-constant (`ascon_add_rc.sv`)
- [x] s-box, serial s-box (`ascon_sbox.sv`, `ascon_sbox_serial.sv`)
- [x] diffusion (`ascon_diffusion.sv`)
- [x] round (`ascon_round.sv`)
- [x] permutation, 12/6-round chaining (`ascon_permutation.sv`)
- [x] init (`ascon_init.sv`)
- [x] ad absorb (`ascon_ad_absorb.sv`)
- [x] pt/ct processing, both directions (`ascon_data_process.sv`, `mode_decrypt` selects)
- [x] finalization/tag (`ascon_finalize.sv`)
- [x] top-level datapath + tag check (`ascon_top.sv`)

note: pt/ct processing is one module handling both directions at runtime, not two separate datapaths — same per-byte xor math either way, differing only in whether the new state takes the xor result or the received byte directly. permutation is also a single shared instance across all stages (muxed by the top-level fsm), not one copy per stage. neither changes what the algorithm does — both are area/power choices over a naive one-copy-per-stage layout.
