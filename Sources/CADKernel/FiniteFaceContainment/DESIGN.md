# Finite Face Containment

## Purpose and Scope
Own point and original parameter containment in authored finite face trims. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
Geometry owns original support projection. Topology owns original pcurve enclosures and certified loop classification. This component prepares immutable original face loops, handles source periodic chart representatives and combines outer/inner trim decisions. It does not classify a solid from a face-containment result.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | finite face containment composition | Shared classifier and query support | No sampled polygon is containment authority |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | CertifiedSurfaceParameterLoopPredicate and original pcurve enclosures | Whole authored finite trim classification | Preserve original interval work and depth ceilings |
| [Surface Projection Admission](../../CADGeometry/SurfaceProjectionAdmission/DESIGN.md) | depends on | finite original support projection with caller admission | Point-to-original-chart correspondence | A closest-point upper residual alone cannot prove absence within tolerance |
| [Original BRep Bounds](../OriginalBRepBounds/DESIGN.md) | depends on | OriginalFaceParameterBounds | Complete authored finite support chart | The retained domain belongs to the exact original face and surface |
| [BRep Ray Classification](../BRepRayClassification/DESIGN.md) | used by | prepared containment witnesses | Actual finite ray event admission | Sessions remain bound to their exact source snapshot |

## Architecture
```text
original model faces -> original trim curves and periodic chart alignment
    -> immutable prepared loop regions -> original point projection / supplied native UV
        -> certified whole-loop predicate -> outer material minus hole interiors
```

## Contracts and Invariants
Prepared sessions reject unowned faces and retain original support and authored pcurve law. Numerical polygons supply chart representatives only; whole original predicates determine containment. Public session capabilities and bounded preparation use protocol requirements, preserving the same Sendable witness and immutable storage on all targets. A bounded injected provider must supply actual same-ledger preparation; missing capability fails explicitly without replacing that provider or resetting its legacy allowance. Optional unavailable preparation uses the provider's direct operation; unavailable parameter containment uses the same session's model-space operation.

Caller accounting covers each processed source face, loop, coedge, parameter box and predicate decision before its work. Original lower producer callbacks consume the same invocation ledger. A callback added only around an opaque producer does not establish a complete query-resource guarantee. Historical tolerances and local proof ceilings remain unchanged; stricter caller depth ceilings compose with them.

Bounded model-space containment retains the exact face's complete finite original UV extent in its immutable preparation. Projection over that extent forwards the same caller ledger and the stricter of the caller and historical projection depth ceilings. A projected witness must carry an original residual upper bound within the requested distance tolerance. Returning false from projection requires complete original threshold exclusion; a closest-point residual upper bound above the tolerance does not establish that exclusion. Ambiguous threshold coverage remains an explicit lower failure. Legacy convenience calls retain their existing projection entry and policy.

## State, Ownership, and Lifecycle
| State | All-target storage | Read | Mutation / lifetime |
|---|---|---|---|
| Prepared face snapshot and bounded original UV extent | Immutable Sendable map | Containment protocol witness | Invocation-local construction and value-owner release |
| Preparation cache | Synchronous caller-owned local dictionary | Exact face-ID lookup in one original snapshot | No shared concurrent mutation |

## Failure, Concurrency, and Constraints
Missing source references, discontinuous original trim charts, unresolved original containment, invalid caller limits, exhausted producer work/depth and cancellation fail explicitly. Primitive constant-level periodic bands retain their existing contract. General nonconstant noncontractible bands remain a separate existing source gap; no ordinary bounded polygon result establishes their completeness. Original pcurve reconstruction and validation preparation must also forward caller admission before a whole-query budget guarantee.

## Verification and Change Impact
After source work, verify original-image trims, holes, periodic chart representatives, singular closed boundaries and foreign session IDs, together with work/depth/cancellation failures. Recheck Boolean region classification, ray classification, surface queries and edit publication after changes to original pcurve or projection authority. Source-only work does not establish behavioral completion.

## Original Trim Box Interior
Byte-admitted classification overloads retain one original boundary-exclusion DFS stack per invocation and reuse it across all outer/hole boundaries. Its depth-first traversal requires at most caller depth plus one cells; that owned capacity is admitted before allocation. Modified-patch curve-copy payload is admitted before construction. Legacy work-only entries retain their existing policy. The same byte callback remains a separate required lower dependency for Topology enclosure/winding temporaries; owning this stack does not authorize a whole query storage claim.

The unchanged-face entry `classify(_:in:validatedModel:maximumSubdivisionDepth:consumeWork:)` derives its support, tolerance, loops and pcurves directly from an immutable exact or volumetric source receipt. After whole-box exclusion of every original boundary, it constructs the Topology receipt-bound loop predicate by original LoopID. The predicate retains the original immutable coedge buffer through its source view; no copied-curve buffer, sewing patch reconstruction or endpoint re-evaluation is needed. Modified sewing patches continue to require their separate original validation premise. Lower enclosure and query temporary byte admission remain separate storage dependencies.

`classify(_:inAdmitted:tolerance:maximumSubdivisionDepth:consumeWork:)` distinguishes `.inside`, `.outside` and `.boundaryOverlap`. Outside is authorized only after every original boundary excludes the whole connected box and original winding establishes a nonmaterial region. Boundary overlap retains the candidate for original intersection-cell refinement and never proves an actual model-space intersection or absence. `containsStrictly` is the compatibility projection of this classification to `.inside`. Unresolved separation at the supplied work/depth limit remains a typed failure.
`OriginalFaceTrimBoxContaining.containsStrictly(_:inAdmitted:tolerance:maximumSubdivisionDepth:consumeWork:)` consumes a nonempty finite connected original UV box and an already-admitted immutable original face patch in its authored chart. Complete original boundary enclosures must exclude the entire box from every outer and hole boundary. Only after that exclusion may a certified signed winding at a point inside the box select its connected material region. The point does not supply an intersection witness; the caller retains the original nonempty intersection component and its enclosing UV box. Numeric periodic wrapping never changes this chart.

```text
original intersection component + original UV box + admitted original trim patch
    -> every original outer/hole boundary excludes the WHOLE connected box
        -> original signed winding -> strict material interior certificate
```

Each visited original normalized interval and nested enclosure/predicate call consumes the same caller callback, with remaining depth after its actual enclosing interval depth. Original enclosure/loop ceilings remain 131072 cells and depth48; outer box exclusion observes those same local ceilings. Boundary overlap cannot yield true; exhausted separation, source ambiguity and cancellation propagate. A hull entirely inside the queried box proves a boundary witness and returns false. The source patch's original validation/endpoint/correspondence receipt remains a caller prerequisite: constructing the lower loop predicate is not paid full source admission, and this port does not establish that missing prevalidated-patch accounting. F8 and Boolean callers must retain that causal gap until their actual original patch admission is closed.

Deferred checks include narrow holes, curved trim extrema, tangencies to the box, an intersection component whose numeric center lies inside but its original box crosses a boundary, native image charts, no point-only witness, and shared work/depth failures.

Modified/generated patch winding construction binds every original curve to `patch.surface` through the bounded Topology predicate constructor. Its original continuous-chart and closed endpoint admission shares caller work, depth, source-recursion allowance and optional byte callback. Independently modified supports cannot reuse an unchanged model receipt. The per-query boundary DFS and curve-copy payload remain this component's byte responsibility; lower original enclosure/winding scratch admission remains the lower owner's explicit gap.

Original boundary exclusion and signed winding forward the same optional caller byte callback into Topology query frontier, output and winding buffers. These actual allocations share the caller invocation; remaining chart preparation and specialized lower scratch retain their own explicit incomplete contracts.

A configured containment provider retains an optional byte admission and independent source/algebra limits. Its original finite extent and loop query forward that exact byte callback, including nil when byte accounting is not selected. These additions preserve legacy defaults. Chart alignment, original endpoint queries and projection preparation must still close their concrete lower contracts before the provider can issue a whole resource guarantee.

Whole-box containment retains independent original source-recursion and algebra limits, defaulting to the lower existing policies 16 and 32. Both immutable-face and generated-patch entries forward these limits to boundary enclosures and receipt-bound winding; geometric subdivision never selects either limit. Invalid selected limits fail before original traversal.

The additive unchanged-face whole-box protocol requirement accepts explicit source and algebra caps in addition to geometry depth, work and optional bytes. Injected providers must implement this witness; compatibility cannot substitute a provider with reset policy. The original implementation constructs an immutable configured classifier and consumes its existing original receipt path.

The generated-patch whole-box requirement accepts those same independent caps directly. It retains the caller's admitted patch premise and delegates to the configured original boundary-exclusion and winding algorithm. Both the unchanged-face and generated-patch witnesses preserve optional byte admission without substituting a no-op callback; a provider's default configuration cannot override explicit caller limits.

Authored parameter samples retain the complete ModelingTolerance for the same work visit and use its distance member only for numerical duplicate/pole comparisons. An original affine-word pcurve preserves the authored winding policy of its retained source parameter curve, including directed subranges; its spatial word does not select a different periodic chart.
