# Original Plane Derivatives

## Purpose and Scope

This child of [Original Coons](../DESIGN.md) owns original real arithmetic
projection of generated endpoint and surface transverse derivatives onto exact
support planes. It has no children. It closes strict planar Loft G1/G2 source
generation; final correspondence, regularity and topology remain caller proofs.

## Responsibilities and Boundaries

The producer retains support Surface3D sources, requested derivative orders and
the original generated source. Exact plane coefficients and prepared interval
derivatives are derived immutable caches. It owns the coefficient equation and
orthogonal null-space action, never rounded native row projection.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../../DESIGN.md) | depends on | Original framed infinite-plane chart | Authored U defines the support image | Tolerated nonorthogonality does not replace the chart cofactor |
| [Original Coons](../DESIGN.md) | parent | Original corner incidence | Coherent four boundaries | Position sources are retained |
| [Boundary Correction](../BoundaryCorrection/DESIGN.md) | depends on | Native tensor and original flat position correction | Unconstrained base | Its pure native Dv claim applies only to that base |
| [Original Root Span](../../OriginalRootSpan/DESIGN.md) | depends on | Requested-order original directed jets | Source endpoint derivatives | No midpoint becomes a derivative source |
| [Loft](../../../CADModeling/Loft/DESIGN.md) | used by | Canonical generated connector and final side | Strict plane continuity | Fresh final source certification is required |

## Architecture

```text
original support sources -> exact plane equations -> orthogonal normal basis
original connector -> endpoint D1/D2 projection -> same endpoint positions
native tensor + original position-corrected base + corrected connectors
    -> endpoint-coherent transverse fields -> Hermite derivative residual
    -> final original side -> fresh target/regularity/correspondence proof
```

## Contracts and Invariants

Each plane equation uses the original source coefficients. For `Plane3D` with
an authored U, the support equation uses the exact original cofactor
`U cross (N cross U)` and the original origin, following the module's authored
chart contract. Tolerated nonzero `N dot U` is retained; the stored N alone is
not the support equation. A zero cofactor fails explicitly. Nil-U and direct
analytic plane arms retain their existing raw-normal equation and admission.
Raw affine images
use the exact cofactor/determinant equation. Independent normals are reduced by
exact rational Gram-Schmidt without normalization; their null-space projection
is an exact real law. A dependent plane is retained as original source but adds
no duplicate normal. Rank-three corner constraints cannot silently produce a
regular tangent; final nonzero derivative/normal admission must reject them.

The connector adds quintic Hermite derivative bases with zero endpoint values.
Start/end D1 or D2 targets are projections of the same original derivatives.
The two endpoint positions remain the same original traversal expressions. Cached interval delta vectors enclose exact raw endpoint/projection expressions; they are not source coefficients. Numeric midpoint positions are error-guarded candidates only and are never retained as a new curve law. Exact polynomial consumers must reconstruct the raw expression, never reinterpret an interval or its midpoint as an exact coefficient.
All adjacent plane constraints share one canonical connector, and each side
checks inclusion of its original requested constraints in that connector.

Let P be a side's exact derivative projection and N its native construction.
At a section end, the target transverse field is P(N_v) plus quintic U blends
of endpoint differences between the canonical connector derivative and P(N_v)
at that corner. Every difference remains in the requested planes. Subtracting
the actual position-corrected transverse field produces a residual that is
exactly zero at U=0 and U=1. Quintic V derivative bases apply that residual
without changing any of the four original position boundary sources. D2 uses
the same law when curvature is requested, with actual Taylor factorials. The second-order public numerical facade requests only order two; third-order publication is a separate contract. Native transverse-field queries admit the exact required mixed partials rather than imposing unrelated pure higher derivatives at U joins.

The unconstrained original boundary-corrected source is unchanged. Its package nativeTaylor query exposes its already retained original tensor owners to this child; no second native preparation or boundary surrogate is introduced. New raw
curve fields are source traversal and two constraint arrays. New raw surface
fields are construction, final four-boundary carrier and two constraint arrays.
Equality/codecs/fingerprints include these fields and exclude preparation. Native strict field decoding forwards the one decoder-owned allowance, prepays constraint array growth, and obtains source nesting from the explicit source decoder key independently of the algebra allowance. The source wrapper intersects that admission with retained child capabilities.

## State, Ownership, and Lifecycle

Source and caches are immutable Sendable values. One invocation allowance pays
source coefficients, basis storage, native preparation, query scratch and copies
before allocation. UInt32 words are four bytes; byte callbacks convert by checked
ceiling division. No private allowance, refund or context reset exists.

`ProceduralSurface3D.originalPlaneDerivative` retains this immutable payload in
an indirect case on every target. Copies of an existing enum value share the
same immutable owner; releasing the last value releases the payload. The enum
is non-frozen, and the package enables no library-evolution ABI promise. Source
equality, hashing, Sendable conformance and the native source codec schema are
independent of this storage choice.

The bounded Loft factory reserves one payload stride and the added retained
procedural field stride in its existing original
source allowance immediately before publishing the indirect case. Native
source decoding reserves that payload through its existing shared decoder
allowance. These reservations measure retained payload capacity, following the
existing UInt32-word ledger; they do not claim allocator metadata accounting or
cover unlimited caller-authored reboxing. Caller-authored source construction
and decoding precede an intersection invocation. A query consumes the existing
immutable source and admits its own preparation and scratch; it does not charge
again for an input box that already exists.

## Failure, Concurrency, and Constraints

Invalid plane authority, missing corner constraints, incompatible endpoint
derivatives, unavailable original requested-order continuity, zero final normal,
cancellation or caller exhaustion fail explicitly. Scalar algebra, source
nesting and geometric subdivision remain distinct capabilities. Normalized
algebraic plane coefficients require their actual ordered-field issuer, not a
rounded equation. Unsupported arms retain a precise incomplete marker. The supporting equation issuer
checks cancellation at every successful publication boundary, including after
recursive affine and word cofactor transport. A terminal admission callback may
cancel and return normally; this never authorizes successful issuance. These
checks consume no additional work or storage allowance.

## Verification and Change Impact

After source implementation, exercise tilted plane G1/G2, coincident and
independent corner planes, zero constrained tangent, affine support equations,
exact four-boundary identity, mixed requested orders, original C0/C1 joins,
cancellation and resource exhaustion through the final Loft publication path.
Source authoring alone establishes none of these behavioral results.

The portability smoke exercises copied and released indirect values, unchanged
hash/equality, point evaluation and native codec round-trip/requery. Full
production Embedded and normal WASM builds run the same public smoke with
`-Onone`; optimized lowering cannot establish this storage portability.

Exact rational boundary consumers apply the retained exact normal-basis projection to original quotient-rule endpoint derivatives. The four Hermite corrections are reconstructed from original homogeneous source coefficients and raw constraint equations. This path uses no cached interval delta as a coefficient and preserves original piece domains through directed affine restriction. The interval projection cache and exact action share the same immutable normal basis.

### Retained Rational Surface Position Atlas

The exact position atlas consumes the existing correction atlas, retained Native
tensor owners and original connector laws. It uses package projection ports on
the original surface to apply the already retained exact normal basis; it never
prepares another projection or imports interval coefficients. Every Native
boundary field comes from the owner whose closed V support contains the actual
section station, with the same exact U support. An interior tensor is never
extended to a different original boundary owner. Original quotient-rule D1/D2,
quintic connector blends and corner-flat Hermite residuals implement the same
source expression as intervalTaylorJet without changing that evaluator.

```text
existing correction XYZ/D + retained Native boundary XYZ/D
                         + original exact plane projection
original connector XYZ/D + original Hermite bases
                         -> immutable complete position cells
                         -> SourceIssuer exact import and sealed UV family
unchanged intervalTaylorJet -> existing numerical admission and derivatives
```

The position atlas retains every original correction cell, subdivided by any
original connector station cell. Its denominator is the uncancelled product of
validated positive-weight Native and original rational traversal denominators
and their derivative powers, so it remains nonzero throughout each closed cell.
No normal regularity guard is added to position support. All coefficients, cell
slots, array capacity and scratch use the caller's single algebra admission;
the SourceIssuer retains the inherited coefficient/value depth. Missing Native
boundary ownership, unavailable rational child authority, incomplete coverage,
source-depth/cell/work/storage exhaustion and cancellation fail before family
publication. The atlas grants position/support/correspondence only, without a
new claim of differential continuity across original joins. Non-rational and
angular surface supply remains outside this rational capability.

Verification compares nonzero projected position against the unchanged actual
point and derivative path, including section/connector endpoints, all Native
chart sides, multiple Native V owners, raw plane normals, identity projection
and explicit source/admission failures. SourceIssuer reuses its already verified
sealed retained-surface family contract; a caller cannot drop a cell and retain
the whole-domain witness. The [actual source-to-DI fixture](../../../../Tests/OriginalRevolutionSourceVerification/Sources/DerivativeSurfaceProof/Proof.swift)
and [focused verification receipt](../../../../Tests/OriginalDerivativeSurfaceIntakeVerification/VERIFICATION.md)
own this rational surface handoff; whole-CAD rebuilding is separate.

The [authored support tests](../../../../Tests/CADGeometryTests/OriginalAuthoredSupportingPlaneEquationTests.swift)
exercise exact chart incidence, original tangent projection and retained source
identity, exact affine cofactor transport, malformed chart refusal, and independent
caller work, storage, source-depth and cancellation failures. These local proofs
do not establish final Loft or complete public intersection publication.
