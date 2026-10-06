# Original Surface Embedding

## Purpose and Scope
Parent: [CADGeometry](../DESIGN.md). Own the symmetric original surface self-contact atlas, local projection contraction and immutable prepared embedding session. No children.

## Responsibilities and Boundaries
Retain one original surface preparation and its finite authored UV domain. Geometry owns original continuity, differential and surface-pair contact witnesses. Consumers own material trim membership and publication. This component has no dependency on Topology, Modeling or Kernel.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original surface values | Neutral original geometry producer | No topology authority is introduced. |
| [Surface Surface Query Admission](../SurfaceSurfaceQueryAdmission/DESIGN.md) | depends on | prepared original self pair | One preparation and caller accounting | Critical and coincident completeness remains with the producer. |
| [Geometry Conversion](../GeometryConversion/DESIGN.md) | depends on | immutable admission | Construction callers borrow the same work and byte owner | No fresh allowance is created. |
| [Original Offset Feasibility](../../CADKernel/OriginalOffsetFeasibility/DESIGN.md) | used by | contact visitor with finite trim proof | Material self-contact composition | Consumers may exclude only whole outside trim boxes. |

## Architecture
```text
original surface + authored UV box + caller admission
    -> one original self-pair preparation + continuity receipt
    -> symmetric complete product atlas
    -> original differential contraction / original cross contacts
    -> full-domain embedding or consumer material-trim admission
```

## Contracts and Invariants
The session derives both self-query operands from one immutable preparation. Source recursion, geometric subdivision and exact algebra caps remain independent. Every atlas visit and lower query uses the supplied live callbacks; an absent byte callback remains absent. A conversion admission overload borrows its exact identity and counters rather than copying an allowance.

On a convex original chart box, a separately issued continuous piecewise-Lipschitz map receipt and outward infinity-norm contraction of `I - C J` strictly below one prove injectivity. A numerical inverse is only a preconditioner. Derivative hulls alone never issue continuity. A proved injective hull excludes the whole parameter pair, including its diagonal.

The atlas covers the complete symmetric product by two closed diagonal children and their one unordered cross pair. No small cell or coincident numerical endpoints prove injectivity. All cross contacts reach the original contact visitor. A full-domain certificate accepts an original implicit contact cell only when an injective hull proves that all its contacts belong to the same UV parameter, or throws self-intersection for a nonempty cell whose two parameter boxes are strictly separated and strictly inside the authored domain. A domain-boundary contact can represent an original periodic seam or declared boundary incidence; numerical parameter separation cannot label it an interior self-intersection. Critical, point, coincident and unresolved overlapping-UV or domain-boundary contacts require their original producer proofs before certification; they fail explicitly in the current partial branch. No absent numerical witness proves contact absence.

## State, Ownership, and Lifecycle
The session retains immutable original pair, UV domain, policy and callbacks once. No shared mutable counters are introduced; the composing invocation remains their owner on all targets. The atlas reserves its typed DFS payload before allocation. Intersection temporary accounting remains the lower producer's contract.

## Failure, Concurrency, and Constraints
Original source validation, cancellation, resource exhaustion and unresolved contact authority propagate. Historical surface-intersection per-proof limits remain intact and are tightened by an explicit smaller caller spatial cap. No private aggregate ceiling or tolerance widening is added.

## Verification and Change Impact
Deferred behavioral verification must cover regular sheets, discontinuous joins, separated-parameter self-intersections, shared UV interfaces, finite trimmed holes, exhausted work/bytes/depth and concurrent independent invocations. Offset and drafted-sheet consumers must recheck their original authority and publication whenever lower continuity or contact contracts change. Source-only publication of this component does not claim whole-domain implementation completion or runtime verification.
