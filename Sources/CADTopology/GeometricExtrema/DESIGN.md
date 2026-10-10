# Geometric Extrema

## Purpose and Scope
Child of [CADTopology](../DESIGN.md), owning global minimum distance over selected exact vertices, curves and trimmed faces.

## Responsibilities and Boundaries
Topology selects support entities and bounded domains, including a face restricted to a closed original parameter box. Restricted face witnesses retain every original trim predicate; they never become a representative midpoint or an untrimmed support band. Geometry supplies original whole-cell position enclosures. Kernel supplies trimmed-face closest projections and solid classification. Witnesses carry support and parameter provenance.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Topology](../DESIGN.md) | parent | entity incidence and pcurve domains | Resolves selected bodies to their full boundaries | Representative points do not certify minimum distance |
| [Geometry](../../CADGeometry/DESIGN.md) | depends on | curve/surface differential enclosures | Supplies complete closed-cell bounds | No sampled lower bound |

## Architecture
```text
Selected entities -> exact domains -> cell-pair lower bound / exact witnesses
    -> global branch-and-bound -> certified distance interval and all retained minima
```

## Contracts and Invariants
Surface interior witness proposals require strict original outer-loop inclusion
and strict exclusion from every hole. A tolerance-near boundary classification
is inconclusive and cannot admit a free UV station as an exact face witness.
Original retained boundary curves are independently present in the domain cover
and supply boundary witnesses with their native edge parameters. Conservative
trim-cell retention remains unchanged; uncertain cells continue refinement.

Distance norms scale nonnegative coordinate gap bounds before interval
squaring and restore the original scale afterwards. Outward division, sum,
square-root endpoints and final multiplication authorize each lower/upper norm;
finite representable distances do not fail from intermediate squared overflow.

The global lower bound covers every admitted cell pair; witness distances are upper bounds. Cells only disappear when their certified lower distance exceeds the admissible minimum. Trims may be conservative lower-bound covers, but every published face witness is trim-admitted. All candidate pairs, witness combinations and local witness improvement steps share one 262144-operation/depth32 allowance. Prepared original surface enclosures are retained by immutable support domains for the query lifetime. Witness distance arithmetic rounds coordinate subtraction, products, sums and square root outward. Failure to achieve requested width fails explicitly.

Original coordinate-gap magnitudes use Geometry's outward interval arithmetic
and scaled norm evaluation. Importing that interval owner does not change the
physical metric. Both final domain admissions remain throwing checks; failure
on either side prevents a closest-pair witness from being returned.
Regression owner: [Native dependency contracts](../../../Tests/CADTopologyTests/NativeDependencyContractTests.swift).

## Failure, Concurrency, and Constraints
Cancellation and resource exhaustion propagate. No midpoint or bounding-box center is returned as a minimum without a complete lower-bound proof.

## Verification and Change Impact
Independent edge-edge, edge-face, face-face and body-body solutions, multiple solutions and containment classification must exercise the public Kernel caller after this source batch is complete.

The invocation owns a single `BRepDistanceProofBudget` with the same Mutex storage on all targets. Original pcurve traversal and winding refinement debit this owner before each visited cell; lower depth cannot exceed the query depth. The source predicates remain immutable and Hashable: callbacks are invocation arguments, never retained source or cache authority.

The package composition entry accepts the same immutable request-bound budget from Kernel. Boundary extrema and subsequent original solid/contact classification debit that one owner. The supplied allowance must match the exact tolerance, work ceiling and depth ceiling; a foreign allowance is rejected. Historical public providers create their own invocation owner.

Pending distance cells use a deterministic binary minimum heap. Each heap comparison and support witness visit debits the shared operation owner; extracting the smallest global bound does not repeatedly scan the full frontier.

Witness upper distance uses original coordinate enclosures around each retained source parameter, not just subtraction of rounded point evaluations. A positive representable neighboring interval contained in the original native domain may conservatively enclose a singleton curve station until the lower closed-singleton port is selected; all witness provenance retains the actual station parameter. Distinct support identities remain distinct even when their locations agree.

An edge, including an exactly collapsed original lift, retains its original curve domain in the metric query. Topological endpoint tolerance does not replace its geometric image with a possibly displaced stored vertex. Explicit vertex selections retain the selected vertex authority.

`BRepDistanceOptions` owns finite absolute/relative error and caller-lowered work/depth ceilings. The stopping width is at most max(absoluteAccuracy, relativeAccuracy times the certified nonnegative lower distance); near-zero distances therefore retain absolute accuracy. Results publish the request and consumed original proof visits. The historical absolute-accuracy overload delegates this same algorithm.

Distance domains retain one prepared original curve/support source for the invocation. Position-only closed station/cell bounds consume the shared query ledger and caller remaining subdivision depth. Full derivative preparation must not silently become a new work allowance; all native owning cells, source images and retained chart localizations debit that ledger. A singleton original station is queried directly rather than enlarged into a neighboring derivative interval.

Original authored curve selections validate their complete retained source with the same invocation callback and caller subdivision ceiling before preparing position bounds. Source-validation visits do not receive a separate allowance. Legacy untrimmed edge parameter projection remains a distinct lower producer dependency; it cannot establish complete caller accounting.

The validated-source distance entry derives its entire topology model and tolerance from one immutable exact/volumetric BRep receipt. Face predicates borrow the original loop through that receipt and retain the caller depth/visit callback. Independently authored curve selections still validate their source under the same request. The compatibility raw-model entry does not assert validated source authority.

The caller may supply `maximumCumulativeStorageBytes` independently of original work and depth ceilings. One request-bound Mutex owner accumulates checked nonnegative original byte requests before lower allocation. A nil ceiling retains historical work/cell policies and records requests without asserting bounded storage. Byte accounting does not create a private allowance or turn an opaque lower phase into a complete receipt. Prepared original geometry and source validation receive the same byte callback; remaining trim, projection and graph temporary owners must forward their actual allocation requests before whole-query storage completion can be claimed.

The raw-model distance entry obtains one bounded exact BRep source receipt with the same request work and byte owner before domain preparation. Receipt-based loop admission replaces the opaque raw loop constructor. Kernel solid distance shares that receipt with classification and the finite face-pair graph factory, preserving the exact input model and tolerance without revalidation phases.

Candidate station locations use the midpoint of their complete prepared original position box, with original parameters retained. Those representatives only propose upper witnesses: the complete station boxes still determine their published upper distance. Local improvement uses position-only original station boxes under the same callback and byte owner. Its bounded coordinate proposals do not demand higher smoothness at a legal C1 join, and only complete station-box upper distances choose an improvement. The global cell cover remains the optimality authority.

Heap frontier and retained witness buffers reserve original typed slots through `DistanceQueryStorage` before growth. Checked stride multiplication charges each requested replacement buffer to the same cumulative byte owner before `reserveCapacity`. Existing buffers keep their retained capacity across removals; growth follows that observed capacity and never charges every insert as a new allocation. Original nested parameter/source buffers remain separately owned allocation requests.

Distance-width stopping uses outward subtraction of the published upper/lower bounds. The relative allowance is the downward original product of caller relative accuracy and the certified nonnegative lower distance; the absolute allowance remains exact. Rounded inward subtraction cannot authorize a successful distance interval.

Domain arrays, retained station parameter buffers, source interval copies and position-box arrays charge their original typed payload slots before factory allocation or copy-on-write mutation. The nested payload and copied capacity are counted independently of borrowed immutable curve/support values. This does not substitute for lower trim predicate, chart enclosure, or projection allocation callbacks.

Independent authored curve support comparisons visit their complete original structural payload through Geometry's structural-comparison work port before equality. Witness deduplication cannot hide a source-sized scan behind one outer query debit. Entity-only support identities retain their fixed-size comparison.

## State, Ownership, and Lifecycle

Optional lower storage admission is present only when the original request
selects a cumulative byte ceiling. With no ceiling the original work/depth
callbacks remain active, while lower algorithms retain their historical storage
policy. Known owned typed requests may still be counted; that partial counter
does not certify complete storage. Mandatory-byte producer APIs remain an
explicit separate connection dependency for the no-ceiling request route.

The request creates one immutable-configured `BRepDistanceProofBudget`. It retains
one `Mutex<State>` containing both visit and cumulative-byte counters. All proof
callbacks borrow this owner; no callback runs while its lock is held. Failed
admission leaves the rejected counter request unapplied and abandons publication.
The request lifetime owns all temporary domain, heap, witness and result buffers.

| Logical state | Native storage / isolation | WASM storage / isolation | Embedded storage / isolation | Read / mutation | Release |
|---|---|---|---|---|---|
| Visit counter | `Mutex<State>` | `Mutex<State>` | `Mutex<State>` | `consumedWork` / `charge` through `withLock` | Invocation owner release |
| Cumulative bytes | Same `Mutex<State>` | Same `Mutex<State>` | Same `Mutex<State>` | `consumedStorageBytes` / `chargeStorageBytes` through `withLock` | Invocation owner release |
| Request ceilings | Immutable stored values | Same values | Same values | Request-bound admission | Invocation owner release |

This matrix records source ownership only. Fixed-target compilation, link,
concurrent callback/reentrancy and cancellation behavior belong to the final
verification phase; source composition does not establish those runtime results.

Face upper-witness candidates first use strict original winding when the retained
UV loop has an exact authored endpoint-closure proof. This admits legal thin
interiors within the modeling boundary corridor without accepting free points
outside the exact trim. Other endpoint families retain conservative inside/outside
admission and their explicit original endpoint-relation dependency. Empty-cell
exclusion keeps the existing conservative corridor and complete domain cover.

An authored surface station retains its original support and exact stored U/V
parameters as a singleton two-dimensional distance domain. It is independent of
the owning face's trim, matching the public support-parameter selection contract.
Complete original position bounds supply its witness error; numeric differential
frames and normals are unnecessary for this legal position-only query. Original
support comparison traverses the complete retained surface payload on the same
ledger before equality.

Source nesting, algebraic root depth and geometric subdivision are independent request ceilings. `maximumSourceDepth` defaults to 16 and admits 0...16; `maximumAlgebraicDepth` defaults to 32 and admits 0...32. Missing native transport fields preserve these historical defaults. The immutable shared budget binds both values to the original request and forwards them to source preparation, exact algebra, trim admission and solid classification without deriving one from the other.

The selection composition entry may attach immutable external work-depth and
optional typed-byte admission callbacks to the existing distance budget. Each
request first reserves its local counter under the same Mutex, then invokes the
external owner outside the lock. External failure aborts the invocation and
retains the already consumed local reservation; counters are never copied back
or refunded into a concurrently shared owner. The external owner imposes an
additional ceiling and cannot increase the distance request's existing work,
source, algebra or subdivision limits. A BYTE callback remains absent when
neither the local request nor the composing caller selects byte admission.
Requested typed-byte observations retain their existing scope and do not prove
Swift allocator capacity or overhead.

Owned body relationship ID buffers use in-place comparison-charged heap ordering
and adjacent deduplication. Face and edge incidence visits request typed array
capacity before appending; they do not create unobserved Set storage or copied
sorted arrays. Classification summaries retain fixed counters/booleans instead
of separate classification and filtered-index arrays. The operation covers
original source ordering only and supplies no new geometry or absence theorem.

OriginalDistanceMagnitude owns the shared outward Euclidean norm of three
nonnegative original coordinate-gap magnitudes. It scales before squaring and
restores the original magnitude after outward square-root, so finite tiny/large
source errors do not fail solely from intermediate squared underflow/overflow.
Distance lower/upper bounds, Kernel boundary localization and Mesh original
station-discrepancy admission consume the same primitive without changing their
separate physical allocations or source authority.

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.
