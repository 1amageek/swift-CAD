# Portable Geometry Verification

## Purpose and Scope

Child of [the package](../../DESIGN.md), without children. Owns G1/G2/G3 cyclic geometry, knot-reduction and source-signature checks,
plus G4 overlap, G6 common-conversion, Q3 C0 area and T8 raw-topology admission checks on matching normal WASM and
native targets.

## Responsibilities and Boundaries

Exercises actual cyclic geometry, refinement, restriction, projection and source
transport, richer intersection results and continuous conversion admission through
public protocols. It does not establish whole-kernel, Embedded, exchange or application
coverage; those remain in the final integration item. Each new geometry requirement
must add its own behavioral evidence before this executable can cover it.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Verification ownership | Platform-specific geometric runtime evidence | Full integration remains required |
| [Periodic B-spline](../CADGeometry/PeriodicBSpline/DESIGN.md) | depends on | Periodic evaluation, exact editing and budgets | Exercises rational cycles across their seam | No sampled curve fitting |
| [KnotRemoval](../CADGeometry/KnotRemoval/DESIGN.md) | depends on | Full-domain deviation bounds | Exercises cyclic curves, pcurves and both tensor axes | Resource refusal must remain explicit |
| [CurveSurfaceOverlap](../CADGeometry/CurveSurfaceOverlap/DESIGN.md) | depends on | Public intersectionResult and owned correspondence | Exercises authored overlap and whole-span refusal | Angular support similarity is insufficient |
| [GeometryConversion](../CADGeometry/GeometryConversion/DESIGN.md) | depends on | Public GeometryConverting and source protocols | Constructs and certifies same-chart geometry | Full intervals, native target resources and source errors must retain their contracts |
| [Non-Manifold Topology](../CADTopology/NonManifoldTopology/DESIGN.md) | depends on | Immutable raw snapshots and explicit structural admission | Exercises preserved non-manifold edge incidence and typed refusal | No raw snapshot is a modeling validity certificate |
| [SurfaceAreaIntegration](../CADTopology/SurfaceAreaIntegration/DESIGN.md) | depends on | Certified area and three centered moments | Executes folded C0 support and a crossing hole through public measurement | General procedural/implicit trim conditions remain open |
| [CADIR](../CADIR/DESIGN.md) | depends on | SubshapeGeometrySignature transport | Retains the exact periodic value in a finite edge span | A signature is not a evaluated body |

## Architecture

```text
Native/WASI host -> periodic rational value -> evaluation/refinement/restriction
                -> prepared projection/bounds -> geometry signature transport
                -> richer overlap protocol -> authored range/correspondence
                                           -> tilted-support refusal
                -> common conversion protocol -> full-domain same-chart success
                                              -> negative-cycle candidate refusal
                                              -> typed resource/source failures
                -> malformed input and resource-budget refusal
```

## Contracts and Invariants

A success marker requires each operation to execute and satisfy its behavioral
checks. Failed comparisons throw classificationFailure; expected resource and
input failures must retain their own typed codes. All values are task-local and
no target changes the storage, isolation or error contract.

The executable owns its WASI linker stack provision. The debug third-order
interval-jet path needs more than the linker default: the captured failing
artifact consumed 135,872 stack bytes before trapping in allocation. This smoke
uses the same finite 64 MiB stack provision as CADWASMSmoke, only on WASI.
This is an executable resource setting, not an algorithmic fallback or a claim
about Embedded memory requirements. Any change to the provision must rerun the
same C0 public measurement and typed-budget fixtures on the matching SDK.

## Verification and Change Impact

Build with Swift 6.4.0 and the matching normal WASM SDK. Execute the exact emitted
artifact with Scripts/run_wasi_smoke.mjs, bounded by the repository guard. Native
SubshapeGeometrySignatureTests owns source transport and corruption rejection.
Tensor checks execute independent periodic axes, mixed derivatives, origin-aware
projection, seam restrictions/refinement, interval derivative containment, face
signature transport and resource/input refusals, including a folded periodic
Bezier span with two regular roots that must not yield a unique answer when
its subdivision budget is exhausted. Knot reduction executes the public protocol
for rational pcurves, periodic curves and both periodic tensor axes, checks
source/origin and bound retention, and checks typed work-budget refusal. Periodic geometry or transport
changes invalidate this runtime evidence. Overlap evidence executes an authored
free-surface lift with an explicitly clipped finite range and forward-verified
correspondence, and refuses a nearby tilted plane whose angular agreement masks
a large between-station distance. Native rational isocurve evidence
uses independent literal U/V homogeneous sections, restricted/reversed intervals,
source/target forward checks and owned correspondence after source mutation.
Large shifted charts retain signed affine direction; an ill-conditioned wide
chart and a low work allowance must retain typed projection/work exhaustion.
The wide public query does not reach the internal compensated boundary path;
its nonrepresentable-boundary proof remains in the Native owner tests. C0 area evidence
uses real retained surface-lift edges with complete sheet ownership and public
pcurve validation before measuring a non-dyadic folded rectangle and crossing
hole against independently composed model-space areas and XYZ first moments.
The same complete C0 face also executes with exact rigid-image trim charts,
using the literal independent image (-y + 0.125, x + 0.25, z + 0.5) for centroid
validation. All pieces and loops share one work limit, including the explicit three-cell
refusal. These checks do not complete full G4 or Q3. Conversion evidence constructs an exact cubic
line and tensor plane through the public protocol, verifies continuous position,
tangent and curvature bounds and source charts, refuses the known negative-cycle
false candidate, and preserves degree-dependent scalar and public source-error
refusals. T8 execution captures one raw three-face shared-edge compound, verifies complete
retention and excessive incidence, refuses both modeling admission paths with the
retained report, admits a valid standalone vertex only to Shape operations, and
checks typed work exhaustion and missing-reference preservation. These are portable execution checks; native component suites own the
broader contract matrix, and existing sampled consumer migration remains a
separate G6 completion condition. The matching
Embedded SDK currently lacks Foundation used by existing CADCore/CADGeometry;
normal WASM runtime success does not establish Embedded support.
