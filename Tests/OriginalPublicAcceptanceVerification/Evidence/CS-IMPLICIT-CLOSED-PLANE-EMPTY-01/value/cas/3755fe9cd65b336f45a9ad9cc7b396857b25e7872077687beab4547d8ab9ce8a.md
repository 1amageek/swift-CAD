# Original Higher Curve Jets

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns requested-order
whole-interval original curve derivatives, including retained implicit root
charts and surface lifts. The preparation lifetime belongs to one caller operation.

## Responsibilities and Boundaries

Source geometry and original chart coefficients supply derivative authority.
Converted controls, sampled stations and a numerical root midpoint do not.
Surface higher coefficients remain owned by [Surface Silhouette](../SurfaceSilhouette/DESIGN.md).
The caller supplies span, subdivision, source-depth and cumulative work admission.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | native and implicit source charts | Composes original derivatives. | One-sided joins require original continuity. |
| [Surface Silhouette](../SurfaceSilhouette/DESIGN.md) | depends on | requested-order original surface Taylor coefficients | Supplies exact derivative order for implicit composition. | Pass the same caller admission and callback. |
| [Surface Area Integration](../SurfaceAreaIntegration/DESIGN.md) | depends on | interval Taylor algebra | Factorial-scaled composition and reciprocal arithmetic. | No independent proof allowance. |

## Architecture

```text
original native coefficients / retained intersection cells / source lift
    -> caller-owned immutable preparation
    -> closed original parameter cover
    -> requested Taylor order and implicit Jacobian recurrence
    -> complete interval derivative fields
```

## Contracts and Invariants

Native rational derivatives use the original homogeneous Bernstein coefficient
receipt and positive original denominator. Implicit parameter coefficients retain
the original root cover and signed free-coordinate law. At each order the known
Taylor residual is composed from the genuine original surface coefficients, and
the three dependent unknown coefficients are solved by the same original source
Jacobian. The free coordinate has no derivatives above order one. Surface-lift
coefficients compose the original UV law with original surface coefficients.
A coefficient of order k equals derivative/k!, with exact integer scaling.

Parameter reparametrization preserves the original zeroth coefficient by direct
copy for every gain: exponent zero is exactly the identity. Only derivative
coefficients carry gain powers. Multiplying the value interval by an outward
representation of one must not extend a certified original parameter range
beyond its retained support. This rule preserves existing coefficient-loop work,
storage and cancellation admission; the receiving surface's strict closed-domain
validator remains unchanged. Verification checks exact zero and upper support
boundaries under positive, negative and zero gains, derivative gain powers, and
continued rejection of an actually out-of-support caller box.

Lift composition passes the requested order unchanged into the shared surface
Taylor provider, including zero through three. The surface owner supplies those
actual original coefficients; requesting a value does not impose C4 continuity.
Retained root/construction traversal and rolling-ball point callers inherit this
contract through the same existing call path. The low-order source/caller regression
is owned by `Tests/OriginalRequestedOrderLiftVerification`; whole-family source,
domain and identity completion remain independent.

For a validated positive-weight Native pcurve on its native support, the original
Cartesian control hull independently encloses its value. The requested-order
pcurve owner intersects only the zeroth coefficient with that hull after parameter
scaling. This preserves exact boundary coordinates such as constant zero without
clipping to a receiving surface or changing derivative coefficients. Every control
visit and final intersection uses the same caller work/cancellation admission;
the already-owned scaled tables are updated without another coefficient copy.
Direct constant-U/V charts likewise retain their authored constant coordinate
and varying-coordinate endpoint hull. An affine chart with an exactly zero
coordinate direction retains that original constant; general affine and harmonic
bounds keep their original outward expression. Continuation queries retain their
separate extrapolation contract and do not use the native-support hull.
Verification includes weighted/nonclamped sources,
exact zero/one boundaries, tiny nonzero and out-of-surface coordinates, and actual
nested lifted-traversal callers.

## State, Ownership, and Lifecycle

Prepared native spans retain immutable original coefficient authority. The source
value and exact tolerance remain bound to the preparation. No mutable state or
platform-dependent synchronization is added.

## Failure, Concurrency, and Constraints

All loops check cancellation and debit the caller work callback. The caller owns
maximum native spans, subdivision depth and source recursion depth; lower work
never increases them. Unproved smooth joins, singular Jacobians, nonpositive
rational denominators and unsupported original chart laws fail explicitly.

## Verification and Change Impact

After all source implementation, verify original rational fourth derivatives,
implicit fourth and higher derivatives against independent exact source laws,
closed endpoints, reversed graph cells, source lifts, transformed images and
same-budget exhaustion. Recheck silhouette and offset composition consumers.

### Original Image Chart Recursion

Requested-order image UV coefficients recurse into the retained source pcurve.
Directed traversal scales derivative order k by its original fraction difference
to power k; signed original ratio inverse and axis permutation transport every
coefficient. Original rigid images use their exact affine UV chart transform
when that transform exists. Nonlinear spherical inverses keep their own source
branch authority requirement. No numerical UV candidate supplies derivatives.

### Exact Original Join Equality

Knot multiplicity grants the structural smoothness order. For higher requested
orders, exact original homogeneous quotient derivatives on the left and right
are evaluated at the shared original station. Every XYZ difference crossproduct
must be exactly zero. Periodic seams compare both actual original end stations
and require exact stored translated-knot equality separately. Exact preparation,
scalar operations and retained slots debit the same caller work callback; no
independent exact-algebra allowance is introduced.

Implicit closed value and one-sided derivative queries may select an original
retained owning cell index. That selection validates the original cell identity
and preserves the full source graph and global normalized derivative scale.
Adjacent cell endpoint receipts remain separate; their value hull does not
authorize a smooth derivative through a chart join.

The owning homogeneous Taylor evaluator accepts a retained normalized interval
and can differentiate with respect to that local coordinate. Its owner must prove
that chart from original rational knots before outward conversion. This route
avoids amplifying native station rounding in arbitrarily narrow admitted spans.

Bounded implicit preparation retains caller span, subdivision and source-depth
capabilities and forwards optional retained-byte admission into both prepared
source surfaces. Every state preparation, restriction and advance accepts the
same work callback, including source-binding comparisons and matrix rows.
Original closed center-position bounds supply the Krawczyk residual; numerical
centers choose only finite representatives. A subdivided higher-jet query passes
its remaining depth to each nested surface operation. Query-temporary allocation
and general cross-cell continuity remain separate incomplete requirements.

Original native curve higher Taylor evaluation accepts optional byte admission
for its scalar coefficient tables, de Casteljau COW scratch, derivative arrays
and rational scalar operations. Each concrete allocation reserves checked
count times stride immediately before materialization. Source-degree and query
order are unchanged; this port does not account unrelated implicit or conic
station atlas allocations.


### Caller-Paid Ideal Conic Taylor Storage

Requested-order ideal line, circle, circular arc and ellipse queries admit the
original source through bounded validation and use the shared continuous
canonical angular harmonic. The byte callback reserves each coefficient table
and original derivative recurrence buffer before allocation. Parameter and
spatial images forward the same callback into the source and every result table;
word action uses exact final field extrema. Native nonperiodic queries forward
bytes through the original owning cover, exact join law and Taylor scratch.
Periodic native and implicit/lift byte paths retain explicit incomplete failure
until their remaining allocations carry the same callback. No chart parameter
map or join continuity is inferred from these derivative coefficients.

Requested-order original native and explicit analytic queries admit order zero and above. A value-only or first-order request does not demand C4 merely to satisfy an implementation entry point. Native joins prove only the requested order; higher implicit/lift composition keeps its actual lower order constraints and explicit failures.

Original normalized pcurve value bounds expose an order-zero package facade using the same bounded source admission. Native rational pcurves reserve converted original Point3D payloads and forward source coefficient/Taylor bytes; direct affine charts reserve their scalar tables. Aggregate native value hulls require only the requested C0 law. Implicit, nonlinear chart and shared harmonic scratch producers without complete byte forwarding reject explicit storage queries. The value facade does not fabricate higher continuity or change the pcurve family.

Polyline UV fraction authority is the original Euclidean length expression for each segment and its exact total. Numerical binary prefix accumulation does not authorize a source join station or exact chart substitution. The value/derivative producer must retain ordered square-root station expressions; unsupported exact extraction remains explicit until this source producer is connected.

Bounded surface-lift Taylor composition forwards optional byte admission through original UV coefficients, source-surface coefficients, exact word transport and every Bell-composition buffer. Removing constant terms reserves the actual COW coefficient payload before mutation. Original harmonic UV charts use paid scalar trigonometric ranges; implicit higher recurrences retain explicit byte refusal until their own scratch buffers are connected.

Exact Euclidean polyline bounds consume the shared retained square-root/prefix law under an explicit optional algebra cap, independent of source and subdivision depth. Value-only queries union every original intersecting segment endpoint; derivative queries require exact equality of adjacent directed first derivatives before publishing a common higher law. A missing bounded algebra capability refuses this exact producer; legacy numerical point representatives remain candidates until their uncapped outward-length evaluator is connected.

Implicit requested-order zero through three consumes the localized original coordinate jet directly; it does not allocate an unnecessary fourth-order solve. Bounded localization reserves each actual parameter/Jacobian/preconditioner/derivative buffer before allocation or COW mutation and forwards byte admission into both retained support queries. Higher orders preserve the original Jacobian recurrence and requested continuity; separate owning cells remain separate source laws.

### Plane-Constrained Generated Sources

The [original plane derivative source](../OriginalCoons/PlaneDerivatives/DESIGN.md) supplies requested-order correction coefficients and preserves the native owning partition. Shared prepared position queries use its order-zero law; they do not require higher continuity merely to enclose positions. Its endpoint expressions remain those of the retained source traversal. Higher curve and surface queries delegate the full corrected law with unchanged caller work, optional byte storage and independent source/subdivision capabilities.

The original drafted curve delegates requested-order closed coefficients to the
[original draft owner](../OriginalDraftedSection/DESIGN.md). Its tangent-dependent
quadratic ruling retains the raw generator traversal and branch law. A returned
whole jet is not a native owner, a continuity theorem, or a generator polynomial.
Value-only queries request only the source derivatives needed by that ruling.

Original guide chains consume the retained guide producer for requested D0-D3
only, with exact declared stations and separate per-traversal owning covers.
Orders above three require an additional original derivative producer; the
shared higher interface fails explicitly until that authority exists.

Requested-order curve queries accept an optional independent algebra cap. It
flows unchanged through source validation, parameter/spatial recursion, exact
UV coefficient selection and implicit support preparation. Legacy nil retains
existing intrinsic lower policies; explicit selection does not derive an algebra
cap from geometric subdivision or source nesting. Corrected guide queries
forward the selected cap into retained endpoint capability rebinding.


### Original UV Value Hosting

The order-zero `originalParameterBounds(on:over:)` facade accepts the actual
retained hosting surface when one is known. Its bounded relation validation
uses that exact source value and the unchanged caller work, byte, source,
subdivision and algebra admission. Standalone numeric 2D laws retain their
independent original value contract without claiming surface containment.
Native splines and continuations validate original controls/weights/knots under
the same callback; polyline and finite scalar laws use their original bounded
value producers. A hosting-dependent chart queried without a host fails with
explicit unsupported capability. No invented plane or replacement support
can authorize a source relation.
