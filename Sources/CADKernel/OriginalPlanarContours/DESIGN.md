# Original Planar Contours

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Owns original planar directed contour contact preparation and nonzero material arrangement for drawing glyph geometry. No children.

## Responsibilities and Boundaries
Native drawing owns command-to-original Bezier construction and source/shared endpoint IDs. This component owns global contour contact identity, directed incidence and region assembly. Geometry owns exact roots, cut order, overlap correspondence and outgoing germ sectors. Exchange owns legal HATCH output; this component imports no Exchange types.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | contour preparation | Original drawing geometry composition | Preparation alone does not publish regions |
| [Original Planar Contact Partition](../../CADGeometry/CurveCurveContact/PlanarPartition/DESIGN.md) | depends on | partition and mergeCuts | Complete exact incidence and retained split laws | Exact empty incidence is not a tolerance separation receipt |
| [BRep Drawing](../BRepDrawing/DESIGN.md) | used by | original contour sources | Native glyph bridge | Preserve paper coordinates and nonzero fill |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | signed original winding | Material sectors | Native pcurve enclosure and lower admission remain binding |

## Architecture
```text
closed directed original Bezier contours / shared endpoint IDs
    -> every original segment pair, including self contact
    -> source-bound exact contact/overlap events
    -> merge all cuts per original source
    -> retained original root spans + pair event identity
    -> overlap multiplicity / original outgoing sectors / nonzero winding
    -> true outer and hole boundaries
```

## Contracts and Invariants
The public input retains original nonperiodic clamped degree-one/two/three Bezier BSplineCurve3D controls and weights. Each directed segment uses its whole authored native interval and stable segment/vertex IDs. Contours close by exact shared endpoint identity and original endpoint coordinates; duplicate segment identities and conflicting vertex coordinates are invalid input. Controls and endpoints remain original values, never a fitted or flattened glyph.

Contact preparation traverses all unordered pairs including self pairs, retaining each complete partition and both input segment indices. One caller-owned OriginalQueryExecution spans all pair partitions and global cut merges. The public protocol requires that execution directly; removed contact allowance/admission adapters are not reconstructed. Upper copies, retained arrays and endpoint references charge the same execution before allocation or visits. This stage introduces no new numeric ceiling or fresh per-pair allowance.

Merged cuts retain exact input-endpoint indices, original native owner and source-bound algebraic roots. Produced pieces retain OriginalCurveRootSpan3D. Pair-local roots or numerical isolation centers never become global vertex identity, curve endpoints or replacement control nets. Preparation does not establish nonzero material boundaries: overlap direction, exact tangent/cusp sector order and signed winding must all be composed before region publication. No parity or sampled polygon fallback is admitted.

## State, Ownership, and Lifecycle
All source/preparation values are immutable Sendable. Input COW curve/contour buffers remain retained. Search arrays and the inout execution belong to one invocation; no shared mutable state or target-dependent synchronization is introduced. Retained byte counts use checked actual MemoryLayout strides.

## Failure, Concurrency, and Constraints
Invalid source/identity/closure, incomplete exact roots or sectors, exhausted existing contact allowance, callback failure, overflow and cancellation propagate. Prepared contact graphs are source stage values and never stand in for successful glyph regions. Complete region publication remains tracked until exact overlap/germ and winding consumers are implemented.

## Verification and Change Impact
Deferred checks must cover overlapping same-winding contours, opposite winding holes, line/quadratic/cubic tangent and cusp events, self-intersecting glyphs, unchanged original split laws, conflict IDs, callback exhaustion and cancellation. Recheck Native glyph command bridge and legal Exchange HATCH output. Source-only preparation is not a behavioral or region-completion claim.

Incidence composition unifies vertices only by authored endpoint IDs, retained paired exact events, and whole monotone-overlap correspondence. Signed union of complete overlapping original fragments retains native direction and sums authored contour multiplicities with checked integer arithmetic. Exact globally constant Bezier laws contribute no outgoing edge; no endpoint proximity removes a fragment. The Geometry issuer orders all remaining outgoing original germs at each unified vertex. This is directed incidence, not filled-face publication; global exact left/right sector winding is an additional required receipt, including disconnected and nested contours. All union traversals and buffer capacities use the identical caller units/BYTES callbacks.

Nonzero boundary resolution prepares one immutable Geometry winding source for all original directed contours, then reuses it for every incidence fragment's exact left/right sector winding. Native left-minus-right winding must equal the incidence multiplicity. A fragment is emitted only when exactly one side has zero winding, oriented with material on its left. The exact counterclockwise outgoing sector receipt selects the next boundary use by clockwise traversal from the incoming reverse germ, skipping internal non-boundary fragments. Every emitted edge must belong to exactly one closed cycle; conflicting coincident candidates, branches without continuation, premature revisits and uncovered edges fail. The result retains original span/direction/segment identity and whole side-winding receipts. Resolved zero/nonzero boundaries support parity filling equivalent to the authored nonzero material; no parity is applied to authored overlapping contours. Output boundary cycles do not infer outer/hole labels from rounded endpoint area.
