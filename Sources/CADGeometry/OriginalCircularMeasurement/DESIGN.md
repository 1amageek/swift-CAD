# Original Circular Measurement

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), with no children. Owns source-bound circular
center/radius/normal/boundary measurement for primitive circle/arc laws through
parameter, rigid, affine and original-word images. This is a query receipt, not a
new persistent geometry family or construction approximation.

## Responsibilities and Boundaries
The caller resolves original topology, native boundary station and scene placement.
This component proves circularity from the original primitive plane and exact
retained affine action. Native singleton curve jets own the boundary source;
Topology summaries and display midpoints are never center authority. Rupa owns
paper precision, dimension layout and current scene/evaluation freshness.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original curve laws | Supplies common source families | No shared enum change |
| [OriginalAffineOperationWord](../OriginalAffineOperationWord/DESIGN.md) | depends on | exact retained action and field | Transports original circle plane | Do not flatten source matrices |
| [RationalBivariateAlgebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | exact Gram/sign/square root | Proves circularity and radius | Independent coefficient depth |
| [OriginalGeometrySourceValidation](../OriginalGeometrySourceValidation/DESIGN.md) | depends on | bounded source preparation | Admits singleton original jets | Same exclusive execution, no display replay |

## Architecture
```text
original circle/arc chain -> original ordered action -> exact plane Gram
 -> circularity receipt + exact radius/center/normal enclosures
original full curve + native station -> prepared singleton jet -> boundary enclosure
 -> immutable measurement -> caller paper layout
```

## Contracts and Invariants
Two independent raw vectors spanning the original normal plane are chosen without
rounded products. Let H be their original Gram and G their exact image Gram. The
image is circular iff G = s² H for positive s², proved by exact field equalities.
This does not demand three-dimensional similarity: scale(2,2,3) preserves an XY
circle. An actual ellipse fails explicitly. Radius is the exact positive square
root of s² times original radius²; center and normal retain exact field action.
The normal uses normalized inverse-transpose, with determinant parity retained.
Boundary position is the original full curve law at the supplied native station;
no chord midpoint or computed analytic phase is substituted.

## State, Ownership, and Lifecycle
Inputs and receipt are immutable Sendable. Both protocol operations require the
original exclusive execution. Their source descent, exact scalar work, typed
buffer capacities, preparation and final publication debit that same owner.
Every typed buffer is admitted before creation.
Outer image groups use explicitly grown typed capacity, paid before reservation.
Physical radius admission compares the exact squared radius with the original
physical threshold squared; an outward lower endpoint is never that predicate.
No private counters, fresh limit or asynchronous state is introduced. Original
source, requested station and additional placement word are retained in the receipt.

## Failure, Concurrency, and Constraints
Invalid source/station, noncircular image, nonfinite bounds, cancellation and caller
source/geometric/algebra exhaustion fail before receipt publication. Source descent
and geometric queries use separate explicit capabilities. Exact coefficient work
reports structural depth zero; no algebra depth is charged as source nesting.
The original global and lexical byte policies remain binding; no child ledger
or byte-policy substitution is created. The explicit source, geometric and
algebraic capabilities intersect the actual execution limits independently.
Ordinary convenience methods create one execution and invoke the direct core.

## Verification and Change Impact

[OriginalCircularDirectExecutionTests](../../../Tests/CADGeometryTests/OriginalCircularDirectExecutionTests.swift)
checks the actual authored circle, retained source after input replacement,
center/radius/boundary enclosures, cumulative independent query costs, inner byte
refusal, malformed selection and cancellation. Its runtime execution remains a
required integration gate; source authorship is not success evidence.
Deferred until SOURCE87: public Native radial dimension/export paths for circle,
arc, reflected/nonuniform plane-preserving scale, parameter chains, an actual
ellipse refusal, tiny raw radius under large legal scale, source changes, same
ledger exhaustion/cancellation and stricter paper projection errors. No runtime,
review, commit or full D4 claim follows source authorship alone.

The receipt also owns outward projection of its center/boundary into an authored
OrthographicProjectionFrame and outward radius/diameter scaling. Arithmetic
remains inside Geometry; external consumers receive public ScalarInterval boxes,
not package-private interval operators or duplicated rounding algorithms.

Normalized boundary selections use a retained ParameterImageCurve3D with exact
originalUpper-originalLower gain and original lower offset. The supplied binary
normalized fraction remains original source, with no rounded native station.
Its zero-turn displacement is an exact identity and asserts no source period.
