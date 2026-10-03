# Document Assembly

## Purpose and Scope

This component owns PARX.X2 source assembly definitions, shared occurrences,
nesting, and local coordinate systems. Parent: [CADIR](../DESIGN.md). No children.
An assembly references existing feature-owned local shapes; it does not own a
second B-rep source. Product attributes and general long-term topology reference
resolution remain outside this component.

## Responsibilities and Boundaries

`CADDocument.assembly` is the sole assembly source authority. The product/formation/definition graph owns three distinct persistent values.
A product owns its standard identifier, name and nullable description. A formation
owns its version identifier, nullable description and optional specified-source
subtype, and references one product. A definition owns its standard identifier
and nullable description, references one formation, and retains local body-producing
FeatureIDs and child occurrences. An occurrence has a persistent identity, a
definition reference, and a proper rigid transform into its containing frame.
Roots are occurrences in the document world frame. Reusing a definition retains
sharing; it never duplicates its feature source. A complete occurrence path,
rather than the final edge identity alone, identifies an expanded occurrence of
a shared nested assembly.

The feature graph owns local geometry and feature dependencies. Assembly source
validation owns structural references and finite proper rigid placements;
[Assembly Evaluation](../../CADKernel/AssemblyEvaluation/DESIGN.md) owns resolution
against live evaluated outputs and world topology. No synthetic feature node is
created to impersonate an occurrence. Local modeling remains in feature coordinates.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | CADDocument, FeatureID, source validation | Retains assembly as source value data | Fast validated-document transitions must preserve assembly admission |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | RigidTransform3D | Provides exact coordinate transforms | Assembly admits proper rotations, without scaling or reflection |
| [Assembly Evaluation](../../CADKernel/AssemblyEvaluation/DESIGN.md) | used by | occurrence expansion and local output resolution | Generates world results from this source | Evaluation artifacts are derived, never persisted source |
| [STEP Assembly](../../CADExchange/STEPAssembly/DESIGN.md) | used by | product definitions and occurrence placements | Maps standard STEP structure to this source | Ambiguous alternative geometry is explicitly refused |
| [CADExchange](../../CADExchange/DESIGN.md) | used by | NativePackageStore strict envelope | Persists source references and frames | The current CADCore envelope requires nullable assembly; older envelopes fail |

## Architecture

```mermaid
flowchart LR
    Document[CADDocument] --> Product[Shared Product metadata]
    Product --> Formation[Formation/version owners]
    Formation --> Definition[Definition views and local feature references]
    Definition --> DAG[Definition occurrence DAG]
    DAG --> Roots[Root occurrences]
    DAG --> Children[Child occurrences]
    DAG --> References[Local FeatureID references]
    References --> Graph[DesignGraph local source]
    Roots --> Paths[Bounded occurrence paths]
    Children --> Paths
    Paths --> Evaluation[Assembly Evaluation]
```

## Contracts and Invariants

- The development source envelope uses
  [SchemaVersion.current](../../CADCore/SchemaVersion.swift), owned by CADCore.
  `assembly` is required in encoded
  documents and may explicitly be null. Unknown keys, missing fields, malformed
  identifiers, and older versions fail; no implicit migration is performed.
- Assembly definitions, direct occurrence records, and roots have unique valid
  identities. Every referenced definition and feature exists. A referenced
  feature is active and declares a body or sheet output. Definition references
  form an acyclic graph. Every retained definition is reachable from a root;
  an unreachable product is not silently discarded. An empty root list is invalid
  source, independently of resource ceilings.
- A definition may contain local feature shapes and explicit child occurrences.
  Distinct definitions may refer to the same existing FeatureID list. That feature
  is the sole local shape source; definition metadata and attribute selectors
  remain separate views, not copied geometry or additional feature nodes.
  Their source meaning is additive and unambiguous. STEP files whose assembly
  geometry could instead be an alternative flattened representation are refused
  by the exchange owner rather than assigned this additive meaning implicitly.
- Placements are finite orthonormal frames with positive determinant. Their
  translations use internal meters; direction vectors are dimensionless. World
  composition applies each parent placement to the child's local placement.
- Occurrence paths retain all persistent edge identities from root to leaf.
  Sibling order or dictionary serialization order is not identity. Repeated
  nested definitions generate distinct paths while retaining one definition.
- Validation and expansion use explicit owner limits for source record count,
  depth, expanded occurrence count, work, and derived topology storage. Counters
  use checked arithmetic and charge before growing derived collections. Source
  record/work admission precedes duplicate-detection allocation. The protocol's
  expansion result reports consumedWork together with the complete occurrence list;
  downstream assembly evaluation carries that consumption into the same cumulative
  maximumWork ceiling, rather than granting each phase a fresh allowance.
  Callers may choose positive record/work limits and nonnegative text ceilings; limits do not relax source invariants.
- Products and formations are required source arrays. Each has a unique typed
  identity; formation-to-product and definition-to-formation references must exist.
  Every retained formation and product is used by a retained reachable definition.
  Formation `(productID, versionIdentifier)` is unique by exact UTF-8 identity,
  following standard UR1; canonically equivalent Unicode sequences remain distinct versions.
  Multiple definitions may share a formation and multiple formations a product.
- Each standard string has one owner. Product identifier/name/description are
  independent of definition identifier/description and formation version/description.
  Empty identifiers are valid standard strings; UUID-shaped business identifiers
  do not authorize native identity. All descriptions and specifiedSource are
  required nullable native keys; no missing-key default or migration is admitted.
  A nil specifiedSource means the base formation entity; made, bought and notKnown
  mean the actual standard subtype literal, with no lifecycle inference.
- Metadata lifetime is the immutable document lifetime. Canonical ordering includes
  products and formations without changing references. Their records, retained UTF-8
  text bytes and UTF-8 traversal are charged before index allocation and text
  traversal to maximumRecords, maximumTextBytes and the shared maximumWork ceiling.
  String admission has no normalization, trimming, repair or guessed default.
  Product, formation and definition equality compares every owned text field by
  exact UTF-8 sequence, with nil distinct from empty. UTF-8 views implement equality
  and version-key hashing without intermediate buffers. This keeps source equality,
  fingerprints and producer receipt freshness consistent for canonically equivalent
  but differently authored Unicode. Occurrence and attribute text owners are unchanged.
- Product names are resolved by the AssemblyProductLookingUp protocol through
  definition -> formation -> product under a caller work ceiling. Metadata lookup
  does not rebuild geometry or expand occurrence paths.
- Assembly values participate in member-wise document equality and stable source
  fingerprints. Graph-stable replacement and append fast paths recheck assembly
  source admission. Deleting or suppressing a referenced feature fails before a
  copied document is published.
- `translatingSources` on an assembly translates only root placements. It leaves
  local feature sources and nested relative placements intact, then validates
  the complete copy. Ordinary nonassembly translation retains its existing contract.

## Runtime Flows

```text
source DAG -> validate IDs/feature references/frames -> bounded cycle/reachability
 -> bounded occurrence expansion -> resolve local outputs -> world materialization

source edit -> copied document -> full or justified fast-path validation -> publish
native decode -> strict envelope/keys -> source validation -> owned CADDocument
```

## State, Ownership, and Lifecycle

Assembly source is owned value data with the CADDocument lifetime. Removing an
occurrence ends that path identity; removing a definition is admissible only when
no retained occurrence references it. Derived expansions and local/world indexes
belong to an evaluated snapshot. They never mutate the source or become a hidden
second authority. Validation has operation-local counters and no shared registry.

## Failure, Concurrency, and Constraints

New public operations are exposed through protocols with typed assembly errors.
Missing, suppressed, cyclic, duplicate, unreachable, nonfinite, nonrigid, or
resource-exhausted source is refused. Cancellation propagates at traversal
boundaries. All validation is synchronous over immutable snapshots; a failure
does not publish partial source or an incomplete occurrence list.

## Verification and Change Impact

[DocumentAssemblyTests](../../../Tests/CADIRTests/DocumentAssemblyTests.swift)
owns source sharing/nesting, frame validation, cycle/dangling/suppression refusal,
bounded expansion, fingerprint changes, strict decoding, validated fast paths,
and root-only translation. Product graph tests verify sharing and formation UR1, strict required nullable
fields, dangling/unreferenced owners, pre-allocation resource admission, source
fingerprint changes for every owner, copied validated transitions,
and preservation through source translation. STEP and native package tests verify persistence
through their real public paths. Source contract changes require coordinated
revalidation of Assembly Evaluation, STEP Assembly, and strict NativePackageStore
admission; parent design indexes are maintained by the integration owner.
