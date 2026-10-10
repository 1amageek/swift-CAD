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

## Exact Native Self-Contact Port

`OriginalExactNativeSelfContactQuerying` adds a public retained-L5 route beside the interval atlas. It consumes a complete `NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>` issued from one shared immutable source binding. It always issues the selected authored-coordinate diagonal, and accepts additional nonforgeable DI identity receipts for chart boundaries, periodic orbits, collapsed subsets and declared incidences. Equal XYZ alone never creates an exclusion.

```text
complete retained Native UVUV family + scoped DI identity receipts
    -> checked original-coordinate affine views for each chart/lift pair
    -> scope membership AND proved affine equality / complete-product identity
    -> NOT(identity union) in the retained L5 polynomial ring
    -> L4 whole-cell pullback refinement, preserving raw cell ordinals
    -> immutable residual contacts + original covers, laws, identities and lifts
```

The consumer retains every raw pair ordinal, including empty refinements. It does not claim an embedding certificate when residual contacts remain; completeness describes exact subtraction of the supplied proved identities from the complete original relation. A missing additional identity leaves its contact selected. A foreign owner, incompatible coordinate semantics, exhausted work/storage/depth, cancellation or incomplete lower refinement throws a typed `NativeExactRelationFailure`; no such path publishes absence or a partial result.

The checked DI views are the authority for affine words and identity constraints. Each receipt's selected left/right scopes are compiled with exact open/closed endpoints and disconnected interval unions in original coordinates. The original-to-local inverse maps are retained for queries; neither raw equality solving nor source law issuing is repeated. Caller L3/L4 limits and the same noncopyable admission apply throughout.

| Invariant | Behavioral evidence |
|---|---|
| Only selected proved identities are excluded | diagonal, seam, collapsed pole and scoped boundary fixtures |
| Nonstructural same-XYZ UV remains | folded surface opposite-UV fixture |
| All chart/lift and raw/refined owners survive | raw pair count and `sourceCellOrdinals` membership checks |
| Failure cannot become absence | foreign proof, cancellation and work/storage/depth refusal fixtures |
| Result owns its source lifetime | query after source value mutation |

The additive exact port depends on [Native Exact Relations](../NativeExactRelations/DESIGN.md), [Original Parameter Identity](../OriginalDomainIdentity/OriginalParameterIdentity/DESIGN.md) and [Original Parameter Transport](../OriginalDomainIdentity/OriginalParameterTransport/DESIGN.md). Existing interval atlas callbacks remain unchanged. Changes to DI views or L4 pullback guarantees require rechecking this exact consumer and its Native behavioral fixtures.

### Latest-main Native intake verification

The independent consumer assembly recompiles the actual Native consumer and its
source/DI/L5 adapters against current independently verified lower modules. It
reuses receipt-bound unchanged Native DTO/validation products; numerical CS/SSI,
Coons construction and cached old DI/L3 consumers are outside that reuse path.
Verification-only imports select these DTOs explicitly, preventing old cached
relation types from satisfying the new consumer signatures. Native and isolated
builds retain identical consumer bodies, immutable owners and failure semantics.
Actual face issuer/Topology acceptance remains separately bound to its retained
source and compiler receipt. No broad CAD production module is rebuilt.

### Authored-coordinate query field

The exact Native self-contact result accepts an optional query field, defaulting
to the prepared source field. Both two-coordinate tuples are validated in full
before visiting any pair, including a completely empty source product. The same
field supplies DI membership, inverse transport and retained refinement lookup.
The folded u=+/-sqrt(2)/2 fixture refutes treating new algebraic coordinates as
foreign ancestor-field values; unrelated fields and insufficient query depth must
still fail. Retained identity scope and original pair ordinals are unchanged.
