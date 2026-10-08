# Exact Heap / PSC Verification

## P1 Snapshot
Heap native fixture passes independent multivariable/rational/algebraic products,
exact cancellation, exponent overflow, work/storage/coefficient-depth limits and
terminal callback cancellation. The repaired equal-key chain/direct-separated
implementation is the accepted snapshot. First unchained-heap measurements are
retained as rejected performance evidence, not an acceleration claim.

KernelBenchmark executes five products per sample, with three alternating samples
for each input. Setup and exact reference checks are outside the timed region.
Reference expanded() reproduces the prior pre-admitted cartesian products and
canonical constructor. Both methods use the same fields, inputs and limits.

| Product | Old median | New median | Generated payload old -> new |
|---|---:|---:|---|
| 32x32 same axis | 0.017294s | 0.010337s | 775,720 -> 69,080 bytes |
| 32x32 separated axes | 0.009509s | 0.003975s | 737,280 -> 245,760 bytes |
| 32x32 alternating cancellation | 0.015145s | 0.010514s | 747,200 -> 45,280 bytes |

These are Swift 6.4.0 Native debug kernel timings and cumulative admitted typed
payloads. They are not real allocation/RSS counts or public geometry speedups.
Evidence: heap-native.log, heap-performance.log. One P1 source review verifies
canonical streams, chain cursor lifetime, checked maxima/counts, pre-admitted
scratch/growth, same owner/depth/terminal checks and no shared state. P2/P3 and
ASAN/WASM/Embedded remain pending. Lower unchanged source evidence is retained.

## P2 Snapshot
Complete public PSC sequence executes through its generic protocol witness. All
indices match determinant reference values; small cases also match independent
Laplace expansion built directly from original terms. Eighteen rational and
multivariate/content cases cover both variable axes; retained algebraic fields
cover both depth axes. Brown's 8,6,4,2,1,0 sequence verifies consecutive abnormal
normalizations and zero PSC indices 5/3. The explicit x^3+1 versus 2*x^2 oracle
returns [8,0], detecting missing full-prem leading-coefficient powers. Input
swap parity, common axis factors, zero/constants, invalid owner/axis, separate
work/storage, terminal cancellation and source/domain destruction are checked.
Zero PSC values carry the entire sequence proof depth, not their creation depth.
The recovered sqrt(2) source/result still has PSC [8,0] after all local owners
leave scope. Final Native PSC fixture passes in 0.143 seconds.

| PSC input | Matrix median / five runs | PRS median / five runs |
|---|---:|---:|
| Dense degrees 4,3 | 0.008306s | 0.001169s |
| Sparse degrees 4,4 | 0.003315s | 0.000215s |
| Degrees 2,1 | 0.000357s | 0.000183s |
| Linear pair, direct 2x2 | 0.000058s | 0.000115s |

Final operational selection is direct 2x2 for linear pairs and PRS otherwise.
Complete determinant reference is retained inside L1 for differential verification.
No matrix/PRS recovery runs after failure. Performance is specific to these
Native debug rational kernels; upper public and target evidence remains P3.
P2 review checks determinant orientation, full prem, degree-defect correction,
strict decreasing degrees, exact division, zero index/depth stamping, retained
owners and terminal checks. No open P2 correctness finding remains.
