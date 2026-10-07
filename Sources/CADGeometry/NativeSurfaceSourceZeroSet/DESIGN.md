# Native Surface Source Zero Set

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), with no children. Issue a limited immutable
real-zero equivalence proof from an original finite nonperiodic Native chart pair.
One original world coordinate is constant on one source; the other source's exact
homogeneous coordinate difference has a verified square identity or a verified
bilinear corner zero set on its full closed native rectangle.
No roots, approximate fits or generic sum-of-squares algorithm are introduced.

## Responsibilities and Boundaries
Geometry owns the issued Native charts and original homogeneous coordinate meaning.
This issuer checks source coefficient identities and supplies necessary factor laws.
Common SSI composition retains and consumes them with the original equations,
denominator guards and raw Jacobian. Existing algebra owns ideal reduction, cell
lifting, real roots, closure and incidence. The publisher consumes that coverage.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original Native source meanings | Geometry owns source interpretation | Parent indexes this child |
| [Rational algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | exact coefficient arithmetic | Checks complete polynomial identities | Same original caller ledger |
| [Intersection algebra](../IntersectionAlgebra/DESIGN.md) | depends on | original polynomial arithmetic and ideals | Factors are laws, not computed roots | Raw Jacobian remains original |
| [SSI relations](../NativeSurfaceSurfaceRelations/DESIGN.md) | used by | common original source bindings | Retains necessary-law authority | No independent pair solve or proximity identity |

## Architecture
```text
issued original chart + constant coordinate counterpart + original H/W
 -> exact constant-coordinate identity
 -> full square identity or closed tensor-corner identity
 -> original SSI equation identity and native domain authority
 -> retained necessary factor laws
 -> common necessary ideal or bounded chart zero conjunction
 -> exact sign compiler + complete original four-UV coverage
```

## Contracts and Invariants
The constant coordinate c is recovered from original homogeneous coefficients and
verified by the complete identity H=cW. The other original numerator N=H-cW is
oriented by its nonzero quartic leading coefficient. Candidate monic factors
F=s^2+a*s+b and G=t+d are recovered from the original quartic/cubic/quadratic and
other-axis quadratic/linear coefficients, with independent source parameters s,t.
Both coefficients L,D are strictly positive after orientation. Every original
coefficient must satisfy the complete identity oriented(N)=L*F^2+D*G^2.
No original Native degree or numerical root is assumed from the fixture.

Thus N=0 if and only if F=0 and G=0 over the real source chart. The raw four-UV
SSI equation is independently checked as the correctly signed product of N and
the constant counterpart's original W. Original strictly positive source weights,
validated Native closed support and original Cox-de Boor partition of unity prove
both W nonzero over the full closed native domains. The original chart, all H/W,
guards, coefficient identities, factors, coefficients, orientation and world
coordinate role remain strongly retained. Binding checks reject source, owner,
domain or raw equation changes. Square factors augment necessary constraints;
they never replace the original equation, guard or raw Jacobian authority.

### Closed bilinear corner evidence
The separate corner issuer recovers the four exact values of N on the original
native rectangle and proposes its tensor degree-one Bernstein reconstruction.
The complete coefficient identity must hold. Exactly one corner value is zero;
the other three have one strict sign. Orientation makes these three values positive.
With positive native side lengths, the four normalized tensor basis polynomials
are nonnegative on the full closed rectangle and sum to one. Their positive terms
can simultaneously vanish only at the unique zero corner. Thus, on this retained
closed chart, N=0 is equivalent to the two original coordinate-minus-corner laws
being zero. A higher-degree remainder, another zero corner or opposite signs declines.

This is a domain-bound zero equivalence, not an assertion about N's sign outside
the chart. Its original raw equation, coefficient values, tensor basis, full identity,
native bounds, constant counterpart, guards and source owners remain retained.
Composition emits the two zero atoms only inside the corresponding original chart
bounds and requested selection. The factors may strengthen that chart's rank ideal,
but are never added to the global necessary ideal. Every consumer must preserve
that branch's native bounds: common selection, owner equation checks, common graph
clauses and ordered station fibers. The raw three equation/guard ordinals stay intact.

## Runtime Flows
Try original world-coordinate counterparts and both source roles before selection.
A failed coefficient identity is a scope decline. Both successful and normal nil
returns check cancellation. All exact arithmetic, comparisons, visits, array buffers
and owner/header storage are charged before use to the same caller admission.
Errors after admission propagate without retry, reset or alternate solving.

## State, Ownership, and Lifecycle
The proof is immutable Sendable. It retains the original source-issued chart pair
and all identity evidence through the common coverage receipt and its fibers.
There is no shared mutable state or target-specific synchronization contract.

## Failure, Concurrency, and Constraints
Unsupported source representation returns nil. Foreign binding, exhausted work,
storage, depth and cancellation throw atomically. All original public caps and
requested domains remain unchanged; no partial component success is published.

## Verification and Change Impact
[NativeSurfaceSourceZeroSetTests](../../../Tests/CADGeometryTests/NativeSurfaceSourceZeroSetTests.swift)
checks positive/negative orientation, nonzero constant counterparts, whole coefficient
identity refusal, foreign source/domain binding, independent work/storage and final
normal-decline cancellation. Existing Native multi-chart SSI tests retain the actual
mixed and irrational inputs, all UV/component identities, public source lifetime,
resource/final-cancel behavior and genuine irrational depth/refinement failures.
The common coverage compiler, chart rank reduction and graph predicate adapter must
be verified together when this necessary-law contract changes.
[NativeSurfaceSourceCornerZeroSetTests](../../../Tests/CADGeometryTests/NativeSurfaceSourceCornerZeroSetTests.swift)
owns corner identity, negative orientation, full identity refusal, extra zero corner,
opposite sign, foreign source/domain/owner and final-decline cancellation. The original
mixed public fixture is the performance evidence; its region, curve and isolated
point, original UV identities, closed joins and component ceiling remain required.
