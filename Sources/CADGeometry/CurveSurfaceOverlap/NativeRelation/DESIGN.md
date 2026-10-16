# Native Curve Surface Relation

## Purpose and Scope
Child of [Curve Surface Overlap](../DESIGN.md). Publishes the complete original
finite selected native CS relation, including mixed-dimensional
components. Multi-span isolated publication remains owned by
[Native Point Relations](../NativePointRelations/DESIGN.md).

## Responsibilities and Boundaries
Retain original operands, domains, cells, closure incidence and connected components.
Numerical overlap correspondence does not represent this multivalued relation.
Multi-chart composition refines all original chart equations, denominator guards,
Jacobian minors and source bounds in one original sign-invariant parameter partition.
Each internal knot and every periodic seam belongs to its right positive span;
nonperiodic final native endpoints are closed. Periodic nativeDomains are genuine
unbounded parameter ambients; requestedDomains/effectiveDomains remain finite
closed selections. Omitted periodic ranges use the existing public [0, period]
default independently of origin metadata, never a finite-window claim over the
ambient. The common refinement uses the finite effective selection, or the
finite requested box with a false owner predicate when exact native intersection
proves exclusion. Unbounded periodic ambient metadata never becomes a solver
window. Source chart descriptors retain the curve and surface issuers' original
span indices, independent cycles, represented translations and native domains. This predicate, rather than numerical boundary pairing, owns source values.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Overlap](../DESIGN.md) | parent | rich publication | Whole relations accompany legacy fields | Empty overlap arrays do not certify discreteness |
| [Intersection Algebra](../../IntersectionAlgebra/DESIGN.md) | depends on | decomposition, incidence, ordered relation | Complete original cells and exact fibers | Resource/cancellation failures propagate |
| [Curve Chart Cover](../../OriginalNativeCurveChartCover/DESIGN.md) | depends on | complete finite original translated laws | Every curve cycle retains original authority | Same cumulative span/work/storage admission |
| [Surface Chart Cover](../../OriginalNativeSurfaceChartCover/DESIGN.md) | depends on | complete finite original tensor transports | U/V cycles remain independent | Closed seam owners grant no XYZ identity |
| [Native Points](../NativePointRelations/DESIGN.md) | coordinates with | isolated localization and admission | Preserve isolated fast path | No boundary cells published as isolated components |

## Architecture
```text
original native products -> proved local decomposition or retained source binding
  -> multi-chart owner predicate + common original sign refinement
  -> retained cells + closure attachments + connected components
  -> exact maximal t-prefix projections + image/fiber dimensions
  -> immutable public owner
exact t station -> original equations/guards -> ordered UV relation -> all fibers
```

## Contracts and Invariants
Every selected original cell is retained. Handles are scoped to one immutable owner.
Connected components use proved closure incidence, never XYZ equality or tolerance.
Projection merges consecutive selected t-prefix cells in the original cylindrical
order, preserving open/closed endpoints. Cell image dimension is zero for a fixed
t-prefix or an identically constant original curve law, otherwise one. Parameter
fiber dimension is cell dimension minus its t-prefix dimension; geometric image
fiber dimension is cell dimension minus image dimension. Samples are exact points,
not whole-cell ranges. Rich legacy points contain isolated components only.
Discrete queries fail atomically on every positive-dimensional selected cell.
A common refinement retains all original chart laws and partitions on their exact
bounds and indexed Jacobian minors. Original laws that differ by a nonzero exact rational unit share one admitted
monic partition polynomial. Retained original-to-issued ordinals and exact rational units (including their signs)
restore every original sign atom and source-owner comparison; zero/rank witnesses
remain equivalent. Unit normalization uses original leading coefficients and exact
rational division/scaling, with every operation and retained mapping admitted.
Original chart laws remain retained without numerical root merging.
Public sourceCharts and sourceChartDomains retain every closed source chart product; a cell's
sourceChartIndex selects its exact original source domain. Each selected cell has
exactly one original source-chart owner, whose rank and curve image law apply throughout that cell.
Multi-chart rich preparation retains original source bindings without redundant
local solving; one complete common refinement owns every selected cell, original
rank witness and incidence. Single-chart rich and discrete entries retain proved
local decompositions. A source binding never masquerades as an empty local proof.
A chart whose exclusive upper bound equals the selected lower bound owns no
selected tuple. Exact domain comparison records this exclusion before admitting
partition laws; its issuer token, original laws and source descriptor remain
retained, and the aggregate admitted product ceiling still includes it.
Only when every active chart supplies a nonconstant original univariate zero
equation for each of the same authoritative t/u/v axes, the composition retains
those original equation ordinals and three exact products of distinct issued
witnesses. Every selected original tuple necessarily zeros all three products,
which prove a finite coordinate set. Existing cell preparation may prune prefixes
excluded by these equations; each retained ExcludedPrefix.equationIndex addresses
the corresponding retained product. Original partition laws, DNF, raw Jacobian
rank and source ownership remain complete and use the actual partitionSignOffset.
A missing axis witness keeps the original unpruned positive/mixed path.
The global incidence and connected components determine rich isolated points; a
locally isolated knot value attached to a neighboring positive component is never
published as an isolated point. Identical XYZ values with different UV tuples remain
distinct. Closed requested boundaries remain selected even at internal knots.

## Runtime Flows
The public fiber query substitutes an exact retained scalar into every original
equation, denominator guard and chart owner predicate, preserves its causal source depths and requested
t membership, and uses the existing ordered real relation engine for all UV cells.

## State, Ownership, and Lifecycle
The receipt retains immutable issuer tokens, original chart laws/systems/domains, proved local decompositions when selected, and the complete common refinement and
source operands. Samples retain their exact field owners. CellIdentifier is an
immutable identity-only token scoped to one receipt; it requires that receipt for
membership and does not independently retain original geometry or chart laws.
No mutable cache, shared state or numerical inverse owns membership or identity.

## Failure, Concurrency, and Constraints
Publication uses the original invocation ledger and candidate ceiling. The
candidate ceiling independently bounds all selected cell records and connected
component records, including boundary cells, rather than their geometric XYZ
images. Publication preserves source and
algebra depth, storage admission and cancellation. The preferIsolatedCells lower port prepares original cells once for its initial
classification. The isolated rank path is selected only when every actual selected
real cell has zero dimension, including real-only isolated loci of a positive-
dimensional complex ideal. Any positive-dimensional real cell selects full
original rank partition and incidence. The positive preferred path retains an
unpruned full partition to satisfy the existing finite-branch closure theorem;
initial isolated pruning remains unchanged. There is no failed-solver retry. Fiber queries use caller-provided
the original scalar admission and independent parameter/coefficient depth. No private quota. Multi-chart rich queries use the same admission ledger for chart
source binding preparation, the selected complete decomposition, closure and final publication. The discrete N2
path remains isolated-only and keeps its existing exact closed-boundary ownership
proof. Source validation retains its existing rejection of position discontinuities;
internal open multiplicities above degree remain outside this contract. Periodic
operands require the verified exact finite curve and surface chart issuers. Their
unsupported approximate transports and unrepresentable cycles propagate after
admission; no legacy fallback or private quota replaces required coverage.

## Verification and Change Impact
NativeCurveSurfaceRelationTests, NativeCurveSurfaceMultiChartRelationTests and
NativePeriodicCurveSurfaceRelationTests exercise full overlap, multiple UV, collapsed
images/fibers, mixed components, exact membership/projection, foreign handles and
independent admitted failure. Changes to decomposition or incidence require this
owner's full relation evidence; isolated fast-path evidence remains separate.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
