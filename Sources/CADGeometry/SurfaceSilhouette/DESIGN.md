# Original Surface Silhouette

## Purpose and Scope

Parent: [CADGeometry](../DESIGN.md). This component owns the original scalar
silhouette law, finite closed-UV certification and retained native graph curves.
Its children [OriginalProvenance](OriginalProvenance/DESIGN.md) and
[OriginalProjectedCurveContacts](OriginalProjectedCurveContacts/DESIGN.md) own retained
source visitation and native projected contact partitioning. Face trim clipping, visibility and drawing projection belong
to the kernel drawing owner.

## Responsibilities and Boundaries

The authority is the supplied original Surface3D, finite closed UV box, view
vector and tolerance. The law is F = (Su cross Sv) dot view. A plane intersection,
mesh contour, sampled root or fitted surrogate is never a silhouette certificate.
An original native B-spline coefficient receipt supplies order-four surface jets
and hence order-three F jets. Existing order-three surface jets supply only
order-two F jets; their padded higher entries are never treated as derivatives.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original stored surface and charts | Owns common geometry facade | New enum routing is owned by parent |
| [Surface Area Integration](../SurfaceAreaIntegration/DESIGN.md) | depends on | Original coefficient receipts and requested-order interval Taylor algebra | Supplies actual higher rational derivatives | Surface/domain/span/side/tolerance authority remains exact |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | Exact original native rational normal numerator | Proves full scalar zero and original factors | A factor GCD alone is not real branch topology |
| [CADCore](../../CADCore/DESIGN.md) | depends on | ModelingTolerance, cancellation and KernelError | Supplies failure boundary | No private resource ceiling |

## Architecture

```text
original surface + complete UV domain + view + caller budget
 -> prepared original closed jets / native homogeneous coefficients
 -> F, gradient, Hessian, established third derivatives
 -> exclude / unique transverse graph / refine / explicit failure
 -> retained original graph chart -> original UV and XYZ interval derivatives
 -> kernel face trim clipping -> projection and visibility
```

## Contracts and Invariants

Point-source visitation retains the actual issuing field for isolated contacts and
issuing curve for singular stations. Public point descriptors never bind a station
to an arbitrary envelope by curve ordinal alone. Original parameter/root laws and
achieved endpoint depths accompany derived spatial enclosures; full envelope
visitation includes all point, curve, whole-zero and component incidence entities.


The higher source dispatcher consumes original plane-derivative surfaces through
their retained requested-order Taylor provider, forwarding the same source/subdivision
caps, work callback and byte admission. It never substitutes the uncorrected native
construction or derives a support plane from numerical endpoint samples.


`SurfaceSilhouetteUsage.maximumSourceDepth` is an immutable independent structural
source cap, defaulting to the existing intrinsic 16 and admitting 0...16. Recursive
source visits consume scalar work and this cap; they never debit a UV subdivision
cell or coefficient root depth. The public drawing caller forwards its actual source
cap to the same live invocation owner. The public producer validates the original surface through its bounded source
provider, then applies the existing `SurfaceParameterBox.validateAssumingSurfaceValidated`
domain contract. Original parameter images additionally admit their exact gain/offset
native-box membership; their displayed transformed Double endpoints alone are not
a closed-domain proof. It does not invoke the unbounded surface validator again.
Prepared surface and pcurve providers receive
source, geometric subdivision and algebra caps separately, including actual byte
callbacks. Retained source values and all three counter domains remain common across
targets.

Escaping Taylor storage callbacks retain the existing invocation accounting owner
through `SurfaceSilhouetteUsage.preparationStorageCallback`. They never capture a
borrowed `inout` usage value or create a separate allowance. Byte admission reaches
the same mutex-protected counters and external admission as original coefficient
preparation; copies of the usage facade share that owner.

Generic exact polynomial Taylor operations borrow their caller's storage callback
with `withoutActuallyEscaping` only during synchronous value construction. Taylor
values retain coefficient buffers, never the callback. No borrowed accounting value
survives the borrow scope.


Ordered-field coordinate components retain exact fixed-axis roots and partition their
free native range at every zero of the original complementary factor. Vertical
content is included in the primitive projection event polynomial so crossings
with non-coordinate branches are original stations. Each coordinate segment uses
strictly ordered algebraic endpoints and its exact linear factor, with the full
original zero law retained for endpoint equality and global incidence. Publication
counts every matching original curve end before publishing joins or station
provenance; coordinate germ counts include each distinct fixed-axis component
alongside the primitive singular germs. No coordinate locus is omitted from a
successful atlas.

A regular graph certificate requires a derivative separated from zero throughout
its entire original box and opposite strict signs on the two complete transverse
edges. The intermediate-value theorem and strict monotonicity establish exactly
one original root at every free parameter, with no unobserved root component in
that box. Every accepted rectangle is retained; every excluded rectangle has either a
strict scalar interval exclusion or a definite-Hessian nonzero-extremum certificate. Closed subdivision covers both child boundaries.
Completion is atomic: an undecided rectangle prevents publication of the entire
result. Retained curves use the original free UV coordinate as native parameter.
Original implicit differentiation supplies interval derivatives without fitting.
Nested genuine native offsets request original order four plus the actual
nonzero offset chain length, then use the shared original normal composition
with requested result order four. Exact chart-preserving equivalents retain
the original outer source identity. Same-original ruled rails with identical
basis, knot domain and weights reuse the existing same-denominator tensor
authority without fitting; its original finite control ceiling is unchanged.
Independent denominators and generic implicit rails still require the original
higher curve authority.

Original harmonic word images issue exact scalar coefficients from the cached
original primitive basis and the effective authored word. Cofactor columns are
constructed from exact original linear coefficients in the retained ordered
field. Cylinder coefficients multiply cos(U) and sin(U); sphere and torus
coefficients multiply cos(U)cos(V), sin(U)cos(V), and sin(V), using their original
angular transports. A whole-domain coincidence is published only when every
exact coefficient vanishes. Finite interval brackets of transformed directions
never issue coefficient equality. Parameter-root depth and coefficient-root
depth remain distinct admissions with the same cumulative counters.

Higher derivatives require actual higher source authority; a lower-order jet may
never be promoted by filling unknown fields with zero.

The reusable OriginalSurfaceHigherJetProvider exposes original requested-order
analytic/native/offset/original-image jets, with caller span and source-depth
admission. Native joins require actual original derivative continuity; raw lower
D3 values never become S4.

The shared surface Taylor entry accepts requested order zero and above. A lift or
retained traversal requesting a value or D1-D3 must not require C4. Native chart
joins prove only the requested partials; analytic and procedural owners evaluate
their original expression at that same order. Ruled/rolling-ball composition adds
the V first coefficient only when requested order is positive. Revolution composes
the retained generator and Rodrigues law without a minimum fourth-order gate.
Existing order-four-and-higher callers retain the same equations, guards, resource
callbacks and selected source/subdivision/algebra caps. This change adds no source
identity or continuity theorem and does not promote any padded derivative.

`Tests/OriginalRequestedOrderLiftVerification` owns the low-order surface and actual
traversal/point/rolling-ball regression. Its independent assembly compiles the four
changed surface/pcurve producers and links the two original Swift entry boundaries
to receipt-admitted unchanged callers. The old-source public failure and current
public success verify body selection. Native uses a private copied archive with
only those entries weakened; WASM uses the linker's function wrappers. Original
cached products are never modified. The generated boundary annotation is fixture
only, has the original Swift signature, and is stripped/checked against the exact
production source before compilation. This evidence does not replace the separate
full M8 platform and public-family acceptance.

Analytic Taylor preparation evaluates the original plane/cylinder/cone/sphere/torus
expressions through order four, with the existing original chart basis. Normal
fields are computed from those expressions rather than replacing them with a
normalized or surrogate surface. Work counts scalar preparation/algebra admission;
cells count visited rectangles; storage counts cumulative retained traversal and
result slots. Temporary Taylor allocations are also admitted by their algebra work
callbacks; storage is not silently interpreted as a byte ledger. Limits have no
private defaults and are supplied by the composing caller.

Planar constant normal projection is classified using exact rational original
coefficient triple products under the same work and storage ledger. For an
authored plane U direction the V law is the exact cross product of the stored
normal and U direction, rather than a rounded candidate cross product. Legacy
parameter-basis producers retain their represented basis contract; this issuer
does not redefine their source law. A proved identically-zero plane retains its
entire original domain in coincidentDomains; it is not emitted as a discrete
curve or an empty zero set. Exact source magnitude admission is controlled by
the caller ledger, without a private exponent window.

Native nonplanar identically-zero fields now use an exact original Cox-de Boor
rational polynomial constructed from stored control/weight/knot bits and the
selected original translation. Its zero coefficient map proves the entire native
chart scalar law zero without treating an interval receipt as exact coefficients.
Exact rational stationary stations with a zero original scalar numerator and
zero two partial numerators, combined with a definite original Hessian over the
whole cell, publish SurfaceSilhouetteContact. Their exact source point retains
its original UV and spatial enclosure. Other algebraic critical stations, multiple
branches and zero-area fields still require complete real-root lifting certificates.
The native root equation may use an exact square-free polynomial only with the
original numerator/GCD/exact-division authority retained. This changes the proof
law, not the original surface, UV chart or zero set. Repeated root multiplicity
must not prevent a regular geometric branch from being certified. They are not regular graphs.
The gradient/Hessian Krawczyk path isolates a unique original critical point
with strict inclusion and contraction. Definite-Hessian minima above zero and
maxima below zero exclude the complete convex rectangle. A critical gradient
root is not an exact scalar-zero witness; the latter requires original equality
authority that the interval coefficient receipt does not provide. Such a
rectangle cannot be labeled complete; production
branches carry an incomplete marker and propagate typed failure. Full D1 therefore
remains unfinished until those mandatory source families are implemented.

Regular chart components are assembled from exact common
native boundary stations, original first-order continuity and a shared signed
transverse derivative over overlapping endpoint brackets. Exactly repeated
periodic homogeneous source tails and selected native lifts authorize seam joins.
Analytic trigonometric seam equality is not inferred from rounded period values.

## Runtime Flows

Production traverses an invocation-local rectangle stack. Work and retained
storage are admitted before queries and growth. A curve query contracts its
transverse interval with original interval Newton steps, then differentiates the
original implicit equation and composes original surface jets. The caller retains
one budget through extraction, curve evaluation, clipping and projection. Public
consumeCell(depth:) and retain(_:) admit upper clipping traversal and retained
records against these same counters; a wrapper never introduces a new allowance.
OriginalSurfaceSilhouetteBoundary retains the actual source pcurve provider and
exposes original UV position/tangent enclosures, including an explicit smoothness
flag, under that same usage. Face/coedge provenance and complete loop membership
remain with the kernel. Unavailable original chart families propagate typed
failure rather than a sampled continuousChartLift.

## State, Ownership, and Lifecycle

Prepared source values and charts are immutable Sendable values. Mutable traversal
and budget values have exclusive inout invocation ownership. There is no shared
cache, target-specific raw state, external callback under a lock or escaped pointer.
The retained curve keeps the original source owner alive for every later query.

## Failure, Concurrency, and Constraints

Caller-supplied cumulative work/cells/storage/depth are never reset. Cancellation
propagates before expansion and interval queries. Overflow, resource exhaustion,
nonfinite bounds, contradiction and unresolved critical contacts are explicit
KernelErrors. No partial successful envelope is published after failure.

## Verification and Change Impact

Source implementation is currently ordered before all behavioral verification.
Later proofs must execute original analytic/rational/procedural domains, regular
branches, contacts, coincident fields, native point and D1/D2/D3, whole-interval
jets, all boundary/periodic charts, caller exhaustion and cancellation, and the
kernel drawing public success/failure route. Source authoring alone proves none
of those execution outcomes. Changes to higher coefficient authority require
rechecking the original source/domain/branch and derivative order contracts.

The original rational contact path additionally uses the exact whole-polynomial
higher-order isolated-point certificate from the algebra child. Shared closed
native cell boundaries use upper-open ownership except at the original global
upper domain; actual algebraic coordinate equality decides ownership, never a
rounded point. All unidentified singular curves remain an atomic typed failure.

Regular clipped native graphs can retain a normalized affine parameter image
between exact authored/algebraic original free-axis endpoints. UV/XYZ jets scale
by the original endpoint difference to each derivative order. Equality/hash retain
that source image; Hashable is never source fingerprint authority. Exact endpoint
identity and native continuity decide component joins. Unknown joins remain typed
incomplete rather than creating separate successful components.

The regular component assembler retains each exact original endpoint fiber once.
Cross-axis joins prove both native coordinates through exact polynomial zero and
isolating interval identity, then verify the original native normal continuity.
The original same-axis monotonicity certificate owns dependent-coordinate identity.
Endpoint comparison work and retained receipts use the same cumulative usage.

The original root-span revolution higher path consumes the generator's retained
owning coefficient Taylor port. It exchanges the rail Taylor axis into native V,
normalizes the authored raw axis with the actual constant interval norm, and
composes the full Rodrigues law to the caller's requested order. At an endpoint
with an original exact axis-incidence receipt only radial C0 is set to zero;
all original higher rail and mixed derivatives remain present. No new root
separation, private allowance or mesh approximation occurs in that composition.

Native joins whose degree/multiplicity test is inconclusive use actual one-sided
homogeneous C0/C1 cross-products. A same-axis join requires exact whole-edge
identity; cross-axis corner incidence requires all actual native first partials
to agree at the retained original algebraic point. Offset/procedural joins without
that source producer remain typed incomplete. No tolerance-based join is assumed.

`SurfaceSilhouetteAlgebraicContact.refined(maximumUWidth:maximumVWidth:usage:)`
retains the original critical or boundary pair and certified native rectangle.
It forwards the same caller depth and cumulative budget into exact root/fiber
refinement, then reevaluates the actual original surface over the refined UV box.
No system solver replay, source rebinding or allowance reset is performed.

For a complete original coordinate-factor identity, prepared field copies retain
the same original surface/native coefficients and specialize only the exact zero
factor. Each retained graph is cut at every exact opposite-axis root. The original
factor tangent determinant distinguishes transverse crossing joins from tangent
or unresolved singular incidence. Multiway joins are permitted only with that
source crossing certificate. Curve equality includes its original factor law.

A regular graph whose exact restricted factor vanishes on its complete upper
transverse edge is owned by the adjacent native cell, except at the global upper
domain. This complete original edge identity and transverse monotonicity exclude
any other zero in the cell. No duplicate full curve is issued from the other side.
Ordinary endpoint incidences remain closed and are joined by their exact receipt.

The odd-binomial cusp path retains its complete exact polynomial native UV law
and an affine image between original algebraic parameter endpoints. It evaluates
UV polynomial derivatives and the full original spatial multivariable chain
through D3. The source cusp station uses the same finite parameter chart; no
implicit division by its zero gradient occurs. Rectangle clipping is the exact
complete boundary-root decomposition owned by the algebra child. Unrelated
singular source families remain explicitly incomplete.

Cusp publication retains the exact t=0 station, its original rational U/V center,
a whole outward native parameter enclosure, and the
outward normalized parameter enclosure derived from the original exact endpoint
image. `SurfaceSilhouetteSingularStation` distinguishes that curve incidence from
isolated contacts. Endpoint joins at the same original station are tagged cusp;
stationary parameter presence follows exact source signs, not a derivative sample.
Upper trim membership must classify the entire parameter enclosure; a rounded
rational center cannot authorize membership or omit an unresolved trim incidence.

The exact odd-binomial cusp station retains square-free branch multiplicity two,
its original odd characteristic exponent, and the one or two real parameter
half-branches actually retained by that issued chart. These counts are derived
from the complete source parameter bijection and exact endpoint signs; each
reported incidence references its actual retained curve and native station.

Higher native surface requests retain the existing 262,144-span physical source
ceiling and forward the smaller of that ceiling and the caller span allowance.
An oversized caller allowance does not invent an invalid-input failure; actual
source overflow remains a resource failure from the native cover producer.

### Exact Quadratic Multiple-Branch Incidence

Complete source quadratics whose discriminant is an exact polynomial square
produce two separately retained regular factor fields. Both factors reconstruct
the entire original law; every intersection station is isolated from the full
original branch-difference polynomial and inserted into the graph partition.
Factor exclusions cannot exclude the other factor. Source branch ordinals keep
distinct curves and critical caches distinct. Exact factor-gradient determinants
classify transverse joins; exact first nonzero branch-difference derivative
classifies finite tangent contact order. Component output retains that order
with both original curve endpoint incidences. No generic multiway classification
is inferred from this two-branch theorem.

### Original Native Pole Normal Gauge

The same prepared native cover is injected into the pole-normal owner. Its
optional exact collapsed-boundary recognition distinguishes ordinary edges
from source-proved poles; input, cancellation and admission failures propagate.
Retained oriented normal numerator quotients have removed the exact original
boundary factor. Their strict whole-box nonzero norm establishes direction-field
regularity; their view dot product supplies the exact zero law and its scalar
D3 derivatives. Original spatial D0-D3 remain the original owning surface jets.
The positive weight denominator and inward boundary factor are direction gauges,
not surface metrics. No sampled epsilon parameter authorizes a pole contour.

An identically zero original view-dot-normal polynomial authorizes a coincident
domain only after the same whole box has a nonzero original normal direction
field. A constant or rank-one tensor with identically zero normal cannot become
a successful coincident silhouette. Uncertain regularity subdivides under the
unchanged original cell/depth ledger; exhaustion propagates explicit failure.

### Exact Higher Native Join Authority

Requested-order native surface jets prove actual rational partial equality across
every selected owning boundary pair, including closed query endpoints and lifted
periodic seams. Original source homogeneous coefficients and their quotient
partial recurrence supply all mixed derivatives; cross multiplication and exact
edge restriction prove equality. Degree-minus-multiplicity insufficiency alone
does not reject a genuinely smoother source. Edge ownership keys restrict
comparisons to actual neighboring tensor cells. Exact word/work/storage admission
for this callback-based higher provider is forwarded to the same caller work
callback before retained allocations; it creates no independent budget. The
callback is borrowed lexically and never escapes the synchronous producer.

Analytic sphere silhouette uses its original unit radial law; the collapsed
angular tangent is a metric factor and does not create a full polar row contour.
Analytic cone silhouette uses the exact native-V normal quotient evaluated from
its original degree-one V law at V=1, retaining the U dependence and all scalar
D3 coefficients while zeroing only proven absent V derivatives. Both use original
spatial surface jets. Sphere direction regularity follows the original unit
radial identity; cone regularity requires a strict whole factored normal bound.

Original analytic/canonical cylinder whole-zero classification uses the exact
represented radial basis, axial vector and view coefficients. Exact triple
product nonzero proves independence of the two normal harmonic coefficients
and thus whole direction regularity. Both exact harmonic view coefficients
must vanish before a nonplanar coincident domain is issued. Normal intervals
containing zero or a sampled axial alignment are not this authority.

Rotated cusp output retains the complete original U(t)/V(t) polynomial map.
`freeCoordinate` is a chart label on this normalized polynomial traversal and
does not authorize native-coordinate monotonicity; upper consumers use the
actual parameter enclosure. The original rational station and spatial D3 chain
are evaluated after inverse shear, preserving original face UV provenance.

### Native Offset Zero-Set Transport

On every admitted regular parallel-surface chart, each original offset normal
is a nonzero scalar multiple of its original source normal. The original native
view-dot-normal polynomial therefore supplies the complete zero law through a
retained offset chain. Original requested-order normalized-normal composition
still evaluates all spatial jets, and strict whole final normal regularity is
required before publication; focal or undefined-normal charts fail or subdivide.
Source continuity proofs retain all original mixed partials through one plus
the number of nonzero offset stages, rather than claiming offset C1 from only
base C1. No offset distance is fitted or discarded. Native offset pole charts
whose original normalized-normal higher law is undefined remain explicitly
unsupported until their owner supplies the factored extension.

Native pole normal preparation removes every source-proved collapsed clamped
side touched by the owning box, including both endpoints of one axis and mixed
U/V endpoints. The same immutable coefficient port carries the final oriented
quotient field; no caller selects only the first side as whole-panel authority.
Exact dependent-root identity and original C1 spatial continuity suffice for a
join across such native charts. A negative normal gauge can reverse scalar
monotonicity signs and does not negate an already proved original root identity.

Canonical analytic sphere harmonics consume the shared
[Canonical Sphere Chart](../CanonicalSphereChart/DESIGN.md) continuous phase
contract. Requested Taylor order n carries the shared scaleBounds^n/n! and
uses exact symbolic quarter/full-turn singleton base values from that same
source law. Both longitude and latitude share the phase; other primitives keep
their original angular laws. Sphere radial silhouette gauges consume these
spatial source coefficients, not a separate endpoint snap or raw libm chart.

Coprime-binomial stationary curves retain their actual min(m,n) branch
multiplicity and max(m,n) characteristic exponent. Both original polynomial
coordinates are used directly in spatial chain evaluation. These germ counts
are not hardcoded to the quadratic cusp and do not imply native-coordinate
monotonicity or an ordinary regular edge at the stationary parameter.

Complete reducible translated binomial zero laws are specialized into their
retained exact real factors, with an ordinal on the original native chart.
No factor-local exclusion certifies absence for the original union. All original
polynomial cusp traversals are split at the exact stationary parameter zero in
addition to every trim boundary root. Distinct signed branches have exactly
one common original center: the ideal of the two reduced factors is
`((u-c)^M,(v-d)^N)`. Original endpoint equality checks both exact coordinates;
the resulting singular intersection retains M*N as its exact intersection
multiplicity, separately from regular tangent contact order. No fitted tangent
or interval overlap authorizes this finite branch incidence.

Original Coons requested-order spatial jets consume the
[Original Coons](../OriginalCoons/DESIGN.md) Taylor contract directly. Four
original boundary traversals and original corner incidence are owned there;
the silhouette provider only forwards the requested order and same work
callback. It does not reconstruct a fitted tensor or another corner authority.

### Unique Original Native Pole Normal

`OriginalUniquePoleNormalAuthority` owns a whole-original-boundary certificate,
not a selected-panel extension. Preparation consumes the original prepared
native boundary cover and the existing collapsed point/factored normal ports
from [Surface Pole Geometry](../SurfacePoleGeometry/DESIGN.md). Every original
positive-width owning span is retained, and the ordered cover must reach both
original free-axis endpoints without gaps. On each original boundary, the
three oriented quotient coefficients are exactly parallel to one nonzero
original rational reference vector. Their exact dot-reference polynomial has
no closed real root by Sturm and has positive exact sign. This proves a unique
oriented unit normal on the entire original collapsed support. Missing collapse
or varying/opposite/vanishing quotient directions return no authority; budget,
source-binding and cancellation failures propagate. There is no numerical
normal sample that can authorize the whole boundary.

The immutable receipt publishes the original source, boundary, preparation
tolerance, collapsed source point and exact reference direction. Its package
coefficient query validates the original owning span and requested closed box
before returning the retained quotient field to an offset higher-jet adapter.
The adapter owns normalization/product composition; this child does not copy
collapse recognition or infer uniqueness from the first nonzero local normal.
All native preparation, exact algebra, sorting and retained panels use the
same caller work/storage/cell/depth allowance. The receipt is derived source
proof and does not add another persistent CAD source field.

A collapsed axis must be an original closed native boundary; its tangential
axis can be periodic. The whole unique-normal proof uses that source's complete
fundamental tangential domain and retains the original owning cycle/translation
in each coefficient panel. Periodic seam endpoints remain in the closed
Sturm sign proof and are not omitted from the global direction authority.

Two retained polynomial chart endpoints are joined by equality of both original
native coordinates, including algebraic endpoints represented by different
original polynomial parameterizations. Exact resultant coordinate transport
uses the original parameter existence, whole rational image and unique root
proof from Rational Bivariate Algebra; all derived root depths remain causal.
Original one-sided spatial C1 equality is then checked at that same retained
original point. Equal parameter labels or overlapping boxes alone are not joins.

Requested-order normalized pole jets differentiate the receipt's original
quotient polynomials exactly, scale by rational u!/v! inverses before whole
interval enclosure, and normalize the resulting analytic Taylor vector.
Strict whole quotient norm precedes square-root division. The retained
positive norm interval tightens only the value coefficient of its squared
norm; all nonconstant original coefficients remain unchanged. Original
metric factors are not numerically divided at the collapsed boundary.

Requested-order original revolution harmonics share the continuous symbolic
mathematical-turn label law of Canonical Sphere Chart. Their value coefficients
come from that common phase, and every nth angular Taylor coefficient retains
the same phase scale raised to n divided by n!. Original stored domain labels
remain source authority; a raw binary trigonometric endpoint does not define
the full-turn geometry.

### First Native Pole Offset Higher Composition

The native pole offset adapter prepares each touched collapsed boundary's whole
unique-normal receipt once per source cover. Ordinary original boundaries are
classified by the existing exact collapse recognizer; varying or undefined pole
normals are explicit singular failure. A selected original pole panel consumes
its complete oriented factored coefficients only after every collapsed boundary
it touches has that full-source receipt. Exact quotient Taylor normalization
provides the first offset normal at one less than the original source order.
The shared offset composition receives this admitted normal and retains all
original derivatives and distances. Subsequent genuine offsets still require
their own regular normal proof; a first-layer receipt cannot authorize focal
sign changes or later metric collapses. Final silhouette normal regularity is
checked separately from existence of the offset value and its higher jets.

Requested higher queries over several native charts prove original surface
partial continuity and exact oriented projective normal partial continuity.
An anchor component may vanish at isolated edge points: polynomial quotient
identities hold on its dense nonzero edge subset and extend by the independently
proved strict analytic normal norm. A vanished whole-edge anchor requires a
different component. All proof storage, visits and arithmetic use the same
caller allowance; borrowed callback adapters stay in their lexical lifetime.

Base-normal scalar exclusions on genuine parallel charts are consumed only
after final original offset normal regularity is proved on the whole cell.
An undefined or focal offset metric cannot inherit a successful exclusion from
the base polynomial. Unresolved final regularity subdivides under the original
caller depth and propagates explicit exhaustion; no empty result is inferred.

### Original Parallel Metric at Native Poles

The native parallel metric authority retains the original rational first and
second partial numerator fields and the original oriented nonzero normal
quotient Q. It obtains the exact common metric factor phi by dividing one
nonzero original raw normal component by the corresponding Q component and
checks all three identities N_raw = phi Q. The original mean-curvature numerator
W(E_num g_num - 2F_num f_num + G_num e_num) and Gaussian numerator
W^2(e_num g_num - f_num^2) are divided exactly by phi^2 before interval
normalization. The remaining denominators are respectively 2|Q|^3 and |Q|^4.
No collapsed scalar is numerically divided. Missing exact cancellation is not
a smooth-pole curvature certificate.

For every actual offset stage, the original parallel determinant
1 - 2dH + d^2K must exclude zero on the whole native cell. Normal orientation
is its proved sign relative to the base normal. The next authored distance is
added with that sign to an exact rational effective displacement; no rounded
sum or omitted source distance replaces the original chain. The admitted
position and all requested derivatives use S + effectiveDisplacement * n_base.
An unresolved determinant or quotient norm returns no admission and the public
producer subdivides under the same original allowance. This checks every prefix,
so an undefined intermediate focal surface cannot be hidden by a regular final
sum. Full boundary unique-normal receipts remain required for pole panels.

Native offset curve joins additionally prove the exact oriented projective
normal value and first partials at the retained original UV endpoint. All three
raw normal cross-products must vanish, the dot product must be positive, and
an actual nonzero anchor component must admit Q/Qj partial identity. Both
whole admitted curve cells must retain the same exact effective displacement;
matching original distances alone cannot hide a different prefix orientation.
This applies to graph and polynomial parameter endpoints without rebuilding
the retained root or selecting a rounded point.

The public silhouette traversal caches the original plane projection partition
per retained native branch law. Its finite-real-locus certificate is consumed
before the Hessian special cases: every exact root belonging to a closed cell
is retained, original half-open publication ownership avoids duplicate contacts,
and root enclosures are refined before spatial evaluation. A cell is excluded
only when the complete original finite set has no closed-cell root. Contacts
are published atomically after all owned roots fit their certified cell; an
unresolved enclosure subdivides with the same retained roots and caller depth.

### Original Native Periodic Offset Joins

A periodic seam joins two original owning parameter charts through the exact
rational difference of their stored endpoint labels. The second original
polynomial is composed with that translation before any endpoint identity is
queried; derivative values retain their original coordinate meaning. The
producer proves dependent root identity, every required source first-partial
equality and the oriented normalized quotient normal's first-partial equality
at the same retained algebraic endpoint. A periodic control-tail continuity
order alone cannot authorize a collapsed-pole offset join. Every translated
coefficient and root query shares the original caller ledger.

Original affine-word supports transport each requested Taylor coefficient
through their retained exact prepared operation word. Translation participates
only in the constant coefficient. The original UV source and requested
derivative order are preserved; normalized radicals and original inverse
factors never become midpoint matrices. Existing work-only entry points borrow
their original callback for exact transport admission without a fresh allowance.

Generic ramified silhouette traversals retain their original regular strict
transform, complete original U/V maps and exact clipping endpoints. Their
normalized free traversal keeps algebraic endpoint slope enclosures; original
UV D0-D3 are composed through the original surface's spatial D0-D3 under the
same usage. Point refinement retains endpoint roots and coefficient width
with inherited depth. Whole source rectangle clipping proves any D0
intersection with the original face domain; it is not a parameter snap. These
curves enter public envelopes only with complete global atlas incidence.

Near-station curves normalize the exact local origin-to-attachment traversal,
including negative free directions without reversing a fitted curve. Their
endpoint values retain the original ordered-field inverse-blowup source.
Central strip tubes retain exact rational original free endpoints and global
projection branch ordinals. Those original station/strip incidences, rather
than overlapping UV boxes, own the eventual connected-component joins.

Original plane-atlas endpoints retain either the existing exact station pair or
an exact rational free coordinate and its existing source transverse root.
Joins compare those original values with exact signs and unique-root intervals,
including endpoint exclusion flags. A complete station incidence certificate
admits singular valence only for the same retained primitive source. Native
span joins additionally prove equality of original one-sided spatial partials
and offset normal authority. Generic local labels and overlapping enclosures
cannot authorize endpoint identity.

The public producer consumes one complete native plane atlas per admitted
regular source rectangle. It publishes origin-to-attachment ramified curves,
complete central regular tubes, isolated station contacts, and retained station
incidence. Coordinate factors remain on their original dedicated producer;
publication is atomic under the original cumulative usage.

Generic native periodic atlas endpoints transport the second exact projection
and rational fiber constraints by the original selected seam displacement.
The first endpoint must satisfy both constraints and all translated isolating
endpoint flags. Original spatial partial equalities and offset normal proofs
use that identical displacement. Periodic parameter wrapping does not create
a new root or authorize equality from overlapping boxes.

All intrinsic cylinder, cone-U and torus-U/V harmonics use the same canonical
analytic phase as sphere and revolution. Their higher Taylor coefficients
include the phase scale to every derivative order; cone half-angle slope
remains an authored nonperiodic scalar. The whole source law, not a seam-only
point override, owns exact turn and quarter-turn identities.

Higher surface queries accept an additive optional byte-storage admission
callback. Native Taylor allocation, native exact join work and bounded Coons
queries forward it to the actual lower allocation sites. Exact algebra UInt32
storage words convert to bytes with checked multiplication; byte callers are
never interpreted as Double slots. Historical work-only convenience callers
retain their existing contract, while explicit storage callers share one
invocation allowance across recursive supports.


### Original trim-event bridge

The child owns intersection events between an original retained silhouette chart
and an original face-loop pcurve; the kernel owns loop orientation, face membership
and projection. Native rational pcurve segments retain the original fractional
parameter law, XYZ-independent UV homogeneous coefficients and knot ownership.
Substitution clears only a proved positive original denominator. Ordered-field
Sturm isolation returns every root, including multiple/tangent roots and closed
endpoints. Identically-zero substitution is classified as a continuous overlap;
it is partitioned at every original chart-boundary and traversal-critical root.
Original silhouette endpoint fields participate in this elimination, so a rounded
UV coordinate never cuts a normalized silhouette traversal.

The bridge publishes exact endpoint expressions and original boundary fractions,
continuous overlap ranges, and event-free original native sectors. Endpoint sorting
and equality explicitly transport retained original field owners; an overlapping
floating enclosure is not equality. All extraction, coefficient operations, root
isolation, endpoint ordering and retention use the supplied SurfaceSilhouetteUsage.
Unsupported source chart families fail atomically with an implementation marker;
no incomplete event list is exposed. General ramified and analytic pcurve source
extraction remains a required D1 domain until its original equations are consumed.

```text
source pcurve + owning native span -> original UV/W fraction polynomials
original silhouette factor + exact free endpoint image
 -> denominator-cleared event equations -> all ordered original real roots
 -> original chart membership -> exact native traversal endpoints
 -> kernel loop membership / complete retained trim partition / projection
```

Polynomial cusp trim events use the retained complete injective polynomial UV map. At each original boundary event the two original UV equations are lifted into the event's ordered field; their exact univariate GCD returns every preimage. Only preimages inside the retained exact traversal endpoints are published. Coincident sectors are cut at both endpoint images and all original UV traversal stationary roots, including the singular center; no native-axis monotonicity is assumed.

Ramified trim events apply the retained inverse blowup word to original pcurve rational functions, over the original germ coefficient field. Complete local-chart/free-endpoint/denominator cuts select the owning strict-transform graph. Original UV center incidence is checked separately at exceptional denominators; it is never inferred from a cancelled or rounded quotient. Continuous coincidence requires the composed strict-transform numerator to vanish identically in addition to the original map identity.

OriginalSurfaceSilhouetteTrimmedCurve retains the original curve and exact native endpoints as a normalized traversal. Constructor transport proves strict endpoint order and original-domain containment. Queries transport the exact affine endpoint expression, enclose original native derivatives, and apply its complete chain factors through D3. Floating query bounds may conservatively extend a trimmed end but never replace its exact original endpoint or establish face membership; the kernel consumes complete event sectors for that authority.

Exact trim extraction preserves normalized source fractions through original image/word and chart-preserving offset carriers. Original image inverse UV gains use the complete stored OriginalParameterGain coefficient law and axis-swap flag; spatial transforms do not alter face-local UV authority. Each wrapper composes its own original fraction endpoints and clips selected native spans before recursing.

Original B-spline continuation trim spans use the selected first/last native Cox-de Boor polynomials beyond their endpoint domains, with the original oriented start/end labels. Complete original Sturm exclusion proves a constant nonzero homogeneous weight sign on each requested closed span; a negative homogeneous sign is flipped in all three UV/W polynomials together. A genuine denominator zero fails atomically.

Requested-order analytic and native parallel higher helpers forward optional caller BYTES admission to every Taylor coefficient allocation and retained span buffer. Exact arithmetic adapters convert their canonical UInt32-word storage units to bytes once; native/tensor preparation retains its original callback ledger. No Double slot is reinterpreted as one canonical word.

Trim endpoint refinement returns an immutable endpoint retaining its original scalar isolation receipt and causal depth. The floating enclosure query refines only locally; callers needing repeated refinement retain the returned endpoint from `refined`. Interior-witness construction retains both refined endpoint receipts between attempts, so repeated attempts cannot restart a source isolation depth or acquire a separate allowance.

The public silhouette traversal forwards native preparation, requested higher jets and scalar/vector Taylor allocations to its existing cumulative storage ledger using actual byte-to-UInt32-word admission. Analytic normal gauges share that same callback. Source structural recursion, native span counts and algorithm subdivision remain separate caller premises; this forwarding never increases any ceiling.

Polyline trim spans consume `OriginalEuclideanPolylineParameterLaw`: each positive original segment is represented on its own exact local 0...1 chart, while the returned boundary event fraction retains the exact original prefix/total affine image. Periodic UV translations preserve that image. Nested selection wrappers compose the exact field fraction affine image, cut every original local span at its exact image fractions zero/one, and admit only events inside that selected whole traversal. Reversed image gains retain their original direction. Periodic translations and original UV image gains preserve this fraction image; neither local nor binary-rounded fractions replace it.

`OriginalSurfaceSilhouetteTrimmedCurve.refined` retains refined exact lower/upper endpoint receipts and the exact slope isolation without reconstructing endpoint transport or slope algebra. Upper membership callers retain this returned wrapper when tightening source parameter width. Its queries use cached endpoint bounds at normalized zero/one and cached slope bounds; other normalized query expressions remain original affine evaluations.

Requested-order revolution and ruled/rolling-ball higher composition forward the original caller span, subdivision, source-depth and byte callbacks to retained rail producers. Canonical harmonic modular/extremum work is charged through the shared phase callback. Native Taylor field allocation is charged before every scalar/vector operation; direct fixed-cycle scratch arrays use actual stride admission.

### Independent ordered-field depth and normalized native zero law

Silhouette usage retains an explicit maximumAlgebraicDepth (the existing intrinsic 32, validated 0...32) separately from maximumDepth for UV cells and retained root subdivision. Exact normalized coefficient preparation uses the former and the same cumulative work, cell and storage counters. Neither depth is silently minimized against the other. World homogeneous coefficients are original native XYZ/W acted on by retained original words, and their derivative-quotient cross product supplies the ordered-field zero equation. Source weights must remain nonzero and surface normal regularity is a separate premise. Public curves retain the original world surface and unchanged UV chart. Field atlas stations and strip half-branches retain exact coefficient ownership and original incidence; floating coefficient midpoints never replace their authority.

Field-native atlas publication preserves each original coefficient owner, station root, half-branch attachment and closed regular strip cover. The existing public algebraic-contact carrier additionally retains field-system roots and refines them with the same invocation ledger. Ramified field curve identity is conservative issued-receipt identity (shared immutable coefficient owner plus source-domain/leaf/sector/branch/side and exact anchor); it does not equate unrelated prepared towers. Global endpoint equality separately proves exact original UV equality by field transport.

Fixed-coordinate field components retain exact native roots and partition their complete free interval at all intersections with the complementary original factor. Normalized free traversals retain original ordered-field endpoints and slope, including achieved scalar isolation depth; successive refinement never reconstructs the endpoint law. Coordinate component intersections participate in the complete field plane projection events, so primitive strips and fixed-coordinate branches share original station coordinates rather than intersecting only in their interiors.

Native rational fields retain their full original zero-set receipt in the common
ordered-field atlas route. Coefficientwise receipt lifting does not fit geometry,
change native parameters, or repeat root isolation. This avoids splitting out
coordinate factors before primitive crossings are recorded; coordinate and
non-coordinate incidences belong to one complete original chart publication.

## Shared Invocation Accounting

Every `SurfaceSilhouetteUsage` copy retains one immutable accounting owner. The
owner stores one common `Synchronization.Mutex<State>` on Native, WASM and
Embedded; scalar work, parameter proof depth, coefficient proof depth and storage
all mutate the same counters through protocol requirements. Preparation callbacks
retain this owner and cannot detach or restore counters. Cancellation is checked
outside the lock. Work consumed before a cell/storage admission failure remains
consumed, matching the exclusive usage contract.

The proof-depth work callback checks geometric depth and charges one scalar work
unit; it does not invent a cell allocation for a lower port that reports only
work. A separate cell callback charges actual geometric nodes. Storage callbacks
accept bytes and use checked ceiling division into the existing UInt32-word
ledger. The tracking owner's owned payload/reference/header is admitted once
before allocation; no additional allowance is created. Apple API availability
may refuse owner construction explicitly, but storage and Sendable conformances
never switch to a different primitive. A missing baseline Synchronization module
is a compile capability failure.

Component assembly pre-admits concrete Int parent/index buffers, endpoint records, join records, dictionary entries and result records using their actual typed stride. Dictionary growth and inner array growth are separate admissions; existing keys reuse their retained entry. No logical record is charged as one UInt32 word. Assembly keeps the same cumulative invocation owner and atomically publishes only after original endpoint identity and incidence succeed.

The additive SurfaceSilhouetteAdmission connects actual scalar work counts and concrete BYTES to an enclosing invocation's live accountant. Every supported target retains the same immutable callbacks and Mutex owner. Local work/cell/storage/depth policies remain enforced in addition to enclosing admission. Tracking-owner payload, callback storage and header are pre-admitted before owner construction. External callbacks run after the local lock is released and before the admitted algorithm operation/allocation; re-entry never executes under the Mutex. A failed enclosing admission retains the already consumed local work and propagates the caller error. Retained preparation callbacks keep both owners alive; no residual snapshot or copied allowance is introduced.

Native higher continuity additionally accepts an explicit nonempty list of required (uOrder, vOrder) partials. It proves only those original quotient cross-product identities on each selected owning join; constructing a higher formal derivative table does not assert continuity of its unrequested entries. Legacy throughOrder callers continue to require every total-order partial. Fixed-boundary plane-derivative consumers can therefore require genuine mixed U/V derivatives without imposing unrelated pure-U continuity. Negative orders, overflow, or missing original partials fail explicitly; work/BYTES and the caller proof depth remain shared.

Requested higher-surface borrowed admission carries coefficient depth independently of geometric join/subdivision depth. D1 forwards its actual maximumAlgebraicDepth; legacy work-only callers retain the prior intrinsic 32 coefficient policy. Native image UV mapping forwards actual work and BYTES to the same caller before selected source evaluation. A UV depth of zero does not by itself invalidate an already admitted normalized coefficient field.

The analytic sphere normal gauge is evaluated directly from its original canonical angular direction. Center translation and positive radius are removed symbolically before interval evaluation; subtracting a large center from already rounded position bounds or multiplying by an overflowing reciprocal radius cannot supply its normal authority. The same direction helper constructs original sphere positions, so the gauge and spatial source share the canonical phase and original chart basis. Original source validation and position tolerances remain the spatial owner responsibility.

The public authored-native-range trimmed curve initializer retains the exact binary64 endpoint values as rational field constants, delegates strict ordering/domain proof to the same existing endpoint initializer, and uses the supplied live invocation ledger. It is appropriate for already admitted original native span endpoints; it never substitutes floating enclosures for retained algebraic event endpoints. Nonfinite, reversed or out-of-domain endpoints fail explicitly.

Each external SurfaceSilhouetteAdmission owns a distinct immutable identity allocated only after its header work/BYTES are admitted by the supplied caller. Copies retain that same identity. SurfaceSilhouetteUsage.sharesAdmission uses identity equality through the common accounting protocol; equal callbacks, caps or observed counters cannot establish shared ownership. Independent admissions are never treated as interchangeable.

SurfaceSilhouetteUsage.sharesAccountingOwner compares the identical retained live accounting reference, independently of sharesAdmission. Two new usages supplied the same external token share its enclosing admission but do not share local cell/work/storage counters; page issuers must prove both relationships. Copies of an issued usage retain the same local accounting owner across targets.

External silhouette admission optionally reports each genuine parameter/coefficient cell visit to the enclosing invocation entity quota. The existing scalar-work callback still reports that visit once; the cell callback does not imply another work debit. Local cell reservation remains synchronized and the external callback runs outside the lock before the algorithm visits its admitted cell. A rejected outer admission propagates and retains the already consumed local reservation, preventing retries from resetting counters.
