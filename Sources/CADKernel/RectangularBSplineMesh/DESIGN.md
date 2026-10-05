# RectangularBSplineMesh

## Purpose and Scope

This child of [CADKernel](../DESIGN.md) owns original rectangular B-spline basis admission. It has no children. MeshTessellator remains the module composition root and consumes the Geometry-owned original closed-span authority. M1 includes finite legal positive-weight regular C0/C1 supports with open or periodic axes; this sprint composes nonclamped native open axes with the unchanged selected periodic lift authority. Separate curvilinear-trim work does not establish M1 completion.

## Responsibilities and Boundaries

OriginalBSplineRectangleBasisAdmission classifies original knot continuity and endpoint structure. It chooses a retained native-panel route for C0, periodic C0 or nonclamped open axes. Classification is not a geometric regularity or fidelity certificate. Geometry alone encloses original homogeneous coefficients, closed native jets and selected endpoint normals. Kernel consumes those bounds, retains compatible grids and publishes checked original stations/facets. The source support, knots, weights and topology are immutable.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | checked retained preflight/emission and FaceRun | Composes the admitted family with invocation storage | Parent owns the public entry and module index |
| [CADGeometry](../../CADGeometry/DESIGN.md#original-native-span-tessellation-authority-parm1r3) | depends on | original closed incident span tokens, selected normals and aggregate bounds | Supplies all numeric authority for original native panels | Same depth32/cell262144 traversal; no reconstructed support or epsilon endpoint |
| [CADIR](../../CADIR/DESIGN.md) | depends on | original TessellationOptions/Limits/Mesh | Owns caller geometric and storage allowances | Every diagonal and original normal must meet the unchanged options |

## Architecture

```text
Original support + exact ordered constant-coordinate rectangle
    -> validated basis admission
    -> Geometry original native closed-panel bounds/tokens
    -> per-axis compatible retained grid counts
    -> invocation-wide checked storage admission
    -> original points + independently selected normal owners
    -> complete triangles + FaceRun
```

## Contracts and Invariants

A source is validated under the caller modeling tolerance before basis classification. Stored finite positive weights retain the BSplineSurface3D contract. Internal active knot multiplicity cannot exceed degree; unresolved source discontinuity is explicit refusal. A nonclamped nonperiodic axis retains its actual native domain knots[degree]...knots[count], not the outer knot-vector ends and not a normalized replacement chart.

All nonclamped open rectangles use exact ordered constant-coordinate coedge-use endpoints, connected directed vertex identities, alternating monotone sides and complete original ranges. Those exact source conditions supply rectangle ownership; sampled endpoints or spatial tolerance do not substitute for UV connectivity. Split sides retain their existing exact contract.

Nonclamped C1 and C0 sources both consume native panels. Every positive original panel receives the existing closed one-sided Geometry proof. Compatible maximum counts are retained per original U/V interval; each triangle stays in one original panel, including C0 boundaries. Adjacent panels retain the same boundary positions with independent selected original normal/index owners. No crease-crossing triangle or unproved panel omission is permitted.

The existing outward actual representable station gaps, original tangent/Hessian/unit-normal derivative bounds and all-triangle-edge policy own count selection. Position deviation, normal angular variation and every edge including the diagonal simultaneously satisfy original caller options. Preflight and emission consume the same retained grids; no fixed-step or legacy retry authorizes success.

## Runtime Flows

Source validation and exact rectangle admission precede basis route selection. Geometry prepares all selected native panels under one depth32/cell262144 allowance. Kernel chooses per-panel counts, takes compatible per-axis maxima, rechecks those exact counts and retains panel tokens/grids. Invocation storage admission precedes output allocation. Emission evaluates actual source stations and token-selected normals, preserves face/shell orientation and admits every triangle. Any failure abandons the entire Mesh map.

## State, Ownership, and Lifecycle

The helper is stateless and Sendable. Source/model/options remain immutable; grids and tokens live only for one tessellation request. No persistent cache or mutable shared owner is introduced. Native, WASM and Embedded use the same storage and authority contracts.

## Failure, Concurrency, and Constraints

Invalid sources retain their original typed failure. Discontinuous basis, inexact periodic translation/width, foreign source/tolerance/domain and unproved regularity refuse explicitly. The nonperiodic selected axis retains cycle0/translation0 on its original native domain; mixed rectangles consume the same original Cartesian selected panels as other native-panel sources. Resource overflow, exhausted existing proof/grid/storage limits and cooperative cancellation propagate without retry or fresh allowance. Existing maximum per-axis65536 steps, checked aggregate vertices/indices/bytes/reservations and original cancellation checkpoints remain unchanged.

## Verification and Change Impact

[TessellationFidelityTests](../../../Tests/CADKernelTests/TessellationFidelityTests.swift) owns literal nonclamped cardinal quadratic U/V graphs S=(t,v,A*t*t), t=U-2 on native2...3, whole triangle position/normal and all-edge checks, independently tightened position/angle/curvature counts, and nonclamped C0 tent one-sided normals. The original source knots/coefficients are independent of the oracle. [MeshTessellatorFaceRunTests](../../../Tests/CADKernelTests/MeshTessellatorFaceRunTests.swift) owns provenance/extraction/source metadata; [TessellationBudgetTests](../../../Tests/CADKernelTests/TessellationBudgetTests.swift) owns cumulative caller storage and cancelled publication. The unchanged clamped and periodic suites retain evidence where their premise is unchanged; targeted affected verification covers dispatch composition.

Full M1 requires public Native/normal-WASM/Embedded behavior with fixed Swift6.4/matching SDKs, source-derived capability/domain consistency, and verified main integration. This nonperiodic sprint is not full M1 completion. Mesh is pure scalar logic, so SwiftPM Native tests own this path; no Metal implementation is introduced. Root owns graph/integration/commit and the module design index.

Mixed periodic/open fixtures independently retain literal cardinal or diamond cycles scaled by an original nonclamped parabolic or C0 tent radius with original height t. [OriginalMixedPeriodicTessellationTests](../../../Tests/CADGeometryTests/OriginalMixedPeriodicTessellationTests.swift) owns exact lower closed jets, zero-width seam/open endpoint incidents, foreign-token and shared cover/cancellation refusal. The Kernel fidelity suite covers both axis roles, full periods and unwrapped seam crossings, source C0 sides and all emitted triangle edges; FaceRun and budget suites verify original extraction and cumulative/cancel publication. The periodic width, exact shift, native derivative scaling and ordinary normal selection contracts remain unchanged.
