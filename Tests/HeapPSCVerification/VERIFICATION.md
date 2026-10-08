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
