# Periodic Native Surface Lift Verification

## Scope and authority

M4.S.LP supplies a sealed source family for periodic Native surfaces and finite
rational B-spline pcurves. Every fundamental chart pair and exact arbitrary-size
integer UV translate is retained through the existing lift graph producer.
Authored normalized T remains one-dimensional; U/V are auxiliary coordinates.
Cycle indices describe the hosting surface's lifts, not a period theorem for T.
No inverse, finite cycle window, fitted XYZ curve or tolerance clamp is introduced.

Design owner: [source issuance](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md#periodic-native-surface-lift-supply).
DI member/incident consumption, general surfaces/pcurves, priority-image equality,
M5/M6/M7/M8 and whole-seven/full87 remain required unfinished work.

## Accepted execution

Swift 6.4.0 release and matching normal/Embedded Wasm SDKs are fixed. Independent
L0/L1/source builds use two jobs with a 240-second build deadline and 180-second
runtime deadline. Actual source/adapter compile, link and runtime each use a
120-second deadline. No broad CAD or L2-L6 target is rebuilt.

| Lane | Final independent compile / runtime seconds | Actual source compile / link / runtime seconds |
|---|---:|---:|
| native | 1.011 / 2.050 | 11.790 / 2.581 / 2.473 |
| asan | 1.542 / 1.593 | 20.714 / 2.708 / 1.966 |
| wasm | 1.144 / 2.589 | 11.078 / 1.467 / 2.786 |
| embedded | 8.019 / 1.537 | 2.203 / 48.818 / 1.469 |

The final Native/ASAN/normal-Wasm independent compilation is an incremental fixture
repair against receipt-admitted unchanged source/lower objects. The driver checks
all prior source/artifact hashes before reusing the same scratch directory and
rejects unexpected source issuance recompilation. Embedded's earlier incomplete
fixture compilation is not accepted evidence; its final independent build is fresh.
Generation and receipt records bind current sources, actual compiler input plans,
modules/objects/products, commands and runtime logs. No exit-only result is used:
fixtures assert exact equations, positions, complete incident counts and failures.

Actual assemblies compile current source issuance and the seven real Native/lift
snapshot adapters. Receipt-admitted unchanged numerical Core/Geometry children
provide actual surface/pcurve validation, periodic basis wrapping and public lift
point evaluation. The selected original source files are checked against retained
M6 source/product/runtime receipts before use. Unselected cached shape/solver
branches are outside this evidence. Source/adapters and independent lower objects
are ASAN instrumented in the ASAN lane; cached numerical children are not.

## Behavioral evidence

- One-axis and independent two-axis periodic Native surfaces have complete three/
  nine-template families. Negative/positive translated charts and every closed
  knot/seam side satisfy independently expected positions and counts.
- Linear, nonmonotone quadratic and constant pcurves retain all original T and UV.
  Exact graph XYZ matches both independent expectations and public original lift
  evaluation. Same-XYZ UV shifted by a full period is rejected by the unchanged
  authored pcurve equations, even inside the translated surface chart.
- An exact cycle of 2^96 exceeds machine Int and issues the correct seam member;
  no integer narrowing, finite enumeration or floating cycle calculation occurs
  in production. Small Int cycles in the actual fixture only select test members.
- Member preparation/query succeeds at measured exact work/storage and fails at
  one less independently. Entry, intermediate and final storage-triggered cancel
  abort before publication. Source depth, template/chart limit, malformed cycle
  arity, noninteger cycles and nonzero nonperiodic-axis cycles fail explicitly.
- Foreign surface and pcurve bindings cannot prepare a family. Original source
  preparation scope ends before subsequent graph queries; caller Native-net COW
  mutation leaves original retained evaluation and proof unchanged.
- The existing finite lift producer passes weighted surface/weighted pcurve exact
  position and actual numerical regression. Its periodic refusal remains intact.
  The snapshot provider still rejects tolerance-only clamps on nonperiodic axes.

The new member API accepts exact rational integers, not scalar-field values;
foreign algebraic-coordinate validation in graph evaluation remains the unchanged
parametric graph contract. This unit does not claim newly verified general-field
DI, image/fiber publication or full family acceptance.

## Ownership and scoped review

| State | Native / normal Wasm / Embedded storage | Access / lifetime |
|---|---|---|
| Family and children | Identical immutable sealed structs and retained arrays | Original source/period/pcurve owners until result release |
| Graph evidence | Immutable original chart pair plus exact translation | Retains authored UV correspondence and causal proof depth |
| Query scratch | Local shift/term/condition buffers and exclusive admission | New output costs admitted; no shared mutable state |

Source inspection covers original validation, basis wrapping and public lift
branches, complete child coverage, exact substitution signs, authored UV equations,
all translated guards, owner/field/depth admission, resource/cancel boundaries and
retained lifetime. No unchecked initializer, unsafe pointer, mutable shared state,
Sendable weakening or platform-specific synchronization is introduced. Searches
classify computed properties and invocation-local mutable scratch explicitly.

One stable scoped review has no remaining production findings. A design wording
clarifies that auxiliary surface cycle indices do not establish periodicity of T;
no implementation or runtime premise changes. Target diagnostics before acceptance:
actual Native 01 used an unavailable `floor` spelling in the fixture (replaced by
`rounded(.down)`); initial Embedded fixture logging used unsupported variadic print
(replaced with static strings). Neither diagnostic is a successful target proof.
Final actual compile/runtime logs are checked for actor-isolation, data-race and
null-function diagnostics and contain none. Existing broader finite-lift evidence
is reused within its unchanged scope, not as full M4-M8 evidence.

## Latest-main delivery

Independent source/artifact/log comparison and fresh Native/Embedded interaction
runtime are required before final source-unit delivery. They do not replace the
still-open periodic lift DI consumer and general public acceptance.
