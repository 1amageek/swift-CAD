# Rational Bivariate Algebra

## Purpose and Scope

Parent: [CADGeometry](../DESIGN.md). This child owns exact rational arithmetic,
sparse bivariate polynomial equality, primitive pseudo-remainder GCD, exact Sylvester/Bareiss elimination and original
native homogeneous surface polynomial construction. Its [ExactScalar](ExactScalar/DESIGN.md) child owns the isolated L0 numeric contracts and their scalar implementation closure.

## Responsibilities and Boundaries

Stored finite Double bits represent exact dyadic rationals. Rational knot division
is performed exactly, never through rounded interval extraction. Original surface
identity, selected span and periodic lifts remain supplied source authorities.
The exact square-free root law divides the original polynomial by its common
GCD with both original partial derivatives, retaining all original irreducible
zero factors exactly once. A polynomial GCD proves common factors; it does not by itself certify real root
isolation, branch topology or that an interval containing zero is an exact root.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [ExactRealTopology](ExactRealTopology/DESIGN.md) | child | L4 closures, complete incidence and selected parameter components | Consumes public L0-L3 contracts | Independently verified on Native/ASAN and both WASI families; upper geometry integration is separate |
| [ExactRealCell](ExactRealCell/DESIGN.md) | child | L3 complete real-cell partitions, selection and retained conditions | Depends only on public L0/L1/L2 and Swift | Isolated paths and L4 inspection extension verified; upper integration remains separate |
| [ExactRealRoot](ExactRealRoot/DESIGN.md) | child | L2 complete univariate roots and selected-root coefficients | Depends only on public L0/L1 contracts and Swift | Independently verified; higher consumer integration is separate |
| [ExactPolynomial](ExactPolynomial/DESIGN.md) | child | L1 polynomial protocols | Depends only on L0 | Independent verification excludes higher consumers |
| [ExactScalar](ExactScalar/DESIGN.md) | child and depends on | Exact scalar operation and admission protocols | Owns the five L0 contracts | Higher consumers are outside the independent L0 build |
| [CADGeometry](../DESIGN.md) | parent | Original stored coefficients and native charts | Owns geometry source validation | No fitted source |
| [Surface Silhouette](../SurfaceSilhouette/DESIGN.md) | used by | Cumulative work/storage admission | Uses original scalar equality | Real-root lifting is a separate proof |
| [CADCore](../../CADCore/DESIGN.md) | depends on | KernelError and cancellation | Failure publication | No partial successful polynomial |

## Architecture

```text
finite original Double bits -> exact integer ratio
 -> sparse rational bivariate polynomial -> equality / primitive PRS GCD
 -> original homogeneous surface derivatives -> scalar normal numerator
 -> exact elimination projection + Sturm root stations
 -> caller-owned algebraic fiber / real branch certification
```

## Contracts and Invariants

Original uniquely isolated roots compare a linear expression by exact Sturm
variations at its zero, after checking original endpoint inclusion and order.
Ordered-parent-field stations are evaluated in that retained parent owner;
rational root stations remain original rational coefficients. No floating
station or broader caller depth is introduced. This sign decision consumes
ordinary arithmetic and coefficient-sign admission but does not subdivide the
queried root merely to determine on which side of the station it lies.

Ordered-field fraction operations reduce numerator and denominator modulo the
retained extension root's defining polynomial. This is an exact identity at that
root, not a change to its defining source or isolation. Denominator leading
coefficients are normalized over the parent field to control expression growth;
root identity, nonzero-denominator obligations and caller admission remain intact.
Reduction never cancels a root-zero denominator into a successful value. Polynomial
division and coefficient normalization recurse only into the parent field under
the same work, storage and depth capabilities.
Exactly rational constant fractions use their reduced rational sign directly,
without invoking an unrelated root Sturm proof. Nonconstant expressions keep
the retained original-root sign issuer.
A fraction with only one exactly rational operand determines that operand's
sign directly from its original reduced rational coefficient. The other operand
still uses the retained original-root sign issuer, including its unchanged cell
visits and parameter/coefficient depth. Extended operands must belong to that
root's identical parent context before either sign is queried. A degree-zero
operand with a nonrational parent coefficient still uses the original root path;
zero denominators and unrelated contexts remain failures. Constant recognition
uses the same caller work and cancellation checks; it creates no root receipt
or shared cache and grants no admission to the nonconstant operand.
Constant root expressions delegate their sign to the parent field. Linear
expressions compare their exact parent-field zero against the retained isolating
interval; an interior zero is accepted only when the original defining polynomial
vanishes there. Otherwise original root refinement separates the two stations.
This preserves original equality while avoiding repeated expression Sturm chains.

Exact rational hashing consumes only the canonical reduced sign, numerator
words and denominator words used by equality. Equivalent rational values have
the same hash contribution; no rounded representative or derived enclosure is
part of source identity. Hashing is the nonthrowing value-protocol operation;
caller-paid algorithmic traversal must admit source hash work before using it.

Ordered-field scalar roots retain their admission domain. Parameter roots consume
causal UV/root depth; coefficient roots retain their original independent algebra
cap and consume `visitCoefficientCell`. The protocol operation is a requirement
with a forwarding default for callers sharing one intrinsic cap. Callers with
separate caps route both admissions to the same work/cell/storage owner. Field
contexts report parameter depth separately from coefficient depth; transporting
or refining a root preserves its domain and attained depth. A normalization
coefficient cannot silently become an inherited UV subdivision.

`OriginalRationalCurvePolynomial` retains both the selected original native B-spline
and its complete `originalCurve` spatial-image source. Its bounded Curve3D initializer
unwraps only parameter-preserving rigid/affine images and rational original action
words, applying original exact columns to XYZ and translation times W. The selected
span, exact parameter bounds and W remain unchanged. Each descendant consumes the
caller source depth and every coefficient operation/storage consumes the same ledger.
Normalized algebraic words belong to the ordered-field producer; this rational port
rejects them explicitly rather than rounding their coefficients.

`OriginalRationalCurveIntervalJet` evaluates a selected original homogeneous native
law over exact rational normalized bounds. It imports the retained affine parameter
map, proves both mapped endpoints belong to the original selected knot interval,
and transports derivative order k by the exact gain power k. Exact power-to-Bernstein
conversion on the closed raw interval bounds each original numerator and positive
weight power by its coefficient convex hull. Only the final quotient bounds convert
to outward binary intervals. Outward localization boxes are never owning-domain
premises. No subdivision, normalization, solver replay or independent allowance is
introduced; original coefficient arithmetic and typed buffers share the caller ledger.
A nonpositive denominator bound is an explicit proof failure, never a finite jet.

`OriginalFieldHomogeneousCurveIntervalJet` applies the same exact-domain Bernstein
bound over a retained original ordered coefficient field. The caller supplies original
XYZ/W in the selected normalized chart and owns the native source/domain binding.
The producer retains those equations and exact query bounds, forms genuine quotient
derivative numerators through order three, and compares Bernstein controls by exact
field signs. All coefficient sign/refinement work is routed through the caller's
independent algebra cap; geometric/root subdivision is not consumed or reset. The
caller also supplies positive coefficient enclosure width. No rounded transformed
control net or interval coefficient becomes source authority.

Integers use canonical base-2^32 magnitude limbs and an explicit sign. Rational
numerators and positive denominators are reduced by exact integer GCD. Zero has
one canonical representation. Reduction returns unit numerators and already
coprime numerator/denominator buffers without dividing both buffers by one.
The exact GCD remains the authority for coprimality; this reuse changes neither
the canonical value nor cancellation and caller admission. Original intersection
projection is a composing consumer and must retain its work/storage limits.
Equal rational denominators retain their original immutable denominator and add
only signed numerators. For unequal canonical denominators d1 and d2, addition
retains g=gcd(d1,d2), u=d1/g and v=d2/g. Its signed numerator is
T=sign1*n1*v+sign2*n2*u. Canonical inputs and gcd(u,v)=1 imply
gcd(T,u)=gcd(T,v)=1, so gcd(abs(T),g*u*v)=gcd(abs(T),g)=h.
The fully reduced result therefore has numerator abs(T)/h and positive
denominator u*(d2/h). Both divisions use exact remainder-checked cancellation;
the unreduced LCM is never materialized. If g=1, the combined numerator is
already coprime to the denominator. Zero retains sign zero, empty numerator
and unit denominator. Addition and subtraction use the same signed identity.
These operations admit every GCD, magnitude operation, division and buffer
through the original caller's checked work/storage ledger, without cell/depth
visits or private allowance. Failure and cancellation propagate unchanged;
task cancellation is checked after the final admission callback before the
unequal-denominator result is returned. Equal-denominator reduction, multiply
cross-cancellation, division and canonical source validation are unchanged.
[IntersectionRationalAdditionTests](../../../Tests/CADGeometryTests/IntersectionRationalAdditionTests.swift)
checks independently calculated canonical multiword golden values, signed
addition/subtraction and immutable aliases, independent work/storage refusal,
final callback cancellation and canonical zero/sign rejection. Intersection
composition additionally verifies its existing exact-math suite and original
finite-budget public query; coefficient tests alone do not prove that query.
A denominator proved to be exactly a power of two uses
the numerator's exact trailing-zero count to remove their common power by right
shifts. Odd numerators already prove coprimality. General fractions keep integer
GCD and exact division. One-limb integer GCD uses scalar Euclidean remainders
and retains only its final magnitude; every inspected limb/iteration and new
buffer is admitted. This removes repeated dyadic root-refinement allocations
without changing canonical original coefficient words or root depth.
Division by a one-limb divisor processes canonical base-2^32 limbs from most
significant to least significant. Its UInt64 partial numerator is bounded by
`(divisor - 1) * 2^32 + (2^32 - 1)`; its quotient limb fits UInt32. Each limb
consumes caller work and cancellation checks, and both output buffers are
admitted before allocation. Multi-limb divisors retain exact binary long
division. Behavioral verification reconstructs numerator = quotient * divisor
+ remainder and checks the strict remainder bound, including multi-limb input,
maximum limb values, exact division and independent admission failure.
Portable exact endpoint source identity uses canonical sign and little-endian
UInt32 numerator/denominator words. The caller-admitted original-parts initializer
rejects noncanonical signs, trailing zero limbs, unreduced fractions and zero
with a nonunit denominator; reconstruction uses the same composing algebra
ledger. Native decoding forwards its owned ledger through
`NativeRationalSourceDecodingContext.key` in Decoder.userInfo into this initializer.
The available Native-only `NativeRationalSourceAllowance` reference owns exactly
one Mutex<State>; work, cells and retained source storage use the original caller
limits. It has no default/private allowance. The immutable required operationCheck callback enforces the composing caller deadline
before every admission; it and cancellation run outside the mutex,
and locked sections perform only counter checks/mutations. Missing context and
unavailable Synchronization capability are typed failures. The fixed Swift6.4.0
Apple interface makes this adapter available on macOS15/iOS18/visionOS2; earlier
Apple targets cannot decode this new exact-root capability via a raw/no-op lock.
Common exact source values and portable identity do not change across targets.
Canonical `orderedTerms` is a package source-value contract, admitting its sort
and retained term array before publication. Every polynomial stores only nonzero coefficients;
monomial exponents are checked for overflow. Polynomial equality is exact.
Primitive pseudo-remainder sequences operate in Q[u][v], and univariate content
is removed by exact Q[u] division. Univariate Sturm sequences retain exact rational root bounds with explicit
endpoint inclusion. Original endpoint roots are published separately; open
interval bounds must not silently become closed unique-root claims.
A retained scalar root refines a degree-one original law directly to -b/a,
checking exact membership, endpoint conventions and the existing Sturm unique-root
receipt. No subdivision depth is consumed by this exact singleton extraction.
A retained ordered-field root whose coefficients are exact rational values forwards
to that same scalar refiner while keeping its original field polynomial and parameter
or coefficient admission domain. An adapter routes visits to the original domain on
the same ledger; no defining root, normalization or allowance is reconstructed.
The retained unique-root Sturm certificate is revalidated over the unchanged source
polynomial, rather than running another all-roots solver.
For a general regular square-free root, exact Bernstein derivative bounds authorize
rational interval Newton contraction m-P(m)/P'(I), intersected with the retained
original interval and checked by the same Sturm chain. Every contraction consumes
one next refinement depth and the same cell/work/storage ledger. Dyadic subdivision
is used only when the original derivative interval contains zero; an invalid Newton
root count is an explicit contradiction, never a fallback. No ceiling is widened.
Each isolated root retains the causal subdivision depth of its source interval.
Projection and ordered-field fiber refinement continue from that retained depth;
repeated calls never restart a depth allowance. Sign queries start at the retained
source depth and remain bounded by the same caller limit and cumulative ledger.
A finite source ideal publishes all real parameter pairs atomically. A source ideal
whose leading monomial ideal does not contain a pure positive power of both
original variables has positive complex dimension and raises the dedicated
`ExactBivariateSystemClassification.positiveDimensionalOriginalIdeal`, preserving
its original equations and reduced basis. This classification is not evidence of
a real branch or exclusion of isolated real points.
Exact simultaneous critical zero lifting solves the original square-free P, Pu,
and Pv ideal together, including vertical source factors. A resultant of P and
Pv alone cannot stand in for finite-ideal coverage. A retained algebraic pair
can decide a source polynomial sign by exact ordered-field GCD zero witnesses
and disjoint Sturm-root isolation, with the same retained depth and ledger.
An isolated-point certificate expands the exact finite polynomial at the actual
retained critical root, deciding every Taylor coefficient sign through the root
field. If every nonzero coefficient has even u and v powers and one common sign,
and nonzero pure-u and pure-v terms occur, its only real zero is the retained
point. This is a whole polynomial identity, not a positive interval or sampling
claim; lack of that sufficient certificate leaves the general atlas mandatory.
The exact monotone rectangle graph producer partitions the original free axis at
all exact roots of both transverse boundary restrictions. A whole-box separated
transverse derivative proves uniqueness, while exact edge signs in each
projection sector prove existence for the entire sector. Each retained span has
original authored/algebraic endpoints and exact incidence to its projection
stations. Boundary-only tangencies are returned as isolated stations. Rational
sector anchors authorize signs only together with exhaustive original projection
root coverage; no sampled IFT or contour is published. Isolated station materialization retains the original projection root and the
fixed transverse source boundary, exchanging axes back into native UV when
needed. It constructs the certified pair directly; it does not rerun elimination
or root isolation. Multiplicity fields refer to the chosen exact domain-constraint
projection/fiber, not an unconstrained positive-dimensional ideal.
The caller still owns native-parameter curve jets and composition into a whole critical atlas.
`ExactBivariateCriticalPoint.proven` promotes an existing system root only after
exact sign decisions establish original P=Pu=Pv=0; it retains that root fiber and
its source domain/depth without rerunning system isolation or changing budgets.
The original curve polynomial producer binds homogeneous XYZ/W to the original
curve, selected knot span and exact stored translation. Original plane and axis
incidence numerators use exact source bits for every coordinate. Original rational
curve derivative receipts keep numerator A_n and denominator W^(n+1), using
A_(n+1) = W A_n' - (n+1) W' A_n. Endpoint and seam equality therefore uses
exact cross multiplication, not an interval containing zero.
Returned GCD is normalized by its leading
rational coefficient; it is not a tolerance-dependent factorization.
Sylvester matrices use fraction-free Bareiss elimination with exact polynomial
division, including symbolic nonzero pivot row selection. A resultant identifies
projection candidates; a common factor or zero resultant does not certify any
particular real component.
Exact univariate root, pending-cell and Sturm buffers admit their concrete typed
strides; polynomial coefficient slots admit Power/coefficient pairs rather than one
UInt32 word. Limb storage alone uses raw UInt32 counts. Exact-domain derivative and
Bernstein buffers follow the same typed-slot policy before materialization.
All operations use the composing caller's admission requirements before growth;
no private work, storage or depth allowance is introduced. Cancellation and
resource failure propagate, with no partial result publication.

### Original normalized-word polynomial actions

`OriginalFieldHomogeneousImage` acts on supplied original homogeneous XYZ/W
polynomials using the prepared word's retained exact normalized frame. Its
coefficient field preserves every original direction square root; a rounded
matrix is never an input. Rational words use their exact source coefficients.
`OriginalSingularFieldTransport` combines unrelated immutable owners by importing
each original defining root into the destination tower. It retains the original
isolating endpoints, exclusion flags and causal depth and verifies unique-root
coverage over the transported defining polynomial before allocating a new root
owner. Original bivariate station fields retain both projection and original
fiber roots. Importing a field is an exact ordered-field embedding, not a new
normalization or an identification based on overlapping floating intervals.
`OriginalSingularFieldTransport.originalScalarValue` imports a retained authored or algebraic scalar endpoint into a supplied destination field. It reuses the original defining polynomial, isolation flags and depth, verifies count one after exact coefficient transport, and returns the immutable parameter value. It does not rerun elimination or root isolation and does not manufacture a bivariate spatial-incidence witness. Consumers retain the returned value when comparing native curve germs.
The invocation-local transport grows one destination tower monotonically; its
retained mapping prevents repeated imports. All scalar arithmetic, retained
mapping entries and coefficient arrays share the caller's work/cells/storage
ledger. Consumers retain native source/domain binding; this action does not
certify native root coverage or a plane atlas by itself.
`OriginalSingularFieldPlaneProjection` retains the exact square-free source,
coordinate factors, all discriminant/leading/boundary projection stations,
original real fibers at those stations and complete root ordinals on every open
strip. Bareiss elimination and Sturm decisions operate over the retained ordered
field. A finite real-locus result requires every open strip to have no real roots
and no coordinate component; projection absence alone never excludes geometric
contacts within a distance tolerance. Regular strip publication additionally
requires a whole derivative separation and opposite transverse edge signs.
`OriginalFieldPlaneAtlas` retains this projection without recomputation, resolves
every original station by the same exact point-blowup algorithm used for rational
sources, clips every resulting regular germ to the original rectangle, and
retains exact lower/upper half-branch attachment for every open-strip branch
ordinal. Its regular tube cover fills the original free interval between both
ramified attachments. Coordinate components remain explicit separate projection
outputs; this atlas does not silently discard them or infer their crossings.
The ordered-field limiting-fiber producer chooses exact transverse cuts between
every station root, moves beyond all original intersections with those cuts,
and retains the unique limiting station neighborhood of every ordered strip
root. The same inverse blowup uses original station coordinates obtained from
the retained maps at local zero, allowing normalized-word coefficient towers as
well as rational station fields. A half-branch attaches only after exact map
identity and strict membership in one regular ramified chart are proved.

The frame's explicit `NormalizationPolicy.dimensionlessOriginalDirections`
admits foreign direction ratios by exact positive raw and projected Gram values.
Their scale is dimensionless and cannot be compared with SI position distance.
The immutable minimum Gram receipt supports revalidation by the same policy
without root reconstruction. `physicalDistance` retains the existing squared
distance threshold for physical-vector clients. Both policies retain exact
independence, original angular precision and the same cumulative ledger.

## State, Ownership, and Lifecycle

Values are immutable Sendable values. Intermediate arrays/maps and counters are
invocation-local exclusive values. No shared mutable cache or platform-specific
synchronization exists. Admission remains one inout caller owner. The Native codec reference owner is
retained by its decoder userInfo and shared by every nested source value until
decoding ends. It releases its Mutex storage with that reference lifetime.

| Target | Storage | Read | Mutation | Release |
|---|---|---|---|---|
| Available Native/normal WASM codec | Mutex<State> | Immutable limit fields | Same three admission methods withLock | Decoder context reference lifetime |
| Embedded common source | Original injected caller ledger | Protocol requirements | Same caller admission methods | Original caller lifetime |
| Earlier Apple Native codec | Capability unavailable | Typed failure | No alternative mutable state | No context created |

## Failure, Concurrency, and Constraints

Nonfinite source, division by zero, inconsistent exact division, index/exponent
arithmetic overflow and cumulative budget exhaustion are typed failures.

## Verification and Change Impact

[NativeSSILowerResourceTests](../../../Tests/CADGeometryTests/NativeSSILowerResourceTests.swift) verifies the Native SSI causal resource delta with original projection cuts/source lists, necessary root visits, denominator and parent authority, independent admission limits and cancellation. The original public folded and mixed inputs are the upper composition evidence at unchanged caller caps.

Exact rational to Double enclosure starts with the leading three UInt32 magnitude
words (at least 65 significant source bits when the highest word is one), padded
with zero words for one- and two-word values. The checked binary shift is
(wordCount-3)*32 and admission charges three inspected words per magnitude.
Exact rational comparisons and adjacent Double endpoint checks retain final
outward authority. The extra prefix word prevents long ULP walks caused by a
33-bit initial ratio estimate; it changes no source value or accuracy threshold.
ExactRationalIntervalConversionTests checks short magnitudes, both signs,
highest-one large fractions and subnormals under a bounded conversion work ledger.

The current source-only phase precedes all build/test/compile/runtime/review.
Later behavioral evidence must exercise exact subnormal/normal Double conversion,
signed arithmetic, integer division/GCD, polynomial content and primitive GCD,
original native knot extraction, zero and repeated factors, cancellation and
caller exhaustion. These algorithms alone do not prove full D1 completion.

### Original regular graph endpoint authority

`ExactMonotoneGraphPoint` retains a supplied original free endpoint and the unique
original transverse fiber on a certified monotone rectangle. It does not rerun
the bivariate system solver. Its native-coordinate sign port preserves axis
exchange, root exclusion flags and causal isolation depth. Cross-axis endpoint
incidence uses the other endpoint's exact polynomial and isolating bounds, rather
than overlapping floating enclosures. Same-axis joins additionally require the
same original normal field and continuous overlapping transverse monotonicity.

`OriginalRationalSurfaceDerivativeLaw` derives every requested mixed source
partial as A_(i,j)/W^(i+j+1). The recurrence differentiates the actual homogeneous
source polynomial and positive weight law. Equality uses exact cross products,
retaining original native UV coordinates. Native normal continuity can therefore
be established from original one-sided coefficient equality even when degree /
knot multiplicity alone is inconclusive. Point-only equality authorizes only that
point; a whole seam requires polynomial identity of the restricted edge law.

### Separable flat critical authority

For an exact original P=p(u)+q(v), a constant exact remainder of p modulo the
retained projection polynomial establishes p(alpha)=c. The retained original
critical P=0 proves q(beta)=-c. Complete original Sturm root count one on each
closed axis interval, combined with matching nonzero endpoint signs (or the
unique closed endpoint zero), proves p-c and q+c each have one zero and the same
sign everywhere else. Their sum therefore has exactly the retained real zero
in the whole rectangle, including irrational flat roots and odd translated
Taylor coefficients. This theorem does not authorize nonseparable source laws.

### Mixed weighted-square isolated authority

Exact lexicographic square completion can establish a full original identity
P=sign*sum(weight_i*factor_i^2), with strictly positive rational weights. A
negative or uncompletable remainder does not establish this theorem. Every
factor must vanish at the retained actual original critical point. Complete
finite-ideal real lifting of all original factors on the same source rectangle
must return exactly one root. Actual point existence, the complete original
identity and the complete factor-system cover jointly prove whole uniqueness;
root count without those authorities is insufficient. Positive-dimensional
factor ideals are classified separately and do not authorize uniqueness.

### Coordinate-factor crossing atlas

Complete exact U/V content extraction can prove P=c*U(u)*V(v), c nonzero.
Only this complete identity admits the coordinate crossing atlas. Every distinct
original U/V root is retained by full closed-domain Sturm isolation. Vertical
and horizontal regular graphs are split at all retained opposite-axis roots.
A crossing join requires exact original endpoint incidence and a nonzero exact
factor tangent determinant. General residual factors and tangent/cusp incidence
remain outside this theorem; they require the general real singular atlas.

### Original odd-binomial cusp parameter authority

For the complete original square-free law A*(y-d(x))^2+B*(x-c)^(2k+1)=0,
A and B nonzero rational, the rational centers c/d are recovered from the
original next-to-leading coefficients after exact polynomial square completion
in the quadratic coordinate. The retained center function d(x) may be nonlinear.
Exact reconstruction of the entire
original polynomial is mandatory. The native polynomial map
x=c+(-A/B)*t^2 and y=d(x)+(-A/B)^k*t^(2k+1) has exact original zero identity.
Every real zero except the rational center has the unique inverse
t=(y-d(x))/(x-c)^k; the center has t=0.
This establishes a complete real cusp parameter law, not an interval-fit chart.
Exact original rectangle inequalities are cut at every real boundary polynomial
root and classified by exact source signs on root-free sectors. All endpoint
inclusion and source isolation depth are retained. Other singular polynomial
families still require their own complete real desingularization authority.

The package Sturm sequence port exposes its immutable original square-free source
and actual chain under the same injected algebra allowance. Root-boundary owners
may evaluate chain signs at their retained exact source endpoints to prove open
station root counts without constructing fresh endpoint roots or private budgets.

### Complete Original Quadratic Polynomial Branches

An original quadratic in one coordinate with nonzero constant leading coefficient
may split into two exact polynomial graphs. The discriminant must have an exact
rational polynomial square root, established by canonical integer square roots
and full polynomial identity. The two monic graph factors must reconstruct the
entire original law. All common branch stations are the complete original
closed-domain Sturm roots of their difference, not sampled tangencies. Original
factor gradients determine transverse crossing; a zero determinant with a
nonzero univariate branch difference proves a finite tangent contact whose two
retained graph branches and source station are explicit. General irreducible
singular factors remain a separate incomplete atlas.

A rotated cusp is admitted by recovering a rational dominant linear form from
the complete odd-degree leading homogeneous coefficients, performing an exact
invertible shear, and applying the same full square-completion identity. The
retained polynomial map is composed back into original U/V and checked against
the entire original source. The inverse of the shear and the inner cusp inverse
prove a complete joint parameter bijection; neither original coordinate is
claimed to be globally monotone. Its retained affine squared-coordinate law
equals gain*t^2 and supplies an exact four-corner Cauchy bound on the original
rectangle before complete clipping. Unsupported leading forms yield no theorem,
not a fitted rotation or partial zero cover.

The binomial germ also admits complete translated laws
A*(U-c)^m+B*(V-d)^n with coprime m,n >= 2. Exact Bezout coefficients a,b
with a*m-b*n=1 construct U=c+g^a*t^n, V=d+g^b*t^m, g=-B/A.
Integer-power rational arithmetic supports negative a/b without rounded roots.
Coprimality establishes a unique joint inverse away from the retained rational
station; the station has t=0. Full original coefficient reconstruction and
substitution are required. Branch multiplicity is min(m,n), the characteristic
exponent is max(m,n), and the retained affine power coordinate supplies the
complete finite-rectangle parameter bound. This theorem does not classify
noncoprime multiple-factor germs or arbitrary residual singular equations.

Exact translated reducible binomial recognition retains the entire coefficient
identity `a*(u-c)^m+b*(v-d)^n`. With `k=gcd(m,n)` and an exact rational real
k-th root `h` of `-b/a`, odd k has the same complete real locus as
`(u-c)^(m/k)-h*(v-d)^(n/k)`; even k with positive gain has the two signed
factors. Each published factor divides the original exactly. The residual
homogeneous ratio factor has no additional real zero: odd real powers are
injective, and even real powers have exactly the signed pair. Rational root
recognition is exact arbitrary-integer arithmetic, not a floating candidate.
A failed recognizer returns no authority and never excludes a contact.

Polynomial traversal clipping optionally consumes additional authored exact
interior stations, under the same caller ledger. It orders and deduplicates
them by exact original root identity together with the complete trim-boundary
Sturm set. Stationary parameter zero partitions a binomial curve's two real
half branches even when the original trim does not cross its singular center.

Original binomial chart discovery composes two exact triangular linear
changes of variables and optional axis exchange. Their unit determinant
supplies a complete global real bijection. Only a fully reconstructed original
binomial identity publishes a chart-derived locus; transformed native factors
are pulled back and exact-divided into the original polynomial. Characteristic
exponents and reduced intersection degrees belong to that retained chart,
not to the degree of a rotated native coordinate projection. All output
parameters and centers are transported back to original native U/V.

Exact polynomial triangular shear charts extend the same branch producer to
`a*(v-d(u))^n+b*(u-c)^m`. The original coefficient of v^(n-1) determines
`d(u)`; composition must reduce the complete original polynomial to the exact
separated binomial identity before any branch receipt is issued. The inverse
subtracts the same original polynomial and has determinant one. Original
native maps and factors are transported exactly; characteristic/intersection
multiplicities remain those of the local bijective chart. A nonaffine retained
parameter-power coordinate uses a whole original rational coefficient absolute
bound for finite clipping, rather than assuming its extrema lie at four corners.

An original polynomial traversal coordinate can be transported to an exact
algebraic endpoint by the resultant of its original retained parameter
polynomial and `x-coordinate(t)`. A whole exact rational image interval contains
the actual coordinate; only exactly one resultant real root in that interval
publishes the transported endpoint. No-root count contradicts the original
existence authority and fails. Multiple projected roots cause refinement of
the same original parameter, with no new parameter-root solve. Resultant root
isolation forwards the same ledger with the parameter's causal depth offset;
the returned root retains the summed depth, so subsequent equality/sign
queries cannot reset admission. Original rational endpoints and globally
constant coordinates remain exact authored values. This port proves equality
of original coordinates across different retained polynomial chart maps.

Original rational coordinate transport extends that same authority to N(t)/W(t).
The retained parameter's exact sign proves W nonzero before composition. Only
original parameter-polynomial factors sharing W are removed from elimination;
the selected original root cannot lie on such a factor. Resultant elimination
uses `W(t)*x-N(t)`. The exact rational image divides only by a whole parameter
interval excluding denominator zero, refining the same retained source root
when needed. Original rational proportional remainders publish their exact
constant ratio directly. Three transported XYZ equalities supply native
rational endpoint incidence to Original Coons; no new source roots or hidden
allowances are manufactured by that consumer.

Native curve polynomial preparation forwards each source validation scalar,
control, weight, knot and periodic predicate visit into the composing exact
ledger. Bulk table-size debit followed by an opaque validation scan is not the
admission contract; validation failures and cancellation propagate directly.

Original surface polynomial binding consumes the native token's metered source
comparison port: both complete original tensor payloads and token/domain checks
are charged to the same caller before identity comparison. Derived prepared
patch caches remain outside source identity. Validation failures propagate.

The exact rational three-vector partial recurrence owns homogeneous XYZ/W
coefficients separately from its surface-source binding wrapper. It issues
formal rational derivative numerators/denominators and equality numerators;
it does not authorize division at a zero denominator. The source-bound surface
wrapper retains its immutable original source and delegates this recurrence.
Native pole normal continuity uses Q/Qj projective partial equality at the
original edge, with Qj nonzero on a dense open edge and strict whole normal
nonzero/positive relative orientation; analyticity extends the normalized
partial equalities across isolated Qj zeros. No new arbitrary surface source
or missing normal is created from the formal coefficient recurrence.

### Native Decoding Admission Snapshot

`NativeRationalSourceAllowance.snapshot()` checks the original operation deadline
and task cancellation outside the critical section, then returns one atomic
immutable snapshot of consumed work, visited cells and retained storage together
with their original maximum values and maximum source depth. Remaining counts
are exact subtraction in those original units. Depth is a path bound, not a
cumulative counter and has no invented remaining-depth interpretation. A snapshot
does not reserve or reset resources. Concurrent or subsequent validation keeps
the same reference admission owner; post-decode consumers can carry remaining
counts only at an established decoding-to-validation ownership handoff. The same
Mutex continues to protect every Native and normal WASM codec access.

### Original Plane Curve Projection Atlas

The original square-free plane law is split into its exact U-content, exact
horizontal boundary factors and primitive-in-V remainder. Projection retains
the remainder's leading coefficient, discriminant resultant and both original
closed-V boundary restrictions. Their product's complete Sturm root partition,
including authored U bounds, divides the original closed rectangle into exact
stations and open strips. On a strip there are no degree changes, critical
V-fibers or original boundary crossings. The ordered simple real fiber roots
at one admitted rational free station therefore give the complete number and
ordinal of original regular branches throughout that strip. That rational
station supplies an exact Sturm count, not sampled geometric exclusion.

Every projection station retains complete ordered-field roots of the original
primitive remainder over the original closed V interval. Original vertical and
horizontal components remain explicit and are never hidden by finite lifting.
If all strips have zero roots and no coordinate components exist, all original
real zeros are exactly those retained station fiber points; this certifies
finite real loci of general positive-dimensional complex ideals, without a
Hessian or sum-of-squares restriction. Nonempty strips retain their original
projection/fiber ordinal authority for subsequent critical incidence and
ramified charts; a strip count alone is not a joined curve or D3 endpoint proof.

All endpoint ordering/refinement uses retained algebraic isolation depths and
the same caller work/cell/storage ledger. Original projection roots are never
replaced by rounded double events. Publication is atomic after the complete
original station/strip/fiber partition has been produced.

General projection incidence uses exact rational transverse cuts strictly
between the retained station fiber roots. Every cut's original free-axis
restriction is isolated with its inherited source depth. An admitted rational
free station is chosen between the selected original event and the nearest
cut-crossing event on that same strip. No cut crossing lies in the remaining
open band. The ordered simple fiber roots there therefore determine every
half-branch's limiting station fiber, including multiple roots, crossings,
cusps, boundary-only events and degree-drop stations. Root counts must match
the retained strip count. Each incidence retains its original sector ordinal,
station root, side, safe free witness and fiber root authority; it does not
claim native-axis D3 at a singular station without a ramified chart.

Original rational derivative equality can transport the second stored chart by
an explicit exact constant parameter translation. Each already-differentiated
original numerator and denominator is composed with that translation, and
comparison retains original mixed orders. This is a source-chart identity
query, not a fit or a new independent coefficient authority.

### Original Singular Ordered Fields

Generic singular resolution translates the original polynomial at the retained
exact original UV station. Its coefficients belong to that station's ordered
real field; recursive tangent directions extend that same field with a retained
real root of an exact tangent polynomial. Immutable field contexts retain the
original station or their parent context and root. Arithmetic admits ancestor
embeddings only, and unrelated selected root contexts fail explicitly. Exact
Sturm signs, division and root isolation use the same caller work/storage/cells
and inherited depth at every extension. Rational labels never replace an
irrational center or tangent. A field root or tangent count alone does not
publish a joined silhouette: the strict transform, original branch incidence
and requested native derivative bounds remain publication requirements.

Point blowup resolution first square-free-reduces the original law and translates
it at the retained original pair. For every singular strict transform, complete
ordered-field tangent roots supply finite projective directions; the remaining
vertical direction is included exactly when its homogeneous coefficient is
zero. Each composed source map divides only the complete exceptional-axis
power. A regular leaf retains its strict transform, both original polynomial
maps and all tangent/root steps. No-real-tangent leaves retain their exact
definite leading homogeneous law as isolated germ evidence. Every step consumes
causal depth from its parent's original isolation; exhausting the existing
caller depth fails atomically. Germ resolution alone does not establish whole
rectangle clipping, interval D3 or a global connected-curve publication.

Regular strict-transform leaves admit an actual closed local graph rectangle by
whole interval derivative exclusion and opposite transverse edge signs. Free
and transverse widths shrink together with the original caller depth until
those conditions hold; all coefficients are enclosed by exact sign bisection
in their retained field. The graph is the unique original strict-transform
root for every admitted free parameter. Original polynomial maps compose its
UV D0-D3 by complete mixed chain rules. This closes local ramified chart
existence and derivatives, but global source clipping and incidence assignment
remain distinct requirements before an entire silhouette envelope is published.

Original ramified chart clipping solves strict-transform plus authored source
boundary equations over the same retained ordered field. Lexicographic exact
Groebner reduction supplies finite projection events and complete original
ordered-field fibers; a non-finite boundary ideal is classified explicitly as
coincident geometry, never inferred empty. Complete root coverage, original
endpoint exclusions and same-ledger depth must precede any clipped-sector
publication. Generic field elimination owns algebra only; source-domain
membership and tolerance contact decisions remain with the original consumer.

Original normalized STEP frames use a rational base field and extend it only
with the selected positive real square root of each original squared norm.
Raw axis coordinates become exact original dyadics; no rounded normalized
component is fed back into projection or inversion. Axis2 uses normalized axis,
projected normalized reference and its oriented cross. Cartesian uses the
original normalized axis3, projected normalized axis1 and projected axis2; the
original uniform scale remains exact. Default reference changes to Y only for
an original axis structurally equal to a signed X direction. Every original
normalization retains its original squared tolerance refusal.

Original location length gain and ordered world-displacement adjustments are
consumed without precomposing a rounded frame. Post translations add the exact
original displacement; conjugations add displacement minus the original linear
image of displacement. Output columns and translation remain immutable exact
field values with same-ledger square-root source receipts.

Original singular incidence transports a retained original strip fiber into the
selected germ's existing ordered field. The raw original rational fiber
polynomial and its inherited isolating interval are converted coefficientwise;
complete unique-root authority is checked on that same interval, without a new
root isolation. Each blowup step retains its actual tangent value context. The
inverse rational blowup uses that retained value and proves nonzero denominators,
the strict-transform identity and the original U/V maps. A point selects a local
chart only after all exact local bounds hold. A failed chart membership is not
a source branch exclusion; the global incidence owner must retain all original
half-branches and complete their assignment before publishing an envelope.

Normalized frame temporary vectors reserve their actual FieldElement payload
strides in UInt32 storage words before allocation. Inverse columns use fixed
scalar rows rather than an unadmitted nested-row temporary. The ordered field
element is a direct immutable enum value; its polynomial array/map storage
breaks recursive layout, so no indirect payload box is required. Context
construction admits its stored Source payload, retained owner reference and
the Swift object header before allocation through the same injected ledger.
No mathematical operation, root context or normalization gets a fresh allowance.

A regular strip half-branch is attached to a singular leaf only by exact inverse
blowup membership at a retained original fiber. The source station equality
port verifies identical original projection values and one common fiber root
in the intersected original isolations. An adaptive anchor remains between
that exact station and the previously certified cut-free strip witness; its
complete original fiber count and ordinal remain fixed. Approach refinements
consume inherited caller depth. All candidate leaves are checked, and exactly
one closed local graph must contain the nonexceptional branch anchor before
a half-branch attachment is published. Exhaustion or ambiguous ownership fails,
never removes a source half-branch.

Normalized frame linearGain is an original exact positive rational, separate
from location lengthGain. It multiplies each original normalized axis and the
original uniform scale before any world conjugation adjustment. Mapping
placements retain linearGain one; primitive local model-unit images pass their
exact source unit gain. The two gains are never merged into a rounded scale.

Prepared normalized frames retain the exact minimum original squared norm of
every raw and projected normalization in their source construction. Inverse
actions preserve that premise, and ordered composition selects the exact
minimum in the common descendant field. A later caller validates its squared
tolerance against that immutable receipt once; it does not replay normalization
or reuse a looser constructor tolerance silently. Authored direct affine
frames have no normalization premise. The receipt is derived and excluded from
source identity, while its comparison uses the same injected ledger.

The original rational plane atlas composes the complete projection and incidence
producers with every retained station's real blowup resolution and actual
authored-domain chart clipping. Every projected half-branch is attached once
to the matching source station and its unique local chart. Coordinate
components remain explicit in the projection packet. This packet owns complete
source station/strip incidence; regular strip derivative covers, spatial surface
composition and periodic native joins remain the composing silhouette owner's
publication duties. No count-only packet is a SurfaceSilhouetteEnvelope.

Regular strip derivative cover retains exact rational free-axis endpoints
between the original projection events. Each adaptive cell isolates the
complete original midpoint fiber and selects the retained global branch
ordinal. A closed original polynomial tube is published only when the whole
transverse derivative excludes zero and both complete transverse edges have
opposite strict signs. Rational root receipts select candidates; they never
authorize a tube by sampling. Failed cells subdivide their exact free interval
under inherited depth until every original interval is covered or the caller
allowance fails atomically. Outward binary boxes must remain inside the same
original projection strip and native source domain.

A station chart used for strip attachment additionally solves the original
primitive transverse-derivative constraint after the complete original blowup
map. Every critical preimage in its closed local graph must be the exact local
origin; any other retained root shrinks that chart under inherited depth. The
primitive source has no vertical component, so this ideal is finite. Away from
the exceptional origin, the original birational map is regular and the source
projection has no critical point. Each free half-chart is therefore a monotone
original strip branch until its retained attachment anchor. This establishes
the near-station coverage premise used with central regular strip tubes.

A derived ramified curve identity retains the original zero law and station
root certificate, deterministic resolution leaf and clipping-sector ordinals,
closed local/source domains and exact free endpoint isolations. It is an
identity for a transient proof-backed curve, not authored document fingerprint
authority. Prepared field caches and reference addresses are excluded. The
sole atlas issuer supplies the original resolution and clipping ordinals.

A near-station traversal retains its original half-branch attachment rather
than guessing a local root endpoint. Its exact local free anchor is the inverse
blowup of the original rational strip witness and selected original fiber.
Projection regularity proves the local path from the exact origin to that
anchor is the same original strip half-branch. The traversal identity retains
that original source anchor, sector/branch side and station certificate;
interval endpoint bounds are derived under the same ledger.

An atlas may retain an already admitted OriginalRationalPlaneCurveProjection
packet. Its source station/fiber roots and depths are reused directly, allowing
finite real-locus classification and subsequent positive incidence to share
one original projection preparation. This reuse does not reset the caller
ledger or re-isolate identical projection roots.

Plane projection accepts an inherited source subdivision depth. Its coordinate
and discriminant root isolations start from that same depth; authored boundary
fibers retain it too. Subsequent station resolution, attachments and regular
strip queries inherit those original root depths. Entering the exact atlas from
an already subdivided public silhouette rectangle does not reset its caller
cell-depth budget.

An original system-root coordinate projection eliminates the retained fiber
against its existing source projection, after removing only poles and whole
fibers absent at the selected original root. Its real coordinate is selected
by the retained pair enclosure and unique Sturm count, refined under the same
causal depth. This transports a known original point; it never runs the system
solver again or treats a resultant root as point existence by itself.

Persistent parameter-incidence polynomials expose their immutable canonical original coefficient map to the portable source adapter. The adapter owns deterministic key sorting and its caller byte/work admission; no derived projection or interval coefficients enter the source payload.

OriginalFieldUnivariateRationalFunction retains reduced exact numerator/denominator polynomials over one original ordered field. Its arithmetic and exact polynomial composition own GCD cancellation and admit all coefficient storage through the original caller. Removal of a common factor establishes only a removable expression value; publishing a source singular station additionally requires the original map identity and selected chart authority.

OriginalFieldPlaneCoordinateComponent proves a whole positive native interval with one original coordinate fixed at a retained real field root. Every coefficient in the other variable must vanish exactly at that same root. Original U/V are never exchanged in the published receipt. These stationary-coordinate continuous loci are distinct from isolated points and may supply S8 ambiguity only when the consumer proves all original XYZ equations by the common factor contract.

### Retained original scalar enclosure

`OriginalSingularFieldValueIsolation` retains an exact value, rational lower/upper bounds and the causal depth of their proof. Refinement starts from those bounds; it never restarts magnitude search or bisection on repeated queries. Every sign subquery uses the same caller ledger, maps its original-root depth onto the current enclosure path, and reduces its available depth accordingly. Returned refined receipts retain the greatest actual subquery depth. Binary bounds are queries of that receipt, not replacement source endpoints. Trim sectors retain these receipts when constructing interior witnesses or refining their exact endpoint bounds.

### Retained regular-strip coordinate cuts

`OriginalRationalStripCoordinateCuts` augments a retained atlas with authored/algebraic cuts of both original native coordinates. It keeps the projection sector and branch ordinal, constructs only new cut fibers, and uses exact Sturm rank in the original transverse closed domain to bind each cut point to an existing strip. Existing station resolution and strip covers are retained unchanged. Identically horizontal cut equations publish a separate coincident-strip receipt. These cuts do not themselves certify monotonicity or complete singular endpoint sectors; native pair consumers combine them with their retained critical cuts and incidence.

Original rational surface polynomial construction admits homogeneous, derivative-numerator and normal array buffers by actual element stride before allocation. Scalar coordinate selection uses fixed axis switches, so control/view temporary arrays are not created. Native source binding visits are forwarded into the same caller ledger before original knot and coefficient construction.

`OriginalSingularFieldElement.nonnegativeSquareRoot` is the shared exact Euclidean norm/root port. It proves nonnegative original radicand sign, preserves an exact rational square when available, otherwise isolates the unique positive root of the original quadratic over its retained coefficient field using inherited caller depth. Native normalization and original polyline arc-length laws use the same producer; no Double square root is an exact coefficient authority.

### Original Euclidean polyline parameter law

`OriginalEuclideanPolylineParameterLaw` retains original UV points, exact positive segment lengths, prefix/total and their normalized whole-curve fractions in one shared ordered field. Exact coincident-point segments are excluded without a distance floor. The caller owns independent algebraic depth and all scalar work/cells/storage. Per-segment local interpolation remains affine in the original raw UV differences; the original whole fraction is the exact prefix/total affine image. Geometry evaluation, inversion and silhouette trim events consume this same receipt rather than binary hypot/prefix candidates. The producer rejects an all-zero original polyline atomically.

Polyline length preparation removes a positive exact common rational magnitude from each raw coordinate difference before quadratic isolation, then restores that magnitude in the returned exact length. This algebraic identity prevents arbitrary UV scale alone from consuming root-separation depth; it does not change the Euclidean law, original zero-segment criterion, or caller ceilings.

Polyline segment queries explicitly select an original positive source segment. They return the original local fraction, UV value and first whole-fraction derivative as exact field expressions, preserving raw endpoint ratios and prefix/total. Segment selection checks every exact whole-fraction boundary under the caller ledger and makes endpoint ownership explicit with `preferFollowingAtJoin`. It does not imply derivative continuity across a polyline corner.

### Original ordered-field surface normal

`OriginalFieldSurfaceNormalLaw` differentiates retained original homogeneous XYZ/W coefficient laws and constructs the exact cross-product numerator and view-dot numerator over the same ordered field. Spatial normalization is unnecessary for the zero equation: its equivalence holds wherever the original W is nonzero, and source-normal regularity remains a separate consumer premise. `OriginalFieldZeroSetAuthority` retains original/repeated/square-free factor identity and original partial bounds through order three for actual field silhouette/projection consumers. It neither replaces original native source binding nor admits a singular surface as regular.

Original homogeneous field images compose subsequent retained spatial words by importing original coefficient owners into one destination tower, acting on full XYZ/W, and retaining the result. No word is renormalized or replaced by rounded matrix columns. The action is linear in homogeneous source coordinates; translation multiplies original W.

Issued field-value identity compares the same immutable coefficient owner and exact stored rational-function structure. It is conservative representation identity for transient curve receipts, not a zero/equality proof across unrelated fields. Source geometric equality and global endpoint incidence continue to use paid exact transport and signs.

The complete field plane projection includes original vertical-component roots in its projection-event polynomial. Primitive strip station cuts therefore also retain intersections with fixed-coordinate components. The additive retainedRoot endpoint port materializes authored linear endpoints or preserves existing algebraic root receipts; it does not rerun an eliminator.

Original coefficient term ordering admits the full `(Power, coefficient)` tuple
payload before the sorted immutable buffer is allocated, using the canonical
UInt32-word storage conversion. A logical term count is not a storage byte count.

Mixed original operation words may embed an authored row-major rational 3x4
source through `OriginalRationalNormalizedFrame.init(authoredCoefficients:in:
maximumDepth:usage:)`. Exactly twelve coefficients are required; columns retain
the original rationals and a nonzero exact determinant. No direction normalization
is performed and no normalization-distance premise is manufactured. All four
field-element arrays and their exact arithmetic use the caller ledger.

A rational zero-set receipt may be lifted into a rational ordered-field context
without repeating its GCD proof. The lifting initializer retains the original,
repeated factor and already-proved square-free law coefficientwise, then issues
its genuine partials through order three. Native silhouettes may therefore use
the same complete coordinate/station/strip atlas as normalized source images.

`OriginalFieldStripCoordinateCuts` retains coordinate intersections of an already
prepared field atlas. Original scalar cuts are imported without isolating their
source again; open-strip cuts use exact retained sector membership and original
Sturm fiber rank. Station cuts use exact retained UV equality, so a closed endpoint
is not inferred from overlapping enclosures. The result records cuts and source
incidence; a caller must use these exact events to form and classify its clipped
sectors, rather than claiming that an outward native box is an exact domain.
Parameter refinement and coefficient refinement use distinct explicit caps with
the same cumulative work, cell and storage owner.

`OriginalFieldStripSectorPartition` consumes a coordinate-cut receipt whose cuts
include all four exact rational rectangle boundaries. It orders every original
free event and retained projection endpoint exactly, preserves attained endpoint
isolation depth across adjacent sectors, and selects each sector's original
transverse fiber ordinal at a strictly interior exact dyadic free witness. Exact
closed bound signs classify the entire event-free sector: complete boundary cuts
and original strip continuity prevent membership changes inside it. Sector
endpoints, selected fiber, source atlas and inside/outside classification remain
retained. Closed station events and coordinate components retain their separate
authorities; this partition never replaces them with a free-parameter midpoint.

Exact univariate isolation admits `Root`, polynomial-sequence and `Pending`
slots by their concrete stride before creating or extending each owned buffer.
Closed endpoint visits use fixed scalar selection, so no unaccounted two-element
coefficient scratch array is formed. Exact magnitude limb arrays alone retain
UInt32-word counts directly; result or traversal slots never do.

Original rational surface/vector derivative equality can select explicitly requested U/V partial orders. It validates each selected order against the retained original table and emits only their three homogeneous quotient cross-product numerators, with typed result allocation on the original admission. Unrequested derivatives supply no join-continuity assertion.

Retained field value isolation recognizes a structurally rational original expression before numeric bracketing. Its exact quotient is a closed singleton at the existing inherited depth; extracting an authored binary rational is not subdivision. Nonrational field values retain original exact comparisons and causal refinement.

The immutable original fields of `OriginalSingularChartIdentity` are package-visible for complete source provenance visitation. Consumers retain the issued station, exact maps, branch/sector ordinals and endpoint expressions without rebuilding resolution or identifying roots from bounds alone.

`ExactBivariateCriticalPoint.retainedOriginalParameters` supplies the immutable issued projection/fiber pair for source provenance without solving or replacing a critical root.

`ExactSurfaceCoefficientPolynomial` retains a selected parameter polynomial with Q[u,v] coefficients. `ExactSurfaceCoefficientResultant` eliminates that parameter by fraction-free original ring arithmetic; its output is only a candidate UV equation until the original common real fiber is lifted and checked. Matrices and coefficient slots use actual typed storage admission.

### Original locus common fibers

`ExactSurfaceLocusCommonFiber` computes the common separate-parameter law in the
original quotient of Q(u)[v] by a square-free original locus. Rational residues
retain numerator and denominator polynomials; pseudo-reduction records every
nonzero leading coefficient whose zero set was excluded. A zero-divisor lead
splits the original locus by exact GCD and repeats the same algorithm on both
proper factors. Pure coordinate factors use an explicit axis exchange, restored
in the result. Original screen equations, the exact factor, clear-denominator
common law and every excluded coefficient are retained. At points outside the
recorded exceptional zero sets, pseudo-PRS is an exact equivalence of common
fibers. Exceptional station fibers require original specialization and complete
lifting; the generic quotient receipt alone never proves complete real coverage,
real existence or emptiness. All typed slots and polynomial operations use the
same caller admission, with no private quotient allowance.

`ExactSurfaceLocusParameterProjection` reorders the retained trivariate common
fiber into Q[u,s][v] and eliminates the original dependent coordinate. It retains
both coefficient-ring equations and the original UV locus binding. Its polynomial
in (u,s) is a projection candidate with exact coefficient authority, not a real
contact or correspondence certificate; common actual real v fibers and original
UV membership must be lifted before consuming its real atlas.

`OriginalEuclideanPolyline3DParameterLaw` owns the same exact arc-length clock
for original XYZ points. It sums all THREE original squared coordinate differences,
excludes only exactly zero segments, and retains exact Euclidean lengths, prefixes,
total and normalized stations in one coefficient field. Its selected-segment and
local-fraction operations return the original XYZ and first derivative expressions.
The caller supplies the authored traversal including any closing segment; this
lower owner does not infer closure or introduce points. Independent coefficient
root depth, scalar work and actual typed storage are caller-admitted throughout.

- [OriginalFieldScalarRoot](OriginalFieldScalarRoot/DESIGN.md): retained original
  tower norm descent and exact scalar real-root transport for native endpoint binders.

Original quotient common fibers expose squareFreeParameters(component:usage:),
which removes repeated separate-parameter factors in the original locus quotient.
Pseudo-division retains its actual leading coefficient exceptions; no ambient
three-variable GCD replaces quotient equality. This supplies projected section
discriminants under the same caller ledger.

Ordered-field plane quotientAndRemainder(dividingBy:maximumDepth:usage:) performs
original sparse lexicographic division in one immutable field owner. The returned
remainder contains no monomial divisible by the source divisor's leading monomial;
original = quotient * divisor + remainder exactly. Exact division delegates to
this producer and rejects any nonzero remainder. All coefficient actions and
temporary records share the caller's admission.

### Original Constant Coefficient Access

An exact sparse polynomial may issue its existing constant coefficient only when
its table is empty or consists solely of the zero-power entry. The lookup admits
work and cancellation, allocates no term array and retains the immutable original
coefficient owner. A nonconstant table returns nil rather than a sample value.
Original ordered-field rational values use this contract for constant numerator
and denominator laws. A denominator equal to one preserves the numerator value;
constant-fraction signs use the two exact coefficient signs without constructing
and reducing an unnecessary quotient. A zero denominator still fails, including
when the numerator is zero. For two original constant fractions, field sum,
product and quotient operate directly on their exact rational coefficients and
reissue the result in the same retained field context. Operand embedding happens
first; division still rejects zero and no unrelated field is identified. This
avoids term arrays, sparse polynomial products and unreduced constant fractions.
Nonconstant and extended algebraic field paths keep their original reduction.
Native, WASM and Embedded share the same immutable source/field implementation.
This closes the actual quantified-incidence constant-field allocation bottleneck;
it is not a new allowance or a numerical coefficient approximation.

Exact rational scalar arithmetic admits its operation and cancellation before
using zero or signed-unit identities. A canonical integer denominator of one
requires no integer GCD or quotient construction; the existing immutable
numerator can be retained directly. Addition multiplies a numerator by the other
denominator only when that denominator differs from one. General nonunit
fractions still use exact magnitude arithmetic and reduction. Zero divisors are
rejected before any quotient identity. These paths preserve canonical signed
source words and use the same arithmetic/ownership contract on every target.

### Original Rational Prefix Substitution

`OriginalIntersectionFieldEvaluation` consumes the immutable ordered-field contract.
When its retained context is rational, validate every coordinate against that exact
owner and obtain its original rational value. Evaluate coefficient sums/products
directly in Q, then issue one field element per final coefficient (or scalar).
This avoids materializing a field quotient for each intermediate rational term;
all new rational arithmetic, arrays and final field storage remain charged to the
caller. A nonrational coordinate in a rational owner is an explicit failure.
Original and extended algebraic contexts retain their full original field path.
Native, WASM and Embedded use the same immutable owner and implementation.
Identity powers may reuse their original coefficient without allocating new
polynomial storage; cancellation and inspected work are still admitted.

### Verified Original Scalar Seeds

A complete native zero-cell consumer may seed scalar localization with retained
rational section bounds. OriginalSingularFieldValueIsolation validates ordered
bounds against the actual retained field value using exact lower/upper signs,
rejects a foreign or invalid interval, and preserves every inherited depth.
OriginalAlgebraicCoordinate can retain those bounds for later caller-admitted
queries. This port changes no root identity, equation coverage or depth ceiling.
[Native Point Relations](../CurveSurfaceOverlap/NativePointRelations/DESIGN.md)
owns section extraction and geometric bound production. NativeCurveSurfacePointTests
owns invalid/reversed/excluding seed rejection and depth-preserving refinement.

### Original Root Separation Refinement

Whole root-union ordering and disjoint-sector separation select the existing
Sturm bisection branch for rational root brackets. Their exact dyadic midpoint
and retained Sturm sequence preserve exactly one original root in a shrinking
closed/excluded interval, using the same inherited caller depth and work/storage
ledger. They do not run interval Newton to manufacture large rational endpoint
denominators. Ordinary scalar localization and sign refinement keep their
existing Newton behavior. Both modes retain the original field polynomial and
root admission domain; cancellation, root-count contradiction and exhausted
depth remain explicit failures. Separation changes no root identity, precision
threshold, maximum depth or allowance.

Root-union ordering contracts only the wider overlapping unique-root bracket.
The narrower root keeps its localization until it becomes the wider one. Equality
preserves each original admission domain and the maximum intersection depth. A
linear expression at a linear root uses exact cross multiplication in the same
parent field; an already issued identical linear root is retained before issuing
another isolation.

The complete issuer retains its immutable field Sturm sequence and, for rational
laws, the existing rational-root authority. Bracket contractions reuse the same
original law and parent context. `minimalSectionRoot` preserves that issued root
when its original law already has the minimum degree. Rational expression signs
reuse the rational Sturm sequence after verifying the contracted unique-root
bracket under `OriginalScalarRootDomainAdmission`. An identical bracket reuses
that exact receipt only when both endpoints, endpoint exclusions, rational-station
flag and inherited depth match the same immutable root owner. Every reuse still
checks cancellation, admits the endpoint comparisons and visits the original
parameter or coefficient depth. Rational refinement binds its already certified
contracted authority into the returned receipt; a changed bracket keeps the
original unique-root validation. Nonrational expression signs
keep the existing field path. All retained buffers belong to immutable root
receipts; no shared mutable cache or admission reset is introduced. Linear
expression signs at a nonlinear root reuse this same original Sturm sequence
for exact threshold rank after evaluating the original law at that threshold;
there is no equivalent-law reconstruction or repeated derivative/GCD issuance.

A degree-one root whose exact parent-field value is a rational affine or observed linear-fractional image of
an already retained rational-law ancestor may contract that ancestor's existing
Sturm bracket and map its endpoints exactly. A degree-one numerator and denominator over a
rational quadratic ancestor use this same port after certifying the linear
denominator has the same strict nonzero sign at both endpoints. A bracket
straddling a pole, including a pole at an excluded endpoint, requires further
ancestor Sturm contraction under its remaining depth. The exact derivative
determinant selects endpoint orientation. The ancestor keeps its own admission
domain and attained subdivision depth; the derived receipt keeps the maximum of
its previously inherited depth and the ancestor's attained depth. Intersection
with the derived original bracket retains endpoint exclusions and is validated
against its original linear law. This reuses the same unique-root proof without
creating a field extension or restarting any root's depth. Both roots must use
the parameter admission domain; other structural cases keep the existing field
refinement. This parameter-only image path forwards the original caller admission
directly: its parameter-cell routing is identical to the parameter-domain adapter.
It must not nest a generic admission wrapper across recursive field refinement,
which requires unbounded specialization in Embedded Swift. Coefficient-domain
sign and ordinary refinement retain their domain adapter. The direct path preserves
every work/storage charge, parameter visit, inherited depth and cancellation check. All endpoint arithmetic and retained proof buffers use the same
cumulative ledger. The retained ancestor contraction is immutable and reused by
subsequent contractions. AdmittedIntersectionRingTests checks positive and
negative image orientation, endpoint/interior pole contraction, inherited depth
24, original source-law equality,
and independent depth/work/storage refusal.

A retained root exposes original-law counting only for a subset of its current
isolation with preserved endpoint exclusions, nondecreasing inherited depth and
its unchanged admission domain/ceiling. It reuses its original immutable Sturm
sequence; a root without that retained issuer constructs the original-law
sequence under the same ledger. This contract counts original roots, not roots
of a proposed common factor. AdmittedIntersectionRingTests checks admitted and
foreign subintervals, excluded endpoints, depth and independent budget refusal.

An exact magnitude GCD with a unit input returns the immutable unit after one
work admission and retains no intermediate limbs. This preserves the canonical
scalar result while avoiding binary subtraction buffers during rational integer
cross cancellation. AdmittedIntersectionRingTests owns the fixed allowance,
independent limit, retained-depth and wider-bracket regression evidence.

### Canonical Field Polynomial Division

Exact long division eliminates the same original leading terms in one immutable
field context. It owns one quotient and one remainder coefficient buffer and
updates those buffers with the existing exact field multiply/subtract operations.
Each eliminated leading coefficient is checked to have exact zero sign; trimming
checks the remaining leading coefficient under the unchanged caller depth.
Canonical results transfer these owned buffers without materializing monomials,
full product polynomials or a second canonical copy. All created scalar buffers
and both output buffers remain admitted to the cumulative ledger. Undefined
denominators, unrelated contexts, zero divisors and independent depth/work/storage
limits propagate their existing failures. AdmittedIntersectionRingTests checks
quotient/remainder reconstruction over an algebraic parent and these refusals.

### Immutable Structural Constants

Each immutable field context owns canonical rational zero/one authority and its
unit denominator. Construction admits the additional heap payload and generated
unit buffers in the same caller ledger before retaining them. An extended
context's zero/unit polynomials refer only to its parent context, so authority
retention follows the existing acyclic parent ownership graph. This is structural
Q0/Q1 authority, not a source-root or query-truth cache. Constant creation and
embedding borrow these buffers only in their matching context and admit work and
cancellation on every call, including after the final admission callback before
returning a borrowed value. Context construction likewise checks cancellation
after its last unit-buffer admission before publishing the owner. Other constants
still construct their original
numerators under the existing sign/depth and storage checks; undefined source
denominators remain failures. No global intern or mutable shared storage exists.
AdmittedIntersectionRingTests verifies zero-storage Q0/Q1 borrowing, nonunit
allocation refusal, independent work/cancellation, retained parent context and
construction-storage refusal.

### Exact Ordered-Field Identity Reuse

Multiplication of canonical field polynomials by the exact rational constant one
retains the other polynomial's buffers only in the identical immutable field
context. It admits cancellation and work and checks the retained leading
coefficient's sign with the unchanged caller depth, as canonical construction
does. Original coefficients and undefined denominators remain in that retained
polynomial. This removes unit-denominator products during original Sturm
endpoint evaluation without changing its root-count proof or allocating another
coefficient buffer. AdmittedIntersectionRingTests checks both orientations,
zero-allocation reuse, independent work/depth refusal and retained undefined
denominator failure.

After embedding into the same immutable field owner, addition by an exact
rational zero and multiplication/division by an exact rational one retain the
existing operand buffers. A zero product retains the other operand's original
denominator, so undefined source fractions remain detectable. Zero division
still validates the divisor sign before retaining the numerator. Cancellation
and inspected work remain admitted; field ownership, source laws and independent
root depths do not change. AdmittedIntersectionRingTests compares these results
with their original algebraic value and checks zero-divisor failure.

Multi-limb magnitude GCD uses exact Euclidean remainders from the retained aligned
integer division buffers. Each nonzero remainder is strictly smaller than its
divisor; every limb inspection, division and retained result stays in the same
caller ledger. This avoids allocating a new shifted/subtracted magnitude for
each binary GCD bit step. AdmittedIntersectionRingTests checks multi-limb common
factors, coprime inputs and canonical rational reconstruction.

A degree-one field Sturm issuer retains the same exact monic source `[B/A, 1]`
and derivative chain `[source, 1]` directly after validating its nonzero leading
coefficient. These are the same quotient and chain that generic GCD/long division
produce; the linear polynomial has no repeated factor. Root counts, endpoint
exclusions, bisection, original field and admission domains remain unchanged.


## Exact Polynomial Contract

The [ExactPolynomial](ExactPolynomial/DESIGN.md) child owns L1 and depends only
on the fixed L0 scalar contracts. The parent owns higher consumers.

## Exact Scalar Contract

The fixed L0 value, decision, arithmetic, ownership and resource contracts are
owned by [ExactScalar](ExactScalar/DESIGN.md). The child keeps the existing exact
numeric algorithms and has no dependency on geometry, CADCore, or Numerics.
Non-scalar consumers and outward floating-point conversion remain in this parent.
