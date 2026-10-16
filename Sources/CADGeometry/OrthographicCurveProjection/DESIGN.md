# Orthographic Curve Projection

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md); no children. Owns D2's geometric curve
projection. Topology, visibility, layout, serialization and approximation are
separate responsibilities; this bounded Native sprint does not complete D2.

## Responsibilities and Boundaries

Owns immutable screen-frame construction and the original projected curve law.
The existing ValidatedCurve3D owns original domain, position and differentials.
No mesh, fitting, sampled polyline or inverse projection participates.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | ValidatedCurve3D and parameter domains | Retains original curve authority. | Source failures propagate. |
| [Edge projection](../../CADTopology/OrthographicEdgeProjection/DESIGN.md) | used by | parameter-preserving projected law | Associates projection with topology. | Projection does not imply regularity. |

## Architecture

```text
Curve3D -> ValidatedCurve3D -> OrthographicProjectedCurve
Normal + horizontal hint -> OrthographicProjectionFrame -> original XY law
```

## Contracts and Invariants

- Normalize the normal; derive vertical from normal cross horizontal hint and
  horizontal from vertical cross normal. This explicitly projects the hint into
  the plane. Zero/nonfinite and nearly parallel inputs fail. The minimum sine
  is the caller's angular tolerance, which must be below one.
- XY is the original point minus origin dotted with the two unit screen axes.
  First/second derivatives use the same linear map without translation. Original
  model units, domain and parameters remain unchanged; no approximation is claimed.
- Retain the immutable validated source by value/COW. All source families keep
  their original evaluator and its failures. Collapsed XY tangents are legitimate;
  no 2D tangent, curvature, visibility or nondegeneracy is inferred.
- Outputs must be finite. Overflow fails explicitly; higher-precision recovery
  is outside this contract.
- Check cancellation before/after construction and before source queries.
  Storage is one source snapshot plus a fixed-size frame; no sample arrays.

## State, Ownership, and Lifecycle

All retained properties are immutable and Sendable. Source buffers keep their
existing COW owners. No mutable shared state, platform branch or shutdown exists.

## Failure, Concurrency, and Constraints

OrthographicProjectionError separates invalid frame from nonfinite output.
Original GeometryError, KernelError and CancellationError propagate. Source
validation runs once; each query adds constant arithmetic to one existing source
evaluation. Source costs/limits are retained, not generalized.

## Verification and Change Impact

[Public geometry tests](../../../Tests/CADGeometryTests/OrthographicCurveProjectionTests.swift)
verify literal oblique/translated projection, rational original parameters,
derivatives, collapsed tangents, finite failures, invalid domains, COW and
cancellation. Native evidence does not imply WASM/Embedded. Changes to frame
orientation or source evaluation require dependent edge tests.

The projected law also exposes `enclosure(over:)`, retaining the original
complete interval differential enclosure and its outward linear screen image.
Position subtracts the screen origin; derivatives do not. Collapsed projected
tangents retain zero-containing bounds. Visibility and curve intersection
consumers therefore receive complete screen intervals without tessellation.

The projected source exposes its immutable certificationTolerance alongside its retained original curve. Caller-owned conversion queries use that exact preparation tolerance and their existing invocation admission; the accessor creates no source preparation or allowance.

Caller-admitted projection construction passes the original execution to the
existing `ValidatedCurve3D` preparation. Projected point, differential and
enclosure queries consume that same execution and preserve retained source
contributions. Ordinary queries obtain the source's existing receipt execution
and enter the same bodies. The frame map adds only fixed scalar arithmetic;
complete enclosures retain the original lower encloser and its failure contract.
