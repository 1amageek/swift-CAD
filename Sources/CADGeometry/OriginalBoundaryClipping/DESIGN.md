# Original Boundary Clipping

## Purpose and Scope
Parent: [CADGeometry](../DESIGN.md). No children. Own the source-bound parameter clipping consumer for complete Native CS/SSI receipts. This component does not publish geometric image strata or a maximal geometric overlap result.

## Responsibilities and Boundaries
The issuer supplies every authored directed pcurve and loop role, bound to one retained raw receipt and one original surface side. The consumer retains all original source laws, denominator guards, requested/native domains and derivative-closed raw cell conditions. Neither a cell sample nor a tolerance authorizes inside, absence, cell identity or source equality. CADKernel owns original face/coedge identity; this component owns exact boundary laws, parameter refinement and raw-cell correspondence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [IntersectionAlgebra](../IntersectionAlgebra/DESIGN.md) | depends on | Complete original sign selection, closure, incidence and components | Existing Q5 engine performs the full refinement | Original ring, source and independent depth admission remain bound |
| [Native CS](../CurveSurfaceOverlap/NativeRelation/DESIGN.md) | depends on | Complete raw chart/domain receipt | Retains original T/UV cells | Native samples do not represent cell ranges |
| [Native SSI](../NativeSurfaceSurfaceRelations/DESIGN.md) | depends on | Complete raw UV receipt | Retains both original sources and UV fibers | Parameter components are not image components |
| [Kernel issuer](../../CADKernel/OriginalBoundaryClipping/DESIGN.md) | used by | Immutable face-issued boundary domain | Face/source binding precedes clipping | Authored pcurves are already directed |

## Architecture
```text
retained Native raw cells + face-issued directed loops
    -> original source/domain and parent-path sign laws
    -> exact directed segment boundary/crossing laws
    -> original Boolean selection in the same T/UV ring
    -> Q5 closure/incidence/components
    -> parameter receipt + whole-cell original raw identifiers
```

## Contracts and Invariants
- A boundary domain retains its particular raw receipt, surface side, source surface and the complete loop buffer. Another equal-valued receipt does not replace its owner.
- The initial issuer supports constantU, constantV, affine and authored polyline pcurves on a nonperiodic native B-spline support. Every endpoint is computed over the original binary-rational coefficients, including affine parameter multiplication; no rounded evaluation is used.
- Each directed segment contributes exact half-open upward/downward ray-crossing predicates. Their signed sum defines nonzero winding, with an independent closed-segment zero predicate for boundary membership. Outer material is the union of outer loop interiors; inner loop interiors are removed. Closed selection retains hole and outer boundaries, strict selection excludes every boundary, and boundary-only selection keeps only retained material boundaries.
- Authored pcurve traversal is used unchanged. Topological coedge orientation is retained by the issuer and never applies a second reversal.
- Raw selected cells are identified by their full derivative-closed parent-path sign conjunction, including original domain bounds. The combined law list also retains the raw source equations/guards. Refined-cell correspondence evaluates complete sign conditions; it never classifies a sample.
- The selected result is fully decomposed before publication. Complete empty selection is valid only after the same original predicate is resolved over the whole original requested domain. Every selected refined cell has exactly one original raw-cell owner.
- Parameter/component identity is receipt-local. Original raw owners, source input and boundary buffers outlive all result queries.

## Runtime Flows
Preparation, Boolean compilation, Q5 refinement, correspondence and result allocation borrow the same caller work/storage/cell/coefficient-cell owners. Retained source depth is admitted before descendant work; descendant visits preserve that baseline. The final normal-return callback is followed by current-task cancellation before publishing a domain, result or membership value.

## State, Ownership, and Lifecycle
All receipts and backing buffers are immutable. There is no global cache, shared mutable state, conditional target storage or independent quota. A result retains its raw receipt and issued boundary domain. Query-local admissions never outlive the call.

## Failure, Concurrency, and Constraints
Checked capacity arithmetic and storage admission precede generated buffers. Invalid source/domain binding, missing or unclosed directed trims, exhausted caller resources, independent depth failures and cancellation propagate without a success value. Rational spline, implicit/nonrational trim charts, periodic/pole chart authorities and refined image/fiber strata remain incomplete branches with explicit code markers and typed failures. Their presence does not count as support for whole requirement 4.

## Verification and Change Impact
[Kernel tests](../../../Tests/CADKernelTests/OriginalFaceBoundaryClippingTests.swift) execute the public raw receipt -> original face issuer -> exact consumer route for holes, nonconvex loops, corners, endpoint/boundary coincidence, strict/closed/empty selection, original raw-cell ownership, source-release lifetime, foreign binding and independent admission/cancellation failures. Native CS/SSI raw receipt behavior and Q5 are unchanged lower premises. Changes to boundary meaning require the Kernel issuer and result correspondence proofs to be revalidated. Whole source-family/domain acceptance and image clipping remain requirement-4 integration work.
