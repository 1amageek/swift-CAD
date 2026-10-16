# Edge Continuity

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. Resolves the original
incident support of an authored edge continuity and constructs leaving rows.

## Responsibilities and Boundaries

The support retains its original surface, edge curve, directed native trim and
face-local coedge parameter curve independently of the interpolated construction
rows. It owns support selection and differential row construction. Feature
builders own final surfaces, finite clipping and publication.

## Related Designs

The exact support equation is issued by
[OriginalCoons PlaneDerivatives](../../CADGeometry/OriginalCoons/PlaneDerivatives/DESIGN.md).
Its original homogeneous plane identity and affine cofactor transport are shared
with the final derivative producer; this component owns continuity admission,
not a second support-equation algorithm.

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | feature construction | Supplies original continuity supports. | Row interpolation alone does not prove continuity. |
| [SectionResolution](../SectionResolution/DESIGN.md) | depends on | retained original parameter charts | Preserves section source laws through restriction. | Candidate parameters cannot replace the original coedge fractions. |
| [CADGeometry SurfaceBoundaryCertification](../../CADGeometry/SurfaceBoundaryCertification/DESIGN.md) | depends on | whole boundary position, normal and curvature bounds | Certifies the actual final surface against the original support. | Source preparation and proof cells must share the feature admission. |
| [Loft](../Loft/DESIGN.md) | used by | incident support and leaving rows | Builds sides and retains support until final certification. | A candidate certificate does not survive an original-boundary correction. |

## Architecture

```text
authored edge + current original topology
    -> incident support selection
        -> retained support surface / edge / coedge law
        -> interpolated leaving rows -> candidate side
            -> final original surface + mapped original coedge
                -> whole continuity certificate -> feature publication
```

## Contracts and Invariants

The retained coedge law runs in its original face traversal direction. Its edge
trim retains the original edge direction separately. A final section parameter
chart must transport these original fractions before certification; projections
of candidate stations cannot establish that transport. Restriction and nonlinear
conic charts preserve the complete original mapping.

Final certification evaluates the actual Surface3D and original support. This
includes plane supports: a corrected original boundary can change tangent and
curvature even when the interpolated candidate rows lie in a plane. The legacy
native candidate certifier is only a construction-stage check and cannot
authorize publication of a subsequently corrected side.

Plane supports retain their exact contract regardless of allowances supplied
for curved faces. Final plane continuity requires the original homogeneous plane
identity; the modeling tolerance does not create a replacement angular or
curvature allowance. For a
corrected Hermite side, its raw section's plane identity and the native tensor's
transverse first and second derivative identities must both be proved. Candidate
leaving rows alone establish neither premise.

The exact plane issuer constructs its equation from original authored plane
coefficients or exactly coplanar native support controls. It clears only positive
original rational denominators. On each original boundary owner it proves the
section's homogeneous equation identically zero, and proves the native tensor's
transverse derivative numerators zero at the authored boundary. The corrected
surface's retained residual-flat law transports those identities to the final
surface. The retained corrected boundary is bound by original traversal identity,
which supplies its exact position correspondence. A whole original first-order
cover must additionally prove nonzero normal. Its existing 4096 cells and
24 geometric levels are combined with the caller admission; algebra keeps its
independent original ceiling and actual UInt32 word storage is charged as bytes.
Original affine support images transport the exact plane equation by the
original cofactor and determinant, including translation. The equation is never
reconstructed from a rounded transformed representative normal or origin.
The original plane-derivative surface retains both unchanged section boundaries
and endpoint-coherent canonical connectors. Its exact nullspace producer issues
the requested whole transverse Dv/Dvv constraint witness. Final admission uses
that witness for this family, then evaluates its actual final first-order law
for regularity. It does not require the uncorrected native candidate's transverse
rows to satisfy the final equation, or inherit its normal certificate.

### Main Construction Execution Binding

Hermite candidate construction borrows one `OriginalQueryExecution` through
normal/projection/curvature reads, leaving and carried row interpolation,
rational basis evaluation, QR and the existing native construction-stage
certificate. Ordinary helper entries create one execution and delegate to those
same bodies. The original 32-station fitted chart, tolerance multipliers,
4096 certificate intervals, depth 24, QR rank threshold and coefficient ceiling
remain unchanged; this mechanical port does not introduce the independent
stronger native construction proof. Final corrected-source planar certification
uses the same execution through the existing original planar certifier. Curved
final-source certification retains its explicit unsupported result. No candidate
chart or accounting/context flag gains source publication authority.

Hermite and continuity construction share one module-internal checked element
count operation. It rejects negative operands and Int addition/multiplication
overflow with `ExactScalarFailure.countOverflow` before storage admission. Counts
remain element counts; the caller supplies the unchanged element stride to the
same execution. This helper does not depend on Geometry-internal declarations.

## State, Ownership, and Lifecycle

Supports and source values are immutable Sendable values. The composing feature
retains them through final output admission. The component has no mutable shared
state or target-specific synchronization branch.

## Failure, Concurrency, and Constraints

Missing original geometry or coedge law fails explicitly. Unproved parameter
transport, regularity or continuity cannot publish a successful certificate.
The original feature's angular, curvature, depth and storage limits remain
binding. Source nesting and intrinsic exact algebra depth are separate limits.

## Verification and Change Impact

CADModelingTests owns final corrected Loft and surface boundary success and
failure fixtures, including reversed native trims, nonlinear conic charts,
plane tangent changes and G2 curvature changes. Verification follows complete
source integration. Changes affect Loft, TurningCapLoop and surface filling
callers as well as the lower original boundary certifier.
