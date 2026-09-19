# Spatial Path

## Purpose and Scope

Child of [CADIR](../DESIGN.md). Owns editable spatial polyline and composite
cubic Bezier source values. Planar Sketch and its constraints remain unchanged.

## Responsibilities and Boundaries

Knots own stable UUIDs, XYZ positions and incoming/outgoing tangent vectors.
Source edits return validated values; rendering, picking, transactions and Undo
belong to Rupa. A path produces curves, never an implicit planar profile.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | source serialization | Persists path values | Old sketches stay planar |
| [CADModeling](../../CADModeling/DESIGN.md) | used by | exact curve evaluation | Converts source to exact curves | No projected XY substitute |

## Architecture

```text
SpatialPathFeature -> ordered stable knots -> exact spatial curves
                   -> validated value edits -> caller-owned transaction
```

## Contracts and Invariants

- Coordinates and vectors are finite. Knot IDs are unique. Open paths have at
  least two knots; closed paths at least three.
- Corner tangents are independent. Smooth tangents are opposite and collinear
  with independently retained lengths. Symmetric tangents are exact opposites.
- Moving a knot retains its relative tangent vectors. Moving one tangent updates
  its opposite according to the knot mode. Zero-length smooth tangent edits that
  cannot preserve the opposite length fail explicitly.
- Inserting a Bezier knot uses de Casteljau subdivision and preserves the curve.
  Splitting shortens adjacent arms; affected symmetric knots become smooth.
- Deleting a knot connects its neighbors with their existing tangent vectors.
  It is an explicit shape edit, not an exact inverse of insertion.
- Every edit validates a copy before publishing. Rejected edits preserve source.
- Encoding and decoding validate source. Unknown fields and enum values fail.

## Verification and Change Impact

CADIRTests/SpatialPathTests verifies spatial edits, tangent modes, shape-preserving
insertion, deletion bounds, stable IDs, serialization and nonmutation on errors.
The CADModeling consumer must verify exact 3D evaluation; UI integration must
verify preview, cancel, commit and Undo separately.
