# Exact Real Cell (L3)

## Purpose and Scope

Parent: [RationalBivariateAlgebra](../DESIGN.md). Children: none. This is the
fixed L3 design authority; its ports and receipts below are implemented as independent
production declarations. L3 owns a complete sign-invariant cylindrical real-cell
partition of an exact requested box, selection by a quantifier-free polynomial
predicate, and exact cell conditions and point location.

L3 depends only on the public [L0](../ExactScalar/DESIGN.md),
[L1](../ExactPolynomial/DESIGN.md), [L2](../ExactRealRoot/DESIGN.md) contracts
and Swift standard-library facilities. It is a component of the existing
CADGeometry target. This design creates no production package, target, external
dependency or lower-layer change. Isolated verification must compile these four
components without higher CAD sources.

Inputs are finite multivariate polynomials over the effective ordered
real-algebraic coefficient fields admitted by L2. Rational and retained algebraic
coefficients, arbitrary finite variable count, zero/constant laws, repeated and
shared factors, singularities, degree drops, nullified fibers, finite/open/closed/
singleton/empty/unbounded boxes and all Boolean sign conditions are mandatory.
There is no mathematical degree cutoff or hidden four-variable cutoff. Resource
limits can refuse a calculation atomically. A zero-variable input has the unique
empty coordinate tuple in R^0, subject to its predicate.

L3 does not own authored shape semantics, chart covers, periodic or pole identity,
closure, adjacency, connected components, quantifier elimination, XYZ images,
fiber dimension, geometric multiplicity, numerical localization or CAD result
publication. Complete L3 cells are not complete connected components or complete
CS/SSI. The seven requirements keep their separate completion conditions.

## Responsibilities and Boundaries

| Owner | Generates / retains | Consumes |
|---|---|---|
| Shape and domain consumers | Exact source equations, denominator and structural exclusion laws, source parameter roles and complete chart cover | Their original shape contracts |
| L3 source preparation | Original polynomial list/order, exact variable slots and requested box | Public L1 owner validation and public L0/L2 endpoint validation |
| L3 projection | Exhaustive projection levels, derivative and reductum provenance, principal-subresultant witnesses | Public L1 construction and arithmetic |
| L3 lifting | Whole-prefix delineability evidence, complete root stacks, section/sector descriptions, exact sample tower and dimensions | L2 complete root evidence and explicit ancestor embeddings |
| L3 selection | Immutable source-bound Boolean program and truth for every full cell | Proven constant original signs |
| L3 queries | Exact retained cell conditions, samples and point location | The same issued partition, original laws and fresh caller admission |
| Later topology consumers | Closure, incidence and connected components | L3 symbolic whole-cell conditions and complete partition |
| Later geometry/publication consumers | XYZ/TUV/UVUV correspondence, image/fiber dimension, contact classification and representatives | Original source bindings and algebraic/topological receipts |

Projection, lifting and selection are responsibilities inside this one component,
not new modules or public solver frameworks. Polynomial arithmetic belongs to L1;
root algorithms and coefficient extension belong to L2. No legacy private exact
field, root or polynomial implementation is accessed by L3.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RationalBivariateAlgebra](../DESIGN.md) | parent | Component index | Owns higher consumers | No existing consumer migration is implied |
| [ExactScalar](../ExactScalar/DESIGN.md) | depends on | Arithmetic/order/import, admission and retained depths | Owns scalar and resource meanings | No replacement quota, allocator or implicit failure conversion |
| [ExactPolynomial](../ExactPolynomial/DESIGN.md) | depends on | Canonical construction, public terms, calculus, GCD/division and resultant | Owns polynomial operations | Coefficient extraction and cross-variable reindexing are not public operations |
| [ExactRealRoot](../ExactRealRoot/DESIGN.md) | depends on | Complete roots, refinement/sign, runtime field family and explicit embeddings | Owns exact section coordinates | Sibling fields are incompatible; no automatic compositum |
| [IntersectionAlgebra](../../IntersectionAlgebra/DESIGN.md) | prospective used by | Complete partitions and retained conditions | Existing real-relation composition is a future integration consumer | Its current one-through-four-variable API and combined closure result are unchanged |

### Confirmed Current Facts

| Fact and actual implementation path | Design consequence |
|---|---|
| [L1 calculus](../ExactPolynomial/ExactPolynomialDomain+Calculus.swift) evaluates or substitutes all slots in the same polynomial owner; importing preserves variable count | L3 specialization extracts/reindexes admitted public terms and imports coefficients explicitly; it cannot pretend a public partial-specialization port already exists |
| [L1 coefficient helpers](../ExactPolynomial/ExactPolynomialDomain+Coefficients.swift) are internal; [resultant](../ExactPolynomial/ExactPolynomialDomain+Resultant.swift) is public, but principal-subresultant coefficients are not | Projection builds its certificate matrices from admitted public terms and computes their determinants with public L1 operations |
| [L2 extension](../ExactRealRoot/ExactAlgebraicScalarDomain.swift) keeps one static type, requires identical parent identity at adjoining, and accepts own/ancestor scalar imports | Every sample has one runtime field family; each section explicitly transports all earlier coordinates into its child |
| [Existing projection](../../IntersectionAlgebra/ExactIntersectionProjection.swift) retains reducta and principal-subresultant conditions; [tower](../../IntersectionAlgebra/ExactIntersectionProjectionTower.swift) adds derivatives | These are algorithmic/reference paths, not allowed L3 implementation dependencies or already verified new L3 behavior |
| [Existing resolver](../../IntersectionAlgebra/DefaultOriginalPolynomialRelationResolver.swift) composes selected cells, incidence and components | New L3 stops at cells/selection; later integration keeps connection decisions separate |
| [Native system](../../IntersectionAlgebra/OriginalRationalIntersectionSystem.swift) constructs three homogeneous coincidence laws in three CS or four SSI slots | Geometry can supply the same mathematical relations without giving L3 shape owners |
| [SSI publisher](../../NativeSurfaceSurfaceRelations/NativeSurfaceSurfaceRelationPublisher.swift) additionally partitions an XYZ/parameter graph | Parameter-cell dimension cannot replace image/fiber dimension |

Lower implementations and their previously recorded target evidence have been
reviewed independently. The preparation/producing/selecting/querying protocol witness paths are implemented;
C1-C10 behavior is tracked by the independent verification package. No existing higher engine execution
establishes the new L3 projection/lifting implementation. No higher engine is built by this design.

## Architecture

Arrows inside the component are data flow. Lower arrows denote dependencies.
Solid green is independently verified lower scope; blue is the implemented L3
responsibility boundary. Gray is later integration.

```mermaid
flowchart TB
    U["Source consumer: exact laws + box + one caller admission"]
    subgraph L3["L3: ExactRealCell — independent implementation"]
        S["Source and predicate preparation"]
        P["Full projection and derivative provenance"]
        L["Prefix lifting: sections / sectors"]
        D["Immutable complete partition"]
        B["Predicate selection"]
        Q["Cell conditions / samples / exact location"]
        S --> P --> L --> D
        S --> B
        D --> B
        D --> Q
    end
    L2["L2: complete roots and runtime field extension"]
    L1["L1: public polynomial operations"]
    L0["L0: scalars and admission"]
    T["Later: closure / components / geometry / publication"]
    U --> S
    L --> L2
    P --> L1
    Q --> L2
    S --> L1
    L3 --> L0
    L2 --> L1
    L1 --> L0
    B --> T
    Q --> T
    classDef fixed fill:#e7f4e7,stroke:#287a35,stroke-width:2px
    classDef implemented fill:#e7f0ff,stroke:#3168a4,stroke-width:2px
    classDef later fill:#eeeeee,stroke:#777,stroke-dasharray:5 5
    class L0,L1,L2 fixed
    class S,P,L,D,B,Q implemented
    class U,T later
```

### Public Ports

The concrete owner is `ExactRealCellDomain<Base>`. Base conforms to L0
arithmetic, ordering and importing with Source == Value. Its coefficient Field
is the existing `ExactAlgebraicScalarDomain<Base>`. The caller supplies that
field, including its existing explicit extension ceiling. Source polynomials
are constructed in the domain's read-only L1 `polynomials` property. Base may
itself contain previously retained real-algebraic coefficients.

Operations are requirements on small Sendable protocols. Generic admission
requirements use static dispatch; they are not invoked through `any P`.

| Protocol | Requirements / output |
|---|---|
| `ExactRealCellPreparing` | Initialize with field/variable count; recover identical domain from source; expose polynomials; bind laws and box into Source; validate and bind a Boolean program into Predicate |
| `ExactRealCellProducing` | Decompose Source with explicit limits into Partition |
| `ExactRealCellSelecting` | Select Partition with a Predicate bound to its identical Source into Selection |
| `ExactRealCellQuerying` | Obtain a cell Sample or Condition; prepare an exact query point with its field; locate a point in Partition with explicit L2 root limits; test that point against an issued Condition |

Each fallible requirement takes `inout A`, with A: ExactScalarAdmission &
~Copyable, and throws `ExactRealCellFailure`. The concrete implementation is
separate from these protocols. Read-only receipt structs are not protocols
introduced merely to abstract storage. These ports are implemented with static generic admission dispatch.

### Required Operation Shapes

All operations below additionally take the same explicit generic inout admission;
receipt types below are implemented. Initialization creates one immutable L3 context
retaining its Field and public L1 construction domain. Sources retain that L3
context. Producing/selecting/querying validate it through their own source binding,
without reading L1/L2 private contexts.

| Operation | Inputs besides admission | Output |
|---|---|---|
| Initialize | Field, checked variableCount | Domain |
| Retaining initialize | Issued Source | Identical Domain |
| bind | Original L1 laws, n exact L2 domain intervals | Source |
| predicate | Validated sign instructions, Source | Predicate |
| decompose | Source, ExactRealCellLimits | Partition |
| select | Partition, same-source Predicate | Selection |
| sample | CellID, its Partition | ExactRealCellSample |
| condition | CellID, its Partition | ExactRealCellCondition |
| point | Supplied Field, n exact coordinates | ExactRealCellSample with no membership claim |
| locate | Prepared point, Partition, L2 ExactRealRootLimits | Optional CellID; nil means proved outside box |
| contains | Prepared point, issued Condition, L2 ExactRealRootLimits | Exact Boolean or typed failure |

### Public Retained Values

| Receipt | Owner and retained meaning |
|---|---|
| `ExactRealCellSource<Base>` | Immutable source owner: Field, identical L1 domain, original laws, variable count/order, exact box and inherited depth |
| `ExactRealCellPredicate<Base>` | Identical source owner plus validated Boolean sign program |
| `ExactRealCellPartition<Base>` | Source, projection derivations, complete in-box prefix tree/stacks, full cells, original signs, root sections/sectors and attained depths |
| `ExactRealCellSelection<Base>` | Partition, identical-source Predicate and all selected full-cell offsets/truth; empty selection still retains complete coverage |
| `ExactRealCellID<Base>` | Opaque partition owner plus checked cell offset; no public raw-index initializer or cross-partition equality |
| `ExactRealCellSample<Base>` | Exact sample/query-point coordinates in one retained Field, and causal depth; it establishes no whole-cell bound |
| `ExactRealCellCondition<Base>` | Partition owner, cell ID and complete ancestral section/sector condition with root addresses and sign evidence |
| `ExactRealCellLimits` | Explicit nonnegative maximumStoredCells and maximumRootsPerStack; no guessed default |

Cell handles expose read-only axis, parent ID, section/sector kind,
parameter-space dimension, source signs, matching projection law/sample sign
arrays (including the derivative closure) and attained depth.
Section addresses retain the whole-prefix union-law binding and distinct root
ordinal; sector addresses retain neighboring section addresses or infinity tags.
A zero-dimensional full cell's sample is its exact point. A positive-dimensional
cell's sample is one witness, never the cell's extent.

## Contracts and Invariants

### Source, Domain and Predicate

Variable slots x0...x(n-1) have mathematical identity only. The caller retains
TUV/UVUV roles and authored chart identity. The source uses one identical L1
polynomial owner; public L1 validation precedes public-term traversal. Foreign
polynomials require explicit L1 import/construction before binding. Original
law order and duplicates are preserved; derived projection deduplication never
changes predicate indices or original signs.

The requested box has exactly n L2 ExactRealRootInterval<Field.Value> entries.
L3 revalidates finite endpoint values/order/inclusion, admits each depth and
retains emptiness. Bounds and source coefficients enter the same supplied
field's admitted own/ancestor path. Infinite bounds are tags. Domain boundary
laws are included in projection so clipping is a whole-cell decision. An empty
axis proves an empty box; an open singleton is empty, a closed singleton is a
section. Finite windows never stand in for infinite requested domains.

The Boolean program uses an English-named enum of literal, polynomial sign
comparison, not, and, and or instructions. Sign comparisons are zero equality,
non-equality, strict order or non-strict order. Native Array stores a validated
postfix program. Binding checks every law index, stack underflow, checked stack
counts and exactly one final value; it retains the identical source owner.
Scalar/operation failure never becomes false. Selection requires the same source
owner as its partition. A changed law list or new boundary requires new source
binding and a complete refinement/decomposition, not silent reuse of old truth.

### Projection and Whole-Cell Sign Authority

Use one full projection-and-lifting algorithm. At each descending axis retain
active laws and their derivative closure, every coefficient and nonzero reductum,
principal subresultant coefficients for a reductum and its derivative and for
pairs of reducta, and all already lower-variable laws. Retain exact provenance
and the mapping to original laws. No reduced projection that assumes nonvanishing
or well-orientedness is selected as the baseline.

The classical projection/lifting basis is Collins' real decomposition method;
[Strzebonski, Sections 3.1 and 3.3](https://arxiv.org/pdf/1405.4925) provides explicit
coefficient/degree-drop and principal-subresultant delineability arguments.
L3 uses exhaustive retained conditions rather than that paper's local selection,
irreducible-factor input assumption or restart strategy. Its obligation is to
prove the induction below using the exact retained coefficient/rank conditions.

L1 has no public principal-subresultant operation. This is not a hidden lower
prerequisite: L3 constructs the appropriate Sylvester truncation matrices from
public terms, and computes their determinants using L1 adding/subtracting/
multiplying/dividedExactly. Fraction-free elimination admits matrix slots,
pivots, copies, overflow and zero-pivot row swaps. This is an internal projection
certificate computation, not a second public polynomial algebra. Its j=0 output
must agree with L1 resultant; higher minors must satisfy independent rank/GCD
fixtures, including repeated/shared factors and specialization degree drops.

For degrees m and n and 0 <= j < min(m,n), use n-j shifted rows of the first law
and m-j of the second, with descending powers. The highest m+n-2j columns form
the principal coefficient minor; row order is fixed in provenance. Constant and
zero laws are handled by their coefficients and degree receipts, not illegal
negative-size matrices. Exact positive normalization may deduplicate projection
zero sets; original sign laws are never normalized without their sign mapping.

The lifting induction owns these proof obligations:

1. The parent is a connected cylindrical cell with all required projected
   coefficient and rank signs constant on its whole extent.
2. Those coefficient signs fix specialization degree or prove that every
   coefficient is identically zero on the parent. A zero sample is insufficient.
3. The retained principal-subresultant zero/nonzero pattern fixes repeated-root
   and common-root degrees. For the nonnull families this justifies continuous,
   ordered sections, constant root multiplicities and equal-or-disjoint branches.
4. The complete L2 sample fiber therefore determines every section/sector over
   that whole parent. Root ordering/derivative signs retain the branch address.
5. Original-law signs evaluated at exact samples extend over the whole child
   only through those induction witnesses. They never acquire authority from
   sampling alone.

A globally zero law and a nullified fiber have constant zero sign and add no
section. Degree drops use the retained coefficient and reductum witnesses. Such
mandatory cases cannot be classified unsupported or omitted. An unestablished
witness fails; it never publishes a complete partition.

### Lifting and One Coefficient Family per Sample

Start at the unique R^0 prefix. At ascending axis k, its sample has one Field and
k coordinates. Reindex active public polynomial terms and explicitly import
original coefficients into that sample field; compute the specialized
one-variable coefficients with L0/L1 operations. Each evaluation/transport keeps
both receipt depths. Any later-variable power at this level is invalid evidence.
No L1 context, internal field getter or private coefficient helper is inspected.

For one stack, multiply the nonzero, positive-degree specialized laws in a single
L1/L2 root domain. L2 isolates its complete distinct root union over the real
line under the same caller admission and explicit per-stack root limit. A
constant product has no roots. A wholly nullified family creates one open
sector. This avoids independently adjoined sibling root fields; it does not
infer common roots from matching numerical brackets. Union-law multiplicity
is auxiliary and must not be reported as source contact multiplicity.

Retain all root receipts and refine neighboring brackets until their finite
bounds have a strict gap. A bounded sector sample is the midpoint of that gap
in the parent field. Outer samples use finite root bounds plus/minus one; with
no roots use zero. Samples are proved strictly interior by exact signs. Keep
refinement receipts and depths; never recompute an old root under a reset quota.

For a section, first inspect retained degree-one source laws in the same
stack. A linear law whose zero at the selected root is proved by L2 supplies
its exact parent-field value -b/a, so the sample stays in its existing field.
Otherwise adjoin its selected root to the identical prefix sample field with
L2, explicitly embed every earlier coordinate into the child and append the
generator. This is an applicability proof before adjoining, not a retry after
resource failure. For a sector, remain in the parent field and append the exact
interior sample. Sibling samples can retain different immutable child owners;
L3 never mixes their scalars. Source coefficients always enter by the verified
ancestor path. Extension policy is the supplied L2 field-family policy; L3 does
not invent another or ignore extensionLevelLimit.

A section preserves parent dimension; a sector adds one checked dimension.
Box boundary signs keep all permitted children and exact endpoint sections.
A child outside the box is discarded only with the whole-prefix boundary
witness; no later suffix is searched. These exclusions and complete retained
in-box stacks establish coverage of the requested box. Predicate-false cells
are retained in the partition; selection runs only after that partition is
complete. No early predicate pruning or partial-CAD optimization is required.

### Conditions, Identity and Point Location

A cell condition is its ancestral cylindrical definition, with section root
functions or strict sector inequalities, projection binding and derivative
signs. Neither an arbitrary sign vector nor a sample identifies a cell. Two
cells with the same XYZ image or close coordinates remain distinct. Cell IDs
are local to one immutable partition; reissued partitions need explicit new
identifiers, not guessed equality.

Point preparation validates all coordinates in one caller-supplied Field and
retains depths. Location proves that original coefficients embed into that
field from the partition's source owner, checks the requested box, then descends
the retained stack definitions. This compatibility check includes importing a
source-field unit through public L2 importing, even with no source terms or
finite bounds, so a constant/empty relation cannot bypass field-family identity. At each supplied exact prefix, specialize the
retained nonnull union law, use L2 roots, and use L2 signs of xk-queryCoordinate
to locate an exact section or open sector. The retained root ordinal, coefficients
and parent delineability justify the correspondence with the original stack.
This does not compare scalars from unrelated siblings or invoke a compositum.
A compatible descendant query field is allowed; an unrelated query field fails.

A point outside the box returns nil only after exact exclusion; a valid inside
point must map to exactly one full cell. A missing/ambiguous stack is invalid
coverage, not nil. Condition membership uses exact location and the issued
cell identity. Foreign IDs, conditions or selection/source pairings fail.
Queries that reconstruct root stacks take the existing explicit L2
ExactRealRootLimits, applied unchanged to each stack. Sample/condition access
creates no cell graph and takes no redundant cell-count policy. Every query
uses fresh caller admission and retains the stored proof depth. Immutable evidence owns no prior mutable allowance.

### Handoff to Swift-CAD

The current Native equations remain a reference for later integration:

| Consumer | L3 relation | Responsibility after L3 |
|---|---|---|
| CS | Three homogeneous coincidence laws in t,u,v; denominator nonzero and exact box | Connect cells; evaluate original XYZ; preserve all TUV and classify image/contact |
| SSI | Three homogeneous coincidence laws in u1,v1,u2,v2; guards and box | Connect cells; establish XYZ image/fiber dimension and all UVUV correspondence |
| Continuous overlap | Same complete CS parameter relation with positive-dimensional cells | Establish maximal projected intervals and geometry, not sample ranges |
| Boundary clipping | Original raw laws plus boundary sign conditions | Preserve source/chart identity and clipped geometric components |
| Real decomposition requirement | L3 partition/selection | Closure and connected-component completion remain separate |
| Projected/self contact | Exact original contact laws and proved identity-exclusion predicates supplied by consumers | Interpret projection/contact and authored shared-boundary identity |

L3 can additionally partition a graph relation supplied by the geometry owner
with XYZ slots first and parameter slots later. It guarantees that new relation's
cells and prefix dimensions. It does not invent the graph, decide its physical
meaning, or equate parameter dimension/Jacobian rank with geometric image
dimension. More than four slots require no new L3 mathematical capability.

## Runtime Flows

```mermaid
sequenceDiagram
    participant Caller
    participant L3
    participant L1
    participant L2
    Caller->>L3: bind original laws / box / predicate, one admission
    L3->>L1: validate owners, derivatives, projection certificate arithmetic
    L3->>L3: retain descending full projection witnesses
    loop Every admitted in-box prefix
        L3->>L1: exact specialization via public terms and operations
        L3->>L2: complete union roots and refinement, same admission
        L3->>L2: explicit adjoining / ancestor transport for sections
        L3->>L3: whole-prefix witness, complete child stack, exact signs
    end
    L3->>L3: coverage checks and final cancellation
    L3-->>Caller: complete immutable Partition or typed failure
    Caller->>L3: select partition with identical-source Predicate
    L3-->>Caller: complete Selection or typed failure
```

Projection witnesses alone cannot escape as a complete partition. Building
scratch progresses through validated source, projected levels, lifted levels,
coverage checked and final checkpoint. Throw destroys scratch while preserving
caller counters and every previously issued immutable receipt.

## State, Ownership, and Lifecycle

| Logical state | Owner/lifetime | Access and retention |
|---|---|---|
| Source field, laws, predicate, box | Immutable ARC owners, retained by receipts | Same Sendable contract on every target |
| Projection levels / cell graph / root evidence | Partition owner and immutable arrays | Prefix/stack offsets stored internally; public handles retain owner |
| Sample coefficient towers | L2 immutable parent-only owners | Children retain ancestors and exact coordinates; no sibling mutation |
| Selection | Immutable owner retaining partition/predicate | Selected offsets share partition data rather than copying cell payloads |
| Work queues, matrices and construction buffers | Invocation-local native Array/COW | Exclusive synchronous construction; admit materialization/COW before mutation |
| Admission | Caller-owned exclusive inout borrow | Same cumulative L0 ledger through all stages and subqueries; never stored in receipts |

Internal graph records hold indices, not handles that retain their own partition,
preventing an ARC cycle. Public IDs/conditions/views retain the partition. Public
root and polynomial owners outlive the caller's original shape/field variables.
Read-only Array buffers are shared; no unsafe view can outlive its owner.

Use native structs/enums, immutable final classes, Array/COW and generic static
dispatch. No mutable global cache, actor, scheduler, custom allocator or type-erased
public adapter is needed. A fixed internal non-Sendable invocation handle may
follow the scoped L2 forwarding pattern to keep recursive admission specialization
finite in Embedded. Any new unsafe borrow needs its own minimal owner/lifetime,
non-escape and ASAN evidence; private L2 forwarding types are not an L3 port.

## Failure, Concurrency, and Constraints

ExactRealCellFailure distinguishes invalidSource, invalidDomain,
invalidVariable, invalidPredicate, incompatibleDomain, invalidCell,
invalidCoverage, countOverflow, cellLimit, unresolved, and preserved scalar,
polynomial and root causes. Invalid projection witnesses are invalidCoverage.
All lower resource/cancellation/extension failures retain their causes. Typed
failure is not a successful exclusion, constant zero or predicate false. A
resource failure does not trigger another solver or a fresh allowance.

| Constraint | Fixed owner and semantics |
|---|---|
| Work/storage | Existing L0 admission; charge source traversal, projection generation, all matrix slots and determinant arithmetic, reindexing/transport, stacks, roots, selections, queries and publication |
| Payload sizing | Public L0 exactScalarPayloadBytes with checked counts; cumulative logical payload, not RSS or guessed allocator capacity |
| Value/coefficient depths | Preserve both lower receipt axes; L3 geometric-coordinate refinement uses value axis; existing coefficient depths remain admitted |
| Stored cell limit | Explicit maximumStoredCells applies to all retained prefix/full records, including predicate-false cells and the R^0 record when materialized |
| Stack root limit | Explicit maximumRootsPerStack passed unchanged to L2; exhaustion prevents complete partition or location publication |
| Extension level | Caller-supplied L2 field policy; checked at actual adjoining, not a hidden new default |
| Cancellation | Entry, causal work, after the last admission callback, before every result or Boolean/optional publication |
| Native stack | Projection axes and prefix queues are iterative; L2 coefficient descent is bounded by its supplied extension policy |

Count policies are checked nonnegative Int values with no defaults. Zero stored
cell capacity admits a proved empty box but refuses a materialized nonempty
partition; count zero roots permits rootless stacks. Overflow refuses before
allocation or index arithmetic. Budget selection is caller/deployment policy;
fixtures measure their required allowance without changing production contracts.

All targets retain the same owner, Sendable, state, failure and admission contract.
There is no Embedded-only raw mutable state or no-op synchronization. Independent
readers share immutable receipts and use distinct exclusive caller admissions.
WASM synchronous evidence must not be generalized to untested multithreading.

## Verification and Change Impact

The test owner is Tests/L3RealCellVerification. It must compile the actual production L0/L1/L2/L3 source
inventories through an isolated SwiftPM graph. No higher CAD target is needed.
Use fixed Swift 6.4.0/matching SDKs, dedicated cached paths, explicit timeouts,
Native behavior/ASAN and normal/Embedded WASM compile/link/runtime evidence.
Lower evidence is reusable only when its hashes and consumed assumptions match.

| ID / invariant | Refutable behavioral completion evidence |
|---|---|
| C1 exact source binding | Owner mismatch, wrong slots/box count, foreign endpoint, lost depth, invalid postfix/index; zero-variable true/false cases |
| C2 projection authority | j=0 minors match L1 resultant; independent higher-minor/GCD degree expectations; repeated/shared factors; all coefficients/reducta and original-index mappings retained |
| C3 whole-cell lifting | Degree drop and nullification such as xy=0 and xz+y=0, including positive-dimensional prefixes; samples on both sides within each emitted cell agree with proved signs, with proof structure checked separately |
| C4 complete requested coverage | All endpoint flags, closed/open singleton, empty box, both infinities, no active laws, identically zero/nonzero constants; exact expected stacks/roots/selected cells, not only presence assertions |
| C5 singular and mixed real sets | Crossing, cusp y^2-x^3=0, isolated x^2+y^2=0, repeated (x-y)^2 and union of a line with an isolated point; finite samples/complex-ideal rank alone cannot pass |
| C6 exact identity / conditions | Every produced sample locates in its original cell; exact nonsample points obey retained section/sector conditions; foreign owner/ID refuses; separate cells with identical signs are distinguished by branch definitions |
| C7 algebraic families | Algebraic base coefficients, multiple runtime section levels, explicit earlier-coordinate transport; sibling query fails and verified ancestor/descendant query succeeds without compositum |
| C8 CAD-shaped algebraic inputs | Three-slot CS isolated/overlap relations; folded parameterization retains two UV solutions for one XYZ; four-slot SSI line/coincidence relations; a small greater-than-four-variable relation succeeds |
| C9 atomic resources / lifetime | Independent work/storage/both depths/cell/root/extension exhaustion, checked overflow, terminal callback cancellation; no partial/empty success; usable receipts after source destruction and failed queries |
| C10 portable ownership | Native concurrent immutable readers with independent admissions, ASAN scoped forwarding normal/throw/cancel paths, both WASM runtime families with unchanged storage/Sendable contracts |

C3 uses the projection induction as the whole-cell authority; extra sample points
are counterexample detectors, not a replacement proof. C8 validates algebraic
input and output correspondence only; it does not run or complete public CS/SSI.
Auxiliary derivative/projection cells can subdivide a geometric set more finely
than its connected components. That is valid L3 output and must not be reported
as duplicate geometric intersections.

Implementation order is bounded: first source/program/box and full projection
certificates; then complete lifting and retained conditions; then exact queries,
selection and cumulative portability/lifetime/resource verification. One owner
controls this directory and the future isolated test package. Stable snapshots
receive one overall review and one scoped finding recheck. This design task
creates no callable placeholders and does not authorize implementation.

L3 completion requires all C1-C10 evidence, review, coherent commits and final
snapshot correspondence. Source structure or theorem citations alone do not
establish implemented correctness. Closure/incidence performance, shape-family
coverage and public CS/SSI migration are separate tasks. Their future consumers
must verify the L3 handoff rather than reopen its internal arithmetic contracts.

Direct lower contract changes invalidate the corresponding L3 assumption and
its affected evidence. Direct parent indices must remain reachable from the
package master. No existing upper contract changes in this design: its new L3
consumer relationship is prospective. The implementation task must update the
real consumed upper contracts when it actually migrates those paths.

### Implementation Sprint I1

Source preparation, postfix validation and full coefficient/reductum/PSC projection
are implemented in this directory. Exact structural deduplication retains original
coefficients; no normalization erases provenance. Derivative, coefficient and PSC
witnesses retain their inputs and outputs. Native tests compare the zero-th PSC with
L1 resultant and a higher PSC with its known rank-deficient minor. The producer,
lifting and querying ports remain pending until their implementation sprints.

### Implementation Sprint I2

Full projection levels feed ascending complete L2 root unions. Each stack retains
its source-bound specialized laws, coefficient signs, complete root count/set,
active-law indices and branch-to-child table. These data implement the projection
induction stated above; a sample alone is never exposed as a whole-cell proof.
Immutable partition storage retains the full graph without cycles. The cell view
shares a retained index buffer and creates handles without intermediate arrays.
Native fixtures cover positive-dimensional nullification, cusp/isolated/repeated
loci, open/closed/singleton/empty boxes and exact coordinate transport.

### Boundary Laws and Auxiliary Derivative Closure

Each projection level distinguishes its incoming source/projection/boundary laws
from its retained auxiliary derivative closure. Only the incoming laws cut the
fiber into sections/sectors. The closure still participates fully in coefficient,
reductum and PSC projection and supplies exact derivative/Thom signs at the issued
samples. Original source signs are invariant on every cell; derivative signs on
sectors describe the sample, not an additional sign-invariance claim. On source
sections, the full retained pairwise rank conditions certify the Thom behavior.

This distinction avoids introducing roots of derivatives of high-multiplicity
projection polynomials as unrelated parameter boundaries. The mixed fixture
previously reached 200M work while isolating a ten-term axis-0 auxiliary union;
the corrected union contains only the required incoming-law zero sets. Resource
ceilings, complete source partitioning and all projection rank conditions stay
unchanged. Branch IDs are issued only after this complete construction.

### Implementation Sprint I3

Selection evaluates only validated source-bound programs over proved original
cell signs. Location validates the field family even on constant/empty relations,
reconstructs complete L2 fiber unions at the supplied exact prefix and finds its
retained branch through signs of x minus the query coordinate. Conditions retain
the full ancestral branch path and partition owner. All failures and final
checkpoints are propagated. Ancestor bounds are explicitly imported both during
validation and before forming projection boundary laws.

The isolated package exercises all four ports through generic protocol requirements.
[Verification package](../../../../Tests/L3RealCellVerification/DESIGN.md) owns
Native/sanitizer/portable evidence. Higher CAD consumers remain outside this task.

### Issued Prefix Handles

The public parent handle is an issued cell ID in the retained graph. Sample and
condition queries accept these prefix IDs as well as full cells. A prefix sample
has one coordinate per attained axis; location still requires a full source point.
A prefix condition tests the corresponding ancestral region intersected with the
complete requested box. Source-sign selection remains restricted to full cells.
The generic cell-query contract never turns a valid parent handle into invalidCell.
