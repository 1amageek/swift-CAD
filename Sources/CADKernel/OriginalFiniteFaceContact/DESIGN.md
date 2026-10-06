# Original Finite Face Contact

## Purpose and Scope
Own original finite face-pair contact classification for generated sheets, Offset, Thicken and Loft. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
This component consumes an immutable exact BRep receipt and one caller's independent source, spatial and algebra capabilities. It prepares the original pair graph once, excludes complete original intersection ranges outside either authored finite trim, and detects material-interior crossings. Geometry owns complete support intersections and retained root localization; Topology owns original parameter-curve enclosures and winding. Feature adapters own their domain-specific rejection errors.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | generated-result composition | One caller admission | Source construction is not runtime evidence |
| [Prepared Boolean Operation](../PreparedBooleanOperation/DESIGN.md) | depends on | prepared original face-pair graph | Identical exact source receipt | Critical/coincident completeness remains the producer's obligation |
| [Finite Face Containment](../FiniteFaceContainment/DESIGN.md) | depends on | whole original UV-box classification | Finite material including holes | Boundary overlap does not prove material absence |
| [Loft Finite Cap Contact](../LoftFiniteCapContact/DESIGN.md) | used by | original cap/side classification | Shared source and caller admission | Shared topology must cover the whole returned component |
| [Original Offset Feasibility](../OriginalOffsetFeasibility/DESIGN.md) | used by | result face-pair classification | Retains result-scope admission | Same-face embedding is a separate contract |

## Architecture
```text
exact original model + face pair + caller admission
    -> one prepared original support-intersection graph
        -> exact shared-edge component identity
        -> original owning UV boxes / truth-issued pcurves
            -> whole outer/hole boundary exclusion and winding
                -> original interval refinement
                    -> disjoint / shared topology / material interior
```

## Contracts and Invariants
A material-interior result requires a retained nonempty original component whose complete UV box lies inside both finite trims. Disjointness requires complete coverage of every returned component by outside decisions for at least one face. A shared-topology decision requires the same original edge identity incident to both faces, structural equality of the entire returned original curve law and coverage of its full native domain by that edge's authored trim. A shared edge never excludes a second component on the same supports.

Implicit localization retains one preparation per original graph and separate owning-cell states. Every child interval is a closed partition of its parent. Spatial refinement reduces only the remaining spatial capability; original source depth and algebra capability remain independent. Truth-issued analytic pcurves use original D0 coverage; residual-only parametric caches cannot issue a contact witness.

## State, Ownership, and Lifecycle
The classifier value is immutable. Prepared graphs, localization states and DFS buffers belong to the invocation. Capacity arithmetic is checked and typed bytes are requested before allocation. Optional byte admission remains nil when unselected. All work, original preparation, comparisons and query bytes use the same borrowed callbacks; this component introduces no cumulative allowance.

## Failure, Concurrency, and Constraints
Cancellation is checked at visits. Unresolved trim crossings fail at the supplied spatial limit; they are never interpreted as touching or outside. Original point/coincident-sector classification, generic critical support completeness, nonlinear shared subspan correspondence and specialized query scratch remain explicit lower gaps. Legacy adapters retain their historical behavior; this selected route never replays an unmetered legacy splitter.

## Verification and Change Impact
Deferred behavioral evidence covers original support intersections outside finite trims, holes, narrow material crossings, full shared edges plus additional crossings, partial shared boundaries, analytic and implicit owning curves, independent zero spatial/algebra capabilities, cancellation and selected byte exhaustion. Recheck feature adapters after changes to graph completeness or finite-trim authority. No behavioral verification has run in this source phase.
