# Original Offset Feasibility

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Own exact result-body contact admission for
Surface Offset, Thicken and the existing generated-sheet callers. No children.

## Responsibilities and Boundaries
Consume the immutable exact/volumetric result model, enumerate its owned faces,
and reject any nonstructural contact in both selected material domains. Geometry
owns source binding, complete DI products, identity exclusion and material
refinement. This owner binds the actual face and shares the caller admission.
The package-level OriginalExactSurfaceSelfContactPreparer is the shared positional
preparation owner for this validator and original embedding. Kernel's Native and
Coons adapters delegate to it before applying their existing material obligations.
No source equality or DI orchestration is duplicated across the two callers.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | default feature composition | Inject this public validator into existing callers | Failure prevents publication |
| [Shared Sheet Offset](../../CADModeling/SharedSheetOffset/DESIGN.md) | used by | OffsetResultValidating | Exact result admission | No unproved embedding success |
| [Thickened Sheet](../../CADModeling/ThickenedSheet/DESIGN.md) | used by | joint layer publication | Same original result authority | Distinct-face coverage remains mandatory |
| [Original Surface Embedding](../../CADGeometry/OriginalSurfaceEmbedding/DESIGN.md) | depends on | retained exact self residual and material query | Complete source product minus proved structural identity | Nonstructural same-XYZ UVs remain |
| [Original Boundary Clipping](../OriginalBoundaryClipping/DESIGN.md) | depends on | OriginalExactFaceBoundaryIssuer | Actual unchanged face and directed pcurves | Preserve all incident owners |

## Architecture
```text
exact result body -> actual owned face -> one source-bound Native DI cover
    -> retained complete L5 self product -> scoped structural exclusion
        -> first material AND second material -> included residual cell?
            yes: topologyFailure / no: final cancellation check -> admit
```

## Contracts and Invariants
All three public entries use the same complete receipt-consuming algorithm. Raw
model admission first obtains the actual exact BRep receipt; when cumulative
limits are selected it uses the bounded constructor under the same invocation.
A modeling-only receipt cannot authorize generated-result contact admission.

The connected Native scope is one trimmed nonperiodic Native face. Its original source
and support are prepared once, all raw chart pairs are retained, and both original
face-issued material conditions refine the existing self residual once. The
closed policy includes outer/hole boundaries. Any included residual cell rejects
the result; a complete empty result is admitted only after final cancellation.
Source equality is independent of modeling tolerance. No UV/root/branch merging,
second decomposition, rectangle approximation or solver retry is performed.

The additive Coons caller consumes the existing source-owned rational atlas,
full authored DI cover, complete issued-graph self product and scoped authored
diagonal subtraction. The source is read from the actual validated face. Complete
global residual exclusion proves exclusion on every material subset, so this
case needs no material re-decomposition or interval callback. The retained raw
and refined owners survive the query; all preparation and final publication use
the same borrowed caller admission. A nonempty global residual cannot establish
material contact without both exact material predicates: that remaining branch
returns unsupportedCapability and is not counted as general Coons completion.
The actual S-COONS-OFFSET-CALLER-01 unit-square face and Native folded rejection
control own success/failure/resource/cancel/lifetime/portable caller verification.

### Exact consumer migration and retired legacy dispatch

The supported drafted coordinate-projection case consumes Geometry's checked
OriginalDraftedSelfExclusion with the same result invocation. Complete global
original exclusion covers every actual face material subset, including holes.
The wall remains the validated face's stored source. A projection that cannot
prove the complete symbolic diagonal implication fails explicitly; it cannot
classify original contact. Distinct-face and unsupported source obligations
remain unchanged. No extra solve, private allowance or approximate angle enters.
The default owner removes its former interval callback and opaque Boolean/Loft
contact replay: they do not establish the complete material exclusion required
by this contract. Successful admission intentionally narrows to connected exact
receipts. Periodic/general-source/untrimmed products and distinct-face pairs without
complete material/shared-boundary receipts return unsupportedCapability. Those
are mandatory remaining M6 cells; refusal does not complete them. Multi-face
bodies are refused before self preparation until every unordered pair is covered.
DefaultFeatureEvaluator continues injecting the same validator into its existing
callers. This migration does not silently substitute another solver.

## Runtime Flows
Stable owned-face enumeration and checked typed storage precede source work.
The exact adapter forwards work/storage callbacks from the one invocation to
source, DI, L5, identity, face issuance and material refinement. Publication and
empty success both perform final cancellation checks.

## State, Ownership, and Lifecycle
One invocation owns checked cumulative counters in Synchronization.Mutex on
Native, ordinary WASM and Embedded. External callbacks run outside the lock.
Geometry results retain immutable source, field, relation, identity, boundary
and refinement owners through subsequent queries and COW source changes.

## Failure, Concurrency, and Constraints
Optional cumulative ceilings add no guessed allowance. Existing span/cell/root
counts, spatial depth, source depth and algebra depth are preserved or tightened
by the borrowed OriginalQueryExecution. Value/coefficient depth remains
independent. Cancel, overflow, exhaustion, invalid binding and missing coverage
propagate; none become successful absence. Unsupported family and distinct-face
products remain explicitly marked incomplete in production code.

### Limit Serialization
On targets with Codable the owner preserves all five limit fields and all twelve
nested surface option fields without clamping. Optional ceilings remain optional.
Source depth 0...16 and independent algebra depth 0...32 retain existing validation.

## Verification and Change Impact
S-TRIMMED-FOLD-01 compiles original public declarations and their actual production
dependencies under real module names. No extracted method, stub or fake provider
is accepted. Unchanged Geometry/Core/Topology products retain generation-bound
authority. Native/ASAN/ordinary-WASM/Embedded exercise the whole-cell material
oracle, three policies, actual public fold rejection, complete-empty/injective
controls, typed refusal, N/N-1 resources, cancel, COW and independent reader lifetime.

Recheck existing generated-result caller failure propagation when accepted scope
changes; add receipt consumption for each newly supported family or face pair
before removing its incomplete marker. Aggregate M6 and M4-M8 remain open.

## Canonical result-validation caller

Ordinary result validation creates one canonical execution; direct validation
borrows the supplied execution through existing source-bound native/Coons/drafted
self-contact producers. Selected cumulative work/storage and independent scalar
limits form local scopes on that same owner. The old conversion invocation and
algebra forwarding adapters are removed, not recreated. Exact/volumetric input
receipt guards and existing unsupported material/periodic/source branches remain
in force. This is the required caller binding for deleted Geometry admissions,
not additional offset source-family implementation or acceptance.
