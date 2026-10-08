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

## P3 Integration Review
L3 invokes the complete L1 sequence once per original reductum pair and consumes
all indices in order. Original first/second laws, eliminated axis and index remain
in each principal witness; insertion, derivative/reductum generation, selected
cells, closure and incidence are unchanged. The removed L3 determinant/individual
PSC functions have no production callers. Existing L3 white-box PSC tests now
use the L1 public port; matrix-size refusal belongs to the L1 kernel fixture and
is exercised through an Int.max-degree input with explicit countOverflow.

| State | Owner | Native / WASM / Embedded storage and access | Release / failure |
|---|---|---|---|
| Heap, cursor and chain scratch | Exclusive inout query | Same local Arrays and helpers; no shared mutation | Scope unwind and propagated typed failure |
| PSC working values | Exclusive query, then immutable sequence | Same Arrays, retained originals and full depth | Retained source contexts, normal ARC/value lifetime |
| L3 projection lists and witnesses | Exclusive borrowed query | Same local arrays and admission | Existing coverage/source owner and explicit failure |

All production declarations preserve Sendable and have no target-dependent
mutable storage or isolation. New fixture timing guards reflect the pinned
Embedded runtime's unavailable ContinuousClock; all exact oracle/failure code
is common. Embedded lower verification builds KernelProof and L4Proof explicitly,
without the existing Native-only LayerBenchmark product. Compile/link is followed
by target runtime verification. No production unsafe code, cache, locks or
parallel admission mutation were added.

Stable lower suite: 72 Native and 72 ASAN tests. Both portable lanes execute the
heap/PSC oracle and combined L0-L4 proof, including 45 folded members, 108 pieces
and one component. Full production Native and ASAN each pass five public tests;
portable preparation and legacy public smoke preserve success/empty/owner/resource
and cancellation contracts. Four compiler input inventories contain every one
of the 1,367 production CADCore/CADGeometry Swift sources. Public performance comparison is complete; latest-main identity remains the
publication condition.

## Accepted Performance Boundary
Three alternating fresh-process pairs on identical public fixture sources produce:

| Public whole process | Before median | After median | Change |
|---|---:|---:|---:|
| Native | 20.929 s | 21.342 s | +1.97% |
| Normal WASM | 30.498 s | 31.011 s | +1.68% |
| Embedded WASM | 17.568 s | 17.629 s | +0.35% |

All source membership, folded incidence, resource and authority assertions pass.
Every median increase is smaller than the observed baseline min/max spread;
these data support neither public acceleration nor universal non-regression.
The accepted claim is the measured local improvement with no degradation outside
observed variability on the fixed mandatory public fixtures. Process timings
include startup/assertions/failures and, for WASM, Node initialization.

The byte-identical LayerBenchmark body is rebuilt against the exact a0890f84
baseline in a separate cache and compared in three alternating pairs. L3's
quartic projection consumes 14,970 work and 644,508 generated bytes versus
67,659 and 2,172,108. L1 monomial and L2 singleton budgets are identical; folded
selection/incidence/components remain 45/108/1. The folded complete pipeline
is effectively unchanged: root lifting/partition and incidence dominate it.
No allocator/RSS, release-build or general geometry speedup is inferred.

L3 projection (three runs per sample) median: 0.038105 s -> 0.009936 s.
