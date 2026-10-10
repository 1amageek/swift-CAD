# Original Coons Lift Verification

## Scope and contracts

M4.S.LC supplies a sealed retained source from the existing original rational
Coons homogeneous atlas and extracts actual Surface3D.originalCoons hosts for
both affine/constant and Native rational B-spline pcurve lift providers. The
existing lift producer, complete chart preparer and guarded DI algorithms remain
unchanged. No alternative Coons formula, correction surface, differential atlas,
fit, inverse, root solver or unchecked certificate is introduced.

Authority: [source contract](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md#retained-coons-atlas-lift-hosts)
and [original producer](../../Sources/CADGeometry/OriginalCoonsIntersectionSources/DESIGN.md).

## Assembly and evidence

Verify.py compiles current source/DI, the original Coons homogeneous producer and
actual source/host adapters using fixed Swift 6.4.0 and matching ordinary/Embedded
SDKs. Receipt-bound numerical Core/Geometry/collection children are reused after
source/product/log hash admission. Each lane has its own UUID scratch path.
Successful initial adapter compilations are reused only with identical commands,
generated source headers/bodies and original input checks; final fixtures are
freshly compiled/linked. Final receipt inputs retain adapter/log/product hashes.
No broad CADCore/CADGeometry/Kernel or L2-L6 target is rebuilt. ASAN instruments
changed source/DI/adapters/fixtures, not unchanged cached numerical children.
Compile/link timeout is 120s; runtime timeout is 180s.

| Target | Adapter compile / final compile-link / runtime seconds |
|---|---:|
| native | 25.683 / 2.666 / 1.275 |
| asan | 41.837 / 5.355 / 1.604 |
| wasm | 21.055 / 1.743 / 1.204 |
| embedded | 14.919 / 48.281 / 0.727 |

All final runtime logs contain the four required success markers and no FAIL,
warning/error, actor-isolation, data-race, null-call or signature-mismatch marker.
The local WASI runner propagates the process exit status; output markers provide
an independent acceptance condition. Superseded diagnostics and premature failed
WASI receipts are explicitly invalidated in Evidence/diagnostics/diagnostics.json.
8,428 unique current inputs/products were rehashed after the four successful runs;
all runtime logs and final receipts are bound independently.

## Behavioral evidence

- Actual original Coons constructors retain four exact directed boundaries and
  original corner incidence. Planar multi-cell and curved quadratic-boundary hosts
  pass through Surface3D, both lift source providers, existing complete chart
  preparation, lift producer, DI request and lifted-position query.
- Affine/constant-U/constant-V/reversed pcurves and weighted multi-span Native
  pcurves with authored support [2,5] retain exact normalized T and auxiliary UV.
  The exact T=1/3 Native knot at the host corner retains all eight incident pairs.
  Reversed and constant-UV fibers preserve their authored parameters.
- Independent exact Coons position expectations are compared with graph XYZ/W.
  Public point evaluation is checked separately for numerical accuracy, and is
  never an equality/identity oracle. Wrong UV, foreign child binding/host and
  tolerance-only support clamps fail or exclude under the original contract.
- Full/singleton/empty requests and chart ceilings exercise current source/DI.
  Strict/disconnected/request and inherited-depth regressions retain their
  unchanged common-algorithm evidence in OriginalRetainedNativePcurveLiftVerification.
- Source plus child preparation, lift preparation and incident queries succeed at
  measured work/storage ceilings and fail one unit below. Entry/final callback
  cancellation is checked; the direct Coons source succeeds at the exact retained
  child-depth-plus-one and refuses one less. Invalid discontinuous Native knot
  data is rejected by its owning validator before Coons construction.
- Detached families retain original Coons/child/field owners after loop inputs are
  released. Existing actual boundary-correction affine and Native-pcurve fixture
  bodies execute unchanged against the current assembly and pass.

## Ownership and stable scoped review

One stable scoped review covers actual host extraction, source/tolerance/depth
binding, canonical coefficient import, complete-cell/denominator authority, shared
lift parameter and auxiliary roles, original field/guard retention and all failure
publication paths. Source, consumers and test bodies were read; final behavior was
executed. No remaining production finding exists within this unit.

| State | Native | Ordinary WASM | Embedded | Lifetime |
|---|---|---|---|---|
| Provider configuration | immutable Sendable | same | same | value-owned |
| Source/atlas/cells | immutable retained owners | same | same | retained by result |
| Scratch/admission | invocation-local exclusive borrow | same | same | ends with invocation |

No new unsafe path, shared mutable storage, conditional Sendable conformance,
isolation bypass or platform-specific synchronization exists. The preexisting
numeric admission adapter retains its checked scoped borrow contract.

## Remaining scope

General nonrational/unsupported Coons boundaries and hosts, derivative actual-host
routing, priority images, full nonlinear/singular domains, identities and general
M6/M7/M8 remain open. This does not widen the original single-span Coons CS/SSI
adapter or certify embedding. Whole-seven remains 1/7; full87 is incomplete.
