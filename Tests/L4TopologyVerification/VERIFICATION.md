# Independent L4 implementation evidence

## Scope and snapshot

Verified on 2026-10-07 in the independent worktree on
`codex/exact-real-cell-l3`. L3 inspection prerequisite: `2bd81a77`.
The source and fixture SHA-256 inventory is [Evidence/sources.json](Evidence/sources.json).
Build input inventories, artifact hashes and log hashes are in
[Evidence/run.json](Evidence/run.json). Logs are retained in this directory.

The standalone package compiles actual source directories through relative
symlinks: L0 (49), L1 (29), L2 (30), L3 (40), L4 (36) Swift files.
The production package graph and L0/L1/L2 implementations are unchanged.
L3 Swift sources are byte-identical to the inspection prerequisite. Existing
lower behavioral evidence remains applicable; the prerequisite separately
ran 50 combined Native/ASAN tests and both WASI proofs. No upper CAD target
was built, no new production dependency was introduced, and no main merge or
push occurred. These parameter-space receipts do not complete seven CAD requirements.

## Environment and execution

| Item | Fixed value |
|---|---|
| Compiler | Apple Swift 6.4 (`swift-6.4-RELEASE`), installed `swift-6.4.0-RELEASE.xctoolchain` |
| Native | arm64 macOS; package minimum macOS 14 |
| Ordinary WASM SDK | `swift-6.4.0-RELEASE_wasm` |
| Embedded WASM SDK | `swift-6.4.0-RELEASE_wasm-embedded` |
| WASM target | `wasm32-unknown-wasip1` |
| Runtime | Node.js 24.19.0, WASI Preview 1 |
| Timeout | `scripts/swift-test-timeout.sh 120 -- ...`, every build/test/runtime invocation |
| Scratch paths | `.build/l4-native`, `.build/l4-asan`, `.build/l4-wasm`, `.build/l4-embedded` |

Native command: `swift test --package-path Tests/L4TopologyVerification --build-path .build/l4-native -j 2`.
ASAN uses `.build/l4-asan` and `--sanitize address`.
Portable builds use `swift build --package-path Tests/L4TopologyVerification --build-path <path> --swift-sdk <SDK> --product L4Proof -j 2`.
Embedded links the matching SDK's `libswiftUnicodeDataTables.a`.
The runner is `node Tests/L1PolynomialVerification/Scripts/RunWASI.mjs <raw-L4Proof.wasm>`.
Full executable paths, arguments and input inventories are recorded in run.json.
Both portable builds emit only an unused `-rdynamic` warning, with no function-signature mismatch.

| Executed evidence | Result |
|---|---|
| Stable Native full suite | 15 tests passed, 31.172 seconds |
| Stable ASAN full suite | 15 tests passed, 70.180 seconds |
| Added independent value-depth regression | Focused Native and ASAN retained-field test passed, 0.357 / 0.820 seconds |
| Ordinary WASM proof, current fixtures | All 12 synchronous fixture routines passed |
| Embedded WASM proof, current fixtures | All 12 synchronous fixture routines passed |

The production snapshot is identical across these runs. After full-suite execution,
the retained-field fixture was extended to reject zero value depth independently
of coefficient depth. Its focused Native/ASAN rechecks and both complete portable
proofs cover that addition. The fold test's Swift Testing annotation was changed
from one to two minutes for ASAN; the external guard remains 120 seconds.
Native's prior full-suite behavior is reused for unchanged code. No solver limit
was relaxed for this annotation change.

## Public behavioral coverage

| Contract | Input and checked outcome | Fixture owner |
|---|---|---|
| Ambient closure | Open interval acquires both endpoints; rays acquire only the finite endpoint; singleton and R^0 remain closed | affineClosures, zeroAndFailures |
| Exact quantified closure | Forced quantified positive ray rejects -1 and includes 0/1; Native differential covers all three one-dimensional cells through four generic protocol ports | quantifiedClosure, differentialStrategiesAndPorts |
| Section graph | Positive branch of y²=x includes its origin and (4,2), excludes negative branch and negative x; retained applicability cover certifies unique weak fiber | graphClosure |
| Partial nullified target | For 0<x<1, 0<y<x, xz-y=0, closure at x=y=0 includes z=0/1 and rejects -1/2; polynomial-graph proof retains exact coordinate substitutions | partialTarget |
| Directed partial incidence | The preceding source meets a full nullified z-fiber in three refined pieces; reverse incidence is empty; combined selection has one component | partialIncidence |
| Excluded-point topology | x≠0 gives two components; xy=0 gives one; excluding its origin gives four | connectivity |
| Singular / mixed | Cusp, tangent branches and repeated factor each give one component; line plus isolated point gives two | singularComponents |
| Exact identity | Distinct points separated by 1/1,000,000 remain two components without attachments | closeDistinctPoints |
| Whole folded relation | Both sheets and meeting set retained; 45 selected cells, 108 attachment pieces, one component | folded |
| Owner retention | Query closures after source/provider lifetime ends; algebraic coefficient field retains level/cap 1; value and coefficient depths rejected independently | LifecycleFixtures.retained |
| Independent limits | Exact work/storage boundary succeeds and one-less fails; root/generated-cell/closure/piece/component limits reject; checked count overflow rejects | zeroAndFailures, resourcesAndCancellation, checkedCountOverflow |
| Atomic cancellation | First, middle and final checkpoint rejection publishes no incidence; fresh valid calls succeed after failures; empty incidence/components succeed | resourcesAndCancellation |
| Concurrent readers | Eight immutable Native readers each use their own noncopyable admission and return true | concurrentRetainedReaders |

WASM proofs exercise public synchronous calls, including both depth failures.
Generic differential, concurrency and internal checked-overflow tests are Native/ASAN
only; portable multithreading or shutdown races are not claimed. Applicable proof
selection and refusal use exact certificates. Started-processing failures propagate
through the same typed public boundary rather than retrying another solver.

## Folded phase measurements

Input: `x0²-x2²=0`, `x1-x3=0`, closed `[-1,1]^4`.
All calls keep 200M work, 700M admitted bytes and 400 for each depth axis.
Admitted storage is cumulative typed payload accounting, not resident memory.

| Phase | Native / ASAN | Ordinary / Embedded WASM |
|---|---|---|
| Complete original partition | 525 cells; 6,190,310 work; 141,394,189 bytes | Same counters |
| Selected original cells | 45 | 45 |
| Individual closure queries | All 45 prove point or affine closure and include their original samples; fresh explicit callers | Same public checks |
| Cumulative source → incidence → components | 15,504,165 work; 573,605,781 bytes | 15,327,127 work; 288,429,097 bytes |
| Final topology | 108 pieces; all 45 members; one component | Same result |

Architecture-dependent payload layouts and lower accounting produce different
admission totals; each target uses the same configured upper bounds. Exact affine
factor proofs and conditional sign-invariance proofs reuse the complete original
partition. Partial-target inputs instead retain complete refinements. Sampling is
used only after whole-cell invariance is certified, never to infer incidence.
This independent L4 result is not evidence for legacy SSI's separate 80M allowance.
The pre-existing two-level L3 `[1,2]^2` probe remains outside this repair.

## Ownership review and convergence

| Logical state | Native | WASM | Embedded | Mutation / release |
|---|---|---|---|---|
| Issued closure / region / incidence / components | Sendable structs with immutable arrays and retained lower owners | Same | Same | No public mutation; native ownership releases backing |
| Formula, quantifier decisions, component forest | Local Swift structs/arrays | Same | Same | Private synchronous inout mutation; no shared cache |
| Count state and admission | Per-call inout, noncopyable caller admission | Same | Same | One cumulative admission across nested operations; final checkpoint before publication |
| Retained lower proof storage | Immutable owner contract from verified L0-L3 | Same | Same | No new synchronization or unsafe boundary |

The one cumulative scoped review found work omissions in filtered traversal loops.
Those visits now consume work before filtering. The final full Native/ASAN and both
portable proofs include the correction. The two depth fixtures close the explicit
independent resource-axis evidence gap without changing production code.
The source scan contains only isolated verification import conditions, local
mutable temporaries and computed counts: no Embedded raw-state branch, unsafe
pointer, unchecked Sendable, try?, shared mutable cache or incomplete marker was
introduced. No unresolved concrete scoped review finding remains.
