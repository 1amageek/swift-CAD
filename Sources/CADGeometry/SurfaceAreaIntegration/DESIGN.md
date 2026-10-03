# Surface Area Integrands

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), consumed by topology's
[Surface Area Integration](../../CADTopology/SurfaceAreaIntegration/DESIGN.md).
Owns integral-specific interval enclosures without publishing internal jets.

## Responsibilities and Boundaries
Exact supports and pcurves determine density and first moments. The component
composes certified geometry with the exact signed fan parameter map. Topology
owns tolerance allocation, adaptive work and measurement acceptance.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | prepared interval differential jets | Exact geometry | Derivative order matters. |
| [Surface Area Integration](../../CADTopology/SurfaceAreaIntegration/DESIGN.md) | used by | integrand bounds | Certified measurement | No sampled error estimates. |

## Architecture
```text
prepared support + exact pcurve -> outward UV fan jets
    -> |S_u cross S_v| and reference-centered position moments
        -> pullback value/gradient/Hessian interval fields
```

`SurfaceAreaParameterChartEncloser` owns invocation-local preparation of numeric
trim charts and exact directed offset/affine rigid chart images. It depends on
the existing numeric interval jet contract, rather than changing the shared
boundary-certification implementation. Topology passes the retained original
trim and its prepared chart authority to integrand evaluation.

## Contracts and Invariants
- Existing structural affine support authority permits exact radial elimination.
  Boundary density and moments retain exact numeric pcurve derivatives.
- Every published interval contains the entire requested parameter box.
- Mapped trim admission validates the exact destination support and the source
  relation only after all nested input dimensions and nesting depth have been
  bounded. Directed offset images retain source UV exactly. Rigid images require
  the geometry-owned affine parameter transform and retain the original source
  fraction map, including reversed traversal. Fraction endpoints outside [0,1]
  are invalid input; modeling-tolerance clamping does not authorize integration.
  Outward affine UV/fraction arithmetic and the third-order chain rule enclose
  values and derivatives over the complete requested interval. No sampled
  reconstruction or materialized approximation changes the original fan map.
  Implicit source charts and non-affine spherical images remain explicit
  unsupported failures. Preparing a chart does not allocate another query error
  allowance or reset adaptive cell/depth/control admission limits.
- C0 spline integration uses prepared native Bezier span domains as its
  partition authority. A smooth proof is valid only when the complete requested
  pullback box belongs to one span, including that span's one-sided boundary
  derivatives. A box crossing a C0 knot has an explicit value-only proof;
  gradients and Hessians are absent, rather than fabricated or reused across
  the density jump. Each intersecting span computes density and centered
  moments before their value ranges are unioned. Intersecting the support box
  restricts enclosure geometry only; it never changes the original fan measure.
- Native span descriptors retain the stored knot coordinates and an opaque
  prepared-span identity. Consumers may partition a translation rectangle at
  those coordinates and request the corresponding one-sided enclosure without
  selecting jets from a neighboring span at a shared boundary. Periodic chart
  normalization retains coverage of every representative piece.
- A constant-coordinate fan boundary may partition its radial parameter at
  native knots when exact expansion arithmetic proves each cut identity and
  the other native coordinate remains inside the selected span. These opaque
  domains retain the original fan map and full radial measure. Unproved cuts
  use value-only cross-span integration. An affine fan with exactly zero
  determinant is structurally zero; sampled area estimates do not authorize
  omitting a boundary contribution.
- Periodic spline axes use the geometry-owned conservative base-chart interval
  normalization before prepared-patch intersection. Each axis returns at most
  two intervals, or one complete cycle; every Cartesian piece contributes to
  the union. Negative and shifted representatives never discard coverage, and
  no control net is copied for a requested cycle. Native derivatives are
  unchanged by a periodic translation; the original parameter map still owns
  pullback scaling and integration measure.
- Genuine offsets normally certify density gradients only. For a single
  constant-weight polynomial Bezier support of total degree at most three,
  every fourth surface derivative is exactly zero. The actual offset interval
  path differentiates source jets into tangent jets whose third derivatives
  are zero; this structural proof makes those tangent third derivatives valid.
  Normalization then certifies the normal through order three, hence the offset
  through order three and the area-density Hessian through order two. Other
  supports retain gradient-only bounds; nested offsets lacking source order
  three remain explicit unsupported failures.
- Translation certificates use exact expansion equality of control differences,
  matching weights and parameter charts. For rectangular trims, density is
  independent of the translation parameter and position is affine in it;
  integration equals band width times density/moments at the exact band midpoint.
  Original chart domains and error tolerances remain authoritative.
- Rolling-ball supports with three normalized linear rails and exactly equal
  control displacements prepare constant contact radials once. Their center is
  affine in U; normalized radials, circular weight and the original native-V
  rational arc are retained with outward bounds. Every U derivative of the
  radial term and every mixed derivative is exactly zero by that structural
  authority, rather than by subtraction of separately enclosed moving rails.
  Constant radial lengths and the regular minor arc are certified before use;
  positive Bernstein denominator bounds cover the complete requested V interval.
  Other rolling-ball supports retain the existing prepared enclosure path.
- Density Hessians require valid third surface derivatives and sufficient knot
  continuity. Insufficient regularity uses gradient bounds or typed refusal.
- Ruled and rolling-ball source curves independently determine available
  derivative order; surface lifts over genuine offsets provide no Hessian.
- Unsupported pcurve derivatives are explicit failure; zero substitution is
  forbidden. UV endpoint rounding is clipped only to the exact support domain.

## Failure, Concurrency, and Constraints
Prepared state is immutable and invocation-owned. Unsupported derivatives,
singular frames and nonfinite interval arithmetic produce typed KernelError.
Topology owns geometry-size admission and subdivision bounds.
Chart preparation additionally preflights nested source/destination geometry
before recursive validation or transform materialization. Prepared charts are
immutable and retain source ownership for the invocation; no shared cache or
platform-dependent state is introduced.

B-spline lift rails consume the shared prepared closed-box and point contract
owned by [CADGeometry](../DESIGN.md). Their original UV jets and native-span
authority remain intact; interval localization has machine conditioning only.
The previously observed modeling-tolerance position floor must be closed by the
literal B-spline-lift ruled rectangle regression under its original default
query allowance. The separate analytic-plane caller/depth fixture continues to
own exact support/depth forwarding. Neither proof completes the remaining
procedural/implicit domains of full Q3.

## Verification and Change Impact
[`SurfaceAreaIntegrationTests`](../../../Tests/CADTopologyTests/SurfaceAreaIntegrationTests.swift)
validates composed behavior, including independently differentiated polynomial
offset density bounds through the actual offset-normal enclosure path,
piecewise C1 support, and admission of both endpoints of an eliminated band.
Periodic-strip fixtures independently evaluate uniform cubic polynomials and
their density derivatives on negative, shifted and seam-crossing intervals,
then compare public face area and moments with a physical-coordinate integral.
Rolling-ball fixtures retain the quarter-cylinder area and centroid contract,
exercise a translated diagonal spine with independent native rational-section
derivatives, and reject the translation certificate for unequal rail motion.
Changes to procedural
jets, pcurve jets or knot smoothness require rechecking derivative-order routing.
C0 verification owns folded rectangles and their three centered moments,
cross-fold triangular trims, holes and reversal, non-dyadic knot coordinates,
the smooth/value-only proof distinction, and whole-query resource/cancellation
failures. Successful C0 support integration does not authorize higher-order
offset derivatives or any other incomplete procedural/trim path.
Mapped-chart verification compares public rigid/offset area and all centroid
coordinates with independent geometric integrals, checks source-fraction
restriction/reversal and interval derivative containment, and rejects foreign
targets, unsupported charts, malformed dimensions and nesting/work exhaustion.
