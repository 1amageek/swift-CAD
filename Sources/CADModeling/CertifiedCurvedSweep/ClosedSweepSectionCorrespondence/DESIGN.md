# Closed Sweep Section Correspondence

## Purpose and Scope

This child of [CertifiedCurvedSweep](../DESIGN.md) owns the closed seam's
original section correspondence and tensor-row transport. It owns no public
feature DTO, path transport, guide solving or topology publication.

## Responsibilities and Boundaries

Authored endpoint twist is admitted independently of bare-frame holonomy.
The original section curve, directed chart and full interval frame action are
its source authority. Proposed rows and cyclic shifts are candidates.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CertifiedCurvedSweep](../DESIGN.md) | parent | retained endpoint frames and one invocation allowance | Supplies original path frames and authored twist. | Correction removes bare holonomy only. |
| [SectionResolution](../../SectionResolution/DESIGN.md) | depends on | original chart and final-candidate correspondence | Keeps original section laws separate from coefficients. | Restrictions retain nonlinear labels. |
| [GeometryConversion](../../../CADGeometry/GeometryConversion/DESIGN.md) | depends on | caller-admitted whole position, tangent and curvature certificate | Certifies every proposed final boundary. | Resource or source failures propagate. |

## Architecture

```text
original section chart + authored end twist
  -> whole span certificates -> unique directed cyclic correspondence
original section chart + retained actual end-frame interval action
  -> certificates against that correspondence
  -> compatible tensor row transport -> parent surface construction
```

## Contracts and Invariants

Authored symmetry is proved against the original section's candidate image
under modeling distance, tangent and curvature limits, independent of the
user's larger sweep approximation allowance. All spans participate; a sampled
seam or coefficient proximity cannot admit an asymmetric authored twist.
Loop order and traversal remain fixed. Every successful cyclic shift must be
unique. Multiple admitted shifts report `ambiguousSelection`.

Actual closure must use that same selected shift and original endpoint-frame
interval action. The action transports source D0/D1/D2, retaining frame
uncertainty. A midpoint rotation is never the source. A proposed row uses its
owning tensor's degree, knots and weights, and must be certified both against
the original target span and the original transformed source span. This binds
row transport to the actual coefficients published by the parent.

Different rational bases or loop permutations require a retained common-basis
or loop transport proof. Missing producers remain typed source gaps. A limited
compatible-basis success cannot close the full closed-sweep requirement.

## State, Ownership, and Lifecycle

Immutable actions, source adapters and guarantees live for one invocation.
All candidate arrays, certificates, source preparations and converter queries
charge the parent's same work and byte admission across all six attempts.
Source preparation is reused through original section owners.

## Failure, Concurrency, and Constraints

Invalid source domains fail explicitly. Rejected geometric candidates may
advance the finite cyclic search; cancellation, missing producers and resource
failures are never interpreted as rejection. No new depth, work, storage or
six-attempt limit is introduced. Mutable allowance state remains in the
parent's common Native/WASM/Embedded Mutex owner.

## Verification and Change Impact

Behavioral evidence belongs to `Tests/SwiftCADTests/ClosedPathPipeTests.swift`
and closed authored-twist fixtures: asymmetric half-turn rejection, square
half-turn and circle quarter-turn correspondence, unchanged intermediate
knots, unique shift ambiguity, original curved section bounds and exhausted
shared work/storage. Source-only integration precedes this verification.
Changes affect the parent's frame correction and sewing boundary publication.
