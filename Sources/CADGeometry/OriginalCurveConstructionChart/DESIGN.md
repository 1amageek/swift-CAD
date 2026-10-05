# Original Curve Construction Chart

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md). Owns persistent normalized original curve
traversals and retained rational construction parameter charts. It has no children.

## Responsibilities and Boundaries

The source carrier retains either an original root traversal or an original curve,
authored parameter labels, a construction law and exact directed rational fraction
endpoints. Modeling owns construction selection, fitting and final-candidate
certification. This component evaluates the retained original law; fitted control
points and rounded inverse stations do not establish its authority.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | persistent source dispatch | Publishes the normalized source family. | Preserve exhaustive dispatch. |
| [Original Root Span](../OriginalRootSpan/DESIGN.md) | depends on | retained endpoint/owning jets | Evaluates directed authored and algebraic traversals. | Constructor capabilities remain binding. |
| [Original Higher Curve Jets](../OriginalHigherCurveJets/DESIGN.md) | depends on | original requested-order jets | Composes original curve derivatives with parameter law. | Derivative hulls alone do not establish join smoothness. |
| [Canonical Sphere Chart](../CanonicalSphereChart/DESIGN.md) | depends on | ideal conic angular phase | Binds rational construction fraction to authored conic labels. | Normative foreign SI radians require a distinct symbolic transport. |

## Architecture

```text
original root traversal ----------------------> normalized original curve
original curve + authored labels
    + exact directed construction fractions
    -> retained parameter law -> original curve Taylor composition
    -> normalized original curve
```

## Contracts and Invariants

The published domain is [0,1]. Exact rational first/last construction fractions
retain the actual directed restriction and reversal law. Endpoint images follow
that law; an outward station bracket or its midpoint cannot become an authored
endpoint. A root-traversal arm consumes the already admitted root endpoints and
original owning-side preparation directly. No rounded endpoint difference or
replacement control net enters source identity.

The circular rational law uses the original ideal conic half-angle and positive
quadratic denominator on one directed construction chart. All derivative orders
include the canonical phase gain. Source curve jets and parameter jets compose
with the complete chain rule under the same caller work, byte, source-depth,
span and subdivision admission. The hyperbolic rational law retains the original cosh/sinh half-weight proved by caller-paid Taylor range reduction, explicit tail bounds and double-angle reconstruction and positive quadratic denominator, with a caller-paid complete atanh series and tail bound. Broader inverse atlases remain explicit unsupported producer branches until their original laws are supplied.

## State, Ownership, and Lifecycle

Source values are immutable and persistent. Derived preparation and interval
caches are excluded from source equality and serialization. Queries borrow the
composing invocation; they introduce no private proof allowance. Retained buffers
reserve checked actual bytes before allocation.

## Failure, Concurrency, and Constraints

Wrong source/tolerance binding, invalid fraction domain, exhausted admission and
inconclusive inverse charts fail explicitly. Source, algebra and subdivision depth
have independent meanings. A finite point candidate cannot authorize endpoint
incidence, correspondence or embedding.

## Verification and Change Impact

Behavioral verification must cover directed restrictions/reversal, original
endpoint incidence, nonlinear derivative chain rules, owning-side joins and
work/byte exhaustion. Changes affect Curve3D dispatch, Native/portable codecs,
Loft/Coons boundary publication and Sweep original frame proofs. The current
source phase does not establish behavioral completion.

Affine parameter-law images retain one immutable original PreparedCurve token under construction work/byte admission. Their bounded first-order query maps exact fraction and authored label expressions before outward localization, then unions the retained original owning D0/D1 fields and applies the exact chart slope. It requires no C3 join law and does not identify a synthetic hull as a smooth owner. Traversal images reuse the RootSpan first-order contract. Nonlinear conic first-order queries use their explicit original source Taylor composition.

Smooth-native admission uses a retained selected RootSpan side or exactly one positive-width original source owner after the exact affine fraction/label map. Explicit ideal circular and hyperbolic parameter laws are smooth on their admitted closed chart. Other source families return no smoothness proof; synthetic hull ownership cannot supply it.

Spatial rigid/affine/flat-word images preserve an original conic’s authored parameter labels and inherit the same construction parameter law. Family admission descends only those parameter-preserving spatial images under original source depth. A parameter image changes labels and requires a transported chart receipt. Circular positive-halfweight inverse charts cover all finite positive ratios by atan(r) for r<=1 and mathematical pi/2-atan(1/r) for r>1, retaining the same tail/work/byte admission.

Affine parameter-law owning covers retain each original native span index and
domain, its exact original gain/offset, and a normalized interval localization.
The exact map and selected original domain determine side ownership; outward
normalized cut bounds do not become exact knot stations. D0-D3 are transported
per original owner, with no continuity inference from their union. Nonlinear and
algebraic traversal charts require their own retained mapping authority.

### Exact Selected Native Domains

A direct affine parameter-law chart can issue an exact selected native interval
jet from rational normalized endpoints and its original native owner metadata.
The issuer reconstructs the original affine gain/offset and proves metadata
equality, binds the actual source knot index/domain, and uses the shared exact
selected-polynomial range producer. Its source-domain membership is proved
before final outward conversion; localization boxes never become exact cuts.
Periodic translated owners and outer parameter-changing wrappers require their
corresponding exact source transport and remain explicit unsupported branches.

Bounded chart preparation accepts an optional independent algebra cap and forwards
it unchanged to original source validation and retained curve preparation.
Affine chart owners retain the original source; their outward normalized cuts
remain localization, rather than exact native partition endpoints.

Smoothness queries forward an explicitly selected algebra cap to retained
RootSpan endpoints. Parameter-law preparation records its algebra policy; a
stricter later policy requires a real cache rebinding capability and otherwise
fails explicitly, rather than using broad cached owners as proof.
