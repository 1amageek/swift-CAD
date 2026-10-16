# OriginalGraphBandMesh

## Purpose and Scope

This child of [CADKernel](../DESIGN.md) owns the bounded original rational
U-graph-band mesh composition. It has no children. Actual original coedges,
spatial trims, shared vertex identities and retained lower receipts are its
inputs. General trimmed faces and adjacent-face conforming subdivision remain
separate responsibilities. Assembly is not complete until the actual Draft
packet satisfies both lower contracts and the unchanged public Draft oracles.

## Responsibilities and Boundaries

Kernel binds actual topology and spatial correspondence, retains compatible
reference grids, admits storage before output allocation, and publishes only
fully admitted facets with original selected normals and FaceRun provenance.
Geometry owns original coefficient, inverse, domain, regularity and whole-facet
proofs. CADIR owns the caller's geometric fidelity and resource limits. No
source curve, pcurve, trim, vertex or support is repaired by this component.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | retained preflight, all-or-nothing mesh publication | Composes this plan with the invocation budget and body meshes | Admit every face before output allocation |
| [OriginalGraphBand](../../CADGeometry/OriginalGraphBand/DESIGN.md) | depends on | immutable original graph receipt, stations and facet admission | Proves complete reference and original uncertainty coverage | Preserve one shared262144-cell/depth32 usage; no sampled fallback |
| [OriginalCurveSurfaceCorrespondence](../../CADGeometry/OriginalCurveSurfaceCorrespondence/DESIGN.md) | depends on | strict original source-bound certificate | Proves each actual spatial use against its original pcurve and support | Retain exact directed trims, source identity and caller allowance |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | original ordered coedges, edges and shared vertices | Supplies actual source provenance | Geometric proximity never replaces vertex identity |
| [CADIR](../../CADIR/DESIGN.md) | depends on | TessellationOptions, TessellationLimits and Mesh | Supplies fidelity, storage ceilings and FaceRun meaning | Whole-facet and all-edge checks precede publication |

## Architecture

```text
Actual face / outer loop / original support
    -> ordered coedge and directed spatial-trim binding
    -> strict per-use correspondence receipts
    -> remaining original mesh linear allowance
    -> original graph receipt and retained compatible grid plan
    -> invocation-wide checked storage admission
    -> actual stations + original normals + complete facet proof
    -> non-fallback triangle emission + FaceRun
```

## Contracts and Invariants

Every original use retains its edge ID, curve ID, coedge orientation, pcurve,
directed trim and start/end vertex IDs and points. Adjacent directed IDs must
match, including last-to-first. The pcurve already follows the coedge direction;
only the spatial trim is reversed for a reversed use. Each correspondence
certificate binds those exact source values, support, tolerance and options.

For caller mesh linear allowance `L` and modeling distance allowance `D`, the
strict correspondence request is `min(D, L/4)`. This is an allocation policy,
not a new source tolerance. The maximum achieved whole-use bound `E` is charged
once against `L`. The graph receipt receives the outward-safe positive
remainder `L-E`; no correspondence tolerance is added to the mesh tolerance.
The correspondence owner retains its unchanged65536-cell/depth32 ceiling.
An unrepresentable request or nonpositive remainder is an explicit failure.
When the caller omits `maxEdgeLength`, the lower receipt receives
`Double.greatestFiniteMagnitude`: every finite representable edge bound is
admitted, while nonfinite arithmetic still fails. An explicit edge ceiling is
passed unchanged and checks all sides and diagonals.

Original graph candidate preparation admits every native 2D spline coefficient
and each control-statistic visit through the same invocation work owner. Candidate
labels remain proposals; only the original graph receipt proves their ordering.
The original correspondence certificate producer uses the same caller execution.
Complete invocation accounting still requires actual public packet preparation
and facet-emission evidence; the call retains an explicit incomplete marker.

Every active reference-law break and original native support boundary is
retained. All original boundary intervals and complete join strips/caps remain
covered. Compatible vertical stations share actual positions after independent
lower receipt admission; selected C0 normal owners remain separate. Actual
facets must pass receipt position, normal and all-three-edge checks. A failed
triangle adoption is a typed failure, not permission to skip a triangle.
Normals cannot be replaced by flat-shading fallback after lower admission.

Checked vertex/index/byte counts precede output allocation and use the existing
invocation TessellationBudget. The exact retained plan used for preflight must
also drive emission. No fresh proof ledger replaces already consumed graph
usage. A face has complete emitted coverage and one corresponding FaceRun.
The retained original graph contribution also debits the invocation's common
OriginalQueryExecution before each original visit. Preferred grid station
work consumes that same owner; the graph's local fixed cap never creates a
second allowance for preparation or emission.

### Candidate-only chain selection

Original stored endpoint U values classify two contiguous oriented chains.
Their deterministic original interior-control V means label the candidate
lower and upper chains only. Constant-V segments may contribute their stored
V to that statistic but are not required. No curve evaluation sample, epsilon,
control statistic or endpoint comparison proves monotonicity or ordering.
Success requires the original graph factory's whole coefficient, separation,
full-strip, join and later facet receipts. The bounded selector attempts one
assignment; a failure propagates without swapped-assignment retry, sampled
fallback or proof-counter reset. A future concrete mislabeling counterexample
requires a separate original-coefficient ordering owner; the current candidate
selector is explicitly incomplete for such unproved graph families.

### Retained upper plan and selected normals

The bounded consumer prepares one invocation-owned face plan retaining its exact
source binding, per-use correspondence certificates, graph receipt, already
consumed proof usage, active reference-cell U counts, a common W subdivision,
and tip-cap recipes. The complete checked vertex/index totals of that same plan
feed invocation preflight; emission does not infer new counts from the source.
Existing rectangular grid planning may supply preferred counts using the
composed F bounds over each U interval and W=[0,1]. Those counts are not a facet
certificate: every actual triangle still requires the retained receipt's whole
position, selected-normal and all-edge admission. A proof failure or failed
nondegenerate triangle adoption propagates; no triangle is dropped or emitted
with a substituted normal.

Reference cells retain their selected original U owner and active-law breaks.
A common W count across adjacent cells supplies the same vertical stations.
At a shared U station, a reused position must pass independent `pointCandidate`
station admission on each incident cell. The consumer retains distinct station
and normal owners at C0 knots even when their admitted positions coincide.
The preparation and emission share the same consumed proof ledger; a fresh
262144-cell allowance is never minted for emission. Each materialized U row
first obtains an immutable `OriginalGraphBandReceipt.Row` from
`stationRow(cellIndex:u:using:)` under that same ledger. This lower-owned
receipt binds the exact graph receipt, selected cell and original U to its
unchanged lower/upper graph enclosures. All W stations in that row use
`station(row:w:pointCandidate:using:)`; they do not repeat the identical
original inverses. Each station still pays before original point, selected
native normal, closed-jet and materialization-error work, and each facet still
pays for complete original admission. A shared position at a neighboring cell
is independently admitted under a separate row and selected C0 owner. Row
reuse does not widen the original intervals, alter any source, reset usage or
replace whole point/normal/facet proof with a cached success value. A foreign
row is an explicit lower binding failure.

### Invocation-owned bounded facet scratch

Emission retains one mutable, invocation-local facet scratch containing exactly
three station slots, three indices, three positions and three original normals.
The same consumed graph proof ledger admits all twelve slots before any scratch
array reserves storage. There is no independent allowance, refund or replacement
ledger. Each actual station and each actual reference or join facet still pays
its existing lower admission charge and executes the original lower contract.
The scratch replaces repeated per-triangle intermediate arrays; it caches no
successful geometric decision. Before each facet admission, all three active
slots are overwritten from that facet's actual retained stations or cap sources.
The lower owner receives the complete current points and original normals, and
the consumer independently checks the exact published orientation transform.
Cancellation and a lower or triangle-adoption failure still prevent publication.
The immutable retained plan remains the authority for counts and source binding;
scratch never supplies preflight counts, positions from another row, or normals
from another native owner. It remains local to one synchronous append invocation
and introduces no shared cache, callback or conditional synchronization policy.

Geometry stations bind the original positive parameter normal. The consumer
checks each raw station/facet against that lower binding, then applies the
existing exact face/shell orientation sign to the published normal and triangle
winding. The published normal must equal this deterministic transform of the
admitted normal. The sign operation changes no angular error and permits no
hemisphere heuristic or normal-consistency fallback.

### Bounded tip-cap assembly and pending admission

A tip is recognized from the retained common entry/exit U station and its
incidence with the first or last reference row. The bounded proposed assembly
connects that complete common-W row to the retained actual spatial tip vertex;
every W interval owns a fan facet. These facets form the complete fan by
construction from the same retained row and apex; no exact UV triangle domain
is inferred for the actual spatial apex. Instead the retained closed tip box
covers every original tip interval/completion, and the whole E+D bound holds
for every such source point and every barycentric point of each actual fan
facet. The complete row intervals and nonempty adopted fan remain necessary
consumer coverage evidence. Each actual facet requires `admitJoinFacet` under
its selected original panel. No original tail or cap strip is removed to obtain a
nondegenerate fan.

This assembly admits only a cap with one positive-width native U owner. Closed
zero-width incident panels remain in the receipt but do not authorize a
triangle spanning a C0 knot. A cap crossing multiple positive-width selected
owners requires a separate complete owner-preserving assembly; the bounded
consumer must refuse rather than interpolate normals across that knot. The
original packet's G-only observation retains one positive owner at each tip:
left span6 over U=[.2,.20000915527343752], right span534 over
U=[.8491196134437144,.849143609346716]. The internal join at U=.8
retains both positive selected owners531 and534. This is a lower admission
premise, not proof that actual upper facets have yet passed.

The original TessellationOptions value remains immutable. The graph receipt
receives `min(options.angularTolerance, Double.pi)` as an explicitly stricter
proof allocation. Every published facet's admitted angle therefore remains at
or below the original caller allowance. A valid caller angle above pi is not
refused solely because the lower proof allocation is stricter. The actual Draft
packet angle is below pi and remains unchanged. No caller allowance is widened
and no proof failure is retried through a different route.

## Runtime Flows

The bounded graph family is selected before the legacy rectangle/sample path.
Its proof failure propagates without retry through either path. Preparation
retains original receipts and checked grids; emission operates on the same
immutable model and plan. Mesh compaction may relabel vertices but retains
triangle order and face-run attribution. Actual grid and cap assembly remains
pending upper behavioral verification of the original Draft packet; lower
admission and source structure alone do not complete publication evidence.

## State, Ownership, and Lifecycle

Source binding and plans are immutable invocation-owned values. Proof usage is
one local inout value through preparation and emission. This component creates
no shared mutable cache, escaped pointer, callback or target-specific isolation
policy. Output arrays remain private until the complete mesh validates.

## Failure, Concurrency, and Constraints

Existing invalid-source and missing-reference failures propagate. Invalid
binding, unproved family, correspondence, graph separation, normal or coverage
fails explicitly. Cell/depth exhaustion, arithmetic overflow and storage
admission retain their typed resource failures; cancellation propagates.
The original source and public Draft tolerances, time limits, volume and angle
oracles are unchanged.

## Verification and Change Impact

Lower Native evidence belongs to the two Geometry components. Kernel tests must
exercise actual ordered coedges, reversed directed trims, foreign/disconnected
vertex identity, retained-source binding, compatible original C0 positions and
separate normals, complete nonconvex interior/cap coverage, all triangle edges,
resource preflight and cancellation. Public evidence must execute unchanged
OriginalCubicExtrusionDraftTests through MeshTessellator and FaceRun. The actual
four-use packet and both lower admission results are required before assembly
can be completed. Lower contract changes require rechecking this composition;
portable and general M2 completion need their own execution evidence.


### Candidate direct proof-owner binding

| File | Actual callee edges | Required binding |
|---|---|---|
| OriginalGraphBandMeshPlan.swift | correspondence validateBinding; retained graph proof contribution; facet scratch | Retain the typed contribution handle rather than deleted mutable proof usage. Direct binding validation borrows the caller execution. |
| OriginalGraphBandMeshAssembler.swift | correspondence certify; graph certify; stationRow/station; reference/join facet admission; grid-count and triangle callbacks | Prepare and emit under the same retained contribution and caller execution. Callback signatures carry inout OriginalQueryExecution, never a private allowance. |

The existing graph-chain candidate algorithm, per-use source identities,
uncertainty remainder, selected C0 normal owner, complete grids and tip fans
remain unchanged. Canonical lower proof owners receive their explicit retained
contribution. The existing 262144-cell/depth32 graph cap does not create a new
ledger or restart at emission. Geometry owns the original math and checked proof
receipts; this candidate batch owns only caller signature and owner composition.
The original collection/triangle algorithms and TessellationBudget output counts
are preserved; broad accounting changes and timeout fixes remain outside scope.
