# Parameter Image

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with [Native Axis Inverse](NativeAxisInverse/DESIGN.md) as a child. Owns persistent original
curve and surface laws under signed independent affine parameter maps and a
finite spatial affine surface map. The original source graph is retained by
value; unit or frame transport never replaces it with fitted controls.

## Responsibilities and Boundaries

Exchange owns unit descriptors and authored trim records. This component owns
`native = offset + gain * foreign` and exact source-graph retention. Gains are
finite and nonzero, including negative orientation. Surface axes retain independent gains and may exchange the original U/V order.
When `swapAxes` is true, foreign U maps to native V and foreign V maps to native U;
gains and offsets stay attached to their foreign axes. The stored permutation is
part of original source identity, native persistence and derivative authority.
Modeling owns topology orientation and uses the resulting parameter derivatives.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original point, derivative and interval laws | Composes retained sources. | No new sampling authority. |
| [Native Axis Inverse](NativeAxisInverse/DESIGN.md) | child | monotone original native axis inverse | Retains native pcurve owner and exact normalized station. | Constant plateaus and nonaxis images have no unique inverse. |
| [Geometry Conversion](../GeometryConversion/DESIGN.md) | used by | original position and derivative enclosures | Converted candidates are certified against the retained image. | Candidates do not replace this source graph. |

## Architecture

```text
foreign native parameter / UV
    -> retained signed gain and offset
    -> original source curve / surface
    -> retained spatial affine map (surfaces)
    -> point and complete derivative chain / original interval chain
```

## Contracts and Invariants

Closed domains invert the original finite bounds and periodic domains divide the
original period by the gain magnitude. Original cyclic origin remains in the
retained source. Directed trims remain in foreign parameter units. Parameter
queries and interval queries validate finite arithmetic and original domain
coverage. Interval clipping requires an independent exact expansion comparison
of both mapped endpoints to original bounds; a tolerance does not supply domain
authority. A gain changes an order-k curve derivative by gain^k, and a surface
(uOrder,vOrder) derivative by uGain^uOrder*vGain^vOrder before the spatial linear
map. Translation applies only to position. Normals and curvature are recomputed
from the mapped tangents and second derivatives by the existing geometry layer.

## State, Ownership, and Lifecycle

Exact chart comparison borrows the caller work closure only inside
`withoutActuallyEscaping`; no returned source value or result retains that
closure. Interval and Taylor validation failures propagate to the caller.

Immutable source values retain COW storage. No mutable state, cache or platform
specific isolation is introduced. Native Codable adapters preserve explicit source
fields with strict expected keys; common values retain Hashable and Sendable.

## Failure, Concurrency, and Constraints

Invalid gains or nonfinite composed arithmetic fail explicitly. Native source
proof budgets remain caller owned. No lower helper enlarges a caller budget or
acceptance tolerance. Rounded inverse domain bounds are not proof that a mapped
interval belongs to a finite original domain; actual interval admission checks
original endpoint expansions independently.

## Verification and Change Impact

After the source phase, verify signed gains, periodic origins, directed trims,
strict native codec roundtrip/rejection, original whole-interval derivative bounds
and foreign frame transforms through Exchange and Geometry Conversion callers.

### Exact ratio unit gains

A parameter gain may retain a binary coefficient or an exact ratio of original
finite binary numerator/denominator values. The ratio is original authority; its
Double estimate is only a numeric evaluation convenience. Endpoint admission
compares exact cross-products of the ratio rather than the rounded quotient.
This retains degree boundaries as the exact original pi/180 ratio and proves
90 degrees maps to the original pi/2 native boundary. A nonrepresentable generic
foreign boundary needs an original native boundary-chart receipt; inverse Double
roundtrip or tolerance proximity does not prove collapse.

### Representable singleton images

Any closed singleton may retain zero width only when exact ratio cross-products
prove the numeric native coordinate equals the original scalar image. This applies
to unbounded and periodic supports as well as finite boundaries. No rounded
quotient or tolerance proximity is used as the identity witness.

### Inverse original scalar images

The inverse-bound port encloses `(native-offset)*denominator/numerator` with
outward arithmetic. A singleton is returned only when exact cross-products prove
that the represented foreign Double maps to the original native singleton. The
exact scalar inverse accessor rejects a nonrepresentable original inverse; a
rounded midpoint is not an exact authored endpoint.

### Original image pcurves

A retained pcurve image binds the original SurfaceLiftCurve3D to an original image
whose source surface is structurally identical. Foreign UV is the inverse of the
stored ratio and axis permutation. Spatial lifting evaluates the original source
lift and applies the stored affine spatial map; it never maps a rounded foreign
UV boundary back to the native pole as its identity authority. Directed source
fractions, reversal and trimming remain stored source-law inputs. Interval UV
coefficients use outward inverse ratio arithmetic, while the lifted XYZ fields
retain the original spatial source and derivative chain.

### Exact Original Affine Orientation

Affine image composition retains each original transform and source recursively;
rounded matrix composition is only a numerical utility, never replacement source
authority. `AffineTransform3D.originalDeterminantSign` evaluates the triple
product of its original stored columns by expansion arithmetic. Finite nonzero
exact sign proves nonsingularity and oriented image parity; a zero or
indeterminate sign fails for operations requiring invertibility. Work and
cancellation remain owned by the invoking transformation operation.

### Original factor products

`OriginalParameterGain.originalProduct(factors:usage:)` retains the flat original
binary/ratio factor list and prepares its reduced exact rational coefficient and
outward interval under the invoking `RationalAlgebraAdmitting` ledger. These
prepared values are immutable derived caches, excluded from source identity and
wire fields. Native decoding recomputes them under the original decoder ledger.
No rounded product is parameter-law authority. Scalar materialization and inverse
materialization compose the original rational expression and enclose it before
choosing a numeric evaluation candidate. Exact equivalence compares reduced
original coefficients, irrespective of foreign unit IDs or names. Endpoint domain
admission uses exact original cross-products; nonfinite expansion arithmetic
fails explicitly and callers requiring arbitrary exact algebra use the borrowed
rational ledger ports. Flat source factors, work, rational words and cancellation
are charged before construction; no private allowance is introduced.

### Original Periodic Translation

`OriginalParameterPeriodicTranslation` retains the original native period, signed
integer turn count and signed gain. Native translation is exactly
`originalPeriod * turns`; foreign translation is that exact rational value
divided by the original gain. Every coefficient operation belongs to the
composing caller's algebra allowance. An estimated `ParameterDomain.periodic`
value is a numeric convenience and cannot authorize a directed endpoint or seam.
Geometry owns the persistent exact endpoint/chart carriers; Exchange composes
these ports before publishing a wrapped foreign trim. Native strict source fields
and common portable writers retain the original three-field law. No new mutable
state or platform-dependent source contract is introduced.

`OriginalParameterImageMap.originalSpanFitsPeriod` compares the absolute exact
gain times the exact difference of original foreign endpoints with the original
native period under the caller's borrowed algebra ledger. Equality admits one
complete cycle without using the width of an outward numerical enclosure as
period authority. An original mapped traversal receipt still owns subdivision
and native periodic partitioning; this comparison does not clip or narrow its
outward parameter enclosure.

### Original Directed Endpoint Difference

A normalized directed chart may compose an outer parameter image whose signed
gain is the exact original upper-minus-lower value plus an original periodic
translation. `OriginalParameterGain.Difference` owns those three source fields
and immutable derived exact-coefficient/outward-bound caches. It is prepared
under the composing caller allowance; source equality and persistence retain
only the original operands. The outer offset remains the original authored lower
Double. Normalized [0,1] trims therefore map to original wrapped endpoints even
when the foreign period cannot be represented as a Double. Numeric gain estimates
do not define singleton membership, endpoint equality or topology closure.

Rigid source transformation preserves the outer original parameter image and
its retained gain/offset, recursively transforming only its spatial source.
Item traversal bindings therefore retain the same chart relationship to their
transformed shared basis; a whole foreign-chart rigid wrapper is not substituted.

### Bounded Spatial Image Construction

The bounded affine curve and original surface-image constructors retain the
identical original source graph, parameter gains, offsets, axis permutation and
spatial coefficients as the legacy constructors. They admit the resulting source
through bounded family validation, forwarding each native control, weight, knot
and source-descendant visit to the composing callback. Remaining source depth and
subdivision depth are explicit caller inputs. Legacy construction remains an
unbounded source convenience; it is not cumulative query admission. COW source
retention does not materialize or round a transformed coefficient net.

### Original Affine Word Jet Transport

The image adapter transforms each original spatial jet field through the
prepared exact affine word, with translation applied only to value order zero.
Every rational or ordered-field enclosure operation uses the composing caller
ledger. The prepared source word, not a representative matrix, binds proof
fields. Higher-order image coefficients use the identical linear source action;
normal/cofactor and image carrier wiring remain separate adapter contracts.

A package validated-source replacement on an original surface image preserves every retained chart gain, offset, axis swap and spatial transform. The caller owns prior admission of both the original chart and replacement source; the replacement performs no validation or new proof work and cannot create a different chart law.

### Caller-Admitted Exact Affine Domain Transport

The generic affine interval and inverse ports evaluate both original endpoints
with exact rational gain and offset coefficients on the borrowed algebra ledger.
Original closed-domain signs authorize clipping; outward floating bounds never
authorize domain membership. Representable exact singleton images remain
singletons. Every exact word allocation is charged by its actual lower owner,
with no work-only surrogate for optional byte accounting.

### Caller-Admitted Hosted UV Image Queries

A hosted original UV image maps its directed original fraction endpoints with
exact rational endpoint arithmetic and outward final conversion. Its inverse
UV value map uses the same exact original gain/offset coefficient law. Selected
queries forward work, optional byte admission and independent algebra policy
through the source Taylor evaluation and each coefficient map. Fixed-field
third-order chart transport allocates no dynamic jet scratch; temporary exact
coefficient payloads are admitted by the same scalar ledger. Value-only bounds
do not demand higher join continuity.

Original surface image closed queries use the same exact affine domain mapper
for each original UV axis before any source jet request. Native-box mapping may
borrow the composing rational ledger directly, or forward work/optional bytes
through a scoped adapter. Gain/offset, axis swap and source-domain containment
remain original source law; the mapper introduces no source validation reset.

A scoped already-validated parameter-image relation may map its interval with
the composing rational ledger directly. This pure map does not revalidate a
local primitive against world tolerance; the enclosing original-image caller
owns the prior physical/source relation admission.

### Identity-UV Native Panel Transport

An admitted original surface image with both gains exactly binary one, both
offsets zero and no axis swap preserves every original native UV owner and knot
station. Its original binary spatial transform may be prepared as one exact
rational forward factor under the same work/storage ledger. The quantitative
differential action transports all seven tessellation bounds: the linear norm
for tangents/second derivatives and the original cofactor condition for unit
normal derivatives. This action neither unions neighboring owners nor grants
continuity across a C0 knot. The composing mesh retains the original selected
owner and uses the unchanged UV box. Nonidentity UV charts still require their
exact owning station mapping and are outside this narrow capability.
