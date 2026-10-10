# Original Euclidean polyline pcurve source/domain

## Scope

This unit supplies the complete original normalized UV polyline to existing
retained-curve charts and exact domain selection. The existing
`OriginalEuclideanPolylineParameterLaw` remains the sole arc-length producer;
its exact coefficient field, positive closed segments and original point indices
are retained. No root, station, UV, branch or tolerance is rounded or merged.
General surface-lift/rolling-ball dispatch, other source families, nonlinear
correspondence, M5/M6/M7/M8 and whole-seven/full87 acceptance remain open.

## Behavioral evidence

The actual original points include a repeated point, an irrational-length segment
and a folded final traversal. The first station is sqrt(2)/(sqrt(2)+2), independently
checked by t^2+2t-1=0 and its positive interval. Every original segment endpoint
evaluates to its authored UV; homogeneous Z/W are zero/one. Distinct derivative
germs at the first join remain distinct. The existing public numerical pcurve
evaluator is compared at five stations as a numerical regression, not as an
equality certificate.

| Contract | Counterexample/behavior |
|---|---|
| Complete source | Three positive segments, original indices 1/2/3; repeated source points remain retained |
| Exact coefficient ownership | Irrational station cannot be imported into a foreign rational field; rational values can |
| Existing retained charts/DI | All three charts, two incidents at both joins, chart cap one-less refusal |
| Request restriction | Singleton, strict interval, disconnected, empty and outside-support requests |
| Resources | Source and incident-query exact work/bytes succeed; each one-less fails with the original work/storage cause |
| Cancellation | Entry, intermediate and terminal checkpoints on source binding and incident query |
| Depth/invalid source | Insufficient coefficient depth, missing/single/repeated-only/nonfinite points refuse |
| Lifetime/COW | Source retained after input mutation and scope exit, then charts/domain/evaluation queried |

## Assembly and target locality

The runner freshly compiles the two new source files, four existing retained-curve
protocol/chart files and four existing retained-curve domain files. Generated files
only prepend imports of the unchanged original CADCore/CADGeometry child modules.
There is no symbol substitution, production access-control change or formula edit.
The original exact arc-length/coefficient/transport/cover implementations and
numerical evaluator are reused from generation-bound hash-admitted caches.
Their sources/products/logs are verified before and after execution through the
retained requested-order receipt. Changed source and fixtures are compiled with
ASAN in that lane; unchanged cached children are not newly sanitized.

All lanes use fixed Swift6.4.0 and matching normal/Embedded WASM SDKs. Every process
has a 120-second timeout. Accepted runtime is Native0.739s, ASAN0.858s,
normal-WASM0.382s and Embedded0.268s. Embedded link takes46.445s. The first WASM
link attempts omitted the SDK Clang resource option; those diagnostics and early
fixture error-normalization trials are preserved under `.build`, excluded from
accepted evidence. The corrected runner retains the original SDK linker options.
No broad CADCore/CADGeometry/Kernel or L2-L6 production rebuild is performed.

## Stable scoped review

One stable review checks original parameter meaning, all positive segments,
coefficient provenance, complete support, unequal germs, proof-depth retention,
count/storage/work accounting, source binding and terminal cancellation. Failure
normalization is checked at both direct scalar and polynomial-wrapped scalar
boundaries without swallowing a different error. No scoped production finding
remains. No existing incomplete-implementation marker is removed.

| State | Native | Normal WASM | Embedded | Ownership/access |
|---|---|---|---|---|
| Source points/law/field | Immutable | Same | Same | Retained COW input and exact context |
| Positions/bounds | Immutable | Same | Same | Owned result arrays; caller pays allocations |
| Construction scratch | Invocation-local | Same | Same | No shared mutation or callback retention |
| Admission | Exclusive local borrow | Same | Same | Existing scoped forwarding contract |

No production shared mutable state, new unsafe boundary, unchecked Sendable or
target-specific synchronization/conformance branch is introduced. Accepted logs
contain no Swift warnings/errors, sanitizer failures, null calls or signature
mismatches. Evidence/acceptance.json binds the four receipts and owned inputs.
Independent latest-main comparison and fresh Native/Embedded runtimes are recorded
in Evidence/main-integration; final delivery is recorded in main-delivery.json.
