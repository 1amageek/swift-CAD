# Original Native Plane Contacts

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), without children. Owns complete original
base-native B-spline contacts with an authored-U original plane.

## Responsibilities and Boundaries
The producer returns retained isolated native roots and positive owning intervals
of plane incidence. Geometry's public dispatcher owns numerical representatives,
final residual certification and surface-domain publication. Original periodic
translations and other source families require their respective source carriers.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | original contact publication | Composes the source events | Midpoints are candidates |
| [Rational Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | original homogeneous polynomial and complete Sturm isolation | Counts all repeated/endpoint roots | Preserve native owner |
| [Original Root Span](../OriginalRootSpan/DESIGN.md) | depends on | retained algebraic root boundary | Publishes source endpoint authority | Never merge discontinuous native owners by station alone |
| [Curve Surface Admission](../CurveSurfaceQueryAdmission/DESIGN.md) | depends on | same caller work/bytes/source/spatial/algebra limits | No private allowance | Algebra depth is independent of geometric subdivision |

## Architecture
```text
original native spans + raw U, N -> V = exact N cross U
 -> chart normal = exact U cross V -> homogeneous incidence numerator
 -> complete Sturm roots / identically-zero owning intervals
 -> original root + rational plane UV law -> dispatcher publication
```

## Contracts and Invariants
Positive original weights retain denominator authority. The actual plane normal
is the exact authored chart cross product, including U with a nonzero raw normal
component. A tolerance-orthogonality check does not replace that source equation.
Every isolated source root is retained, including multiple roots and closed
endpoints. Its derivative numerator decides transverse versus tangent incidence.
Native knot owners remain distinct at discontinuities. Isolated finite plane-box
membership uses exact algebraic signs of UV quotient boundary numerators.
Positive intervals retain source identity and owning native span. Finite-box
clipping forms the product of the selected original UV quotient-boundary
polynomials, isolates its complete unique cut set and selects event-free open
sectors by exact rational sign witnesses. Those witnesses are between certified
source events, never samples used to claim absence. Retained cut roots supply
isolated corner/tangent contact when no positive sector survives. A numerical
endpoint approximation cannot authorize clipping. The existing point-array
public API may explicitly reject a proved positive contact; it cannot reject an
absent overlap merely because the original curve lies in the unbounded plane.
Each contact retains the already admitted owning homogeneous curve polynomial.
Root-boundary construction borrows that immutable expression instead of
re-expanding the same native control/knot law for every incidence or clipping cut.
Position and UV bounds divide exact rational Bernstein ranges before the final
outward binary conversion; overflowing numerator/denominator candidates cannot
replace a finite exact quotient or fabricate a nonpositive weight.
Positive sectors retain exact authored/algebraic start and end authorities and
the original owning polynomial. Public continuous publication prepares one
normalized original traversal per sector under the same invocation. Its
correspondence maps the requested normalized interval through exact endpoint
isolations and bounds the original position and plane UV rational laws before
outward conversion. A caller-selected localization width controls derived
precision; it never changes incidence, membership or any source endpoint.
One immutable invocation-local native source owner binds every emitted contact
after complete original validation. Adjacent sectors share an exact cut-event
ordinal within a native span, or prove both endpoints equal the original common
knot between positive native spans. The admitted interior multiplicity contract
establishes C0 at that common knot. This identity replaces neither one-sided
derivative classification nor source admission in a different invocation.
Joined correspondence keeps each original homogeneous owning-span expression
and unions their exact restricted position/UV ranges; no averaged source or
fitted join replaces them.
The invocation-local owner also retains one bounded prepared native curve. Root
traversals borrow this preparation after endpoint/source binding is established;
each component must not rebuild the complete native span atlas. Preparation
retains the same source, spatial, algebra and optional byte admission.

## Failure, Concurrency, and Constraints
All coefficient/source operations borrow the same caller admission. Source,
spatial and algebraic ceilings remain independent. Optional byte admission is
absent when unselected. The producer retains immutable receipts only.

## Verification and Change Impact
After all source implementation, exercise repeated/tangent roots, both closed
endpoints, adjacent/discontinuous owners, nonorthogonal authored U, complete
positive intervals, reversed trim consumption, exhausted work/bytes and separate
zero source/spatial/algebra policies through the actual public dispatcher.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
