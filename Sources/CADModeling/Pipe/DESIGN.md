# Pipe Construction

## Purpose and Scope

This child of [CADModeling](../DESIGN.md) owns Pipe path fractions, custom
section placement and composed Sweep evaluation. It owns no new CADIR operation
or geometry validation authority.

## Responsibilities and Boundaries

Retains the original directed path spans and section source through composed
Sweep. Candidate samples and composite splines are staging metadata. Original
arc-length fractions, original endpoint tangents and section moments require
whole source bounds. Sweep owns sewing, Boolean application and publication.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | Pipe evaluator composition | Publishes complete feature output. | Generated staging IDs do not create original source authority. |
| [SweepInvocation](../SweepInvocation/DESIGN.md) | depends on | immutable original source carrier | Preserves original paths through nested Sweep. | Nested rings share one allowance. |
| [SectionResolution](../SectionResolution/DESIGN.md) | depends on | original spans and resolved face sections | Preserves analytic/native trims and loop ownership. | Custom face placement cannot use the facade's candidate as source. |
| [CertifiedCurvedSweep](../CertifiedCurvedSweep/DESIGN.md) | depends on | original moving-frame and closed seam proof | Handles closed paths and authored twist. | Original path fractions must remain retained laws. |

## Architecture

```text
original Pipe path + section -> source preparation
  -> original fraction/placement receipts -> invocation carrier
  -> Sweep construction -> final Boolean/topology publication
```

## Contracts and Invariants

The exact constant-speed cut arm requires exactly one retained source span. A first span alone cannot establish that cardinality; all other cuts retain the existing typed inverse-arc-length refusal.


One existing source allowance begins before path conversion and survives all
nested Sweep operations. Every retained span keeps its original curve, directed
chart and actual final correspondence. Circle symmetry does not permit erasing
an authored twist law; the closed original correspondence decides seam closure.
Fraction cuts must retain the original inverse arc-length boundary expression.
On one original constant-speed line chart the fraction itself is the exact
inverse; the shared builder certifies that restricted original chart directly.
Other charts require the complete original inverse-length producer and cannot
publish a quadrature midpoint as a boundary. Tangent extension likewise requires
the original length/tangent expression rather than a candidate spline integral.
Extensions preserve original path portions and their whole endpoint tangent and
length laws. Custom section centroid and placement use original loop moments,
including holes; quadrature and samples are candidate proposals only.
`OriginalPipeSectionMoments` integrates the complete retained directed boundary
jets. Each loop's signed area is separated from zero before its moment sign is
selected by outer/hole role. The planar Gram inverse transports projected
moments without assuming that rounded basis vectors are exactly orthonormal.
Closed interval integrands enclose each entire cell. A midpoint tightening may
use the original first-derivative oscillation only with a retained smoothness
receipt; unknown joins retain rectangular whole-cell integration. The centroid
candidate is admitted only when its complete original position enclosure fits
one eighth of the original distance tolerance. Adaptive cells, source
preparation and every refinement use the existing invocation work/depth/BYTES.
Arc preparation receives independent original source and algebra depth from the
same conversion admission; spatial subdivision never becomes a source-depth
allowance. Each lower producer retains the minimum of caller and owning caps.
The placed origin and tangent likewise come from the retained original path's
closed endpoint jet. Candidate origin error fits one eighth of the distance
tolerance; a positive original speed and whole cross/dot cone admit the tangent
within the unchanged angle tolerance. A candidate construction spline cannot
select this start pose.
Staged path curves are the persistent normalized original construction charts,
one per retained span. Every display station uses paid closed original position
jets; the curve field retains the source chart rather than a composed candidate
spline. Nested legacy straight/twist consumers therefore cannot accidentally
replace the retained path with that staging image.

## State, Ownership, and Lifecycle

Staging context values remain local. The invocation retains immutable sources
and receipts; the shared allowance uses the same Mutex owner across targets.

## Failure, Concurrency, and Constraints

Unresolved original fraction, offset or placement producers fail with typed
errors and precise incomplete markers. No new work, storage, depth or sampling
ceiling substitutes for a required source proof. Hollow-ring operations require
one final Boolean composition over their admitted original union.

## Verification and Change Impact

`Tests/SwiftCADTests/PipeTests.swift`, `PipeCustomProfileTests.swift` and
`ClosedPathPipeTests.swift` own fraction, extension, custom-face placement,
hole/wall, nested Boolean and closed authored-twist behavior. Changes affect
SweepInvocation, section source conversion and final Boolean publication.
Source-only construction precedes verification.
