# Original Source Validation

## Purpose and Scope
This child of [CADTopology](../DESIGN.md) owns caller admission for original-source validation and exact chart arithmetic. It has no children.
Geometry-store and pcurve validation forward the invocation's optional byte
callback into every original source descendant. Exact word revalidation and
period-lattice proofs convert admitted UInt32 counts to bytes before allocation;
work-only legacy calls do not certify storage coverage.

## Responsibilities and Boundaries
Topology owns incidence traversal and composing the original Geometry validation contracts. Geometry owns original curve, surface and pcurve source validity. Immutable `ValidatedBRepModel` receipts retain the validated model itself; consumers use that model as authority rather than comparing an independently supplied model without accounting.
Retained angular transports require directed original trim/correspondence
authority. An underlying intrinsic conic period cannot authorize an untrimmed
physical-radian carrier. Source-family admission and exact pole incidence remain
Geometry contracts; Topology never substitutes the underlying chart's labels.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Topology](../DESIGN.md) | parent | original topology validation | Composes original source validity | Manual and decoded models require validation |
| [Geometry](../../CADGeometry/DESIGN.md) | depends on | exact rational coefficients and source validation | Retains original source bits and descendants | Numeric gain approximations do not authorize closure |
| [Bounded Repair](../BoundedRepair/DESIGN.md) | used by | original chart span arithmetic | Classifies closed edges and validates trims | Every exact word is charged to the same caller |

## Architecture
```text
Original source -> caller admission -> exact coefficient/source traversal
    -> native span or validation receipt -> consuming query
```

## Contracts and Invariants
Selected bounded validation retains an independent algebraic ceiling in
addition to source recursion and geometric subdivision. The optional legacy
policy remains absent; a selected ceiling is forwarded unchanged into original
coefficient proofs and prepared sources. Optional byte accounting remains the
same callback throughout classification and trim/endpoint admission.

The `BRepModel` public validation conveniences and `ValidatedBRepModel`
ordinary/using conveniences explicitly select the existing local producer
algebra maximum of 32. This is a producer policy, not a requested proof depth:
actual operations remain constrained independently by the same execution's
value-depth and coefficient-depth ceilings, work, bytes and cancellation. No
ceiling is raised and neither scalar axis determines the other. Explicit
bounded overloads retain their optional argument unchanged, including `nil`;
the lower original polyline producer still refuses a genuinely unselected
algebra capability. Modeling composes these contracts as described in
[CADModeling](../../CADModeling/DESIGN.md#retained-validity-comparison-admission).
The regression owner is
[Feature validation algebra admission](../../../Tests/CADModelingTests/FeatureValidationAlgebraAdmissionTests.swift).
Binary, ratio, product and difference gains compose their exact original rational coefficients. Directed endpoint subtraction occurs before image transport; offsets cancel exactly. Absolute native span and period comparisons use exact rational differences. Exact word work and allocation are charged before the lower operation; no new private allowance is created. Legacy entry points retain cancellation checks. Bounded consumers supply their invocation callback and preserve its typed failures.

An invertible original affine operation word preserves edge closure and collapse
and leaves the original support UV unchanged. Classification descends to that
source; it never derives a replacement chart from a rounded spatial matrix.
Directed word-image pcurves require their retained exact target binding before
classification uses the original source traversal.
Untrimmed word-image lines validate endpoint membership from original closed
position and derivative bounds. Coedge correspondence derives finite candidate
native parameters from a nonzero original derivative component, then proves the
candidate positions against the actual endpoint vertices under the existing
junction law. A rounded representative line or inverse transform cannot supply
this proof; the unchanged original parameter chart is retained.
Membership also retains the whole linear-locus cross-product residual.
Periodic seam comparison composes exact linear chart endpoints through retained
word images, original parameter gain/axis images and chart-preserving offset
images. Native control laws remain separate whole-basis comparisons. No endpoint
sampling establishes equality for a nonlinear traversal.
Seam displacements stay as original rational coefficients through support
period-lattice proof. Nonrepresentable differences are never rounded to a stored
Double translation before deciding seam identity.

Periodic seam and bounded loop-unwrapping operations borrow a nonescaping work
callback for their entire synchronous invocation. Invocation-local exact proof
adapters and edge classifiers may retain that borrowed callback only inside
`withoutActuallyEscaping`; no adapter, classifier or callback is returned.
Typed callback failures propagate unchanged through validation and publication.
Regression owner: [Native dependency contracts](../../../Tests/CADTopologyTests/NativeDependencyContractTests.swift).

## Failure, Concurrency, and Constraints
Admission contains only an immutable callback and invocation-local value state. It preserves Sendable across all targets. Cancellation and caller resource failures propagate. A bounded validation receipt must cover every lower source and correspondence visit; an opaque phase debit is insufficient.

## Verification and Change Impact
Deferred behavioral verification must distinguish nonrepresentable product/difference spans, signed nested images, complete periods and one-ULP deviations. Bounded validation must reject exhausted caller work and invalid manual source while reusing the exact immutable validated source.

The immutable `OriginalBRepValidationInvocation` owns the existing topology, endpoint, correspondence, seam and area algorithms. BRepModel retains persistent source storage and delegates its established validation/volume/ordered-point entry points. The invocation borrows the model’s persistent tables through computed accessors, retains no mutable shared state, and carries one optional callback and the caller depth. Legacy composition uses the same algorithms with cancellation. Bounded composition charges before each actual visited source/incidence item and forwards this callback into Geometry; lower opaque operations remain explicitly incomplete until their admission port is connected.

Incidence admission visits explicit solid component/void references before materializing flattened shell lists. Reference coverage uses charged source-table scans and deterministic minimum offending IDs without allocating intermediate differences or sorting the full tables. The outer/void orientation law remains the existing SolidShellComponent authority.

Bounded loop UV area uses original signed-flux chart integration over the actual support, with the invocation subdivision ceiling and callback. It preserves exact endpoint gauge corrections, value-only native joins and closed Taylor bounds when supplied. Specialized legacy integration remains the legacy entry’s algorithm; its opaque allowance cannot be substituted for the bounded original chart traversal.

GeometryStore and coedge pcurve source validation forward caller source depth 16 and the original subdivision ceiling to the recursive Geometry facades. Each table/coedge visit is charged before reading the next source; legacy entry points retain their established validation algorithm. Geometry’s explicitly incomplete certified families remain lower dependencies and cannot be treated as a complete manual-source validation receipt.

Structural image recursion retains its independent existing source-depth ceiling 16. Exact chart coefficient visits report proof depth zero; a source image layer is not an adaptive subdivision cell and cannot consume the caller’s subdivision depth.

Bounded trim admission charges every retained image layer and exact span coefficient through the invocation callback, with the independent original source-depth ceiling 16. Trim endpoint incidence uses complete original closed-point position bounds and admits the full residual upper bound under the existing eight-distance junction law. Pcurve endpoint incidence uses the original SurfaceLift position law, including retained image pcurves, rather than a rounded UV round trip. Cancellation and caller KernelError codes propagate through contextual messages.

Bounded transformed-model receipts forward an explicit source recursion ceiling,
capped by the existing validation ceiling 16, separately from subdivision depth
capped by the existing correspondence ceiling 32. Work visits use the caller's
original invocation; byte admission is a distinct optional callback and never
masquerades as source depth. A successful receipt requires the same exact
endpoint, correspondence, seam and loop-area invariants as legacy validation.
Native affine images preserve original UV charts and must revalidate transformed
junction drift; an input receipt cannot certify a scaled output automatically.
Bounded correspondence forwards this invocation's work callback, independent
source/subdivision ceilings and optional byte callback into original preparation
and whole residual cells. The absent optional byte callback provides no storage
receipt. Continuous chart lift, nonlinear/critical correspondence and lower
closed-jet temporary storage remain source dependencies; outer charges do not
establish those guarantees. Legacy correspondence preserves its existing entry.

Bounded loop unwrapping retains original endpoint boxes from Geometry's continuous
chart receipt. Rounded endpoints only select candidate winding; exact original
period multiplication must authorize each stored chart translation. Whole
endpoint difference bounds authorize chart connectivity, and original surface
position bounds authorize the existing eight-distance geometric junction law.
Collapsed-boundary joins require a singleton original shared coordinate and
the original edge classifier. Geometry's original period-lattice proof transports
stored shifts through exact image gains and axis permutations before testing
the native knot/analytic period. Rounded transformed periods only propose a
winding; they cannot authorize a gauge translation. Nonrepresentable exact
shifts require a retained source carrier. All loops,
retained records and source preparation use the same caller admission.

Bounded periodic seam validation compares both original directed chart laws,
without constructing a rounded reversed/translated spline. Linear laws compare
exact original endpoint coefficients. Native rational splines compare original
normalized knot coordinates, directed controls under one constant UV shift and
a common homogeneous weight scale. The original support period-lattice proof
then authorizes that shift. Seam callers select reversal; duplicate-face callers
select the same direction through the same proof without constructing a new
spline. The default preserves reversed seam correspondence. Other chart-law families require their own complete
coincidence proof. Repeated-use discovery uses charged borrowed coedge scans
with constant auxiliary storage; exact algebra work remains on the same caller.

Edge-kind admission uses the same immutable caller visit callback for structural
source traversal, exact period subtraction, endpoint relation algebra and native
clamping/control checks. A mathematical full period is tested on the exact
original binary64 difference, without rounded subtraction or a period tolerance.
No Geometry-internal floating expansion is referenced across the module boundary.
Source recursion and subdivision remain separate limits. Original image parameter
projection and procedural endpoint laws require their lower original callbacks;
outer source validation cannot substitute for work inside those algorithms.

Normalized persistent construction charts and endpoint connectors classify
closure through original symbolic endpoint incidence. Their exact retained
root/parameter laws, not construction control endpoints or a point-distance
threshold, determine whether the edge is closed.

The bounded opposite-seam pair entry consumes the original reversed chart-law
and exact support-period receipt directly on the same caller work/byte and
independent algebra policy. Drawing suppression cannot materialize rounded
reversed/transformed pcurves or infer equality from numeric endpoint shifts.

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.

The nonthrowing diagnose error-message authority is the existing Core failure
port linked by [Topology](../DESIGN.md#m6-portable-validation-wiring). Its failure
flag and invalidInput classification remain unchanged.

### Canonical source API binding

Original incidence, periodic seam and receipt validation use the common
[execution](../../CADGeometry/OriginalQueryExecution/DESIGN.md) for actual source
preparation and every later query. The existing model and immutable policy stay
separate from execution ownership.

### Loop-area algebra capability forwarding

Bounded receipt validation forwards its selected optional algebra ceiling into
both bounded loop-unwrapping overloads. Unwrapping passes that same value to
support preparation, collapsed-connector classification and continuous chart
lift. Those operations borrow the original execution; no new allowance or
replacement source owner is created. An omitted ceiling remains `nil`, including
for unrelated callers. The existing source/subdivision ceilings, winding order,
junction predicates and missing-endpoint-box `invalidInput` failure are unchanged.
The period-lattice proof retains its existing API and the same execution.

```text
ValidatedBRepModel selected algebra ceiling
  -> OriginalBRepValidationInvocation.loopParameterAreaBounds
    -> SurfaceParameterLoopUnwrapper
      -> prepared support / connector classifier / continuous chart lift
```

The concrete regression input is the four two-point Euclidean UV polylines in
[PlanarSheetTestFixture](../../../Tests/CADKernelTests/PlanarSheetTestFixture.swift).
Sewing already selects an algebra ceiling; losing it before the chart lift makes
the original polyline law refuse bounds if validation reaches this phase.
The forwarding contract does not establish completion of sewing or offset:
their existing correspondence work ceiling and runtime limits remain independent.

| Verification owner | Invariant |
|---|---|
| [Native dependency contracts](../../../Tests/CADTopologyTests/NativeDependencyContractTests.swift) | Existing unselected-cap constant-chart closure and admission failure remain unchanged. |
| [Loop algebra admission](../../../Tests/CADTopologyTests/SurfaceParameterLoopAlgebraAdmissionTests.swift) | Selected cap reaches original polyline bounds; unselected cap, zero coefficient depth, exact N/N−1 cumulative work and cancellation retain their explicit contracts on the same execution. |
| [Offset pcurve integration](../../../Tests/CADKernelTests/OffsetSurfaceParameterCurveImageIntegrationTests.swift) | The authentic sewn planar-sheet input reaches the existing offset feature and retains its geometry/source assertions. |
