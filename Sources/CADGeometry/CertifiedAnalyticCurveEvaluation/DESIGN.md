# Certified Analytic Curve Evaluation

## Purpose and Scope

This component owns typed collection transformations used by retained certified
analytic curve equations. Its parent is [CADGeometry](../DESIGN.md); it has no
children.

## Responsibilities and Boundaries

It admits the actual result capacity before allocation and each visited element
before numerical transformation. It accepts the original exclusive execution;
it owns no budget, certificate, mutable accounting state or source authority.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | retained analytic equations | Numerical collection evaluation | Preserve equations and branch guards |
| [OriginalQueryExecution](../OriginalQueryExecution/DESIGN.md) | depends on | work and typed storage admission | Same cumulative owner | Propagate rejection; no child ledger |

## Architecture

```text
certified equation -> typed collection transform -> original execution
                    -> numerical result
```

## Contracts and Invariants

The result array has the same order and element values as the supplied numerical
transform. The transform receives the same exclusive execution. Checked payload
bytes are admitted before reserving capacity; each element visit admits work.
Admission failure propagates without creating a successful partial result.

## Failure, Concurrency, and Constraints

The component is stateless. The common budget owns synchronization identically
on Native, WASM and Embedded. Computation closures run synchronously outside its
Mutex and cannot retain the inout execution.

## Verification and Change Impact

Certified curve and parameter-curve regression tests verify equation results.
[CertifiedAnalyticCurveExecutionTests](../../../Tests/CADGeometryTests/CertifiedAnalyticCurveExecutionTests.swift) exercises real simple-root isolation, inner byte rejection and repeated cumulative charging. Root integration verifies shared cumulative
owner behavior. Changes affect analytic root traces and spatial bound arrays.

### Cylinder-cylinder and sphere-cylinder query closure

These retained families preserve their existing component classifications, full
and open branches, regularized roots, differential formulas, local refinement
limits and reconstruction guards. Their ordinary entries create one independent
execution; their direct query entries pass the caller's original execution
through source validation/configuration, point and parameter reconstruction,
third derivatives and spatial bounds. Private mathematical helpers consume that
same execution. Dynamic collections retain their concrete typed buffers before
growth, and each actual refinement/angle-normalization iteration admits work.
Fixed five-scalar Taylor operations remain pure numerical primitives and create
no admission. Numerical residual certificates retain their existing meaning and
do not become original source equality. The C math import is their only target
selection; immutable curve data and common budget isolation are identical.

`EndpointRegularizedFactorBounder` retains its original simple, one-sided,
double and mixed endpoint-root formulas as one private mathematical body per
operation. Each existing adaptive cell loop debits the same execution; the
`valueRange` producer receives that execution explicitly. Ordinary entries use
the same producer signature and root once, with no admission callback adapter.
Endpoint widths, derivative bounds, progress guards and failure conditions are
unchanged. Certified curve Codable validation consumes the installed common
decoding/encoding context, while a missing context follows the approved ordinary
codec policy; an invalid installed context fails explicitly.

Append operations receive the caller-owned logical capacity. When exhausted,
`OriginalCoefficientAllocation.reserveAppend` admits the full replacement
buffer before growth, rather than charging only the newly appended element.
Capacity metadata is local to the array owner and never constitutes a budget.

Each accepted endpoint interior partition visits geometric depth zero relative
to the caller's already installed geometric offset. These sequential partitions
have no recursive subdivision level; scalar value/coefficient depths are not
used as a surrogate. Original 4,096 partition ceilings remain binding. Arithmetic
work and proof-cell visits are separate actual admission events.

Canonical analytic recognition's retained source traversal is admitted separately
from source validation; numerical canonicalization remains the original pure
formula. The focused
[CertifiedCylinderFamilyDirectExecutionTests](../../../Tests/CADGeometryTests/CertifiedCylinderFamilyDirectExecutionTests.swift)
exercise both full signed branches, independent support equations, derivatives
and spatial bounds, UV reconstruction, repeated cumulative charging, inner
storage refusal, cancellation and the real endpoint factor range producer.
Existing cylinder/sphere spatial-bound suites retain bounded/open endpoint
variant regression ownership. These fixtures are authored, not yet run.

### Sphere-torus and torus-pair query closure

Sphere-torus, congruent torus-torus, general torus-cylinder, general torus-torus
and bounded plane-cone retain their authored support surfaces, branch domains,
root continuation, interval enclosures and residual guards. Their constructors,
validation, points, derivatives, source UV and bounds borrow the same exclusive
execution. Ordinary entry points root once and call those identical bodies.
Certification cells and continuation subdivisions retain their distinct actual
geometric depths, original local limits and explicit exhaustion failures. Pure
scalar helpers borrow generic scalar admission when they admit work or storage.
Derived immutable cache hits are readmitted for actual traversal and retained
storage; cache locks perform no numeric work or caller callback. A missing
original producer remains unsupported, including bounded plane-cone's current
plane-cone relation producer; residual agreement never supplies that authority.

The analytic B-spline builder preserves its control nets, knots, weights and
seam formulas. Direct validation and construction admit their actual collection
materialization on this same execution. These conversions provide retained
analytic representations, not new intersection or topology identity proofs.

```text
original certified family -> source validation / actual certification producer
                          -> retained curve / UV / differential enclosure
                          -> same exclusive OriginalQueryExecution
```

Focused family fixtures own equation and derivative regressions, cumulative
owner charging, storage refusal and cancellation. General torus-torus's actual
meridian certification and continuation helpers are part of this closure;
forwarding only its public dispatcher is insufficient evidence.

The typed collection operations borrow `A: ExactScalarAdmission & ~Copyable`.
Collection maps admit their known output capacity before materialization;
sequence maps, filters and compact maps retain owner-local logical capacity and
admit each full replacement before growth. Neither form captures an accounting
callback. Fixed interval products and five-coefficient sums remain scalar
primitives without temporary heap arrays.

Sphere-torus's successful validation cache and general torus-torus's configuration
cache retain the existing immutable `OriginalGeometryPreparationReceipt` issued
from actual preparation scopes. General torus-cylinder and torus-torus retain
that receipt beside their original mathematical certificate payload. Equality
and hashing consume precisely that original payload, excluding accounting
identity. Cache reuse readmits observed depth and actual retained evidence work;
it never replays historical cell visits or decomposition fees. General
torus-torus's child spatial preparation captures its complete preparation scope;
ordinary child queries retain the original budget, selected policy and
contributions, while admitted child queries borrow the caller's execution.

[CertifiedTorusFamilyDirectExecutionTests](../../../Tests/CADGeometryTests/CertifiedTorusFamilyDirectExecutionTests.swift)
owns independently reconstructed sphere/torus support equations, D1-D3 bounds,
UV reconstruction, cumulative repeated queries, the actual general torus-cylinder
cell ceiling, analytic torus control-net evaluation, inner byte rejection and
cancellation. These new fixtures are authored and await the integrated semantic
and runtime gates; parsing alone is not completion evidence.

Apex cone-torus trigonometric arithmetic admits each concrete cosine/sine and
polynomial buffer before creation, including half-angle elevation arrays and
scaled terms. Dynamic Horner evaluation, sorting comparisons and valid-interval
selection debit the original execution at each visited element. These changes
preserve coefficient order, normalization, all branches and original proof
limits; no numerical tolerance acquires source-equality authority.

Certified analytic-pair and implicit parameter-curve validation codecs borrow the
installed immutable Native context. Pair pcurve differential reconstruction
uses the same execution for its actual surface differential; source equivalence
charges retained structural traversal before equality and canonical recognition.

Third-order surface evaluation passes the actual execution through second-order
partials, analytic angular evaluation, B-spline basis rows, homogeneous control
loops and rational recurrence. Ordinary entries create one root and call these
same bodies. The two fixed order-three dictionaries reserve their ten entries
before insertion; basis and control-point loops account their actual visits.
Certified tangency reconstruction passes the same execution through its original
quadratic certificate, residual proof, deterministic analytic conversion and
pcurve correspondence validation. Original absence/unsupported/proof semantics
remain unchanged.

### Analytic-pair parameter cells

`CertifiedAnalyticPairParameterCellBounds` transports the retained original
curve differential bounds and continuous numerical chart lift into one parameter
cell. Preparation records the actual scalar/source/transport/geometric depths,
tolerance and contribution handles. A later bounds query readmits that immutable
receipt under its own execution and computes only the new cell, preserving
source roles, periodic seams and every existing singular-coordinate refusal.
Preparation is not replayed. The ordinary entry creates one execution and calls
the same direct core. All dynamic breakpoint buffers, sorting comparisons and
unique-element visits are admitted before allocation or computation. Fixed
three-coordinate seam observations and fixed derivative formulas use scalar
locals instead of temporary arrays. Numerical metric enclosures retain their
existing meaning and cannot issue source equality or new structural identity.

The nonthrowing analytic-pair `curve` property only selects an already validated
source view from fixed cone origin/axis/angle fields. It creates no admission
root and supplies no source equality or coverage authority. Query validation
uses the separately admitted equivalence body. Cone-cone differential preparation
uses the existing immutable `OriginalGeometryPreparationReceipt`; its observed
scalar/source/geometric depth is retained once and checked in each independent
query without replaying source decomposition. Same-budget consumption attaches
the issuing contribution handles.

### Cubic Surface Residual Execution

`CubicSurfaceResidualCertifier` borrows the caller's execution through original
Native surface validation, homogeneous derivative matrices, Bernstein composition,
residual comparison and subdivision. Checked output capacities are admitted before
allocation; each coefficient/row/product visit and each actual certification cell
uses that same owner. Its own residual-cell count and subdivision depth remain
independent selected algorithm ceilings. The stack grows only through admitted
capacity. Fixed scalar sums, cubic weights and interval endpoint products use
scalar locals rather than temporary arrays; arithmetic order and outward rounding
remain the same.

A successful certificate bounds the selected derived cubic residual. It does not
issue original intersection or source equality authority. A source mismatch,
exhausted work/bytes/cells/depth or cancellation remains failure. Focused tests in
[Cubic residual execution](../../../Tests/CADGeometryTests/CubicSurfaceResidualDirectExecutionTests.swift)
exercise actual polynomial composition, Native derivative preparation, cumulative
N/N−1 boundaries, rejected cell/storage admission, mismatch and cancellation.

Plane-torus validation caching retains the existing immutable preparation receipt
with actual observed scalar/source/geometric depth. Lookup admits structural
source traversal before hashing and reads the receipt outside the common Mutex.
A cached success checks the new query's retained tolerance/depth authority and
attaches issuing contribution handles only on the original budget. A success
set without this proof authority cannot authorize a later independent query.
Quadratic and quartic height certificates now pass the same execution through
exact plane charts and expansion polynomial coefficients; rejection propagates
through the optional geometric classification rather than becoming `nil`.

### Unconverted General Certified CS Publication

The general certified reduction, cone-cylinder/sphere, cone-cylinder/cone,
cone-hosted quadric, parallel-torus-pair/plane and implicit/analytic CS providers
have ordinary and direct execution entries. Ordinary entries create one independent
execution and delegate. Direct intersection entries checkpoint and report typed
`unsupportedCapability`; eligibility reports false. Their previous residual-only,
sampled coincidence and tolerance-root publication bodies are removed.

The existing source-specific `OriginalCertified*` and `OriginalImplicit*` producers
remain the authoritative implemented routes. These general providers cannot
publish success, empty absence or coincidence until complete original roots,
requested-domain exclusion and parameter correspondence are supplied by U4.
The failure contract is an incomplete family boundary, not implementation evidence
for that required family. Dependency injection constructors used only by the
removed numerical bodies are removed; repository callers use the empty initializer.

| Retained state | Native | WASM | Embedded | Lifetime |
|---|---|---|---|---|
| Plane-torus validation cache | Mutex<State> dictionary and capacity reservation | Same Mutex<State> | Same Mutex<State> | Process cache, bounded to 256 keys |
| Receipt resource authority | Original common budget + immutable handles | Same | Same | Receipt owners |
| Curve coefficients and proof partitions | Immutable source values | Same | Same | Retained curve/preparation |

The cache lock only reads or replaces immutable receipts. Source validation,
resource admission and external work run outside the lock. Cross-target runtime
verification remains owned by the coordinated integration run.

The plane-torus cache reserves its existing 256-entry bound once. The common
Mutex owns the reservation flag and dictionary; payload admission runs outside
the lock before the actual reserve. A concurrent successfully validated query
can skip optional insertion while a reservation is pending. Rejection clears the
reservation without publishing a cached success. Later insertion reuses retained
capacity; clearing at 256 entries keeps that capacity.

### Numerical Helper Semantic Closure

General cone/cone, cone/cylinder and sphere/torus retain only their ordinary and
direct explicit-refusal entries. Obsolete private numerical helper banks have no
caller from those entries and are removed. Ordinary conveniences create one
execution and invoke the same direct refusal contract. This removal does not
convert incomplete original source/UV coverage families or replace them with
numerical success. The test-only height-quadratic candidate solver and its unused
protocol are also removed; the resultant polynomial builder and independent
formula oracle remain. The obsolete solver's sole degenerate-candidate assertion
is removed without changing the retained polynomial comparisons.
The torus/torus Newton representative polisher borrows the caller admission for
its unchanged 24-iteration cap and every alternate traced branch reference;
admission/cancellation throws instead of being treated as numerical nonconvergence.
Analytic candidate conversion maps a parameter-image interval using that same
execution before invoking the original source conversion.
