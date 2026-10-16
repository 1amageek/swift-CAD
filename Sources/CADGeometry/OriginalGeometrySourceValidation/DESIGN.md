# Original Geometry Source Validation

## Exact quadratic pcurve image admission

`OriginalQuadraticPcurveContainment` owns whole-image containment for a validated,
single clamped quadratic Bezier with equal positive original weights. It uses
the original binary64 coefficients as exact rationals: each coordinate's extrema
on normalized traversal [0,1] are the two endpoints and its stationary point,
when that point belongs to [0,1]. No control polygon, numerical sample, tolerance,
or inverse parameterization substitutes for the curve image. Constant and linear
coordinates retain their original traversal. Periodic/unbounded axes impose no
finite image bound. Unsupported representations return no theorem; arithmetic,
resource and cancellation failures propagate instead of becoming exclusion.

Legacy and bounded pcurve validators consume this same proof before retaining
their existing conservative hull fallback. Bounded validation forwards the caller
work/storage/algebra admission; legacy validation adds no private query budget.
The Native lift snapshot owner also consumes this proof against exact knot
support, preventing a tolerance-based clamp from becoming source equality.
The source/DI path retains the original nonlinear pcurve and all graph guards;
this admission theorem neither constructs an XYZ approximation nor issues a
structural identity. S-NONLINEAR-COLLAPSE-01 owns the actual outlying-control
success, genuine interior extremum escape, unequal weights, cancellation and
resource boundary behavior; the red snapshot is retained in its evidence.

Original native 2D continuation admission validates the raw spline on the caller
work ledger, then obtains its complete D0 UV cover through the caller-admitted
original continuation producer. Closed support containment uses this cover;
legacy third-order interval preparation is not a substitute for value admission.
Remaining source depth, spatial subdivision, selected algebra depth and optional
storage policy are forwarded unchanged, with no fabricated storage callback.

Original Euclidean polylines retain their complete raw point sequence and
authored closure flag. Bounded admission visits every original finite point;
when the caller lowers the retained algebra capability it re-admits the exact
3D Euclidean clock under the same caller work and optional storage ledger.
Existing cache policy is never promoted to a stronger selected capability.

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md). Composes actual original native B-spline
structural validation under a caller direct execution; no children.

## Responsibilities and Boundaries

Owns bounded source admission ports for native curve and tensor source values.
The original B-spline validators own finite controls, positive weights, knot
ordering/multiplicity, finite domains and repeated cyclic source tails. Geometry
family dispatch owns recursive source depth and procedural certificates. Topology
owns B-rep references, pcurve correspondence, seams, areas and shell incidence.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | original source structural validity | Composes family source validation. | This port does not establish surface embedding or regularity. |
| [Periodic B-spline](../PeriodicBSpline/DESIGN.md) | coordinates with | original cyclic knots and exactly repeated controls | Uses the same existing periodic predicates. | Existing tolerances and periodic limits are preserved. |

## Architecture

```text
caller cumulative work / cancellation
    -> immutable source validation port
    -> native actual control / weight / knot / cyclic traversal
    -> valid original source or original typed failure
```

## Contracts and Invariants

Every source-sized loop performs admission before reading each item or comparing
its original scalar/point value. No outer aggregate debit authorizes an opaque
legacy validation call. Both legacy and bounded entries execute the same actual
validators. Legacy entries add no resource ceiling; their callback checks
cancellation. The bounded callback belongs to the caller and is never reset.
The composing family dispatcher admits its own recursive source depth.

## State, Ownership, and Lifecycle

Inputs are borrowed immutable value snapshots with COW arrays; this port stores
no source, mutable cache, platform-specific state or escaping callback. Native,
WASM and Embedded use the same validation and admission path. Existing native
Codable adapters remain a separate transport capability.

## Failure, Concurrency, and Constraints

Source errors retain the original Geometry/Kernel typed failures. Callback
resource exhaustion and cancellation propagate unchanged before the affected
source visit; no successful receipt is emitted after partial traversal.

## Verification and Change Impact

After the all-source gate, check valid/invalid finite and cyclic inputs, source
mutation, work exhaustion before each source-sized traversal, cancellation and
Native/WASM/Embedded common execution. Parent family dispatch and Topology's
bounded complete B-rep validation own their respective cumulative composition.


## Recursive Family Composition

The family ports accept remaining source depth, the composing subdivision ceiling
and one `@Sendable (Int) throws -> Void` admission callback. Each descendant
reduces source depth before validation. Native validation charges each actual
control, weight, knot and periodic-tail visit. Immutable implicit graphs retain
constructor/decoder certificates: their fixed certification-contract check does
not replay interval proofs or allocate a new allowance. Surface lifts validate
their raw hosting surface and directed pcurve under the same caller admission.
Unsupported callback-aware certificate producers must fail explicitly until
actual proof loops forward the caller ledger; outer phase charging is insufficient.
Periodic pcurve translations require exact membership in the original support
period lattice, including native knot endpoint differences and image gains/axis
permutations. An approximate zero or approximate integer period is not a source
validity witness. The direct exact-algebra execution borrows the same direct execution;
its word counts do not establish a separate complete byte admission receipt.
An actual byte owner is forwarded through every descendant.
When present, exact-word revalidation and period proofs admit each actual
UInt32 buffer count with checked multiplication by four before allocation.
The existing work debit remains independent; a work-only invocation does not
claim this byte receipt or full lower query allocation coverage.
Algebra cell visits charge source work at depth zero. Ordered-field and root
depth is checked by the immutable word's retained construction authority, or
by an explicitly supplied stricter algebra-depth ceiling in `0...32`, and
is independent of source-tree descent and curve subdivision. Revalidation uses
the current tolerance and the same work ledger without granting new limits.

Flat original affine-word curve and support images retain the original source
parameter domains and one descendant. Their immutable word receives bounded
raw-factor validation under this same execution; no rounded representative
transform can replace it. Directed word-image pcurves bind the complete source
lift and unchanged support chart to the exact retained target image.
Generated endpoint connectors retain their construction and both original
boundary expressions. Bounded validation charges their native construction and
descends into both retained boundary sources before consuming the immutable
endpoint-incidence contract. Construction control endpoints cannot replace the
original boundary expressions or certify a connector's closure.
Original guide traversal chains retain their exact station partition and each
directed root traversal. Their immutable constructor owns positional join and
derivative authority; bounded family admission checks the current tolerance and
descends into every retained original source with unchanged actual bytes and
independent source, spatial and algebra ceilings. Construction or display points
cannot replace those traversal sources or authorize untrimmed membership.
Guide endpoint corrections retain the original guide traversal and both original
section boundary traversals. All three descend through the same family admission.
Algebraic traversal endpoints also check their retained isolation depth against
any explicitly selected tighter algebra ceiling; cached endpoint enclosures do
not grant a different invocation additional algebra capability.
Word image admission delegates to its original relation owner: physical radius
and clearance predicates use the unchanged target SI tolerance before local
source calculation policy is selected. Raw local-unit primitives cannot be
admitted or rejected by applying the target distance threshold before the word.

Prepared surface and rail owners forward an explicit caller subdivision ceiling
into every bounded descendant admission. The legacy convenience ceiling remains
unbounded at the facade; inherent producer limits remain unchanged. Preparation
does not infer permission to rerun opaque source validation from an earlier pass.

The optional algebra-depth ceiling is forwarded unchanged through every curve,
support, lift and pcurve descendant, including the sources retained by immutable
procedural witnesses. It never reuses source nesting or subdivision depth. A
missing algebra ceiling preserves the retained construction authority; supplying
one can only tighten admission under the same work and actual byte owners.

Persistent construction charts retain a normalized root traversal or exact
directed rational parameter law. Bounded admission consumes the immutable chart
contract and descends into its retained original source under the same execution
and independent algebra ceiling. Normalized chart curves require directed B-rep
trims; fitted or rounded endpoint images cannot authorize untrimmed membership.

Original boundary-corrected supports retain both the native construction and
the original Coons boundary receipt. Family admission descends into each under
the unchanged work, actual byte and independent algebra-depth policy. The
immutable correction receipt establishes construction provenance; it never
replaces admission of either retained source or establishes embedding by itself.
Original angular transports validate their retained intrinsic/physical-radian
descriptor and complete primitive relation with the same direct scalar execution. Standalone admission establishes the identity-action physical metric;
an outer original word owns its complete world metric separately. The transport
adds one source level, and an explicitly selected algebra ceiling constrains
its exact normalization independently from source descent and subdivision.

Plane derivative carriers retain their original construction/traversal, final
four boundary sources and every requested supporting source. Bounded admission
visits each constraint before descending into its support and admits all retained
curve/surface descendants with the same actual byte owner and independent
source, spatial and algebra ceilings. Immutable projection provenance does not
replace validation of a retained support or prove the final surface is regular.
Original drafted curves retain their raw generator traversal, directions,
physical angle and height. Family admission consumes immutable construction
provenance and descends into the generator; a drafted ruled support descends
through its retained start curve. Final embedding and correspondence remain
separate contracts and cannot be inherited from a fitted native candidate.

## Direct Execution Admission

Family validation receives the caller's `inout OriginalQueryExecution` directly.
Native source loops, exact scalar predicates and recursively retained sources
borrow that same execution; no callback-to-rational admission is constructed.
Remaining source depth and geometric subdivision policy retain explicit source
meaning. An optional stricter algebra ceiling bounds each scalar proof axis
independently through the execution's local proof scope. All allocation bytes
and actual work reach its sole cumulative owner.

```text
original source -> family validation -> retained descendants / native loops
                 -> direct execution -> scalar proof and cumulative owner
```

The execution records attained source and scalar depths at the actual validation
boundary. Immutable preparation receipts can be readmitted under a different
execution without rebuilding source decomposition. Existing unsupported source
branches remain explicit failures with their existing completion gates.

## Immutable Preparation Evidence

`OriginalGeometryPreparationReceipt` binds the actual operation-local scalar, source, transport and geometric depths, original cumulative budget and immutable tolerance. Prepared curve/surface owners and native conversion adapters retain it beside their immutable original source and coefficients. Every direct reader checks the retained tolerance and re-admits that evidence through the supplied execution. Foreign executions perform fixed metadata verification and retain the receipt cache owner; historical preparation arithmetic and scratch are never replayed or recharged. Query-local scopes and counters are not retained.

```text
original preparation -> operation-local attained depth -> immutable receipt
reader execution -> receipt verification -> retained original coefficient query
```

The optional explicit algebra ceiling is an additional proof-scope maximum over the independent value and coefficient axes. Omitting it preserves the execution's distinct axis limits.

Preparation ownership review (source contract; target compile/runtime evidence remains pending):

| Logical state | Native / WASM / Embedded storage | Isolation | Read entry | Mutation entry | Release |
|---|---|---|---|---|---|
| Preparation evidence | Immutable `let` fields in `OriginalGeometryPreparationReceipt` | Immutable Sendable owner | `admit` | Constructor only | Strong owner release |
| Original coefficient buffers | Immutable COW values in prepared source | Immutable retained source | Direct prepared query | Constructor only | Retained source release |
| Cumulative charges | Shared `OriginalQueryBudget` | Same common Mutex contract | Budget snapshot | Direct execution budget methods | Budget owner release |
| Proof scopes and receipt cache | Exclusive noncopyable execution | Caller-exclusive query lifetime | Direct query | Same execution only | Query end |

No target-conditional state or Sendable conformance is introduced by these preparation ports. The common budget owner design owns synchronization implementation and its portable behavioral evidence.


### Immutable Preparation Receipt Lifecycle

The retained preparation receipt owns its common budget, effective immutable
policy and ordered active contribution handles together with attained proof
depths and tolerance. Later ordinary queries create one execution from that
owner. Same-budget direct queries temporarily enter the retained contribution
ancestry on the original execution; independent executions readmit the actual
proof without importing foreign spend authority. The common execution owns
scope cleanup and all mutable counters. No callback or query-local scope is
stored in the receipt.

## Certified Family Direct Validation

The bounded curve and pcurve dispatcher invokes the genuine certified-family
validation loops through the same execution and current source-depth offset.
These validators retain their existing source/domain/residual meaning and
propagate unavailable lower producers. They do not issue original intersection
coverage or an exact-coincidence receipt; that separate migration remains with
the certified source families. Actual dispatch success/failure and cumulative
resource tests are required before its resource-port marker can be removed.


## Bounded Native and Lift Validation Frame Boundary

The native surface/curve dispatch and the curve surface-lift validation path
must not reserve unrelated procedural-family temporary frames. Private
`@inline(never)` helpers isolate those original family bodies. The public/package
signatures, existing proof scope, source-depth admission, one entry work visit,
cancellation/tolerance order, child depth mapping and actual family validation
remain unchanged. Native controls and lifted pcurves still receive every original
validation; no retained metadata or sampled result replaces it.

The concrete Native worker-stack counterexample is the authored unit-rectangle
Face Rebuild input (IPS `991975f72c78dab01bd6c7fdf0597b52d61c079a3273d5dfa37e967617fc557f`).
Its source validation occurs inside prepared correspondence. Verification owns
original-body/debit comparison, actual fixed-toolchain frame prologues and the
same genuine caller positive/refusal controls. A smaller source form is not
runtime success; caller stack limits and cancellation/resource contracts stay
fixed. Preparation frame ownership is documented by
[Geometry conversion](../GeometryConversion/DESIGN.md).
