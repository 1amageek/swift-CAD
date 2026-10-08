# Complete L2/L3 Convergence Evidence

## Scope and Snapshot

Verified 2026-10-08 on `codex/l2-l3-selected-root-convergence`, based on preserved
upper snapshot `b7cc13e4`. Stages S0–S4 are commits `6beb5a55`, `e533ca2a`,
`2471b28c`, `5d115bc1`, `1b91d41e`; S5 completes the source-bound snapshot in
[sources.json](sources.json). This report supersedes earlier verification claims
only for this twenty-requirement L2/L3 task. Historical optimization/inspection
reports retain their original, narrower scope.

The production package graph, external dependencies and L0/L1 production sources
are unchanged by this task. Builds compile only the independent L0–L3 graph.
L4 closure/incidence, L5/L6 integration, original-geometry producers, geometric
publication and the seven upper requirements are separate completion decisions.

## Requirement Evidence

The authoritative contracts and implementation owners are the matrices in
[L2 DESIGN](../../../Sources/CADGeometry/RationalBivariateAlgebra/ExactRealRoot/DESIGN.md)
and [L3 DESIGN](../../../Sources/CADGeometry/RationalBivariateAlgebra/ExactRealCell/DESIGN.md).
Paths below name behavioral fixtures in the combined package; the same synchronous
fixture implementations execute on both WASI targets.

| ID | Public behavior exercised | Fixture evidence |
|---|---|---|
| L2-01 | Original law, selected variable, retained owner | RootFixtures, EdgeFixtures, TransportFixtures |
| L2-02 | Exact finite/infinite/open/closed/singleton domain | RootFixtures.domains, SignedDecisionFixtures |
| L2-03 | Complete roots, original multiplicities and empty exclusion | RootFixtures, CountReuseFixtures.verify/factored |
| L2-04 | Exact original identity and global rank | SignedDecisionFixtures, CountReuseFixtures, TransportFixtures |
| L2-05 | Signed remainders, shared signs, exact near-root order | SignedDecisionFixtures |
| L2-06 | Local inverse and immutable common calculation laws | LocalLawFixtures, FieldFixtures.denominatorUnits/reducible |
| L2-07 | Runtime tower, explicit self/ancestor root transfer | FieldFixtures.tower, TransportFixtures |
| L2-08 | Certified refinement, strict separator, selected smaller law | SeparationFixtures, RootFixtures.definingDivisorRefinement/exactCandidateCompletion |
| L2-09 | Count reuse, complete small factors, shared query owner | CountReuseFixtures.verify/factored, SignedDecisionFixtures |
| L2-10 | Retained lifetime and independent limits/cancel | EdgeFixtures, TransportFixtures, SeparationFixtures, failure fixtures |
| L3-01 | Original order, duplicates, box, predicate indices | CellTests.projectionAndSource/sourceFailures, ProjectionProofFixtures |
| L3-02 | Indexed PSC, normalization and reductum identities | ProjectionProofFixtures, CellTests.projectionAndSource |
| L3-03 | Parent conditions, degree drop, whole-fiber nullification | CellFixtures.nullification, ProjectionProofFixtures, InspectionFixtures |
| L3-04 | Whole-parent conditions and non-sample root correspondence | PrefixFixtures, InspectionFixtures, ProjectionProofFixtures |
| L3-05 | All sections/sectors, original root membership/multiplicity | CellFixtures.singularities, ProjectionProofFixtures, WeightedOriginalFixtures |
| L3-06 | Complete finite/infinite box, false cells and R0 | CellFixtures.domains, QueryFixtures, PrefixFixtures |
| L3-07 | Original sign invariant and selection | SignInvariantFixtures, QueryFixtures.selectionAndLocation |
| L3-08 | Definitions, every prefix length, exact membership/location | PrefixFixtures, InspectionFixtures, QueryFixtures |
| L3-09 | Proof reuse with exact law/prefix correspondence | QueryFixtures.algebraicQueries/nullifiedQuery, PrefixFixtures, WeightedOriginalFixtures |
| L3-10 | Same cumulative admission, limits, cancellation and ownership | FailureFixtures, VisitAdmissionFixtures, TerminalAdmission, Native concurrentImmutableReaders |

Whole-cell guarantees follow the retained full projection/lifting proof chain.
Extra samples detect counterexamples; they do not replace that chain. Projection
conditions, cut laws and derivative support remain distinct. The original cut
multiplicity matrix is not replaced by radical-union multiplicity. Public views
retain immutable owners without storing self-retaining handles in those owners.

## Mandatory Recorded Performance Input

The original weighted curve has `C=(2t−1,1/4,(2t−1)^2)`. Its surface is
`(X,Y,0)/W`, where `W=1+u/2+v−3uv/2`, `X=−2+5u−2v+uv`,
`Y=−2−u+6v−uv`. [WeightedOriginalFixtures](../Sources/Fixtures/WeightedOriginalFixtures.swift)
checks all original homogeneous equations, exact division by nonzero W, the
identity `4(t−1/2)^2` and every original=quotient*factor+remainder identity.
It consumes the recorded proof-reduced L3 laws `[-X,W/4−Y,0,1,W,t−1/2]`,
retaining all three original closed unit domains and both nonzero guards.
A raw sign partition before those proven reductions is a different workload;
its exploratory failure is not counted as this mandatory input's completion.

The corrected input exhausted work16,777,213 before the S5 factor reuse. L3 now
extracts disjoint small factors of its retained union; L2 independently checks
issuer/variable, coprimality, exact divisions and nonzero constant remainder before
issuing Count. Existing isolate(count) then preserves original source, global
ordinal and multiplicity. There is no fallback after resource or proof failure.
Missing, overlapping and foreign factors fail; N/N−1 work/storage and terminal
cancel execute. No caller ceiling was increased.

| Configuration | Work / 16,777,216 | Cumulative admitted storage bytes | Value/coefficient depth / 32 | Complete full cells / selected |
|---|---:|---:|---|---|
| Native / ASAN | 2,409,963 | 103,174,098 | 28 / 0 | 245 / one isolated point |
| Normal / Embedded WASI | 2,382,027 | 52,195,146 | 28 / 0 | 245 / one isolated point |

The fixture uses a 1GiB byte allowance, stricter than the original Native
Cell-stride allowance. Structural and extension ceilings remain Int.max as in
the recorded public query. These are cumulative logical payload counts, not RSS,
allocator-count measurements or a general wall-time improvement claim. The actual
three-stage coefficient-field tower also succeeds under work16,777,216/depth32.
The expected weighted point retains `t=1/2`, `u²−15u+8=0` in the closed unit
interval, and `9v+4u−7=0`; no nearby numerical points are merged.

## Executed Targets

| Target | Result | Evidence |
|---|---|---|
| Native debug | 70 tests: L3 27, L2 23, L1 8, L0 12 | [native.log](native.log) |
| Native Address Sanitizer | Same 70 tests; no sanitizer error | [asan.log](asan.log) |
| Normal WASM debug | Compile/link and combined synchronous proof, exit0 | [build](wasm-build.log), [runtime](wasm-runtime.log) |
| Embedded WASM debug | Compile/link and same proof, exit0 | [build](embedded-build.log), [runtime](embedded-runtime.log) |

All commands use the pinned Swift6.4.0 release executable
`/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`,
the matching `swift-6.4.0-RELEASE_wasm` and
`swift-6.4.0-RELEASE_wasm-embedded` SDKs, wasm32-unknown-wasip1,
and Node24.19.0 WASI Preview1. Embedded is WMO/Onone with the matching SDK's
Unicode archive. Actual build task-store markers are bound in
[compiler-configurations.json](compiler-configurations.json); Embedded mode is
not inferred from artifact size. Debug artifact size is not a performance claim.
Existing unused-rdynamic warnings remain; no signature mismatch or trap occurs.

The actual compiler file lists exactly match all production source directories
on all four targets: L0 49, L1 39, L2 43, L3 48; see
[compiled-sources.json](compiled-sources.json). There are no missing or extra
production files. 223 project input hashes bind the compiled sources, fixtures,
test runners, package and guards. Eight SwiftPM generated entry records retain
one byte-identical compressed source in [generated-inputs.json](generated-inputs.json).
[logs.json](logs.json) binds the six final logs. Earlier failed diagnostics are
not final success evidence.

Each build/test/runtime uses `scripts/swift-test-timeout.sh 120 --`, dedicated
`.build/l3-native`, `.build/l3-asan`, `.build/l3-wasm`, `.build/l3-embedded` caches
and two build jobs. WASI runs `scripts/run_wasi_smoke.mjs` on the raw L3Proof.wasm.
An Embedded fixture key-path compile rejection was corrected to the same static
closure reads; all final targets were executed from the corrected fixture snapshot.

## Ownership, Review and Integration Boundary

| Logical state | Native / normal WASM / Embedded contract |
|---|---|
| Original sources, fields, selected roots, laws | Same immutable Sendable owners; retain original identities and causal depths |
| New factor/count/sign/projection/stack evidence | Same immutable owner-backed values/views; no ARC owner cycle |
| Temporary polynomial/count/factor buffers | Invocation-local exclusive construction, checked admission before payload generation |
| Caller budget | Same inout/scoped forwarding owner; not stored in results, reset, escaped or shared across tasks |
| Query concurrency | Independent caller ledgers; Native immutable-reader test executes concurrently |

No target-conditional raw mutable storage, Sendable weakening, new lock or unsafe
pointer escape is introduced. Production L2/L3 have no Embedded-specific state
branch. Existing scoped bridges remain nonescaping; ASAN and both WASI runtimes
exercise success and failure. Synchronous WASI does not establish parallel WASM
thread/runtime semantics, and no new shared mutable state depends on such a claim.

One overall stable source review found no concrete contract defect. One scoped
recheck covered complete factor reuse and weighted reduction correspondence;
no scoped finding remains. The final combined graph establishes cumulative
L0–L3 integration only. Source changes outside the authorized L2/L3/design/test
scope are empty relative to b7cc13e4; preserved upper and Claude work is intact.
This branch has no upstream; no push or main integration is implied.

## Committed Lower-Graph Integration

Source commit `78a5fce3` contains the verified final production, fixture and package
snapshot. After commit, all project input and six log hashes match their Git
objects. The existing local WASI runner and timeout guard were not previously tracked;
their original bytes are retained in [external-inputs.json](external-inputs.json), so the same
223-input manifest remains fully inspectable. Generated entry bytes are retained
losslessly as gzip; decompression matches all eight generated-source hashes.
Compression preserves SwiftPM's original whitespace without changing any
compiled source. This integration record changes only evidence and progress.

The final combined Native/ASAN executions and both WASI runs already compose all
changed lower layers; their source-bound evidence remains valid. No source or
verification premise changed after those runs, so they are not repeated. Upper
source changes outside the fixed task scope remain empty relative to b7cc13e4.
