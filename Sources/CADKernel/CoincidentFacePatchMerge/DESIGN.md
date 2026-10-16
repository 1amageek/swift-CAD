# Coincident Face Patch Merge

## Purpose and Scope
Own one geometric representative of each identical arranged face region before Region Boolean cell extraction. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
Merge faces only after shared face arrangement has split all trim outlines. Preserve provenance on face, edge and vertex boundaries. Spatial coincidence of supports alone does not authorize merging different trimmed domains.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | RegionBooleanEvaluator | Shared support partition then cell extraction | Duplicate coincident faces must not create zero-thickness cells. |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | ExactTrimEdgeIntersector | Exact common edge support | Endpoint equality alone is insufficient. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | SurfaceSurfaceIntersecting | Certified common surface support | Partial overlap is resolved before this merger. |

## Architecture
```text
Shared arranged trim regions -> certified matching support + complete matching loops
                            -> one face with merged provenance -> cell complex
```

## Contracts and Invariants
A face merges only when every loop role and complete trimmed edge has a bijective corresponding loop/edge on a certified common support. Different holes, different boundaries and touching domains stay distinct. Representative ordering is stable by patch ID. The merged provenance includes every contributing face, edge and vertex parent.

## Verification and Change Impact
Deferred verification must cover fully coincident regions, partial planar and curved overlap, holes, opposite orientations, multiple operands, touching-only faces and resulting cell volumes. Exact matching failures propagate; this source stage does not claim behavioral verification.

Finite coincident area classification first isolates all original trim-edge intersections, subdivides both oriented boundaries at the complete event set, and classifies one point only within each event-free interval. A point on an opposing boundary does not prove area. Complete matching outer boundaries prove equal material on their interior side; outer-to-hole coincidence is only contact. Root isolation, boundary containment and whole-span correspondence failures remain failures. This replaces fixed quarter/midpoint side probes, which could skip sliver regions.

A transverse segment is admitted as an existing face boundary only after whole original curve-span coincidence with one scoped authored edge. Endpoint projection selects a candidate subspan; endpoints plus an interior sample cannot establish boundary ownership. This admission is used by the coincident ownership resolver before deciding whether a face requires arrangement.

Common-point publication prefers an interior point of a proved coincident regular original boundary span before isolated endpoint events. Singular pole/apex contacts remain valid fallback witnesses for touch queries, while coincident ownership can use a regular whole-span witness instead of evaluating a surface normal at a coordinate singularity. No midpoint belongs to both faces unless the whole span correspondence or actual finite-face containment proves it.

Complete coincident ownership actions are material selection even when no trim boundary partitions a face. The general intersection composition must consume these forced actions through the face materializer instead of falling back to whole-body contact rejection. Exactly one kept face paired with a discarded fully equivalent face merges the discarded original face/edge/vertex ancestry into that retained region; the duplicate is never published. Pairs with both faces discarded do not create a representative. A completely discarded material selection is typed emptyResult.

## State, Ownership, and Lifecycle

The canonical direct merger and finite-area classifier borrow one OriginalQueryExecution through original source patch construction, trim contacts, subdivision, containment and support intersection. Invocation-local collections own mutable construction. Ordinary merger entry creates one operation execution; direct callers retain incoming limits, selected contributions and cancellation. Constructive arrangement proximity remains marked incomplete original authority and cannot establish Boolean/M7 completion.
