# Original Revolution

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns a retained original
root traversal revolved around an authored parametric axis, with its original
angular chart and normalized generator chart.

## Responsibilities and Boundaries

Geometry owns the spatial law, closed derivatives, root-bound endpoint incidence
and source persistence. Modeling owns sheet topology, orbit admission and all four
SurfaceLift boundary uses. A numerical root station never replaces a source root.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | persistent surface dispatch | Publishes source family. | Preserve original charts. |
| [Original Root Span](../OriginalRootSpan/DESIGN.md) | depends on | retained owning coefficients and endpoint roots | Supplies original generator. | No numeric root collapse. |
| [Surface Pole Geometry](../SurfacePoleGeometry/DESIGN.md) | used by | closed normal factor law | Certifies collapsed endpoints. | Higher pole order needs coefficient factor proof. |

## Architecture

```text
original generator + root endpoints -> retained normalized generator jet
raw axis -> outward normalized original axis
original angle -> Rodrigues law -> closed surface jet -> SurfaceLift boundaries
```

## Contracts and Invariants

U is the authored finite angle interval in radians; V is normalized [0,1].
The axis direction is retained unnormalized. Normalization belongs to outward
original arithmetic. At an endpoint whose original root proves axis incidence,
the radial value and all pure angular derivatives are exactly zero; generator
and mixed derivatives retain the original owning law. A point is a numerical
representative enclosed by the complete source value, never an incidence proof.

## State, Ownership, and Lifecycle

All source and prepared coefficient records are immutable and Sendable. Equality
and persistence use original public source fields, excluding derived enclosures.
Preparation consumes caller work/storage; fixed evaluation forwards the same caller execution
and performs no independent root refinement or traversal budget reset.

## Failure, Concurrency, and Constraints

Wrong source tolerance/domain, uncertified source roots, missing retained owning
coefficients, nonfinite arithmetic and unresolved position error fail explicitly.
No mutable shared state or platform-dependent synchronization is introduced.

## Verification and Change Impact

After the source phase, verify original interior axis roots, reversed generators,
closed mixed derivatives, arbitrary pole order, signed axis orientation, finite
partial/full turns, source decoding admission and four boundary publication.

Package point and third-order realization overloads forward the same exclusive
`inout OriginalQueryExecution` to retained coefficient evaluation. Modeling boundary realization uses
these overloads; ordinary public convenience methods preserve historical fixed
evaluation while never starting a separate proof traversal.

The retained Rodrigues angular law exposes the same intrinsic radian orbit period
as original analytic angular surfaces, while its authored U domain stays finite.
SurfaceParameterTopology carries this intrinsic period and exact axis endpoint
V values. Foreign image periods are numeric chart proposals; exact closure still
binds the original source/chart receipt rather than a rounded inverse gain.

### Closed Original Pole Normal Factors

The dedicated OriginalRevolutionPoleNormal producer owns rational-generator
endpoint germ preparation and closed whole-panel factor bounds. It reuses exact
original derivative numerators and the retained algebraic endpoint sign witness.
Transverse and axial derivative vanishing orders determine the least shared
inward power of the Rodrigues normal. Integral Taylor remainders retain original
closed coefficient authority after division, including arbitrarily high native
pole order. Prepared immutable proof values and evaluation forward the same
caller exact work/storage/cell/depth admission. Surface composition adapters use
its source-bound OriginalSurfacePoleNormalPanel; tensor factor recognition stays
with SurfacePoleGeometry. Algebraic angular and transformed root germ support
remains an explicit completion condition of this producer.

An inconclusive remaining factored normal lower norm reports singularSystem so
the original caller subdivides its owning panel. It does not assert geometric
singularity. Upper-pole inward extents use an outward original 1−V difference;
point normal publication requires the same whole-station panel receipt.

### Coherent Closed Angular Orbit

The intrinsic orbit uses the continuous symbolic angular phase from
[Canonical Sphere Chart](../CanonicalSphereChart/DESIGN.md). Authored conventional
radian labels map by mathematical pi/conventionalPi on the entire U chart;
canonical full-turn labels close the Rodrigues orbit. All original angular
partials include this scale, including mixed generator derivatives and the
factored pole field. Source singleton turn identities and neighboring ranges
therefore share one law; no endpoint-only trigonometric substitution is used.

Missing analytic, transformed or unselected-native generator germ production
reports unsupportedCapability. Invalid caller limits or source binding report
invalidInput. An exactly entirely axial owning generator reports singularGeometry;
an interval-inconclusive regular factor remains singularSystem for subdivision.

Closed query evaluation forwards caller byte admission and independent source/span/subdivision capabilities into the retained generator owning jet. Fixed Rodrigues scalar/vector fields require no temporary array materialization; generated rail Taylor buffers retain their actual allocation owner.

### Direct Execution Contract

Construction, retained interval and Taylor queries, point realization and pole
normal production receive one exclusive caller execution. Ordinary query entries
create one explicit root and delegate to the same body. Root-span preparation
receipts readmit their original immutable budget contributions; no callback,
word-to-byte adapter or child total-work counter is retained. Explicit native
span, source and subdivision policies remain local bounds. Taylor arrays retain
checked typed byte counts before allocation, and value/coefficient depth visits
remain independent. Decoder construction uses its existing decoding root owner.
