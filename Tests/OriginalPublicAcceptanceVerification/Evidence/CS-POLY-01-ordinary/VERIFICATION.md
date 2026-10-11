# CS-POLY-01 ordinary public acceptance

## Input and independent oracle

Use `PolylineAtlasLiftProof.shape(multi:true)` and the authored pcurve
`[(0,0),(0,0),(1/2,1/2),(1,1/2),(1/2,1/2)]`. Query the complete original
curve against the whole plane with origin `(1/2,0,0)` and normal `unitX`, using
default options and standard tolerance through ordinary bare/rich CS entries.
The independent roots are `T=sqrt(2)-1` and `T=1`, both at `(1/2,1/2,0)`.
They retain original lift UV `(1/2,1/2)`, plane UV `(0,-1/2)`, and eight/four
closed incident representatives. Equality of XYZ does not merge the two T values.

## Changed path

Original Coons/polyline/lift issuers -> complete source/DI graph family ->
checked polynomial UV elimination and exact plane-incidence preimage -> one
retained L5/L6 relation -> original-coordinate restoration -> exact TUV grouping
and certified numerical publication -> existing public result. The plane retains
unbounded UV support. Scalar isolation, transport, source and graph producers are
reused; no new root engine, tolerance equality or second decomposition is added.

The ordinary result retains a sealed numerical-to-exact incident mapping. The
prepared overload retains exact geometry without a numerical mapping. Existing
prepared GP behavior is exercised separately. Unconverted Native plane/B-spline
scaled-normal rejection remains outside the new selector's applicability.

## Behavioral evidence

| Obligation | Checked behavior |
|---|---|
| Success/equality | Actual bare/rich APIs return two distinct T values; exact scalar oracle and all twelve ordinals/UV are checked |
| Boundary/exclusion | T=1 gives one root/four incidents; root-free, outside-support and excluded plane-UV requests retain complete empty receipts |
| Resources | Query work 2,512,353 and storage 14,912,548 bytes pass exactly; one less fails; candidate, degree, source/algebraic-depth failures are explicit |
| Cancellation | Already-cancelled Task performs zero work/storage; first/last callback errors and final callback Task cancellation propagate; empty publication cancellation is checked |
| Ownership | Detached input, COW modification, retained result after failed independent queries and independent TaskGroup readers |
| Prepared entry | Exact twelve incidents/restored UV; numerical mapping absent; direct typed point-cap and cancellation failures |
| GP regression | Actual existing prepared GP public entry retains exact TUV/XYZ, complete exclusion, representation and point limit |

Fixed Swift 6.4.0 release compiler and matching WASI SDK compile/link/runtime
lanes: Native, ASAN, normal WASM and Embedded WASM. Embedded checks its last
cancel/GP/prepared cases in one executable, with independent Tasks/admissions;
the successful ordinary/selection/resource modes use their retained executables.
WASI TaskGroup checks do not assert physical thread parallelism.

## Receipt scope and reproduction

`receipt.json` binds each lane's compiler commands, inputs, products, logs and
the same 23 changed production bodies. Binary libraries/executables and exact
compiler-source snapshots are retained under
`.build/cs-poly-01-ordinary-accepted-20261011`. Each lane admits its recorded
lower receipt before use. Input maps store only hash differences from that parent;
unchanged premises are referenced without duplicating their manifests. The two old
dispatcher premises are explicitly replaced
by current source compiled in `PublicLiftPlanePort`; the actual full public
entry bodies execute. An unselected legacy-rich tripwire throws if fallback is
attempted. This is independent changed-path assembly, not a new broad production
CADCore/CADGeometry/Kernel build or whole M8 verification.

Native/ASAN/normal lanes execute ordinary, selections, resources, cancel-entry,
cancel-final and GP modes plus the prepared probe. Embedded compiler commands
record its fixed modes and combined remaining fixture. Driver recipes and exact
commands are included; they require the admitted parent artifacts. Runtime
commands have 120-second timeouts. The accepted remaining Embedded compile uses
two workers and a 300-second timeout, completing in 63.749 seconds. Compiler
worker/wall-time settings do not change any query ceiling.

Three earlier compiler timeouts (360 seconds of timeout windows), and the earlier
private-error-fixture linkage diagnostic, are excluded from success. Their
diagnostics remain in the retained Embedded directory. The fixed prepared probe
checks the public typed error directly. Contended elapsed times in the logs are
verification measurements, not a before/after performance benchmark.

## Review and delivery

[Scoped review](REVIEW.md) owns the stable change review and finding-specific
confirmation. `PROGRESS.md` owns commit/main delivery state and completion counts.
The current cell catalog is not exhaustive. Continuous overlap, subnormal saved
normal, general source/domain/identity, boundary/self consumers and symbolic
publication remain open requirements. No whole-seven or full87 completion is
inferred from this cell.
