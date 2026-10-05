# Original BRep Bounds

## Purpose and Scope
Own finite spatial enclosure of original body and face source. Parent: [CADKernel](../DESIGN.md). No children. Existing face-query and body-classification callers consume these bounds.

## Responsibilities and Boundaries
Topology owns complete original finite trim extent. Geometry owns closed original position bounds and preparation. This component unions source enclosures and refines unresolved finite chart cells. It does not authorize surface regularity, material classification, or intersection completeness from a spatial box.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | spatial bounds composition | Finite face and body preparation | Bounds are conservative, not material witnesses |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | finite original parameter bounds | Complete trim chart coverage | Caller work/depth must reach the original pcurve producer |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | PreparedSurfaceDifferentialEncloser.positionBounds | Original closed source position enclosure | No sampled support or normalized normal is an enclosure |
| [BRep Ray Classification](../BRepRayClassification/DESIGN.md) | used by | immutable original bounds | Finite ray extent and face culling | Retain exact source snapshot binding |

## Architecture
```text
original finite face trim extent -> immutable original surface preparation
    -> closed position enclosure -> unresolved chart-cell refinement
        -> finite face bounds -> deterministic body union
```

## Contracts and Invariants
The compatibility `BRepFaceCurveClipper.parameterBounds` entry used by imprint completion and isoparametric publication resolves the original face support and delegates to this same complete native trim extent. A fixed number of boundary samples cannot select a projection domain or exclude a trim extremum.

The position-bounds operation retains the original surface/chart law, including nested images and singular boundary values. Each original producer and each refinement cell consumes caller work before processing. The caller depth ceiling constrains chart refinement and remaining original-source nesting. Historical local cell and span ceilings remain upper bounds; no new call resets a caller ledger. Existing analytic and control-net bounds remain their existing source-authorized paths.

`BRepBodySpatialBoundsResolving` exposes direct original body enclosure and caller-bound enclosure as protocol requirements. Its caller-bound route prepares each face's complete original finite trim extent with the same ledger, forwards that finite box to closed original position bounds, and unions every original shell face deterministically. It does not route through unaccounted edge-support sampling or legacy projection. The historical entry keeps its existing analytical/control-net policy; the caller-bound entry uses original closed position producers for every supported source family.

## State, Ownership, and Lifecycle

Legacy edge support bounds for original affine words and endpoint connectors consume the complete original position enclosure over the retained directed trim. The connector's construction control hull alone cannot bound its endpoint correction.
Preparation, chart stack and accumulated box are synchronous invocation-owned values. Prepared source backing is immutable Sendable; no shared mutable plan, target-specific storage, runtime type discovery or no-op lock is introduced.

## Failure, Concurrency, and Constraints
Missing source, invalid finite chart bounds, unresolved producer failure, exhausted work/depth, cancellation and nonfinite enclosure fail explicitly. The existing procedural cell ceiling is 1,048,576, chart depth 32, and original native span ceiling 262,144. Caller limits may be stricter. Until trim-extent, containment, intersection and projection callback paths are connected, this component does not establish a complete query-budget guarantee.

## Verification and Change Impact
After all source work, verify curved trimmed faces, holes, original image planes, poles and nested source images; confirm conservative containment and cancellation/work/depth failures. Recheck classification, query preparation and Boolean candidate pruning when enclosure authority changes. Source implementation is not behavioral evidence.

Normalized original construction charts consume the same original prepared whole-position enclosure as other retained source wrappers. No construction candidate control net or sampled endpoints supplies their spatial extent.

Finite original parameter extent accepts the caller's optional byte callback and independent source/algebra ceilings. It forwards them to Topology's original extent producer alongside the actual subdivision/work policy. A missing byte callback remains nil; this composition neither creates a private allowance nor claims complete physical allocation bounds from requested value slots.

Additive original body/face bounds carry independent source and algebra ceilings and optional bytes. Original extent, prepared support and closed position query forward the same callback. The four-way DFS reserves at most three times depth plus one retained cells before allocation; each four-cell subdivision scratch is separately admitted. Existing work-only entries preserve their original source-depth policy.
