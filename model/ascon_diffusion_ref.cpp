// ascon_diffusion_ref.cpp
// ---------------------------------------------------------------------------
// C++ golden-reference model for the Ascon linear diffusion layer.
// Independent from the SystemVerilog RTL — used to generate/verify golden
// test vectors, same role the Python version played earlier.
//
// Build:   g++ -std=c++17 -O2 -o ascon_diffusion_ref ascon_diffusion_ref.cpp
// Run:     ./ascon_diffusion_ref
// ---------------------------------------------------------------------------

#include <cstdint>
#include <cstdio>
#include <array>

using u64 = uint64_t;

// Right-rotate a 64-bit value by n bits (n in 1..63)
static inline u64 rotr(u64 v, int n) {
    return (v >> n) | (v << (64 - n));
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

    return 0;
}
