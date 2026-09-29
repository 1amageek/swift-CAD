# Rolling Ball Sewing Boundaries

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. Converts an admitted
rolling-ball blend into a face patch and updates its partner-cap boundary for
the existing B-rep sewer.

## Responsibilities and Boundaries

Owns the four directed boundary edges and blend-local pcurves. Original contact
rails remain the 3D edge geometry; endpoint cross-sections retain the blend
surface rather than fitted curves. The cap builder replaces an admitted
contiguous boundary chain and trims its neighboring edges at shared contacts.
Treatment selection, other source-face trimming, endpoint closure and solid
validation remain the feature evaluator's work.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | sewing request values | Owns topology construction. | Do not publish partial solids. |
| [Geometry RollingBall](../../CADGeometry/RollingBall/DESIGN.md) | depends on | immutable blend and contact rails | Supplies the exact represented surface. | Geometry alone does not prove machining feasibility. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | existing BRepSewing implementation | Combines source patches with the blend. | Shared contact spans must become one topological edge. |

## Architecture

```text
Admitted blend + face ancestry + requested orientation
    -> retained first/second contact rails + two surface-lift end sections
    -> directed rectangular UV loop -> existing orientation adapter
    -> BRepSewingFacePatch -> existing sewer
```

## Contracts and Invariants

`RollingBallTangentChainResolver` follows a selected edge along one fixed partner
face within a supplied shell. It indexes native coedge/vertex incidence once;
each boundary edge is visited at most once. Continuation requires a whole-seam
normal certificate between the other incident faces. A proved crease ends the
chain; missing topology, nonmanifold incidence, unsupported charts, or an
inconclusive certificate throw. The source model must already satisfy exact
positional correspondence. The result selects geometry only; it is neither a
closed-solid treatment nor permission to publish a feature. State is request-local,
and space/time for topology traversal are bounded by supplied shell incidence.

The default loop traverses (0,0), (1,0), (1,1), (0,1). Its first and third
edges retain the input contact curves with forward and reversed trims. End
sections are surface lifts with constant U. Reorientation reverses all trims,
pcurves and vertex ancestry together through the existing adapter. Stable edge
identities derive from the caller's face identity. No mesh, projection, fitted
boundary or widened tolerance substitutes for the admitted geometry.

A terminal patch may replace exactly one constant-U end with a caller-owned
certified implicit edge on the blend. A start boundary runs from V=1 to V=0;
an end boundary runs from V=0 to V=1. The native parameter derivative must
certify strict V monotonicity across the complete trim.
The whole U enclosure must remain inside the retained range and strictly
separate from the opposite end, excluding crossing or pinched boundary loops.
Both contact rails are trimmed at the boundary's U endpoints without replacing
their geometry.
The caller may supply a retained U interval for the opposite chain junction;
the entire computational support extension is not implicitly retained.
When given the opposite junction and an unoriented terminal, the builder chooses
the retained side from the whole terminal U enclosure relative to that junction,
then normalizes traversal to the required V direction. Curve reversal cannot
change the retained region; a crossing or touching junction is rejected.
Canonical terminal vertices, edge identity and ancestry are preserved through
patch reorientation. Invalid direction, unsupported certificate, degenerate
remaining rails or inconsistent correspondence fail before emitting a patch.
This constructs a trimmed patch, not a closed-solid machining result.

`junctionParameter` projects an adjacent patch's first contact onto the retained
first rail, then verifies its second contact at the same normalized U. It
returns a candidate section location, not a whole-edge coincidence proof;
the existing sewer must still admit the complete shared section. Off-rail or
inconsistent contact pairs fail instead of independently shifting either rail.

`RollingBallCapPatchBuilder` consumes original cap-edge identities and already
oriented replacement rails lifted from that exact cap support. It derives cap
pcurves from the rail truth, preserving curves and canonical vertices. Each cap
edge use retains its original cap-use identity and combines source and rail
ancestry; it must not reuse the blend face's use identity in a sewing request.
Reverse trims are restricted in ascending parameter order before pcurve reversal.
Exactly one contiguous cyclic chain in one loop may be replaced, including a
whole loop. Unchanged loops remain intact. At an open chain's ends, the existing
edge subdivider retains only the original edge segment joining the new contact
to its retained endpoint. Unknown identities, disconnected replacement chains,
off-support rails, ambiguous retained segments and nonclosing loops throw.
The output proves boundary construction only; global self-intersection and
closed-solid admission remain downstream requirements.

## Failure, Concurrency, and Constraints

All data is immutable request-local value state. Construction emits four edges
and one loop; existing geometry validation owns its bounded evaluation costs.
Invalid identity, degenerate edges or inconsistent endpoints throw rather than
returning a publishable patch. This operation does not mutate a source model.

## Verification and Change Impact

[NativeTerminalTrimTests](../../../Tests/CADKernelTests/NativeTerminalTrimTests.swift)
checks both terminal sides, reversal-invariant retained regions and canonical
boundary identity, and rejects a junction crossed only by the trim interior.

[RollingBallCapPatchBuilderTests](../../../Tests/CADModelingTests/RollingBallCapPatchBuilderTests.swift)
checks neighboring-edge retention, cyclic and whole-loop replacement, hole
preservation, and refusal of disconnected or off-boundary inputs.

[InvoluteGearProfileTests](../../../Tests/CADKernelTests/InvoluteGearProfileTests.swift)
must sew an actual trimmed helical flank and its blend with one shared contact
edge, preserving source geometry. A sheet result is not a completed machined
solid. Changes affect feature integration and the geometry rail contract above.
