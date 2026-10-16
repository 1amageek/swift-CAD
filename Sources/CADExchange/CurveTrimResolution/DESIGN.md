# CurveTrimResolution

## Purpose and Scope
Owns the parameter correspondence of independent Cartesian STEP trims. Parent: [CADExchange](../DESIGN.md). No children.

## Responsibilities and Boundaries
The actual stored Curve3D law is the sole parameter authority. Geometry owns analytic and certified B-spline inverse projection. This adapter resolves an affine line in its actual world direction even when the ambient matrix is singular, and inverses original nonsingular affine and rigid coordinate images without changing their parameters, and checks the result against the original world curve. STEP selector parsing remains in ExactSTEPReader.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [IndependentShapeExchange](../IndependentShapeExchange/DESIGN.md) | used by | caller cumulative ledger | trim ingress | No new allowance is created |
| [Geometry](../../CADGeometry/DESIGN.md) | depends on | parameterProjection and native images | inverse law | Ambiguity and residual failures propagate |

## Architecture
```text
Cartesian selector -> original image inverse -> original lower parameter projection -> original world residual -> directed trim
```

## Contracts and Invariants
Parameter and Cartesian selectors must identify the same world point within the existing modeling tolerance. Mixed selectors retain the preferred native numerical representative. Nonperiodic endpoint order agrees with sense. Closed curves choose the consistent cyclic representative without exchanging endpoints. B-spline inverse work is admitted from the caller's remaining allowance before lower projection, including coefficient and subdivision/refinement upper bounds. Unproved inverse or multiple inverse candidates fail explicitly.

## Failure, Concurrency, and Constraints
Values and invocation accounting are local. No shared mutable state. Original caller cancellation, deadline and nesting are checked before and after lower calls; bounded lower subdivision/refinement work cannot create an unbounded search. Numeric overflow is a typed source failure.

## Verification and Change Impact
Public independently authored Cartesian, mixed, periodic crossing and reversed parameter trims must retain their directed original interval through Native and two STEP generations. Off-curve, contradictory selectors, ambiguous spline inverses and cumulative resource exhaustion must fail before publication. Source edits are not verification evidence.

### Original periodic endpoint admission
Numeric ParameterDomain.periodic values are candidates for a foreign chart. IndependentCurvePeriodicTrimResolver derives its exact original period through retained parameter-image gains and immutable spatial wrappers under the same caller rational ledger. A shifted binary64 endpoint is admitted only when its exact original difference equals an integer number of original periods and it is the nearest representative with the requested directed sense. A nonrepresentable shifted endpoint remains an explicit persistent directed-chart producer gap; it never succeeds from rounded period addition.

Affine Cartesian inversion computes the determinant and Cramer numerators from the original stored binary64 columns, selector coordinates and translation as exact rational values under the same caller ledger. Exact zero alone identifies singularity. Finite outward materialization supplies a lower projection candidate, not an exact parameter witness; the existing original world-curve residual remains the final admission condition. Cancellation, word storage and all rational work are charged by the existing invocation.

### Original cyclic selection chart
The periodic resolver derives the original deepest native period and complete signed parameter gain from the retained curve graph, proves the minimal directed turn count using exact rational arithmetic, and retains an OriginalParameterPeriodicTranslation when the endpoint is not binary64. The shared basis is unchanged; the item owns a normalized directed chart with original selector provenance. Actual readers use that chart and [0,1] selection, while STEP egress emits the original basis and original selectors. No estimated foreign period becomes source authority. The same caller work/storage/depth ledger owns the factory and all exact arithmetic.

ExchangeResourceLimits.maximumCurveSubdivisionDepth forwards the existing operation's separate supported 0...32 algorithm ceiling, default32. maximumNesting continues to bound retained source graph recursion only. Cartesian inverse and exact cyclic factory use the caller subdivision value; remaining exchange phases retain it unchanged.


## Canonical Trim Admission Binding

Periodic selection, retained gain/turn arithmetic, original affine inversion and lower parameter projection borrow the same `OriginalQueryExecution` as exact ingress. The independent exchange owner retains format limits/deadline; it does not implement the removed rational admission protocol. Existing source recursion bounds, integer turn search, directed chart construction and residual validation are preserved. Canonical source-cell and scalar admission replace only the old usage calls.
