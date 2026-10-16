# CADIR

## Purpose and Scope

The drafted-sheet caller verification compiles its real declaration dependency
closure on WASM/Embedded, retaining the same module and production declarations.
Direct imports and closure-based member projections supply Embedded witnesses;
Codable is a Native/ordinary-WASM capability, while identity, Hashable and Sendable
contracts remain common. This scoped evidence does not certify unrelated document
authoring or the whole IR target on Embedded.

`CADIR` owns source/evaluation interchange values, topology references, and
complete geometry signatures. It also owns the serialized source value for an
exact imported B-rep feature. It is a child of the [Swift-CAD package
design](../../DESIGN.md); its children are indexed below.

## Responsibilities and Boundaries

Typed source attributes and persistent document/object references are owned by
[Document Foundation](DocumentFoundation/DESIGN.md). `CADDocument` validates
that child contract before publishing or fingerprinting a source snapshot;
external links resolve only against explicitly supplied document snapshots.

[Product Attributes](ProductAttributes/DESIGN.md) owns product appearance,
physical material descriptors, explicit property overrides and layer membership.
These persistent values participate in full and justified fast validation,
source fingerprints and complete copied edits. Evaluated local/world target
resolution belongs to CADKernel.

[BoundaryContinuity](BoundaryContinuity/DESIGN.md) owns whole-boundary continuity
certification using the existing G0/G1/G2 vocabulary.

Editable gear dimensions are owned by [InvoluteGear](InvoluteGear/DESIGN.md).

Editable spatial path source is owned by the child
[SpatialPath](SpatialPath/DESIGN.md). Its explicit XYZ model does not change the
planar Sketch contract.

Operation-independent profile/curve section references belong to
[SectionReference](SectionReference/DESIGN.md). Sweep and Extrude consume this
contract. Revolve adopts the same section contract and explicit topology body
kind. Loft section controls wrap the same reference rather than a profile-only
field. Curve sections require Sheet output; the original profile-only Loft
payload is rejected rather than silently migrated.

Loft's required `profileDirection` controls correspondence, not Profile winding:
`automatic` permits alignment to choose traversal, while `forward` and `reversed`
lock traversal relative to the source loop. Curves use their shared reference's
direction and require `profileDirection == automatic`. Native persistence must
retain this distinction; a missing direction field is not silently defaulted.

This module owns the value contract for `StableSubshapeReference` and its
`SubshapeGeometrySignature`, including Codable validation. Finite curve-span
transport retains the periodicity and fundamental origin owned by CADGeometry
without approximating the geometry. SubshapeGeometrySignatureTests exercises seam-crossing
periodic values and malformed cycle rejection. Full closed edges and downstream
modeling/exchange representation closure remain owned by the topology and G5 tasks.
It also owns the product-neutral value contracts for tessellation fidelity and generic
resource admission: `TessellationOptions` and `TessellationLimits`. The
`ImportedBRepFeature` value retains one exact, validated `BRepModel` as a
source feature; `CADKernel` owns its evaluation and generated topology
identities. CADIR does not parse exchange files, evaluate a document, generate
primitives, or choose Rupa measurement methods or presentation LOD.

`TessellationLimits` is implemented in `TessellationLimits.swift`. `CADKernel`
charges an invocation against the supplied limits; this module owns only the
value contract and the package-versioned constants.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Independent Shape Source](IndependentShapeSource/DESIGN.md) | child | Complete immutable original shape graph and bounded validation | CADDocument owns its required nullable independentShapes field and real representation-to-product-definition ownership | Equality, strict encoding, source fingerprint and copied validated edits retain the whole source |
| [Portable Source Encoding](PortableSourceEncoding/DESIGN.md) | child | Explicit complete original source records | Encodes source identity on every target without reflection or Native codecs | Caller bytes, work and depth allowances remain cumulative |
| [Imported Source Translation](ImportedSourceTranslation/DESIGN.md) | child | Atomic exact source-frame affine transformation | Transforms imported curves, supports and vertices while retaining topology and original charts | A copied document publishes only after complete validation |
| [Product Manufacturing Information](ProductManufacturingInformation/DESIGN.md) | child | Typed datums, dimensions, tolerances and annotations | Persists authored semantic and graphical manufacturing meaning | Targets are original source references; transport belongs to CADExchange |
| [Product View Metadata](ProductViewMetadata/DESIGN.md) | child | Saved cameras, clipping, annotation placement and validation properties | Persists authored presentation and validation values | Rendered pixels do not establish source geometry or measurement authority |
| [Swift-CAD package](../../DESIGN.md) | parent | stable topology contract | Defines complete signature retention. | A signature is not a live topology authority. |
| [Document Foundation](DocumentFoundation/DESIGN.md) | child | typed attributes and persistent reference validation | Owns source attribute identity and local integrity. | Strict current envelope owned by CADCore; symbolic external links require explicit resolution. |
| [Product Attributes](ProductAttributes/DESIGN.md) | child | typed product attachments, explicit property graph and source validation | Owns persistent product metadata and physical material meaning, including definition selectors for common source geometry. | Required non-null source container; selector membership follows the child contract and evaluated/STEP semantics belong to consumers. |
| [Document Assembly](DocumentAssembly/DESIGN.md) | child | shared source definitions, persistent occurrence paths and proper local frames | Owns assembly source DAG and bounded structural admission. | Live local/world topology belongs to Assembly Evaluation; required nullable source uses the current envelope. |
| [CADGeometry](../CADGeometry/DESIGN.md) | depends on | analytic curve/surface validation | Validates pcurves and surfaces. | Preserve structural rejection rules. |
| [CADKernel](../CADKernel/DESIGN.md) | used by | snapshot signature construction | Supplies exact signatures for current subshapes. | No partial or Mesh-derived signatures. |

## Architecture

The document envelope retains `independentShapes: IndependentShapeSource?` as
a required nullable field. Full validation invokes the child validator with
its standard cumulative limits and the common current-task cancellation
checker by default. The document supplies its original DesignGraph as the child
validator's explicit imported body-source context. Mixed representation members
retain source SubshapeID selectors; the child checks their real imported feature
and declared solid/sheet output under the same cumulative allowance. Standalone
validation without that context cannot admit body references. The explicit caller
overload forwards independent-shape limits and its checking callback to the same child validator and returns
only its completed accounting. A bounded exchange operation charges that
accounting into its existing ledger; it neither treats accounting as a
source-bound validation receipt nor silently resets the caller allowance.
The complete source encoding participates in the document source
fingerprint. Graph-only validated edits copy this immutable source unchanged,
revalidate any retained imported body selectors against the changed graph, and
mint a fresh fingerprint memo. Native round trips must
preserve nonempty source, original laws, item/frame/map identities and text;
missing-field, old-schema, foreign-reference and fingerprint-change fixtures
own the parent composition evidence. This source does not fabricate evaluated
B-rep bodies or alter feature graph evaluation.

`ValidatedCADDocument` graph-stable replacements and appends retain the original
immutable geometry proof and invoke the child's body-source association check
before their private validated publication. This new graph-edit invocation owns
only changed-graph reference admission under the source association limits;
it does not rerun unaffected geometry or reuse accounting as a geometry receipt.

```mermaid
flowchart LR
    Topology["TopologyReference"] --> Signature["Complete geometry signature"]
    Signature --> Validate["CADIR validation"]
    Validate --> Codable["Deterministic Codable round-trip"]
    Imported["ImportedBRepFeature\nexact BRep source"] --> ValidateBRep["BRep validation"]
    ValidateBRep --> KernelEvaluate["CADKernel evaluation"]
    SurfaceFill["SurfaceFillFeature\nsource + boundary seed"] --> Validate
    SurfaceFill --> KernelEvaluate
    Bridge["BridgeSurfaceFeature\nsource + two stable boundary edges"] --> Validate
    Bridge --> KernelEvaluate
    Fidelity["TessellationOptions\nfidelity"] --> Kernel["CADKernel consumer"]
    Limits["TessellationLimits\nresource admission"] --> Kernel
```

## Contracts and Invariants

### Complete Document Validation Execution

The finite review controls also own four concrete allocation/hash boundaries:
FaceRebuild charges the stored role and signature through
`chargeStructuralComparison(using:)` immediately before Set insertion, after its
original face validation. SurfaceParameterDomain2D admits its four-Double bounds
array, mesh winding validation its three-Int normal-index array, and assembly
source counting its four-Int count array before each is materialized. These
requests use the caller's existing typed storage policy; empty/invalid guards
that precede them remain first. No source fields, numeric guards or residual
selection order change. The dedicated shared validation checks compare role
length work and exact additional typed scratch against otherwise identical
actual calls, so a missing debit cannot pass merely by measuring its own budget.

Opaque feature-ID reference validators that genuinely have an empty constant body
remain ordinary no-op guards inside an already-admitted feature visit. They do
not receive a redundant admission overload. Source-bearing references (including
`SurfaceOperationTargetReference`) forward their actual stable-signature
validation through the incoming execution. Native Revolve section encoding and
decoding choose an ordinary execution for their existing section-only guard;
admitted document validation calls that same section body directly. Square refit
validation composes the actual fit options guard with the same execution.

The only shared mutable state added by its verification is the checkpoint probe;
production scratch state remains owned by one synchronous validation invocation.

| State | Native / WASM / Embedded storage | Isolation and access | Release |
|---|---|---|---|
| Authored document, feature, reference and source values | Same value/COW owners and Sendable conformances | Immutable reads during validation; no target-specific mutation | Caller/source value lifetime |
| Parameter caches, graph stack/indexes, owner sets, assembly expansion, metadata scratch | Same local typed Array/Set/Dictionary values | Exclusive incoming execution and local variables | Normal return or throw unwinds the invocation |
| Verification checkpoint count | Same `Mutex<Int>` in a Sendable probe | Increment/read inside `withLock`; cancellation throws after unlocking | Last probe reference |


`CADDocument.validate(tolerance:independentShapeLimits:using:)` owns the complete
source-validation traversal on the supplied `OriginalQueryExecution`. Its ordinary
and explicit-check conveniences select one root execution before entering that
same traversal. A child validator never selects another root, reconstructs a
remaining-work budget, or replaces direct admission with a counting callback.
The caller budget, effective independent capabilities, active contributions and
typed resource/cancellation cause remain authoritative through publication.

The existing validation order is preserved:

```text
schema -> units -> metadata -> parameter identities/kinds/values
 -> graph structure -> graph expressions -> document foundation
 -> assembly -> independent shapes/product associations -> product attributes
 -> selection-dimension identities/values -> final checkpoint
```

| Actual owner | Preserved contract | Admission before the owned operation |
|---|---|---|
| ParameterTable and its kind/value states | Key/name identity, reference/cycle and quantity-kind rejection; all existing expression formulas and finite-value checks | Same-execution visits, actual recursive ancestry and typed cache/path storage |
| DesignGraph | Existing order, dependency, suppression, operation-contract and expression checks, including their current first-invalid-input order | Source/node/edge/expression visits and actual typed scratch collections |
| DocumentFoundation | Owner/local-reference existence, unique names, attribute values and ownership-cycle rejection | Attribute/value/reference visits and typed index/name/path storage |
| DocumentAssembly | Existing record, text, occurrence, topology, work, source-depth and algebra ceilings | Existing direct assembly expansion with the caller execution and the unchanged local limits |
| IndependentShapeSource and ProductAttributes | Existing original source/association rules and independent source, target, record, text, override-depth and work ceilings | Existing direct child bodies and their retained contribution scopes on the same execution |
| SelectionDimension and its source references | Existing reference, expression quantity, nonnegative distance and angle-range checks | Same-execution reference/expression visits and typed duplicate-ID storage |

Variable-sized processing admits its actual visits and typed storage before
iteration, reserve, insertion or append. Recursive calls use the same execution;
actual source ancestry is independent of numeric value/coefficient ancestry.
Existing fixed scalar guards, formulas, field layout, JSON schema, error values
and every local structural ceiling remain unchanged. Admission may reject before
the next source operation, but does not replace an invalid-source rejection with
success. Dynamic allocations and source traversal cannot be accounted merely by
charging a summary and then invoking an ordinary recursive validator.

The [Assembly](DocumentAssembly/DESIGN.md#contracts-and-invariants),
[Product Attributes](ProductAttributes/DESIGN.md#contracts-and-invariants) and
[Document Foundation](DocumentFoundation/DESIGN.md#contracts-and-invariants)
contracts remain the authorities for their source semantics. This composition
does not change fingerprint memoization or introduce paid drawing equality.

Verification is owned by `CADDocumentDirectExecutionChecks` and its Native and
portable entries. A nonempty valid parameter/feature/foundation/assembly/product/
dimension document must validate normally. Zero caller work or typed storage,
measured interior caller cancellation, and later exact N/N-1 controls must refuse
without completed publication on that same owner; original structural rejection
controls retain their exact causes. The initial RED uses only the already-public
`CADDocument.validate(...using:)` entry against the previously accepted IR module.

The [package deployment contract](../../DESIGN.md#supported-deployment-baseline)
owns the current-OS-only baseline. Source codecs and the validated-document
fingerprint memo use their current implementations directly, without earlier
Apple OS refusal or uncached fallback bodies. Actual Native Codable and target
capability boundaries remain unchanged. Fingerprint copies share the same
Mutex-protected completed value on every supported target; fallible computation
remains outside the critical section.

### Kernel Sampler and Subshape Validation Execution

The product-resolution validation path also forwards one caller execution from
`ProductAttributeTarget` through `StableSubshapeReference`,
`SubshapeGeometrySignature`, and the existing body/shell/face/loop/coedge/curve-span
signature validators. Each actual visit is admitted before validation and all
Geometry calls use existing direct overloads. Original identity, nonempty
collection, optional trim, endpoint, surface, and pcurve checks retain their
original order and `GeometrySignatureValidation.tolerance`. Source validation
does not replace exact signature equality or live topology resolution.

`SurfaceParameterCurveSampler.sample(_:using:)` and
`SubshapeIndex.validate(against:lineage:using:)` borrow the caller's existing
`OriginalQueryExecution`. Their ordinary entries create one independent execution
and delegate to those same bodies. They do not create an execution inside a
recursive evaluation or reset a retained source allowance.

| Owner | Preserved behavior | Direct admission |
|---|---|---|
| SurfaceParameterCurveSampler | Original knot breakpoints, midpoint subdivision, distance acceptance, append separation, depth and sample-count limits | Every curve parameter evaluation uses the caller execution; knot/recursive work, actual recursion depth, and typed output growth are charged before processing or allocation |
| SubshapeIndex | Lineage check, duplicate reference rejection, live topology membership, then exact coverage of bodies/faces/edges/vertices | Entry scans, set publication, and final coverage comparison use the same work/storage/cancellation owner |

The sampler remains a numerical containment proposal; its tolerance and samples
do not establish original-source intersection or identity. Kernel containment and
assembly callers consume these direct entries. Verification must exercise the
original sampled values and structural rejection cases together with zero-work,
storage/depth refusal, and cancellation against the same caller execution.

### Source-First Full-Requirement Composition

The current implementation phase completes all original requirement source
paths before new build, runtime verification, review, commit or main integration.
Source readiness does not constitute behavioral completion.

Cache metadata exposes a package-only paid-source validator to the Kernel cache
owner. Its supplied fingerprint is computed from the same immutable document
and requested tolerance once in that invocation; cache-provided or foreign
fingerprints are not authority. Public validators retain their complete source
fingerprint computation. This port shares source work across body caches without
changing their source/configuration/failure contract.

Source value storage is common across Native, WASM and Embedded. Native
Codable conformances and decoder/encoder witnesses are conditional transport
adapters; they neither replace common values nor weaken Sendable or isolation.
`FeatureOperation.bridgeSurface` alone retains its immutable payload indirectly.
Four complete stable geometry references make this the largest operation value;
inline storage otherwise expands the operation and its command/document parents
beyond the WASM engine's function-parameter limit. Compiler-owned ARC storage
preserves value equality, Hashable, Sendable, case matching and the existing
explicit source/Codable fields. Construction or rewriting allocates a box;
plain enum copies and case reads share it. Source authoring has no incoming query
execution, so this allocation is not reported as paid geometry-query storage.
Other operation cases keep their existing inline storage.

Persistent-map consumers import their actual HashTreeCollections dependency in
the files using its operations and conformances. The target declares that same
existing package product directly. Document cancellation sites use CADCore's
[current-task checker](../CADCore/CurrentTaskCancellation/DESIGN.md) with identical
failure and task semantics across targets. Sketch chain ordering uses an
exhaustive reference-case/ID/index formatter retaining the existing Native
lexicographic keys; runtime reflection cannot define a portable ordering key.
Portable collection accessors use direct typed closures where Embedded does not
provide key-path runtime support; the owning collection, lazy evaluation and
element order remain unchanged.
Document metadata timestamps retain finite seconds since the existing reference
date in common storage. Explicit Native Date adapters retain their wire meaning.
Portable document authoring obtains wall-clock time through a fallible C clock
boundary, or accepts explicitly supplied metadata. Clock failure is an error,
never an invented timestamp. The metadata remains excluded from geometry source
identity exactly as before.

`ExtrudeFeature.draftDirection` retains the optional independent pull direction
in the source frame. A supplied vector is finite and nonzero; evaluation
normalizes it once. Nil derives the pull direction from the extrusion axis.
Drafted walls satisfy the original wall-normal angle against that pull
direction throughout the native section, with the continuous solution branch
from the undrafted wall. The expression angle and the pull direction remain
distinct authored inputs through persistence and reference remapping.

`TessellationOptions.faceOverrides` retains face-specific geometric fidelity
beside feature-specific fidelity. Override values cannot contain another
override map. Face identity is resolved against the actual evaluated snapshot
by the mesh owner; unknown faces fail explicitly. Shared edges must satisfy
every incident face's requested bounds under one original caller allowance.
The complete options value participates in derived-artifact identity.

`BridgeSurfaceFeature` retains separate boundary continuity levels, positive
dimensionless tensions, optional positive width in source length units, and
optional stable supporting-wall face references. A nil width derives its law
from the original boundary separation; nil wall references use original
incident support ownership. Every explicit wall joins the source dependency
list and stable-reference remapping. Positional defaults preserve ordinary
bridge authoring; tangency/curvature success requires the modeling owner's
whole-boundary certificate and actual trimming against the retained walls.

Product manufacturing information and saved-view/validation metadata remain
inside the product-attribute source container. Canonical source fingerprints,
validated copied edits and Native persistence retain their complete meaning. Independent representations retain original product-definition associations and validate them against the same document assembly under the original source allowance.
The new source format is development schema 0.13.0; earlier schemas do not
silently acquire absent required source metadata.

### Feature references

`FeatureOperation.mapFeatureReferences` is the single enumeration of the feature
references an operation carries: sections, curve outputs (including Bridge
Curve endpoints), Boolean/sweep/pattern/topology targets, paths, guides and
stable subshape references. `referencedFeatureIDs` and
`remappingFeatureIDs(_:)` derive from it, and `FeatureNode.remappingFeatureReferences`
adds the node inputs. The switch is exhaustive per operation; self-contained
source geometry (sketch, spatial path, PolySpline, constrained and B-spline
surfaces, imported B-rep, primitive, patch surface, involute gear) names no
feature. Every non-reference field is carried over unchanged, and a reference
without a replacement is a typed `FeatureEvaluationError`. Consumers that clone,
fingerprint or trace graphs use this contract instead of enumerating payload
fields. `FeatureOperationReferenceTests` proves enumeration, round-trip
preservation, Bridge Curve endpoints and refusal.

`FeatureNodeFactory` derives Extrude output roles from `resultKind`: `.solid`
produces `.body`, and `.sheet` produces `.sheet`. The native package shape
validator must preserve that field through save/load, as verified by
`ExtrudeSourceRoundTripTests` using exact document reevaluation.

Extrude owns one `section`, whose input port is derived from its reference kind.
A curve section produces only a sheet; requesting a solid is an invalid graph,
not permission to close the curve. The canonical payload requires `section` and
`resultKind`. The former profile-only payload is rejected explicitly rather than
decoded into a default section. The profile initializer remains an authoring
convenience that constructs `.profile`, not a second source representation.

Extrude retains a signed end position in `distance` and an optional signed
`startDistance` (zero when absent), measured along its resolved extrusion axis.
Its shared `resolvedAxialRange` resolves units, finite coordinates and a span
above modeling tolerance, including reverse-only and same-side intervals.
Symmetric mode retains its positive total-distance meaning and rejects an
explicit start position. Both expressions participate in dependency invalidation
and native package replay. Geometry, measurement and editing consume this same
range contract; draft and wall offsets are separate controls.

Revolve likewise persists `section` and required `resultKind` (`BodyKind`).
Curve sections require Sheet output. Graph input/output roles, native package
validation and evaluated topology must agree with those values; old profile-only
Revolve payloads are explicitly rejected. A profile authoring initializer builds
the same canonical value, with Solid as its default output.

Sweep source optionally retains a length-valued `approximationTolerance` and
`twistLaw` containing `SweepTwistKnot(position:angle:)` values. Omission preserves
the previous exact-only behavior. Positions are finite and strictly increasing
from 0 to 1; resolved angles start at 0 and end at the resolved `twistAngle`.
All expressions participate in dependency tracking and canonical source encoding.
Construction and proof belong to
[CertifiedTwist](../CADModeling/CertifiedTwist/DESIGN.md).

`TessellationOptions.featureOverrides` is display fidelity keyed by output feature,
not source geometry. Overrides contain no further overrides. Document evaluation
resolves live body subshapes to their owning feature, tessellates each requested
quality under one cumulative resource budget, and records the complete option set
in cache identity. Direct mesh tessellation requires resolved options without
feature overrides. Missing serialized overrides mean the existing global quality.

`FilletFeature.allEdges` selects the complete current target edge set without
retaining geometry signatures from an earlier dimension. It is mutually exclusive
with explicit `edges`; omitted data decodes as false for compatibility. The supported
all-edge domains are an orthogonal box, a circular cylinder, and a convex prism
extruded perpendicular to a cap profile of straight segments and tangentially
joined circular arcs; other bodies fail explicitly.
The radius remains exact CAD source. Display subdivisions are not fillet source.

`SurfaceFillFeature` retains a source feature and one stable reference to an
edge on that source. Evaluation resolves the complete open boundary loop from
current exact topology and produces one separate `.sheet` output; it never
replaces the source body. The edge is only a loop seed, not a tessellated
approximation of the boundary. Boundary order is resolved from vertex
connectivity. Unsupported, stale, ambiguous, or non-closed boundaries fail
explicitly.

`BridgeSurfaceFeature` retains two stable edge references and the orientation
choice for the second edge. Every distinct source is a declared graph input in
boundary order. References resolve to distinct current open-boundary edges of
their respective evaluated bodies in a common coordinate frame.
Evaluation derives exact trimmed curves from the current B-rep and emits a
dependent `.sheet`; inline copied curves are not source authority.

`ExtrudeFeature.resultKind` selects which body a linear extrusion of a closed
profile builds, and it is the only thing that separates the two: a `.solid`
extrusion caps both ends of the swept wall and sews a solid, a `.sheet`
extrusion leaves both ends open and sews the wall alone. The profile is the
same value in both cases, so the flag lives on the feature rather than on the
profile it consumes. Omitted data decodes as `.solid`, which is the body every
document written before the flag existed carries. The graph contract follows
the flag the way the sweep's does: a `.solid` extrusion declares exactly one
`.body` output and a `.sheet` extrusion exactly one `.sheet` output, so the
role a consumer reads from the node and the body the evaluator builds cannot
disagree. A `.sheet` extrusion of a profile with more than one boundary loop
builds one sheet body of disjoint shells, one per loop, and that is a valid
body rather than a defect: the shells bound no volume between them and none is
claimed.

1. A stable signature retains body, shell, face, loop, coedge, edge, vertex,
   surface, curve, trim, orientation, and pcurve data required for comparison.
2. Validation rejects invalid IDs, empty required collections, malformed
   geometry, nonfinite values, degenerate trims, and wrong-surface pcurves.
3. Encoding validates before writing; decoding validates after reading. A
   successful JSON round-trip preserves the complete signature, not merely its
   topology kind or identity.
4. `TessellationOptions` contains only geometric fidelity inputs and remains
   the identity of the requested sampling profile. It is not a viewport or
   Product policy. `linearTolerance` is the accuracy bound: the distance from
   an emitted segment or facet to the exact curve or surface it samples.
   `angularTolerance` bounds how far the exact tangent or normal turns across
   one segment or facet; it keeps features that are small against the chord
   bound round, and never stands in for the chord bound. `maxEdgeLength`
   bounds a segment's or facet side's length. A refining path satisfies all
   three together (see [CADKernel](../CADKernel/DESIGN.md#tessellation-fidelity)).
   `TessellationOptions.standard` pairs a 0.1 mm chord bound (`1.0e-4`) with
   an angular bound of one turn divided by 63.5: at most 2π/64 of turning per
   segment or facet, 64 per full turn. The turn is divided by 63.5 rather than
   64 so a span that is an exact fraction of a turn does not round up to one
   more segment. Above a radius of about 8.3 cm the chord bound governs; below
   it the angular floor keeps small round features round. Accuracy never
   depends on this floor, so any feasible value is correct; 64 per turn is the
   chosen default, and a caller that needs smaller features finer passes its
   own options or per-feature overrides. The value must be
   feasible: a facet whose normal turns by at most θ covers at most a solid
   angle of order θ², so a closed doubly curved surface needs on the order of
   4π/θ² vertices under any triangulation. The former `1.0e-3` needed about
   12.6 M vertices for one sphere, beyond `TessellationLimits.standard`, and
   appeared to fit only while trimmed spherical faces were fanned from one
   interior point without refining their interior. `.standard` must admit
   twelve complete spheres of 1 m radius under `TessellationLimits.standard`,
   the assembly size the limits were sized for; a change to either default
   re-runs `TessellationStandardFeasibilityTests`.
5. `TessellationLimits` contains only generic checked ceilings for cumulative
   vertices, indices, triangles, and estimated bytes for one complete
   tessellation invocation. It validates positive, representable limits but
   does not select values or estimate CAD-specific geometry. The ceilings are
   `Int`, so a nonfinite or unrepresentable limit cannot be expressed.
6. A caller may lower `TessellationLimits.hardCeiling` but never widen it.
   `validate()` rejects any dimension that is not positive or that exceeds the
   hard ceiling, and `lowered(to:)` is the only composition offered, so no
   consumer can raise the package maximum by constructing its own limits.
7. The hard ceiling and default limit values are selected from the measured
   Swift-CAD fixtures recorded below and versioned by the package; this module
   does not choose product-specific requested values or embed guessed values to
   make a particular Rupa scene pass.
8. `TessellationUsage` is the resource account of one materialized `Mesh`. It
   is derived from the artifact by `init(mesh:)` — never declared independently
   by a producer — and `validate()` rejects a value no invocation could have
   produced. `firstResourceExceeding(_:)` names the first dimension a usage
   outgrows, so a request states its ceiling and the usage answers it.
   The in-flight budget is not a second artifact contract: `CADKernel` charges
   each actual vertex/index growth immediately before the corresponding output
   append. An evaluator may reserve this usage for retained meshes when it asks
   for incremental tessellation; the production tessellator seeds its checked
   budget with that reservation. A normal-consistency fallback that duplicates
   three corners is charged as three vertices and their bytes before those
   corners are appended.
9. A `MeshCache` entry is scoped to the artifact configuration it records.
   Reuse requires the source fingerprint, the design and parameter revisions,
   the kernel version, the modeling tolerance, the complete
   `TessellationOptions`, and the `MeshArtifactPurpose` all to match the
   request, and requires the recorded usage both to describe the stored mesh
   and to fit the requested `TessellationLimits`. A mismatched purpose is
   `meshCachePurposeMismatch`, a usage above the requested ceiling is
   `meshCacheExceedsLimits`, and every other disagreement is `staleMeshCache`
   with the reason. An artifact is therefore never shared across consumers that
   happen to agree on fidelity, and a narrow request never inherits a wider
   ceiling through the cache. The cache contract is checked by the evaluator
   only for bodies it is actually reusing; exact B-rep state can remain reusable
   while a mesh artifact is refused. `DocumentCaches.validateFreshness` remains
   a standalone artifact-table validator and reports a purpose mismatch; an
   evaluator receiving that artifact as a reuse hint may instead discard the
   mesh and regenerate it for the requested purpose.
10. `MeshArtifactPurpose` is the kernel artifact authority. CADIR does not
    define or infer a Rupa representation purpose, and no consumer may relabel a
    cached kernel artifact to satisfy a different purpose. Rupa may deliberately
    use the same kernel `.unspecified` purpose for its unspecified representation,
    but that is an adapter decision outside this module.
11. `BRepCache` records no tessellation input, so exact B-rep reuse is
    independent of tessellation fidelity: the same document evaluated at two
    fidelities yields the same cached model, fingerprint, and revisions while
    yielding different meshes.
12. `ImportedBRepFeature` is a source operation, not a cache or a Mesh
    artifact. It owns one exact, ownership-closed `BRepModel` and the
    embedded `sourceUnits` declared by the exchange file. The model's
    coordinates are already normalized to the kernel's internal frame; the
    unit value preserves source display semantics for an adapter. The feature
    accepts no feature inputs and validates the complete model and units at the
    requested modeling tolerance. Exchange readers publish one imported
    feature per source body, so each feature has one `.body` output for a
    solid or one `.sheet` output for a sheet while the exchange result may
    retain the complete source model separately.
    CADKernel creates feature-scoped body, face, edge, and vertex identities
    for evaluation; it never mutates the retained source IDs. The source model
    is never relabeled as a generated primitive and is never replaced by a
    tessellated Mesh.
13. `CADDocument` retains the existing strict schema-version contract. The
    imported operation is encoded through `FeatureOperation` and therefore
    participates in the current document source fingerprint; unknown operation
    kinds or fields remain typed decoding failures. A schema-version migration
    is not inferred from the new operation and must be introduced explicitly
    if the package later changes the document envelope.
14. Caches are in-memory evaluation state. `CADExchange` writes the source
    document, never `DocumentCaches`, so the `Codable` conformance carries no
    on-disk format and adding a recorded field needs no migration.
15. `CADDocument.translatingSources(by:tolerance:)` must either translate every
    source-owned geometry value or fail with a typed
    `KernelErrorCode.unsupportedCapability`. Imported exact B-rep translation
    is owned by [Imported Source Translation](ImportedSourceTranslation/DESIGN.md),
    including the public ImportedBRepFeature.applying affine source authority, retained original charts and source topology identities.
    Translation works on a local document copy and
    publishes only after all operations validate; a mixed document therefore
    cannot expose a partially translated result.
    Source implementation does not establish the imported-BRep capability's
    runtime completion; the public source translation path needs its deferred
    behavioral evidence before that status changes.
16. `Mesh.faceRuns` is the mesh's record of which B-rep face generated which
    triangles. It is a value carried with the mesh, not a separately indexed
    side table, so the provenance cannot be separated from the triangles it
    describes and cannot be rebuilt per interaction. Runs are ordered by
    emission and are contiguous: the triangles a run describes are the
    `indices` triples `[start, start + triangleCount)` where `start` is the
    sum of the preceding runs' counts, so a consumer resolves triangle `t` by
    a single ordered scan and needs no dictionary. `validate(tolerance:)`
    accepts either no run at all or a complete partition, and rejects an empty
    run, a repeated face, and a covered count other than `indices.count / 3`.
    A partial partition is refused because it would let a consumer resolve a
    triangle to the wrong face. No run means the mesh carries no face
    provenance, which is the truthful state of a mesh an exchange reader built
    from a triangle soup; it is not a fallback that a CAD consumer may accept
    silently. `CADKernel` owns which face produced which run.
17. The source fingerprint is SHA-256 over the common portable binary source
    payload (`sha256-cad-source-binary-v1`). The [source encoding child](PortableSourceEncoding/DESIGN.md)
    owns its explicit typed record, enum, field and container framing. Identity
    includes the original design graph, parameter source, document foundation,
    product attributes, independent shapes, assembly, selection dimensions,
    schema and units. Authored sketch entity order is semantic. Document display
    identity, display metadata timestamps and cache revisions are excluded.
    Canonical maps and unordered collections use encoded source keys; integer
    words are big-endian, floating-point values retain their original bit
    patterns, and UTF-8 strings and optional values have explicit framing.
    Native Codable transport does not define source identity. An explicit
    encoding allowance always admits a new invocation cumulatively; memoized
    identity cannot waive a stricter caller allowance. A `ValidatedCADDocument`
    computes it at most once, on first use, and every copy of that validated
    document reads the same value
    (`ValidatedCADDocumentSourceFingerprintMemo`): the validated document never
    changes, so the evaluation engine, a cache seed and a freshness check
    reading one validated document hash its source once. A mutation
    (`replacingGraphStableFeatures`, `appendingFeatures`) is a new validated
    document with an empty memo. All targets use the same `Mutex` and immutable
    identity storage. Computation
    and fallible encoding execute outside the critical section; publication
    through the memo retains a completed value only. `CADDocument.sourceFingerprint(tolerance:)`
    validates a new document and therefore hashes again; a caller that already
    holds the validated document reads it there. `SHA256Digest` is written in
    Swift so the fingerprint exists on WASI, and hashes in place: one stack
    message schedule serves every block and only the padded tail is copied.
    `SHA256DigestTests` checks the published vectors and every padding
    boundary against the platform digest, and
    `ValidatedCADDocumentMutationTests.aValidatedDocumentComputesItsSourceFingerprintOnce`
    checks the memo, its sharing by copies and a mutation's fresh value.
19. `BRepCache` and `MeshCache` record the source they were made from as a
    `CacheSourceFingerprint`: the fingerprint value, or the validated document
    an evaluation evaluated. `sourceFingerprint` is `get throws` and hashes that
    document only when first read, once for every cache of the evaluation (the
    validated document's memo), so a materialized evaluation no longer hashes
    its source. Encoding writes the value, decoding reads it, and
    `replaceSourceFingerprint(with:)` records another value.
    `DocumentEvaluatorIncrementalTests.anEvaluationHashesItsSourceOnlyWhenACacheFingerprintIsRead`
    checks the deferred hash, agreement across caches, freshness and the
    Codable round trip.
18. `CADDocument` (with `ParameterTable` and `DocumentMetadata`) is
    `Equatable` member-wise over every stored value. A document equals what its
    own encoding decodes to exactly when the encoding reproduces it, so an
    application proves a persisted round trip by comparing the two documents
    rather than hashing both; the fingerprint stays the semantic identity for
    caches and provenance.
    `ValidatedCADDocumentMutationTests.aDocumentEqualsItsDecodedEncodingAndNothingElse`
    checks the round trip and envelope changes.

### Curve continuity levels

`CurveContinuityLevel` runs G0 (position), G1 (tangent), G2 (curvature vector)
and G3 (`curvatureVariation`: the curvature vector's arc-length derivative).
`CurveContinuityTarget.frame` adds that derivative, d(κN)/ds along the frame's
oriented tangent, wherever the curve has an exact third derivative and leaves it
nil elsewhere; a frame without it never counts as G3. G3 compares the two
derivatives within the curvature tolerance's value
(`CurveContinuityTolerances.curvatureVariation`), so stored tolerances need no new
field, and the deviation's `curvatureDerivativeDistance` is optional for the same
reason.

### Sketch spline form

A `SketchSpline` is a clamped, non-rational B-spline in the sketch plane given by
its control points, its `degree` (1 through `SketchSpline.maximumDegree`) and its
knots. With `knots == nil` it is in Bezier-chain form: spans of `degree` joined
end to end, span k on the parameter interval [k, k + 1] using control points
degree·k through degree·(k + 1), so `degree·n + 1` points for n spans, every
interior knot of multiplicity `degree` and the curve passing through every
`degree`-th control point (the joints). The cubic chain every earlier document
holds is the form with degree 3 and no knots. With explicit knots the vector has
`controlPoints.count + degree + 1` finite, non-decreasing values, clamped (the
first and last `degree + 1` equal), a positive domain and no interior knot of
multiplicity above `degree`; it passes through its end control points and, at each
interior knot of multiplicity `degree`, the control point before that knot run
(`jointIndices`; every `degree`-th point of a chain). A closed
spline starts and ends at one point: its last control point equals its first.

`knotVector` is the resolved knot vector of either form; `isBezierChain`,
`spanCount` and `jointIndices` describe the chain form's structure. Encoding
writes `degree` and `knots` only when they differ from the cubic chain, so a
document that holds only cubic chains encodes byte for byte as before, and a
decoder that finds neither reads the cubic chain.

Constraints on a spline read its ends through the clamped end conditions, valid
for either form: the end tangent is along the first (last) control-point leg,
and the end derivatives are C′ = p/(u[p+1] − u[1])·(P1 − P0) and
C″ = p(p − 1)/(u[p+1] − u[2])·((P2 − P1)/(u[p+2] − u[2]) − (P1 − P0)/(u[p+1] − u[1]))
at the start and their mirror at the end. `tangentSplineEndpoints` and
`splineEndpointTangent` hold the end tangents parallel (G1);
`smoothSplineEndpoints` holds them parallel and the two end curvature vectors
C″⊥/|C′|² equal (G2), which does not depend on either curve's parameter
direction. `smoothSplineControlPoint` holds a chain joint's two legs collinear
and names an interior joint index, a multiple of `degree`, of a spline in chain
form. Sketch validation refuses any other form, count or index as a typed
`SketchError`.

### Materials

`Material` is a physically based appearance: base color, metallic, roughness
and opacity, plus index of refraction, clearcoat (and its roughness), sheen (color
and roughness), specular color and intensity, iridescence (and its film IOR),
thickness, transmission and an optional density in kg/m³. Every layer defaults to
no effect with the three.js physical-material defaults (IOR 1.5, sheen roughness
1, specular intensity 1, iridescence IOR 1.3, the rest 0), so a material written
before the layers existed decodes to the appearance it had. Fractions are in
[0, 1], both IORs in [1, 3], thickness is finite and non-negative, and a density
is finite and positive. `MaterialPhysicalLayersTests` prove the round trip,
legacy decoding and each range.

### Measured Source of the Limit Constants

Measured on Mac16,6 (36 GB) at the former `TessellationOptions.standard`
(`angularTolerance` 1.0e-3, before circular sampling enforced the chord
bound), evaluating each fixture in its own process. The rows record the
resource ratios the limits were derived from; they are not the current
standard's emission:

| Fixture | Bodies | Faces | Vertices | Indices | Triangles | Mesh bytes | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| box 2x3x4 | 1 | 6 | 24 | 36 | 12 | 1,296 | 13.4 MB |
| cylinder r=0.001 h=3 | 1 | 6 | 25,130 | 75,360 | 25,120 | 1,507,680 | 19.5 MB |
| cylinder r=1.25 h=3 | 1 | 6 | 25,146 | 75,408 | 25,136 | 1,508,640 | 18.8 MB |
| cylinder r=100 h=3 | 1 | 6 | 25,146 | 75,408 | 25,136 | 1,508,640 | 18.8 MB |
| cone r=1.5 h=3 | 1 | 5 | 12,581 | 37,728 | 12,576 | 754,800 | 16.7 MB |
| sphere r=2 | 1 | 8 | 37,712 | 113,112 | 37,704 | 2,262,624 | 21.4 MB |
| 12 boxes | 12 | 72 | 288 | 432 | 144 | 15,552 | 16.3 MB |
| 12 cylinders r≈0.03 | 12 | 72 | 301,752 | 904,896 | 301,632 | 18,103,680 | 45.5 MB |

Torus R=4 r=1 across angular tolerances, which isolates the quadratic growth of
a rectangular parametric grid face:

| Angular tolerance | Vertices | Indices | Triangles | Mesh bytes | Peak RSS |
|---:|---:|---:|---:|---:|---:|
| 5.0e-2 | 17,424 | 98,304 | 32,768 | 1,229,568 | 18.0 MB |
| 2.5e-2 | 65,536 | 381,024 | 127,008 | 4,669,824 | 33.2 MB |
| 1.25e-2 | 258,064 | 1,524,096 | 508,032 | 18,483,456 | 82.2 MB |
| 6.25e-3 | 1,024,144 | 6,096,384 | 2,032,128 | 73,544,448 | 290.0 MB |
| 3.125e-3 | 4,064,256 | 24,288,864 | 8,096,288 | 292,239,744 | 1,063.9 MB |

Two properties follow from the measurements and set the constants. Successive
tolerance halvings multiply the emission by 3.76, 3.94, 3.97, and 3.97,
converging on 4.00, so a rectangular grid face grows quadratically and the same
torus at angular tolerance 1.0e-3 projects to roughly 39.5 M vertices and
2.85 GB of mesh storage, which the reference machine cannot hold. The measured
peak-resident-to-mesh-byte ratio is 3.6x to 4.5x.

`hardCeiling` admits the largest invocation that completed on the reference
machine and bounds peak growth near 1.7 GB through the measured ratio.
`standard` admits the largest realistic measured model, the twelve-cylinder
assembly at 18.10 MB, with 7.4x byte headroom; it admits the torus at 6.25e-3
and refuses it at 3.125e-3.

### Operation Contract Dispatch Frame

`DesignGraph.validateOperationContract` checks duplicate inputs and output roles
before dispatching on the existing `FeatureOperation.kind` discriminator. Each
operation payload is extracted only inside its private operation helper; the
eight formerly inline payload branches use `@inline(never)` to retain that frame
boundary. Original validation bodies, order, source laws and typed error messages
are unchanged. The discriminator and helper read the same immutable feature
value; a mismatched private dispatch fails explicitly rather than skipping a
contract. Public validation APIs and resource ceilings are unchanged.

The full-enum dispatcher reserved a measured 200,176-byte Native unoptimized
frame even for an operation whose validation already lived in a helper. The
existing tag-only dispatch contract avoids retaining every family payload in the
caller frame; worker-side Drawing source validation must remain on its normal
execution context. Verification compares every moved case body and unchanged
case order, then checks the regenerated Native prologue and the actual
[Document Drawing fixture](../../Tests/SwiftCADTests/DocumentDrawingCanonicalAdmissionTests.swift)
on the normal worker. This change supplies no new feature-validation algorithm.

## Runtime Flows

`CADKernel` constructs the signature from one immutable model, and this module
validates and encodes it. Resolution back to a live topology is owned by
`CADKernel`/`CADModeling`.
`GeometrySignatureValidation.tolerance` is package-visible so bounded original
signature admission uses the same source-structural policy as Native decoding.
Current query SI tolerance remains a separate authority for approximate vertex
matching; it does not replace the stored signature's structural policy.

## State, Ownership, and Lifecycle

Signature values own copied/value geometry and have no lifetime dependency on
the evaluated document after construction.

## Failure, Concurrency, and Constraints

`DocumentMetadata.current` reads one platform UTC wall-clock value, preserves
nanoseconds and the existing 2001 reference-date conversion, and publishes the
same timestamp as creation and update. WASILibc uses its C11
`timespec_get(..., TIME_UTC)` interface; Darwin and Glibc retain their existing
`clock_gettime` interface. An unavailable clock remains a typed metadata
failure, without a substitute timestamp. Explicit authored timestamps and
Native Date/Codable adapters retain their existing contracts.

Validation is pure and deterministic. Codable failures propagate typed
validation errors; no empty signature or dropped topology entry is returned as
success. Tessellation limit validation is likewise pure; exhaustion and
overflow are reported by `CADKernel`, which owns geometry-aware preflight and
all-or-nothing emission.

## Verification and Change Impact

Tests cover all generated sphere subshape signatures, JSON round-trip, invalid
and out-of-domain signatures, and representative planar/cylindrical topology.
`TessellationLimitsTests` covers non-positive limits on every dimension, limits
that widen the hard ceiling, the largest representable limit, lowering, and the
package constants, without coupling the values to viewport policy.
`CADKernelTests/MeshCacheScopeTests` owns the cache-boundary contract, covering
a matching request, a mismatched purpose, a mismatched fidelity, a usage that
does not describe its artifact, a usage above the requested limits, and B-rep
reuse across two fidelities. `CADIRTests/MeshFaceRunTests` owns the
`Mesh.faceRuns` value contract, covering the absent-provenance mesh, the
complete partition, the empty run, the repeated face, the short and long
partitions, and the JSON round-trip that omits and restores the field.
`CADKernelTests/MeshTessellatorFaceRunTests` owns the emitted runs. Changes
require rechecking `CADKernel` stable-reference creation, lookup, and
tessellation admission, and re-measuring the fixtures above whenever the
constants move.

### Boundary coordinate maps

BridgeSurfaceFeature retains optional source-to-output affine maps beside its
stable boundaries. Absence denotes the existing common source frame. Maps are
finite and nonsingular and participate in persistence, equality and source
fingerprints. The application owns live occurrence bindings and map refresh;
CADIR owns no scene-node identity. See [BridgeSurface](../CADModeling/BridgeSurface/DESIGN.md).

### Constrained Surface source

`ConstrainedSurfaceFeature` retains ordered point positions in meters,
positional/angular tolerances and Performance/Smoothness mode.
It has no input feature ports and produces a Sheet. The original values, not a
cached fitted net, are the source authority. CADModeling's
[ConstrainedSurface](../CADModeling/ConstrainedSurface/DESIGN.md) owns fitting and
independent residual checks; existing B-spline admission owns regularity and BRep.

Extrude Boolean inputs retain target feature references after the section input.
The target list, operation and Keep Tools are source-owned and round-trip with
legacy defaults. Target outputs must be solid bodies; geometry admission is owned
by [CADModeling](../CADModeling/DESIGN.md#extrusion-boolean-composition).

A Boolean has one or more `tools`, which act together as one region (their
union), and every target and tool reference carries an optional `placement`: the
rigid motion placing that body in the result's frame (absent means it combines
where it was evaluated). The result replaces its targets; Keep Tools keeps
every tool where it was evaluated, placed or not. Targets and tools are solids (`body`
sources) or sheets (`sheet` sources); the targets are all one or the other.
`targetMaterial` and `toolMaterial` (`BooleanMaterial`: Default, Empty, Inside,
Outside) say how each side's material is taken and decode as Default when
absent. The Boolean's one output is `resultPort(targetPorts:)`: a sheet when the
targets' material is empty (Empty, or Default on sheet targets), otherwise a body. The form written before `tools` (one `tool` with an optional
`toolPlacement`) still decodes, as one tool carrying that placement; the native
package accepts either form but not both. Geometry is owned by
[CADModeling](../CADModeling/DESIGN.md#placed-boolean-tools).

An `ExtractFeature` copies part of its target's body as a body of its own and
leaves the target as it is: `.component(index:count:)` one component of a body
made of `count` components (solid components with their voids, or sheet shells),
or `.faces` chosen faces as a sheet. Its one output is `resultPort(sourcePort:)`:
a component keeps the source's kind, faces are a sheet. Geometry is owned by
[CADKernel](../CADKernel/DESIGN.md#extract).

A `WrapFeature` deforms its target's body from a reference face onto a target
face through `WrapOptions`; both faces are stable references, possibly on the
target itself, and are read as the model is before the feature. The result lives
in the target's frame; each face's optional `RigidTransform3D` placement says
where its body sits there, as a Boolean operand's does. Its inputs are
the target, then each face owner once (`sourceInputs`); its one output keeps the
target's kind. The options' scales and offsets must be finite and the scales
non-zero, and the N offset is a length expression (a parameter dependency);
invalid options fail to decode or encode. `reblends` (Reblend) recomputes the
body's round fillets on the deformed faces; documents written before it read it as
off. Geometry is owned by
[CADKernel](../CADKernel/DESIGN.md#wrap).

A mirror's `output` (combined, reflection or kept) and `cutsAtPlane` round-trip
with the legacy defaults combined and uncut; keeping only the source material
requires the cut. Feature-reference remapping and document translation carry
both. Geometry is owned by
[CADModeling](../CADModeling/DESIGN.md#mirror-output-and-cut).

## Expression Magnitude Contract

Expression consumers follow the [CADCore expression contract](../CADCore/DESIGN.md), including
unit-preserving hypot, dependency discovery, serialization and explicit failure.

Natural Bezier extension expressions use the shared numeric and unit contract in [CADCore](../CADCore/DESIGN.md). Both expression evaluators retain dependencies and propagate continuation errors.

### Symbolic spline refinement

`SketchSplineRefinement` owns affine knot insertion, Bezier degree elevation and
parameter-domain splitting of authored non-rational splines. It operates on
`SketchPoint` expressions without parameter evaluation. Outputs preserve the source
parameter domain and closure where applicable; invalid forms, non-interior splits
and unsupported degree growth throw before returning any output. Knot insertion
and degree elevation use affine combinations of expressions, so changing a source
parameter commutes with refinement. The numeric geometry implementation remains
the differential oracle, not the authoring representation. Storage is bounded by
the source spans times degree; no dense control-point transformation matrix is built.
RupaCore consumes this contract for source edits and owns reference migration and
transaction rollback. Kernel and Rupa regression tests compare reevaluated curves,
including explicit knots, changed parameters, endpoints and serialized expressions.

## Given Face Surface Persistence

`FaceRebuildMethod.given` owns the supplied B-spline value. Its source and Codable
admission validate the complete control/weight/knot/periodic representation with
`CADIRPersistenceValidation.tolerance`, following the existing B-spline feature
persistence contract. A malformed surface cannot be encoded or published in a
Native package. Kernel evaluation independently validates the surface with the
actual document tolerance and proves the resulting body through its existing
[Rebuild Face contract](../CADKernel/DESIGN.md).
`FaceGivenSurfaceTests` verifies strict publication refusal and valid Native
round-trip followed by exact evaluation and volume preservation.

## Sequential Surface Alignment Persistence

`SurfaceAlignFeature.keepsOtherEdges` owns the author's choice to localize a
later edge alignment. Its Codable value and the strict Native feature-field
admission preserve that choice. `SurfaceAlignJointTests` round-trips a two-edge
alignment with the choice enabled, reevaluates the restored source, and verifies
the resulting edge positions and tangent planes. The kernel's alignment contract
owns geometric continuity and localization; persistence does not infer either.


### Reblend Request Source (PAR.CL11A1)

WrapOptions owns the explicit reblends Boolean authoring request from immutable Claude c0c8e3b. Its default is false; Codable and structural equality/hash preserve an explicitly selected true request through the actual feature/document source. This field owns intent, not rolling-ball geometry evidence. Until a certified producer exists, Kernel must reject true before mapping or publication with an explicit unsupportedCapability and original FeatureID; silently ignoring the flag or emitting deformed rounds as recomputed rounds violates the request. Existing false/default Wrap paths retain their actual geometry behavior. Source round-trip/default/malformed tests and the public true-request refusal path establish this bounded persistence/admission unit; successful nonlinear rolling-ball geometry remains PAR.CL11's separate open producer obligation.

### Foreign angular source authority

[Independent Shape Source](IndependentShapeSource/DESIGN.md) owns original
foreign angular unit chains and numeric angular item measures. The context
`units.angle` remains the document/native evaluation convention. A nonnil
`originalAngularSource` is the sole foreign numeric angular law for represented
items; the source's ambient angular law serves actual unassociated primitive/frame
items. Original IDs, factors, dimensions and base chains remain source values.
Geometry's retained factor products consume that law under the same exchange
ledger. A degree semantic node requires exact equality with the existing degree
conversion factor, not a unit name; other factors retain their original binary
values. Native persistence and portable source identity include the owning
child's required nullable descriptors and original item measure carriers.

The independent source also retains each actual STEP GROUP owner, including
unassigned owners, separately from membership assignments. Source ownership and
reference coherence belong to [Original STEP Group](IndependentShapeSource/OriginalSTEPGroup/DESIGN.md);
document copies and source identity retain that complete child value.

### Cache Content Encoding Composition

The Kernel owns ID-independent cache content comparison, including every original
geometry carrier. It composes CADIR portable source writers rather than Native
Codable JSON. An explicit source encoding allowance admits one entire cached and
expected comparison cumulatively; helper calls cannot reset that allowance. The
legacy convenience entry preserves the existing no-additional-source-ceiling
contract of source fingerprint convenience APIs. Tessellation limits remain an
independent mesh contract. Kernel's cache design owns traversal, sorting and
semantic comparison; this relation does not redefine persistent source identity.

## Canonical Geometry API Binding

This delivery rebinds only existing callers forced by the canonical Geometry API
cut. The [Geometry admission contract](../CADGeometry/OriginalQueryExecution/DESIGN.md)
owns the exclusive execution and cumulative resource authority; numerical
coefficient producers use `ExactScalarAdmission & ~Copyable`. Existing source,
feature algorithms, local ceilings and independent source/algebra/subdivision
axes remain authoritative. Ordinary query owners issue one execution and call
the same implementation; retained values carry immutable policy or preparation,
never a copied execution or callback ledger.

```text
existing IR / Modeling caller -> canonical original execution
    -> unchanged source / numeric producer -> Geometry using witness
```

Removed admission adapters are replaced through their real owner and actual
callee chain. Protocol operations invoked through existentials are requirements.
This binding scope does not include independent Document, Mass, Stage or sewing
feature changes, nor does it establish their runtime acceptance. Source readiness
requires a per-file callee-edge inventory. Compilation of the isolated candidate
and public G01 runtime acceptance remain separate integration gates.

### Face Rebuild Request Validation Execution
`FaceRebuildFeature` and its method validate through one caller-owned execution. The original request guards and `CADIRPersistenceValidation.tolerance` remain unchanged. Stable references and a given native surface use their existing direct validators; ordinary entry creates one owner and delegates. This request binding does not implement Square refitting or support replacement.
