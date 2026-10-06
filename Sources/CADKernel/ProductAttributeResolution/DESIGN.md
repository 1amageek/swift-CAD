# Product Attribute Resolution

## Purpose and Scope

This component owns PARX.X3 read-only resolution of persistent product attribute
targets into an evaluated local/world snapshot and property-specific provenance.
Parent: [CADKernel](../DESIGN.md). No children. It does not change
feature evaluation, topology lineage, persistent split/merge policy, geometry,
mesh shaders, or mass/volume integration.

## Responsibilities and Boundaries

A public resolution protocol consumes a source document and its validated
evaluated artifact. ProductAttributes owns values and explicit override rules;
this component owns their applicability to exact local geometry and complete
world occurrence paths. It returns a separate immutable resolved view of
body/face, part, and occurrence properties, with the assignment chain that
authorized each effective value. It never mutates BRep records to turn derived
UUIDs into persistent source authority.

Existing StableSubshapeResolving supplies its current reference policy. Assembly
Evaluation supplies the retained local B-rep, local SubshapeIndex/lineage, and
public local-to-world occurrence correspondence. This component consumes those
contracts rather than copying evaluator identity algorithms or reading private
STEP entity encoding. A source path or target that cannot resolve uniquely is
a failure, not an attachment to the first geometry record found.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | EvaluatedDocument consistency and stable reference resolution | Supplies validated evaluated snapshots | Source and artifact must match before resolution |
| [Product Attributes](../../CADIR/ProductAttributes/DESIGN.md) | depends on | Source targets, typed values, explicit overrides, limits | Owns all product property meaning | Do not infer rank or values from generic attributes |
| [Assembly Evaluation](../AssemblyEvaluation/DESIGN.md) | depends on | Retained local artifact and typed source/world correspondence | Resolves shared definitions and placed instances | Local index and world index are different domains |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | StableSubshapeResolving | Applies existing persistent-reference policy | X3 adds no new lineage or split/merge semantics |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | BRep ownership and body/face membership | Confirms exact attachment coverage | ID presence alone does not prove membership in the selected occurrence |
| [STEP Attributes](../../CADExchange/STEPAttributes/DESIGN.md) | used by | Resolved properties and source provenance | Authorizes standard target correspondence and export admission | A resolved view does not authorize flattening assembly structure |

## Architecture

```mermaid
flowchart LR
    Source[ProductAttributes source] --> Validate[Source/artifact consistency]
    Artifact[EvaluatedDocument] --> Validate
    Validate --> Local[Stable reference resolver with local index/lineage]
    Local --> Correspondence[Public occurrence feature correspondence]
    Correspondence --> Applicable[Target applicability and membership]
    Applicable --> Properties[Property-specific override resolution]
    Properties --> View[Immutable resolved values and provenance]
    View --> Exchange[STEP/export admission consumer]
```

## Contracts and Invariants

- Resolution validates source/artifact correspondence with the caller's admitted
  operation limits before consuming retained indexes. Nonassembly resolution
  uses the ordinary evaluated local topology domain. Assembly resolution uses
  `assembly.local` for persistent geometry references, then public
  AssemblyOccurrenceCorrespondence and AssemblyFeatureCorrespondence maps to
  reach world bodies/faces. A world SubshapeID is not substituted for a local
  source reference.
- Materialized snapshots prove source association through their existing B-rep
  cache and source fingerprint. Successful deferred exact evaluation intentionally
  has no caches. Its producer retains an internal immutable ValidatedCADDocument
  receipt only after evaluation and lineage/curve validation succeed. Resolution
  admits a cacheless snapshot only when that retained source equals the current
  document by the source owners' exact text identity (including Unicode scalar
  sequences), receipt/configuration tolerances agree, and the producer's existing
  exact ValidatedBRepModel equals the current B-rep at the same tolerance.
  Public construction and decoding start without this receipt; it is not a
  serialized field, a caller-supplied certification, or a substitute cache.
  A manually reconstructed or stale cacheless artifact therefore fails explicitly.
- Definition attachments apply to occurrences of that definition; path-scoped
  attachments apply only to their complete persistent path. Geometry targets
  retain the real feature reference and an optional definition or path restriction.
  These restrictions are mutually exclusive under the source contract. A definition
  selector matches the candidate's definition identity before common-feature/body/face
  membership is considered. Consequently two occurrences of the selected definition
  receive the same source attachment, while a third occurrence of another definition
  sharing that FeatureID does not. Global geometry targets retain their existing fan-out.
  Body-to-face property and layer inheritance uses the same selected-definition filter;
  names still apply only to their exact geometry target. Body/face
  membership in the resolved feature/definition/occurrence is checked explicitly.
  Shared geometry may resolve to multiple intentional world instances; this is
  distinct from an ambiguous local target.
- Every returned geometry target exists in the selected snapshot and has the
  required topology kind. Missing, stale source/artifact association, ambiguous
  local reference resolution, invalid path scope, and incomplete correspondence
  fail. Existing stable-reference failures propagate without a new X3 fallback.
- Effective appearance, material reference, and density use only the source
  owner's explicit property relation. Values not specified by an override retain
  their prior provenance. Unordered competing applicable assignments fail;
  sorting UUIDs or choosing face/instance specificity cannot create precedence.
  Layers resolve as membership sets. Part/occurrence names come from their
  existing source owners and do not overwrite body/face names. Part name lookup
  consumes DocumentAssembly's bounded definition-to-formation-to-product contract.
  Shared PRODUCT edits change every applicable part baseline while definition-local
  attribute assignments retain their existing scope; no product-level rank is inferred.
- The view retains source assignment identity, target scope, and ordered
  predecessor provenance for each effective property. A physical material value
  does not imply any PBR appearance or effective density. Effective density
  resolves only from an independent explicit density assignment; a descriptor
  reference supplies the value only when such an assignment exists and the
  descriptor has a density value. Changing a material assignment does not alter
  the density chain. No inferred density, missing color, or
  legacy Body.material reference is returned as a fabricated resolved value.
- Record, occurrence, resolved-target, override-depth, and cumulative work
  ceilings bound the complete operation. Source validation, correspondence
  traversal, property graph evaluation, and result storage consume one caller
  allowance with checked arithmetic before index/result growth. Repeated shared
  definitions do not authorize uncharged expanded result copies. Cancellation
  is checked through all potentially expanding phases.

## Runtime Flows

```text
source + evaluated snapshot + limits -> validate matching authorities
 -> resolve persistent targets locally -> map complete occurrence paths
 -> verify exact body/face membership -> resolve explicit property chains
 -> stage bounded view -> publish complete values with provenance
```

## State, Ownership, and Lifecycle

Inputs are immutable snapshots. The producer source receipt retains the existing
validated source through value/COW ownership and introduces no global state or
additional reevaluation. Its lifetime follows the evaluated snapshot; decoding
cannot recreate producer authority.
 The resolved view owns its values and snapshot
association; source or local geometry edits require a new resolution. It does
not retain mutable evaluator handles, a global cache, raw pointers, or callbacks.
Temporary indexes, counters, and graph state have one synchronous operation
owner. Native and WASM use the same source/ownership contract; no target branch
removes isolation or changes Sendable requirements.

## Failure, Concurrency, and Constraints

Public protocol operations distinguish typed unresolved-target, inconsistent
artifact, ambiguous-property, invalid-scope, and resource failures. Existing
stable-reference, assembly, geometry-validation, and cancellation errors remain
explicit. No partial view is published and no default style/material replaces a
failed target. Stateless Sendable implementations introduce no shared mutation.

## Verification and Change Impact

[ProductAttributeResolutionTests](../../../Tests/CADKernelTests/ProductAttributeResolutionTests.swift)
own shared/nested instance applicability, local-to-world face/body mapping,
source edits and fresh snapshot association, property provenance, unchanged
unrelated properties, layer sets, names, dangling/ambiguity/cancellation refusal,
and pre-allocation cumulative limits. Assertions inspect actual resolved world
targets and values rather than type existence. Definition-scope fixtures retain one
local body with three world placements across two definitions, check independent
density/name/layer results, and refuse foreign membership, combined selectors,
stale receipts, exhausted work and overlap without explicit overrides. STEP remains
a separate composition proof; source applicability alone does not authorize scope
flattening at that boundary. Changes require rechecking
ProductAttributes, stable reference resolution, AssemblyEvaluation correspondence,
and public STEP export. Parent indices remain integration-owned.


### Independent Item Characterization Target Proof (PAR.CIWR2)

Every global itemCharacterizations target enters the same precharged local
geometry index/lineage resolver as assignment/layer targets, using full original
source signature and actual topology presence. A target cache is keyed by its
complete ProductAttributeTarget, never kind/ID alone. Metadata-only input creates
no effective value or invented assignment. Existing immutable exact-producer
receipt validation includes the renamed complete source array; changed wrapper
text rejects an old genuine receipt and fresh evaluation retains geometry and
unchanged effective physical values. Foreign/stale actualgeometry targets refuse.
Native/shared-definition fanout and failure/cancel/budget atomicity remain required.


CIWR2 metadata uses an explicit current-geometry signature invariant beyond the
provenance-first stable resolver's direct-ID policy. After resolving each metadata
target, build its actual local body/face signature and compare with the stored
source signature through SubshapeGeometrySignatureBuilder.matches (body/face exact
structural equality). Precharge the actual bounded signature traversal/comparison
before construction and verify complete target cache entries once. A same-kind
foreign origin or changed loop/pcurve signature refuses even with a fresh genuine
source receipt. The general stable resolver and assignment lineage policy are not
changed by this bounded metadata owner. Source-signature mismatch is a typed
inconsistent artifact; no geometry retargeting or tolerance-based replacement.

### Manufacturing and View Metadata Targets

The same invocation-local paid `localGeometry` map owns PMI, datum, dimension, annotation and validation-value references. Metadata source signatures are admitted before hashing, resolved through the existing stable-source resolver, compared against actual current geometry and retained in the map only on successful correspondence. Producer receipt equality and source fingerprint checks include both source containers. Metadata values do not become appearance precedence candidates. Source validation owns ordered datum and annotation-reference integrity.
