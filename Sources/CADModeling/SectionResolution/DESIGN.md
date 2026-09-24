# Section Resolution

## Purpose and Scope

This component belongs to [CADModeling](../DESIGN.md). It resolves source
profiles and curves for feature evaluation and preflight. It has no children.

## Responsibilities and Boundaries

Own profile-index admission, source identity agreement, curve cardinality and
the distinction between resolving geometry and requiring a planar section.
Do not extract sketches, evaluate documents, construct geometry, infer a plane
from tessellation, or choose which input the user intended.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | FeatureEvaluating | Supplies admitted sections to existing builders. | Resolution is not geometric construction or whole-shape validation. |
| [CADIR](../../CADIR/DESIGN.md) | depends on | ProfileReference, EvaluatedCurve | Reads exact source values. | Identity and array position are different concepts. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | Sweep preflight | Uses the same admission as evaluation. | Preflight still owns fetching source geometry. |

## Architecture

```text
evaluated source arrays + reference
    -> ResolvedModelingSection admission
        -> profile / curve value
            -> exact construction or Sweep preflight
```

## Contracts and Invariants

- Profile resolution checks the index before subscripting, including negative,
  count-equal and Int.max inputs. Missing values throw missingProfile.
- A resolved value must belong to the referenced source feature. A mismatched
  source identity throws invalidGraph rather than using unrelated geometry.
- A curve reference without a segment index requires exactly one source curve;
  empty or ambiguous input is rejected, never truncated to its first element.
- Plane metadata is required by planar consumers, not invented by resolution.
- Input arrays and values retain Swift value semantics; the resolver does not
  map, filter, copy buffers manually, store state or cache results.
- These rules and Sendable conformances are unconditional across targets.

Extrude admits a shared section before construction. Closed profiles retain the
existing prismatic builder and topology roles. Planar curve sheets reuse the
exact linear-section Sweep builder with a single analytic line path; normal,
explicit vector and symmetric placement use the source plane, never display
samples. Generated geometry passes the existing exact BRep admission before
publication. Spatial curves without plane metadata remain an explicit incomplete
construction path, not a fabricated planar profile.

## Failure, Concurrency, and Constraints

Resolution is synchronous, stateless and constant-time, with no I/O, callbacks,
allocation loops, locks or cancellation ownership. Missing and mismatched
inputs remain explicit failures. The construction owner validates geometric
regularity and topology; resolution does not claim these properties.

## Verification and Change Impact

[SectionResolutionTests](../../../Tests/CADModelingTests/SectionResolutionTests.swift)
owns direct bounds, identity, ambiguity and plane behavior.
Existing SheetExtrude, CurvedRevolve, Loft and Sweep preflight/kernel tests
own construction and admission parity. A resolution-contract change requires
reviewing each of these consumers; source extraction remains outside this owner.
