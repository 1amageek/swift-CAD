# Original Analytic Intersection Sources

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns the exact implicit
pullback of a direct authored analytic sphere to one retained original rational
curve span. This is source preparation for CS composition; it does not publish
surface UV fibers, angular-domain coverage or a public curve-surface result.

## Responsibilities and Boundaries

`OriginalSphereCurvePullback` retains the direct sphere source, the original
homogeneous curve issuer, its span/translation and exact closed parameter domain.
It issues the raw equation and unchanged denominator, preserving multiplicity.
The existing relation resolver owns root isolation, whole-domain exclusion,
incidence and component identity. Public CS consumers own sphere UV correspondence.

Only direct `AnalyticSurface3D.sphere` is admitted. A canonical surface reconstructed
from an offset, image or rounded rational conversion is not original authority.
The curve law is supplied by its existing validated native/source-image issuer;
this component neither reconstructs that law nor changes its parameterization.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md#canonical-ideal-angular-primitive-authority) | parent | Direct ideal sphere center/radius | Supplies source meaning | Preparation is not complete public CS |
| [Canonical Sphere Chart](../CanonicalSphereChart/DESIGN.md) | depends on | Ideal closed sphere and intrinsic phase | Establishes the original primitive image | No candidate angle enters coefficients |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | Retained original homogeneous curve and exact rational arithmetic | Supplies original span law and same-ledger arithmetic | Preserve W, span, translation and original parameter bounds |
| [Intersection Algebra](../IntersectionAlgebra/DESIGN.md#public-original-rational-relation-selection) | used by | Original rational laws, predicates and closed domains | Consumes F=0 and W!=0 | Its resolver, not this issuer, owns real coverage |

## Architecture

```text
direct sphere center/radius + retained original curve (Hx,Hy,Hz,W)
    -> exact dyadic source coefficients
    -> F = sum((Hi-ci*W)^2) - r^2*W^2, unchanged W
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

## State, Ownership, and Lifecycle

All production state is immutable and Sendable without target-specific branches.
The receipt owns its source-law values and their immutable backing storage after
the caller releases its input variables. No cache or independent allowance exists.

## Failure, Concurrency, and Constraints

The composing `RationalAlgebraAdmitting` pays every traversal, polynomial operation,
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
