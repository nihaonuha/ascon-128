// ascon_ref.cpp
// ---------------------------------------------------------------------------
// C++ golden-reference model for the Ascon-128 permutation, built up
// incrementally alongside the RTL: S-box, diffusion, add-round-constant,
// and now the full round (all three combined). Independent from the
// SystemVerilog RTL -- used to generate/verify golden test vectors.
//
// Build:   g++ -std=c++17 -O2 -o ascon_ref ascon_ref.cpp
// Run:     ./ascon_ref
// ---------------------------------------------------------------------------

#include <cstdint>
#include <cstdio>
#include <array>
#include <vector>

using u64 = uint64_t;

// Right-rotate a 64-bit value by n bits (n in 1..63)
static inline u64 rotr(u64 v, int n) {
    return (v >> n) | (v << (64 - n));
}

// The Ascon 5-bit S-box, same golden table used in tb_ascon_sbox.sv
static const uint8_t SBOX_TABLE[32] = {
    0x04,0x0b,0x1f,0x14,0x1a,0x15,0x09,0x02,
    0x1b,0x05,0x08,0x12,0x1d,0x03,0x06,0x1c,
    0x1e,0x13,0x07,0x0e,0x00,0x0d,0x11,0x18,
    0x10,0x0c,0x01,0x19,0x16,0x0a,0x0f,0x17
};

// Apply the S-box to all 5 state words, one bit-slice at a time (this is
// the "parallel" reference model -- same result the serial hardware
// version produces, just computed all at once instead of over 64 cycles).
static std::array<u64,5> sbox_layer(std::array<u64,5> x) {
    std::array<u64,5> y = {0,0,0,0,0};
    for (int b = 0; b < 64; b++) {
        uint8_t in_bits = 0;
        for (int w = 0; w < 5; w++)
            in_bits |= ((x[w] >> b) & 1ULL) << (4 - w); // w0 = MSB
        uint8_t out_bits = SBOX_TABLE[in_bits];
        for (int w = 0; w < 5; w++) {
            u64 bit = (out_bits >> (4 - w)) & 1ULL;
            y[w] |= bit << b;
        }
    }
    return y;
}


// Ascon linear diffusion layer: each word XORed with two rotated copies
// of itself, using that word's fixed rotation-amount pair from the spec.
static std::array<u64,5> diffusion(std::array<u64,5> x) {
    std::array<u64,5> y;
    y[0] = x[0] ^ rotr(x[0], 19) ^ rotr(x[0], 28);
    y[1] = x[1] ^ rotr(x[1], 61) ^ rotr(x[1], 39);
    y[2] = x[2] ^ rotr(x[2], 1)  ^ rotr(x[2], 6);
    y[3] = x[3] ^ rotr(x[3], 10) ^ rotr(x[3], 17);
    y[4] = x[4] ^ rotr(x[4], 7)  ^ rotr(x[4], 41);
    return y;
}

static void print_vector(const char* label, std::array<u64,5> in, std::array<u64,5> out) {
    printf("// %s\n", label);
    printf("check_vector(\n");
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)in[0], (unsigned long long)in[1], (unsigned long long)in[2],
           (unsigned long long)in[3], (unsigned long long)in[4]);
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)out[0], (unsigned long long)out[1], (unsigned long long)out[2],
           (unsigned long long)out[3], (unsigned long long)out[4]);
    printf("    \"%s\"\n", label);
    printf(");\n\n");
}

// Ascon round constants for the 12-round p^a permutation.
static const uint8_t ROUND_CONSTANTS[12] = {
    0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5, 0x96, 0x87, 0x78, 0x69, 0x5a, 0x4b
};

// Add-round-constant: XOR the round's constant into the low byte of x2 only.
static inline u64 add_rc(u64 x2, int round) {
    return x2 ^ (u64)ROUND_CONSTANTS[round];
}

static void print_add_rc_vector(int round, u64 x2_in) {
    u64 x2_out = add_rc(x2_in, round);
    printf("check_add_rc_vector(4'd%-2d, 64'h%016llX, 64'h%016llX, \"round-%d\");\n",
           round, (unsigned long long)x2_in, (unsigned long long)x2_out, round);
}

// One full Ascon round: add-round-constant -> S-box layer -> diffusion.
// This is the reference for ascon_round.sv -- combines the three
// already-verified pieces exactly the way the RTL's FSM does.
static std::array<u64,5> full_round(std::array<u64,5> x, int round) {
    x[2] = add_rc(x[2], round);
    x = sbox_layer(x);
    x = diffusion(x);
    return x;
}

static void print_round_vector(const char* label, int round, std::array<u64,5> in, std::array<u64,5> out) {
    printf("// %s (round %d)\n", label, round);
    printf("check_round_vector(4'd%d,\n", round);
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)in[0], (unsigned long long)in[1], (unsigned long long)in[2],
           (unsigned long long)in[3], (unsigned long long)in[4]);
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)out[0], (unsigned long long)out[1], (unsigned long long)out[2],
           (unsigned long long)out[3], (unsigned long long)out[4]);
    printf("    \"%s\"\n", label);
    printf(");\n\n");
}

// Full Ascon permutation: chains full_round() either 12 times (p^a) or
// 6 times (p^b, using round-constant indices 6..11 -- the LAST 6 of p^a).
// This is the reference for ascon_permutation.sv.
static std::array<u64,5> permutation(std::array<u64,5> x, int num_rounds) {
    int start_round = 12 - num_rounds;
    for (int r = start_round; r < 12; r++)
        x = full_round(x, r);
    return x;
}

static void print_perm_vector(const char* label, int num_rounds, std::array<u64,5> in, std::array<u64,5> out) {
    printf("// %s (%d rounds)\n", label, num_rounds);
    printf("check_perm_vector(4'd%d,\n", num_rounds);
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)in[0], (unsigned long long)in[1], (unsigned long long)in[2],
           (unsigned long long)in[3], (unsigned long long)in[4]);
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)out[0], (unsigned long long)out[1], (unsigned long long)out[2],
           (unsigned long long)out[3], (unsigned long long)out[4]);
    printf("    \"%s\"\n", label);
    printf(");\n\n");
}

// Fixed IV constant for Ascon-128 (a=12, b=6, rate=64, key=128, tag=128)
static const u64 ASCON128_IV = 0x80400c0600000000ULL;

// Ascon-128 initialization: load IV/key/nonce, run p^a once, XOR key
// back into x3/x4. This is the reference for ascon_init.sv.
static std::array<u64,5> init(u64 key_hi, u64 key_lo, u64 nonce_hi, u64 nonce_lo) {
    std::array<u64,5> x = { ASCON128_IV, key_hi, key_lo, nonce_hi, nonce_lo };
    x = permutation(x, 12);
    x[3] ^= key_hi;
    x[4] ^= key_lo;
    return x;
}

static void print_init_vector(const char* label, u64 key_hi, u64 key_lo,
                               u64 nonce_hi, u64 nonce_lo, std::array<u64,5> out) {
    printf("// %s\n", label);
    printf("check_init_vector(\n");
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)key_hi, (unsigned long long)key_lo,
           (unsigned long long)nonce_hi, (unsigned long long)nonce_lo);
    printf("    64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX, 64'h%016llX,\n",
           (unsigned long long)out[0], (unsigned long long)out[1], (unsigned long long)out[2],
           (unsigned long long)out[3], (unsigned long long)out[4]);
    printf("    \"%s\"\n", label);
    printf(");\n\n");
}

// Build a padded 64-bit block: keep the first `bytes` real bytes (byte 0 =
// MSB), set the next byte to 0x80, zero-fill the rest. bytes in 0..7.
static u64 pad_block(u64 data, int bytes) {
    u64 out = 0;
    for (int j = 0; j < 8; j++) {
        int shift = 56 - 8*j; // byte j occupies bits [63-8j : 56-8j]
        if (j < bytes) {
            u64 byte_val = (data >> shift) & 0xFFULL;
            out |= byte_val << shift;
        } else if (j == bytes) {
            out |= (u64)0x80 << shift;
        }
        // else: stays 0
    }
    return out;
}

struct AdBlock { u64 data; bool is_last; int bytes; };

// Ascon-128 associated-data absorption -- mirrors ascon_ad_absorb.sv's
// protocol exactly (same per-block padding + permutation + domain
// separator), so this checks the RTL's wiring/sequencing, not just the math.
static std::array<u64,5> ad_absorb(std::array<u64,5> x, bool has_ad,
                                    const std::vector<AdBlock>& blocks) {
    if (!has_ad) return x; // skip entirely, no domain separator

    for (const auto& b : blocks) {
        u64 padded = b.is_last ? pad_block(b.data, b.bytes) : b.data;
        x[0] ^= padded;
        x = permutation(x, 6);
    }
    x[4] ^= 1ULL; // domain separator: mark transition to plaintext phase
    return x;
}

static void print_state(const char* prefix, std::array<u64,5> s) {
    printf("%s: %016llX %016llX %016llX %016llX %016llX\n", prefix,
           (unsigned long long)s[0], (unsigned long long)s[1], (unsigned long long)s[2],
           (unsigned long long)s[3], (unsigned long long)s[4]);
}

struct PtResult {
    std::array<u64,5> final_state;
    std::vector<u64> ct_blocks;   // ciphertext, one entry per block (unmasked by byte count)
    std::vector<int> ct_bytes;    // real byte count per block (8 except possibly the last)
};

// Ascon-128 plaintext processing -- mirrors ascon_pt_process.sv's protocol:
// XOR each (padded, if last) block into x0 -> that's the ciphertext block ->
// run p^b UNLESS this was the last block (no permutation follows the final
// plaintext block).
static PtResult pt_process(std::array<u64,5> x, const std::vector<AdBlock>& blocks) {
    PtResult r;
    for (size_t i = 0; i < blocks.size(); i++) {
        const auto& b = blocks[i];
        u64 padded = b.is_last ? pad_block(b.data, b.bytes) : b.data;
        u64 ct = x[0] ^ padded;
        r.ct_blocks.push_back(ct);
        r.ct_bytes.push_back(b.is_last ? b.bytes : 8);
        x[0] = ct;
        if (!b.is_last)
            x = permutation(x, 6);
    }
    r.final_state = x;
    return r;
}

struct CtBlock { u64 data; bool is_last; int bytes; }; // received ciphertext blocks

struct CtResult {
    std::array<u64,5> final_state;
    std::vector<u64> pt_blocks;   // recovered plaintext, one entry per block
    std::vector<int> pt_bytes;    // real byte count per block (8 except possibly the last)
};

// Ascon-128 ciphertext processing (decryption) -- the mirror image of
// pt_process(): mirrors ascon_ct_process.sv's protocol. For a full (non-
// last) block: pt = x0 XOR ct, then x0 becomes the RECEIVED ciphertext
// block directly (not a recomputed XOR -- same value pt_process's x0 would
// have held, since pt_process set x0 <- ct there too), then run p^b.
//
// For the last (possibly partial) block, real bytes only: recovered
// plaintext byte j (j < bytes) = ct byte j XOR x0 byte j. The new state
// byte j (j < bytes) becomes the RECEIVED ciphertext byte (matching what
// pt_process's own x0 held after XORing in padded plaintext, since for
// those real-byte positions padded_pt[j] XOR x0[j] == ct[j] by
// construction). Byte `bytes` becomes x0's original byte XORed with the
// 0x80 pad marker (mirrors pt_process's padding byte exactly). Bytes past
// that stay as x0's original value, untouched (mirrors the zero-padding
// XOR, which is a no-op). No permutation follows the last block, same as
// pt_process.
static CtResult ct_process(std::array<u64,5> x, const std::vector<CtBlock>& blocks) {
    CtResult r;
    for (size_t i = 0; i < blocks.size(); i++) {
        const auto& b = blocks[i];
        if (!b.is_last) {
            u64 pt = x[0] ^ b.data;
            r.pt_blocks.push_back(pt);
            r.pt_bytes.push_back(8);
            x[0] = b.data;
            x = permutation(x, 6);
        } else {
            u64 x0_before = x[0];
            u64 pt = 0, x0_new = 0;
            for (int j = 0; j < 8; j++) {
                int shift = 56 - 8*j;
                u64 x0_byte = (x0_before >> shift) & 0xFFULL;
                if (j < b.bytes) {
                    u64 ct_byte = (b.data >> shift) & 0xFFULL;
                    pt     |= (ct_byte ^ x0_byte) << shift;
                    x0_new |= ct_byte << shift;
                } else if (j == b.bytes) {
                    x0_new |= (x0_byte ^ 0x80ULL) << shift;
                } else {
                    x0_new |= x0_byte << shift;
                }
            }
            r.pt_blocks.push_back(pt);
            r.pt_bytes.push_back(b.bytes);
            x[0] = x0_new;
        }
    }
    r.final_state = x;
    return r;
}

// Ascon-128 finalization -- mirrors ascon_finalize.sv's protocol: XOR the
// key into x1/x2, run the full 12-round permutation (p^a) once, then XOR
// the key into x3/x4. The tag is the resulting {x3, x4} (128 bits).
struct FinalResult { std::array<u64,5> final_state; u64 tag_hi; u64 tag_lo; };

static FinalResult finalize(std::array<u64,5> x, u64 key_hi, u64 key_lo) {
    x[1] ^= key_hi;
    x[2] ^= key_lo;
    x = permutation(x, 12);
    x[3] ^= key_hi;
    x[4] ^= key_lo;
    FinalResult r;
    r.final_state = x;
    r.tag_hi = x[3];
    r.tag_lo = x[4];
    return r;
}

static void print_finalize_case(const char* label, std::array<u64,5> in,
                                 u64 key_hi, u64 key_lo, const FinalResult& r) {
    printf("// %s\n", label);
    print_state("state_in", in);
    printf("key_hi=0x%016llX key_lo=0x%016llX\n",
           (unsigned long long)key_hi, (unsigned long long)key_lo);
    print_state("final_state", r.final_state);
    printf("tag = 0x%016llX%016llX\n\n",
           (unsigned long long)r.tag_hi, (unsigned long long)r.tag_lo);
}

int main() {
    printf("=== add_rc vectors ===\n");
    u64 sample_x2_values[3] = {
        0x0000000000000000ULL,
        0xFFFFFFFFFFFFFFFFULL,
        0x123456789ABCDEF0ULL
    };
    for (int round = 0; round < 12; round++) {
        print_add_rc_vector(round, sample_x2_values[round % 3]);
    }
    printf("\n=== diffusion vectors ===\n");

    // Same 5 test cases used before, now generated from the C++ model.
    std::array<std::array<u64,5>,5> test_inputs = {{
        {0x0000000000000000ULL, 0x0000000000000000ULL, 0x0000000000000000ULL,
         0x0000000000000000ULL, 0x0000000000000000ULL},
        {0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL,
         0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL},
        {0x0123456789ABCDEFULL, 0xFEDCBA9876543210ULL, 0x1111111111111111ULL,
         0xAAAAAAAAAAAAAAAAULL, 0x5555555555555555ULL},
        {0x8000000000000000ULL, 0x0000000000000001ULL, 0xDEADBEEFCAFEBABEULL,
         0x0F0F0F0F0F0F0F0FULL, 0xF0F0F0F0F0F0F0F0ULL},
        {0x0102030405060708ULL, 0x1122334455667788ULL, 0x9988776655443322ULL,
         0xA5A5A5A5A5A5A5A5ULL, 0x5A5A5A5A5A5A5A5AULL},
    }};

    const char* labels[5] = {
        "all-zero", "all-ones", "mixed-pattern-1", "mixed-pattern-2", "mixed-pattern-3"
    };

    for (int i = 0; i < 5; i++) {
        auto out = diffusion(test_inputs[i]);
        print_vector(labels[i], test_inputs[i], out);
    }

    printf("\n=== full round vectors ===\n");
    // Ascon's real initial state after key/nonce loading is never all-zero
    // or all-one in practice, but for verifying the round's mechanics any
    // fixed input is fine -- what matters is that add_rc, sbox, and
    // diffusion are chained in the right order with the right round
    // constant.
    std::array<u64,5> iv_like = {
        0x0000000080400c06ULL, 0x0001020304050607ULL, 0x08090a0b0c0d0e0fULL,
        0x1011121314151617ULL, 0x18191a1b1c1d1e1fULL
    };
    print_round_vector("round-0-iv-like", 0, iv_like, full_round(iv_like, 0));

    for (int i = 0; i < 5; i++) {
        auto out = full_round(test_inputs[i], i % 12);
        print_round_vector(labels[i], i % 12, test_inputs[i], out);
    }

    printf("\n=== permutation vectors ===\n");
    print_perm_vector("iv-like-p_a", 12, iv_like, permutation(iv_like, 12));
    print_perm_vector("iv-like-p_b", 6,  iv_like, permutation(iv_like, 6));

    for (int i = 0; i < 5; i++) {
        print_perm_vector(labels[i], 12, test_inputs[i], permutation(test_inputs[i], 12));
    }
    for (int i = 0; i < 3; i++) {
        print_perm_vector(labels[i], 6, test_inputs[i], permutation(test_inputs[i], 6));
    }

    printf("\n=== init vectors ===\n");
    print_init_vector("placeholder-key-nonce-1", 0x0001020304050607ULL, 0x08090A0B0C0D0E0FULL,
                       0x0102030405060708ULL, 0x090A0B0C0D0E0F00ULL,
                       init(0x0001020304050607ULL, 0x08090A0B0C0D0E0FULL,
                            0x0102030405060708ULL, 0x090A0B0C0D0E0F00ULL));
    print_init_vector("all-zero-key-nonce", 0, 0, 0, 0, init(0,0,0,0));
    print_init_vector("all-ones-key-nonce", ~0ULL, ~0ULL, ~0ULL, ~0ULL,
                       init(~0ULL, ~0ULL, ~0ULL, ~0ULL));

    printf("\n=== AD absorb test cases ===\n");
    // Use a fixed post-init state as the starting point for each AD test.
    std::array<u64,5> base_state = init(0x0001020304050607ULL, 0x08090A0B0C0D0E0FULL,
                                         0x0102030405060708ULL, 0x090A0B0C0D0E0F00ULL);
    print_state("base_state (after init)", base_state);
    printf("\n");

    // Case 1: no AD at all
    {
        auto out = ad_absorb(base_state, false, {});
        printf("// Case 1: has_ad = 0 (no AD at all)\n");
        printf("// expect x_out == x_in unchanged:\n");
        print_state("expected", out);
        printf("\n");
    }

    // Case 2: single partial block, 3 real bytes
    {
        std::vector<AdBlock> blocks = {
            {0x0102030000000000ULL, true, 3}
        };
        auto out = ad_absorb(base_state, true, blocks);
        printf("// Case 2: single block, 3 real bytes (0x01,0x02,0x03), is_last=1\n");
        printf("// block_data=0x%016llX block_is_last=1 block_bytes=3\n", (unsigned long long)blocks[0].data);
        print_state("expected", out);
        printf("\n");
    }

    // Case 3: exact-multiple case -- one full block, then a pure-padding block
    {
        std::vector<AdBlock> blocks = {
            {0x0001020304050607ULL, false, 0}, // full block, not last
            {0x0000000000000000ULL, true, 0}   // pure padding block
        };
        auto out = ad_absorb(base_state, true, blocks);
        printf("// Case 3: one full 8-byte block (is_last=0), then pure-padding block (is_last=1, bytes=0)\n");
        printf("// block1: block_data=0x%016llX block_is_last=0\n", (unsigned long long)blocks[0].data);
        printf("// block2: block_data=(don't care) block_is_last=1 block_bytes=0\n");
        print_state("expected", out);
        printf("\n");
    }

    // Case 4: two full blocks then a 5-byte partial final block
    {
        std::vector<AdBlock> blocks = {
            {0x0001020304050607ULL, false, 0},
            {0x08090A0B0C0D0E0FULL, false, 0},
            {0x1011121314000000ULL, true, 5}
        };
        auto out = ad_absorb(base_state, true, blocks);
        printf("// Case 4: two full blocks, then a 5-byte partial final block\n");
        printf("// block1: block_data=0x%016llX block_is_last=0\n", (unsigned long long)blocks[0].data);
        printf("// block2: block_data=0x%016llX block_is_last=0\n", (unsigned long long)blocks[1].data);
        printf("// block3: block_data=0x%016llX block_is_last=1 block_bytes=5\n", (unsigned long long)blocks[2].data);
        print_state("expected", out);
        printf("\n");
    }

    // --- Plaintext processing test cases ---
    printf("\n=== plaintext processing test cases ===\n");
    std::array<u64,5> pt_base = ad_absorb(base_state, true, {
        {0x0102030000000000ULL, true, 3}
    });
    print_state("pt_base (state after AD absorb)", pt_base);
    printf("\n");

    // Case A: single partial block (short message, 4 bytes)
    {
        std::vector<AdBlock> blocks = { {0x4142434400000000ULL, true, 4} }; // "ABCD"
        auto r = pt_process(pt_base, blocks);
        printf("// Case A: single partial block, 4 real bytes (\"ABCD\")\n");
        printf("// block_data=0x%016llX block_is_last=1 block_bytes=4\n", (unsigned long long)blocks[0].data);
        printf("ct[0] = 0x%016llX (bytes=%d)\n", (unsigned long long)r.ct_blocks[0], r.ct_bytes[0]);
        print_state("final_state", r.final_state);
        printf("\n");
    }

    // Case B: one full block then a 6-byte partial final block
    {
        std::vector<AdBlock> blocks = {
            {0x0011223344556677ULL, false, 0},
            {0x8899AABBCCDD0000ULL, true, 6}
        };
        auto r = pt_process(pt_base, blocks);
        printf("// Case B: one full block, then a 6-byte partial final block\n");
        printf("// block1: block_data=0x%016llX block_is_last=0\n", (unsigned long long)blocks[0].data);
        printf("// block2: block_data=0x%016llX block_is_last=1 block_bytes=6\n", (unsigned long long)blocks[1].data);
        printf("ct[0] = 0x%016llX (bytes=%d)\n", (unsigned long long)r.ct_blocks[0], r.ct_bytes[0]);
        printf("ct[1] = 0x%016llX (bytes=%d)\n", (unsigned long long)r.ct_blocks[1], r.ct_bytes[1]);
        print_state("final_state", r.final_state);
        printf("\n");
    }

    // Case C: exact-multiple case -- one full block then pure-padding block
    std::array<u64,5> pt_case_c_final;
    {
        std::vector<AdBlock> blocks = {
            {0xAABBCCDDEEFF0011ULL, false, 0},
            {0x0000000000000000ULL, true, 0}
        };
        auto r = pt_process(pt_base, blocks);
        printf("// Case C: one full block, then pure-padding block (empty final block)\n");
        printf("// block1: block_data=0x%016llX block_is_last=0\n", (unsigned long long)blocks[0].data);
        printf("// block2: block_data=(don't care) block_is_last=1 block_bytes=0\n");
        printf("ct[0] = 0x%016llX (bytes=%d)\n", (unsigned long long)r.ct_blocks[0], r.ct_bytes[0]);
        printf("ct[1] = 0x%016llX (bytes=%d)\n", (unsigned long long)r.ct_blocks[1], r.ct_bytes[1]);
        print_state("final_state", r.final_state);
        printf("\n");
        pt_case_c_final = r.final_state;
    }

    // --- Finalization test cases ---
    // --- Ciphertext processing (decryption) test cases: round-trip each ---
    // ---  pt_process case through ct_process and confirm it inverts it ---
    printf("\n=== ciphertext processing (decryption) test cases ===\n");

    auto check_roundtrip = [](const char* label,
                               const std::vector<u64>& orig_pt_data,
                               const std::vector<int>& orig_pt_bytes,
                               const PtResult& enc,
                               std::array<u64,5> pt_base_state) {
        std::vector<CtBlock> ct_blocks;
        for (size_t i = 0; i < enc.ct_blocks.size(); i++) {
            bool is_last = (i == enc.ct_blocks.size() - 1);
            ct_blocks.push_back({enc.ct_blocks[i], is_last, enc.ct_bytes[i]});
        }
        auto dec = ct_process(pt_base_state, ct_blocks);

        printf("// %s\n", label);
        bool ok = true;
        for (size_t i = 0; i < dec.pt_blocks.size(); i++) {
            // Only the real bytes of the recovered plaintext are meaningful;
            // mask both sides to that width before comparing.
            u64 mask = (dec.pt_bytes[i] >= 8) ? ~0ULL
                       : ((1ULL << (8*dec.pt_bytes[i])) - 1) << (64 - 8*dec.pt_bytes[i]);
            u64 got  = dec.pt_blocks[i] & mask;
            u64 want = orig_pt_data[i] & mask;
            printf("pt[%zu] = 0x%016llX (bytes=%d)%s\n", i,
                   (unsigned long long)dec.pt_blocks[i], dec.pt_bytes[i],
                   (got == want) ? "" : "  <-- MISMATCH vs original plaintext");
            if (got != want) ok = false;
        }
        print_state("recovered final_state", dec.final_state);
        print_state("expected  final_state", enc.final_state);
        if (dec.final_state != enc.final_state) ok = false;
        printf("round-trip: %s\n\n", ok ? "OK" : "FAILED");
    };

    // Case A round-trip: single partial block (4 bytes)
    {
        std::vector<AdBlock> blocks = { {0x4142434400000000ULL, true, 4} };
        auto enc = pt_process(pt_base, blocks);
        check_roundtrip("Case A round-trip (single 4-byte partial block)",
                         {0x4142434400000000ULL}, {4}, enc, pt_base);
    }

    // Case B round-trip: one full block, then a 6-byte partial final block
    {
        std::vector<AdBlock> blocks = {
            {0x0011223344556677ULL, false, 0},
            {0x8899AABBCCDD0000ULL, true, 6}
        };
        auto enc = pt_process(pt_base, blocks);
        check_roundtrip("Case B round-trip (full block + 6-byte partial)",
                         {0x0011223344556677ULL, 0x8899AABBCCDD0000ULL}, {8, 6}, enc, pt_base);
    }

    // Case C round-trip: one full block, then a pure-padding empty final block
    {
        std::vector<AdBlock> blocks = {
            {0xAABBCCDDEEFF0011ULL, false, 0},
            {0x0000000000000000ULL, true, 0}
        };
        auto enc = pt_process(pt_base, blocks);
        check_roundtrip("Case C round-trip (full block + empty final block)",
                         {0xAABBCCDDEEFF0011ULL, 0x0000000000000000ULL}, {8, 0}, enc, pt_base);
    }

    printf("\n=== finalization test cases ===\n");
    u64 fkey_hi = 0x0001020304050607ULL;
    u64 fkey_lo = 0x08090A0B0C0D0E0FULL;

    // Case 1: chained directly off PT case C's final state (realistic flow:
    // init -> AD absorb -> pt process -> finalize, all with the same key)
    {
        auto r = finalize(pt_case_c_final, fkey_hi, fkey_lo);
        print_finalize_case("Case 1: chained off pt_process Case C (same key as init)",
                             pt_case_c_final, fkey_hi, fkey_lo, r);
    }

    // Case 2: all-zero state, all-zero key (edge case)
    {
        std::array<u64,5> zero_state = {0,0,0,0,0};
        auto r = finalize(zero_state, 0, 0);
        print_finalize_case("Case 2: all-zero state, all-zero key", zero_state, 0, 0, r);
    }

    // Case 3: all-ones state, all-ones key (edge case)
    {
        std::array<u64,5> ones_state = {~0ULL, ~0ULL, ~0ULL, ~0ULL, ~0ULL};
        auto r = finalize(ones_state, ~0ULL, ~0ULL);
        print_finalize_case("Case 3: all-ones state, all-ones key", ones_state, ~0ULL, ~0ULL, r);
    }

    // Case 4: mixed pattern state/key, different from the key used to reach this state
    {
        std::array<u64,5> mixed_state = {
            0x0BA6F87BEDA3E0EDULL, 0x07BF46E83B6D3C12ULL, 0xEC4DE48E27356A18ULL,
            0x931B0525B74EC2EDULL, 0xBC7E72032A4134FBULL
        };
        u64 k_hi = 0xDEADBEEFCAFEBABEULL, k_lo = 0x1122334455667788ULL;
        auto r = finalize(mixed_state, k_hi, k_lo);
        print_finalize_case("Case 4: mixed pattern state, different key", mixed_state, k_hi, k_lo, r);
    }

    return 0;
}
