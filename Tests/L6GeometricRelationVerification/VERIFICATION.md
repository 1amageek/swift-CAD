# Independent L6 verification

Date: 2026-10-08. Branch: `codex/exact-geometric-l6`. Main base: `857750a2`.
Production sources live in CADGeometry's existing RationalBivariateAlgebra component;
verification builds only symlinked L0-L6 targets. No new production target or dependency.

## Verified scope

Finite closed original rational homogeneous CS/SSI laws and their retained L5
parameter relation. Source extraction and legacy Geometry public publication are
outside this independent implementation. This does not complete any whole-seven
requirement or establish a main merge.

| Execution path | Behavioral evidence |
|---|---|
| L4 pullback | Reordered coordinates; root/sector identities; repeated roots and negative leading signs; endpoint multiplicity change; invalid map |
| L6 CS | Isolated transversal/tangent points; original weighted overlap; constant XYZ with separate UV components; mixed ordinary and exceptional fibers; complete empty result; exact closed maximal t projection |
| L6 SSI | Crossing/coincident affine planes; constant image; folded maps with four exact parameter preimages; collapsed curves; complete empty result; full XYZ graph on a collapsed singleton slice |
| Exact station queries | XYZ, t, CS second-surface UV and both SSI UV stations; all distinct roots retained; wrong station and foreign coefficient family rejected |
| Ownership/admission | Result survives source scope; foreign stratum owner rejected; view retains the result's same immutable owner; scoped Span borrow; independent work/storage/value/coefficient-depth, stratum/span/cell limits; final cancellation for nonempty, empty and fiber results |

Native full run: 9 test functions (14 parameterized CS/SSI cases).
Review confirmation covers changed retained-depth/coverage behavior. The added UV
path has a focused Native test and separate portable proof. L4 regression executes
20 L4 tests and 50 lower L0-L3 tests. All test/build/runtime commands use explicit
Python subprocess timeouts (120-240 seconds) and dedicated scratch paths.

ASAN full proof runs all 14 cases and failure fixtures; the added UV proof is also
run under ASAN. Normal WASM and Embedded proofs exercise the same original laws,
resource bounds and typed failure semantics on Node 24.19.0 WASI Preview 1.
SDKs are `swift-6.4.0-RELEASE_wasm` and
`swift-6.4.0-RELEASE_wasm-embedded`, compiler Swift 6.4 release,
WASM target `wasm32-unknown-wasip1`, debug/Onone.
Native is arm64 macOS with the package's macOS14 deployment floor; Span is an
additive macOS26/iOS26 availability-gated API. No iOS runtime claim is made.

The portable proof's synchronous computation runs in a nonisolated function on all
platforms. Its initial MainActor-body callbacks produced Embedded actor-context
warnings. The corrected Embedded run has no actor/data-race warnings; the historical
log is retained as diagnostic evidence. No production synchronization was removed.
The only build warning is clang's unused `-rdynamic` argument; Node reports the
standard experimental WASI warning.

## Resource/performance evidence

All fixtures keep the existing 80,000,000 work and 1,073,741,824 byte admission
limits and depth limits 400. Storage figures below are cumulative admitted bytes,
not measured heap/RSS. Work figures count charged primitive work, not CPU cycles.

| Native L6 resolution after prepared L5 | Additional work | Additional admitted bytes |
|---|---:|---:|
| Ordinary CS overlap | 1,365 | 71,701 |
| Mixed CS relation | 1,866 | 82,055 |
| Folded SSI | 2,359 | 16,328 |
| Collapsed SSI curve | 2,717 | 19,136 |
| General singleton-slice XYZ graph | 5,520,603 | 258,353,123 |

The earlier folded/collapsed graph path exhausted the unchanged storage limit;
certified finite-fiber/first-parameter-curve laws avoid that added decomposition.
The mixed CS counterexample `t=u`, `v*(u-1/2)=0` failed in lower incidence before
L6. One exact affine refinement retains its partial interior attachment and passes;
the focused run took 1.390 seconds. These observations do not establish whole
CADGeometry speed or a general constant-time guarantee.

The result/view/Span APIs share immutable buffers; the owner-identity and lifetime
tests verify that view construction retains the same owner. Graph laws, stratum
records and index buffers are necessary admitted materialization. No allocation
profiler was used, so this is not a claim of zero allocation for a whole query.

## Shared-state review

| State | Native / normal WASM / Embedded storage | Access and lifetime |
|---|---|---|
| Published relation | Same final immutable class with `let payload` | Read-only; result, handle and view retain it |
| Solver scratch | Same invocation-local arrays/value state | No escape to another invocation; synchronous ownership |
| Admission | Same `inout A: ExactScalarAdmission & ~Copyable` | Caller owns cumulative mutation; never retained/reset by solver |
| Station/fiber | Same immutable values retaining source/result owners | Fresh explicit query admission; inherited retained depth |

There is no new shared mutable cache, unsafe pointer, unchecked Sendable conformance,
platform-specific Sendable weakening or raw Embedded state. The compiled Native,
normal and Embedded implementations use the same production sources.

## Integration boundary

Latest main at comparison remains the base commit. L0-L5/main package differences
are empty; existing component visibility is retained and duplicate new declarations
were checked. This is source/difference mapping plus isolated lower composition,
not a full CADGeometry compile or public `intersectionResult` integration.

Main's dirty PROGRESS and other active worktrees are untouched. This worktree's
PROGRESS is task-local; integrating it must reconcile main's record rather than
replace other tasks. No upstream is configured for this new branch, so no push occurs.
