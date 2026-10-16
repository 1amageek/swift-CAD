# BRep Ray Classification

## Purpose and Scope
Own original finite face ray events used by solid and sheet-side classification. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
Topology owns complete original face UV extent. Geometry owns complete original curve/surface events. This component forwards finite original trim bounds, admits events within actual authored trims, and handles shared topology crossings. Numerical support-plane representatives do not replace original images.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | original classification composition | Solid and sheet ray events | No partial event set may publish |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | FaceParameterExtentResolver | Whole original finite face extent | Fixed stations are insufficient |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | CurveSurfaceIntersecting | Complete original support events | Explicit finite UV ranges required for unbounded image charts |

## Architecture
```text
original body/face snapshot -> complete finite authored UV extent
    -> original ray/support intersection -> actual finite trim admission
        -> distinct oriented face events -> solid/sheet classification
```

## Contracts and Invariants
Every face intersection receives its original finite authored UV extent, intersected only with an original bounded domain. An unbounded original-image plane must not fall into an interval solver with missing UV ranges. Prepared solid classification sessions retain immutable extent maps tied to their exact model snapshot. Ray invocations borrow the same OriginalQueryExecution with independent ray/trim48, source16 and algebra32 local ceilings intersected with incoming limits. Each original face, event and shared-event comparison admits work before evaluation; complete CurveSurfaceIntersecting traversal and authored surface normal evaluation receive the same execution. Unresolved containment propagates on ordinary and direct routes. The former ordinary catches for intersectionFailure and invalidVectorLength in liesOnFace are retired: neither failure proves nonmembership, so skipping that face could incorrectly permit material parity. Other callers may compute the same original bounds at invocation. Boundaries, original normals and curve events remain lower source authority.

Session preparation and parameter-space containment are protocol requirements with identical Sendable contracts on Native, WASM and Embedded targets. Optional preparation absence selects the same provider's direct classification or containment operation; it is not a successful classification. A prepared session owns immutable source-bound data and rejects foreign faces. Parameter-capable sessions supply their decision through a witness-table requirement rather than a runtime existential cast. Point-only sessions retain their original point-containment semantics.

| State | Native / WASM / Embedded storage | Read entry | Mutation / release |
|---|---|---|---|
| Prepared body and face maps | Immutable Sendable session fields | Protocol requirements | Invocation-local construction; value-owner release |
| Preparation accumulator | Local dictionary owned by one synchronous invocation | Construction helper | No shared mutation or callback under a lock |

## Failure, Concurrency, and Constraints
Missing source geometry, nonpositive finite extents, unresolved intersections and existing lower bounds fail explicitly. Existing tolerances and algorithm limits remain unchanged. Session maps are immutable, invocation-owned and Sendable. Bounded original intersection and normal producers now forward caller work/depth admission. Remaining original pcurve reconstruction/validation and lower family join gaps still prevent a whole-query resource/completeness claim; bounds or outer event charging alone cannot establish that claim.

## Verification and Change Impact
Deferred behavior includes parsed planar bodies after translation/rotation/scale/reflection, native and foreign original-image charts, trimmed curved faces, holes, grazing rays and cancellation. Recheck classification and transformed-body publication when original UV extent or event contracts change. Source edits do not establish behavioral completion.

Original ray preparation retains independent source/algebra limits and the incoming allocation policy through finite face extent and authored surface normals. A curve-surface provider lacking the selected byte-admitted event requirement cannot yield a byte guarantee via its work-only route. Numeric normal representatives retain their existing crossing contract; this forwarding does not create an original material-side proof.

Selected ray events consume the non-generic complete curve-surface requirement
with the same execution and independently retained source and
algebra ceilings. No no-op storage sink or legacy service resets that admission.
An original angular enclosure straddling the transverse/tangent threshold is an
unresolved event, not an absent crossing. Typed crossing-buffer growth is admitted
before allocation; selected stable ordering consumes work in place. These typed
requests do not establish completeness of unrelated lower allocation or original
critical/grazing material-sector producers.
