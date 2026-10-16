# Original Analytic Intersection Sources

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns exact implicit
pullbacks of direct authored analytic plane, cylinder, sphere and torus sources
to one retained original rational curve span. This is source preparation for CS composition; it does not publish
surface UV fibers, angular-domain coverage or a public curve-surface result.

## Responsibilities and Boundaries

`OriginalSphereCurvePullback` and `OriginalAnalyticCurvePullback` retain their direct analytic source, the original
homogeneous curve issuer, its span/translation and exact closed parameter domain.
It issues the raw equation and unchanged denominator, preserving multiplicity.
The existing relation resolver owns root isolation, whole-domain exclusion,
incidence and component identity. Public CS consumers own analytic UV correspondence.

Only direct `AnalyticSurface3D` primitive values are admitted; the sphere has its existing dedicated issuer, while the additional issuer owns plane, cylinder and torus. A canonical surface reconstructed
from an offset, image or rounded rational conversion is not original authority.
The curve law is supplied by its existing validated native/source-image issuer;
this component neither reconstructs that law nor changes its parameterization.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md#canonical-ideal-angular-primitive-authority) | parent | Direct ideal sphere center/radius | Supplies source meaning | Preparation is not complete public CS |
| [Original Supporting Plane](../OriginalCoons/PlaneDerivatives/DESIGN.md) | depends on | Raw original origin/normal plane equation | Supplies the direct plane source equation | Does not infer exact unit length |
| [Original Affine Image](../OriginalAffineImage/DESIGN.md) | depends on | Original harmonic normal gauge and exact source-frame coefficients | Supplies cylinder/torus binary chart basis authority | No exact orthogonality or unit assumption |
| [Canonical Sphere Chart](../CanonicalSphereChart/DESIGN.md) | depends on | Ideal closed sphere and intrinsic phase | Establishes the original primitive image | No candidate angle enters coefficients |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | Retained original homogeneous curve and exact rational arithmetic | Supplies original span law and same-ledger arithmetic | Preserve W, span, translation and original parameter bounds |
| [Intersection Algebra](../IntersectionAlgebra/DESIGN.md#public-original-rational-relation-selection) | used by | Original rational laws, predicates and closed domains | Consumes F=0 and W!=0 | Its resolver, not this issuer, owns real coverage |

## Architecture

```text
direct analytic source + retained original curve (Hx,Hy,Hz,W)
    -> existing source equation / original harmonic frame authority
    -> exact original coefficient arithmetic and unchanged W
    -> immutable source/span/domain receipt
    -> original one-coordinate relation: F=0 AND W!=0
    -> existing real relation resolver
```

## Contracts and Invariants

The direct sphere has no authored mutable frame: its fixed unit-Z chart produces
unit-Y and negative-unit-X axes by exact operations on zero and one. The parent
defines its original image by stored center/radius. The Euclidean norm equation
therefore denotes this direct primitive, not a tolerance-unit frame inference.
Center/radius Double bits are transported individually before subtraction or
squaring. No rounded radius square, sampled point or chart candidate is a coefficient.

The input owns four homogeneous laws with no second-parameter powers and a
nonzero denominator. The output is exactly their original sphere equation;
zero F proves only algebraic containment on W!=0, while a nonzero F remains
nonzero regardless of its numerical coefficient magnitude. No square-free
normalization or division changes raw F. The exact source parameter domain,
native span, translation and complete original curve source stay retained.

The relation adapter binds both raw F and W to the same one-coordinate domain.
It includes W!=0 explicitly even when native positive weights already establish
positivity. An adapter does not invent sphere angular parameters or root cells.

### Plane, Cylinder and Torus Laws

The plane uses the existing `OriginalSupportingPlaneEquation` contract: its raw
stored normal and origin define F=n·H+offset·W. Validation within a unit tolerance
does not make the normal exactly unit, and no such property is required.

The direct cylinder and torus consume the existing harmonic coefficient issuer's
`originalNormalGauge`. Its binary chart axes are the original basis authority in
[Original Affine Image](../OriginalAffineImage/DESIGN.md). The affine frame B has
columns (firstDirection, secondDirection, axisDirection) and the original center.
Each coefficient enters exact originalDouble arithmetic before the exact matrix
inverse is constructed. Its determinant must be nonzero in exact arithmetic.
Local homogeneous coordinates Q=B^-1(Hx,Hy,Hz,W) therefore retain this actual
frame even when its axes are not exactly orthogonal or unit. Neither a tolerance
unit check nor raw axis dot projection replaces this inverse.

The raw cylinder equation is Qx²+Qy²-r²W². The raw torus equation is
(Qx²+Qy²+Qz²+(R²-r²)W²)²-4R²(Qx²+Qy²)W². Radius products are exact products of
individual source scalars. Source validation establishes R>r>0; for W!=0 the
positive R²-r² makes the quartic equivalent to the original ring-torus image,
without an extra branch from squaring. Canonical intrinsic phases cover full
circles; selected angular domains and UV fibers remain the consumer's contract.
Raw multiplicity is preserved. The receipt retains raw source, actual frame,
exact inverse, curve span/translation/domain and unchanged W after input release.

The cone's halfAngle is an authored physical-radian scalar, as established by
[Canonical Sphere Chart](../CanonicalSphereChart/DESIGN.md), rather than a symbolic
quarter-turn label. The present exact rational/algebraic coefficient owner has no
issuer for its original transcendental sine/cosine/tangent slope. A binary libm
tan/sin/cos result cannot replace that source. The additional issuer explicitly
refuses cone with unsupportedCapability and an incomplete-implementation marker;
this remaining source domain does not become a rounded rational cone.

## State, Ownership, and Lifecycle

All production state is immutable and Sendable without target-specific branches.
The receipt owns its source-law values and their immutable backing storage after
the caller releases its input variables. No cache or independent allowance exists.

## Failure, Concurrency, and Constraints

The composing `ExactScalarAdmission` pays every traversal, polynomial operation,
retained payload and relation-adapter term/power buffer before growth. Degree and
allocation arithmetic is checked. Preparation does not visit parameter or
coefficient root cells. Source validation failures, unsupported source kind,
invalid homogeneous binding, zero denominator, work/storage rejection and
cancellation fail explicitly, including cancellation from the final admission
callback. No failure issues a receipt, empty relation or coincidence result.

## Verification and Change Impact

[OriginalSphereCurvePullbackTests](../../../Tests/CADGeometryTests/OriginalSphereCurvePullbackTests.swift)
owns raw repeated-root identity, translated nonunit-radius sphere coefficients,
varying positive weights on a nonunit domain,
exact rational-circle containment, strictly positive tiny proximity with whole
exclusion through the existing public resolver, invalid source/weight rejection,
unchanged denominator guard, retained source lifetime, independent work/storage
boundaries and entry/final-callback cancellation. Geometry source, native law or
relation-predicate changes require rechecking their respective lower contracts.
Public UV/periodic composition remains outside this preparation proof.

[OriginalAnalyticCurvePullbackTests](../../../Tests/CADGeometryTests/OriginalAnalyticCurvePullbackTests.swift)
owns literal raw plane/cylinder/torus identities, repeated tangency, exact
containment, four torus preimages, whole-domain exclusion, nonunit original
frames, original translated parameter domains and source lifetime, unsupported
cone/source refusal and independent work/storage/cancellation boundaries. Source
preparation invokes no root cells; relation coverage reuses the existing resolver.
These bounded guarantees do not complete Cone, public angular UV or SA.

Native verification used Swift 6.4.0 release, the warm whole CADCore/CADGeometry
probe and two jobs with a 300-second process timeout. The focused new suite and
unchanged sphere suite passed together: 18 test declarations in two suites
(22 new argument cases and eight sphere cases), 0.346 seconds runtime and
56.554 seconds including compilation. This is Native source preparation and
existing relation-resolver evidence, not a portable or public UV proof.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
