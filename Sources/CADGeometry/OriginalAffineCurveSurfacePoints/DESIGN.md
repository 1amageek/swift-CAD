# Original Affine Curve-Surface Points

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), with no children. Owns the bounded public CS
isolated-point and complete-empty producer for one aperiodic positive-weight
Native curve span against a retained rational original affine word over one
aperiodic Native surface span. This checkpoint does not complete procedural CS
or all seven analytic families.

## Responsibilities and Boundaries
The component prepares original source-bound affine equations, intersects native
and requested domains exactly, verifies the entire selected relation is 0D,
and retains every original tuple and coverage owner. Existing original algebra
owns root search and incidence. The existing Native publisher owns numerical
representative refinement and contact-kind classification from supplied original
homogeneous and normal laws. Root owns result fields and all rich/discrete public
dispatch ports. Failure after recognizing the source shape cannot enter legacy
fallback. Existing ruled receipt types remain unchanged.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | rich/discrete CS composition | Carries the dedicated receipt | Public integration is root-owned |
| [Affine issuer](../OriginalAffineIntersectionSources/DESIGN.md) | depends on | original source, prepared word, homogeneous law and raw guarded equations | Retains exact authored coefficients and Native UV | No replacement surface or normalized-field rounding |
| [Native points](../CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | depends on | Native allowance and raw-law point publisher | Preserves caller admission and representative algorithm | Intrinsic source normal cannot replace transformed normal |
| [Polynomial points](../OriginalPolynomialCurveSurfacePoints/DESIGN.md) | depends on | OriginalPolynomialCurveSurfaceNormal.prepare | Differentiates supplied original rational H/W | Reuse the helper, not the ruled receipt |
| [Intersection algebra](../IntersectionAlgebra/DESIGN.md) | depends on | original cells, incidence, components and scalar isolations | Complete exact equality/exclusion and tuple identity | Same ledger and inherited algebra depth |

## Architecture
```text
Native curve + original affine image + requested domains + caller allowance
  -> source validation and one Native span per axis
  -> existing exact affine issuer / retained original word and H/W
  -> existing raw CS equations and W guards / exact native-requested intersection
  -> existing complete partition / all selected cells must be 0D
  -> derivative normal of transformed original H/W / shared point publisher
  -> immutable original affine receipt and every exact tuple
  -> root-owned rich/discrete public result
```

## Contracts and Invariants
Coordinate order is original curve T and unchanged Native surface U,V. Default
ranges are the full finite closed Native ranges; explicit ranges intersect them
exactly, including singleton endpoints. Exact disjoint-domain arithmetic is
retained as exclusion evidence even when no partition is needed. Otherwise the
receipt retains the original equations, both nonzero W guards and complete
partition/incidence, including complete-empty partitions.

Every selected cell is checked before publication. Any positive-dimensional
selected cell, including a mixed relation, fails atomically with
nonDiscreteIntersection. Every 0D tuple remains separate in exact T/U/V order;
multiple UV preimages and coincident numerical images are not merged. Candidate
count bounds tuples. Numerical tolerance controls representatives and contact
kind only, never original equality, multiplicity or exclusion.

The normal is derived from the transformed original homogeneous law: each
rational tangent numerator is Hi,a W - Hi Wa, and their ordered U cross V
product supplies the normal numerator. This preserves reflection orientation
and shear/inverse action without a numeric transform getter or intrinsic-normal
substitution. Degree checks cover both original inputs; affine action does not
increase their polynomial degree.

## Runtime Flows
One Native allowance flows through source visits, prepared Native span bytes,
original affine word/source issuance, raw equations, domain arithmetic, complete
cells, incidence, normal preparation, localization, representatives, receipt and
result storage. One source product consumes depth-zero caller subdivision
admission; the affine descendant consumes one remaining source level. Final
result storage admission is followed by explicit cancellation checking before
any result escapes. Recognized unsupported sources or any lower failure throw.

## State, Ownership, and Lifecycle
Receipt, point view and published sources are immutable Sendable. The receipt
strongly retains the original curve, affine image and word, Native span/source
issuer, raw equations, partition, incidence and isolation/localization owners.
Point views retain their receipt and ordinal; foreign-owner queries fail.
Exact coordinates retain original field owners and admission depths after caller
inputs are released or changed. No shared mutable cache or callback storage is
introduced. Test counters use Mutex with cancellation outside the critical section.

## Failure, Concurrency, and Constraints
Non-Native descendants, periodic sources, multi-span sources and normalized
algebraic words retain typed unsupported failures and incomplete markers pending
their genuine source/domain issuers. Work, checked UInt32 words/bytes, source
levels, algebra/cell depth, candidate count, polynomial degree and refinement
iteration ceilings preserve their existing caller/options authority. Invalid
source/span/domain and cancellation propagate without partial success. Heap
receipt metadata and every new temporary/output capacity are admitted before
allocation. No retry or alternate solver is introduced.

## Verification and Change Impact
[OriginalAffineCurveSurfacePointTests](../../../Tests/CADGeometryTests/OriginalAffineCurveSurfacePointTests.swift)
checks actual ordinary/admitted rich/discrete routes for forward/inverse shear
and reflection, weighted nonunit domains, multiple UV, tangent, closed endpoint,
complete-empty partition/domain exclusion, positive/mixed atomic failures,
original derivative orientation, retained lifetime/foreign-owner queries,
independent caller/options ceilings and final callback cancellation. Root reviews
one stable source batch and its shared-port patch; P alone verifies complete
Core/Geometry compilation, linking and focused runtime on its fixed warm path.
Issuer, algebra or shared publisher changes require corresponding assumption
rechecks; whole SC/seven acceptance and parent indexing remain root-owned.

### Direct Source Descent Ceiling

The existing procedural point issuer admits one surface-to-direct-native boundary
or descendant step. Its local source ceiling remains one and is intersected with
the caller execution ceiling; direct migration does not expand admitted source
families. Successful construction records that actual one-step descent on the
same execution. A caller ceiling of zero fails before source construction.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
