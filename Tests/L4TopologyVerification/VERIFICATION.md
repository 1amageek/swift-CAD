# Independent L4 implementation evidence

## Scope and snapshot

Original implementation: `49eff264`, verified on 2026-10-07. Its user-requested
work-accounting repair is verified on 2026-10-08 in the same independent worktree,
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
| Repair regressions before modification | Two tests failed against 49eff264; exact budget and cancellation counterexamples reproduced |
| Focused repair regressions | Two tests passed, 0.004 seconds |
| Stable repaired Native full suite | 17 tests passed, 31.746 seconds |
| Stable repaired ASAN full suite | 17 tests passed, 70.094 seconds |
| Ordinary WASM proof, current fixtures | All 12 synchronous fixture routines passed |
| Embedded WASM proof, current fixtures | All 12 synchronous fixture routines passed |

All positive repair runs compile the same production snapshot. The focused green
checks exact work and cancellation boundaries; a universal-barrier regression was
then added to the same test and verified by both full 17-test suites. The retained
field test includes independent value/coefficient depth rejection. Historical
15-test and depth-recheck logs remain retained; their original inventory is in
49eff264. The fold test retains its two-minute Swift Testing annotation and the
external 120-second guard. No solver limit was relaxed.

## Work-accounting repair

| Finding | Before | Repair and new evidence |
|---|---|---|
| Unadmitted repeated quantifier suffix scans | 64 existential slots inspect 2,080 suffix entries at only 128 work | One admitted backward pass per matrix finds the final existential block. The no-equality fixture consumes exactly 192 work, rejects 191, and cancels before its first quantifier read |
| Unadmitted absent boundary visits | An issued R^16 cell inspects 48 absent candidates at preparation-only 24 work | Every section/lower/upper candidate consumes work before access. This fixture consumes exactly 72, rejects 71, and cancels on the first candidate after preparation |

WorkAdmissionTests covers empty, all-universal, mixed and 64-existential blocks,
plus R^0/R^1/R^4/R^16 definitions issued by L3. The mixed relation
`exists x0: forall x1: exists x2: x0-x1=0 AND x2=0` permits eliminating only x2;
the universal barrier and original variable mapping remain intact.
WorkCancellationAdmission is a query-local noncopyable test admission, not shared
state. Both Native and ASAN run these regressions. Portable proofs exercise the
changed operations through the existing public success/failure paths.

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
| Independent limits | Exact work/storage boundary succeeds and one-less fails; quantifier and absent-boundary visits have separate exact/cancel boundaries; root/generated-cell/closure/piece/component limits reject; checked count overflow rejects | zeroAndFailures, resourcesAndCancellation, WorkAdmissionTests, checkedCountOverflow |
| Atomic cancellation | First, middle and final checkpoint rejection publishes no incidence; fresh valid calls succeed after failures; empty incidence/components succeed | resourcesAndCancellation |
| Concurrent readers | Eight immutable Native readers each use their own noncopyable admission and return true | concurrentRetainedReaders |

WASM proofs exercise public synchronous calls, including both depth failures.
Generic differential, concurrency, internal admission repair and checked-overflow tests are Native/ASAN
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
| Cumulative source → incidence → components | 15,504,705 work; 573,605,781 bytes | 15,327,667 work; 288,429,097 bytes |
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

The initial cumulative review closed filtered-traversal omissions. The later
user-requested review found the two additional concrete counterexamples above.
One targeted repair review confirmed admission-before-read, equivalence of the
final-block boundary and preservation of quantifier scope after substitution.
The failing-before regressions, focused green and final Native/ASAN suites plus
both public WASI proofs close those findings. The folded query admits 540 more
work on each target (45 closures, 12 boundary visits each); storage and all caps
remain unchanged. Lower sources are byte-identical and their evidence is reused.
The source scan contains only isolated verification import conditions, local
mutable temporaries and computed counts: no Embedded raw-state branch, unsafe
pointer, unchecked Sendable, try?, shared mutable cache or incomplete marker was
introduced. No unresolved concrete scoped review finding remains.
