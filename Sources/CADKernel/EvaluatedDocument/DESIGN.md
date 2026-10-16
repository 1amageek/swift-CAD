# Evaluated Document

## Purpose and Scope
Child of [CADKernel](../DESIGN.md). Owns the existing complete evaluated snapshot
value and its native codec. This component separates that value from unrelated
protocol composition so genuine measurement consumers can retain it on every
supported target. It introduces no replacement snapshot type.

## Responsibilities and Boundaries
The value retains the original authored document, resolved parameters, B-rep,
meshes, evaluated curves, caches, subshapes, lineage, assembly, configuration,
metrics and internal incremental/exact-source receipts. Evaluation, topology
validation, mesh generation and mass arithmetic retain their existing owners.
Native codecs call the existing complete snapshot validator.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Kernel](../DESIGN.md) | parent | evaluation/publication and incremental state | Composes the complete snapshot | Moving the declaration cannot drop a stored owner |
| [CADIR](../../CADIR/DESIGN.md) | depends on | immutable document, cache and assembly values | Supplies authored inputs and indexes | Preserve original source authority |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | evaluated curve values | Retains actual curve owners | Use the existing production values |
| [Topology](../../CADTopology/DESIGN.md) | depends on | BRepModel and ValidatedBRepModel | Retains exact geometry and optional validation | Raw initialization never invents a receipt |
| [Geometric Measurement](../GeometricMeasurement/DESIGN.md) | used by | complete evaluated document value | Reads geometry, units and optional exact receipt | Mass does not manufacture a simplified document |

## Architecture
```text
Existing evaluation / public initializer
    -> complete EvaluatedDocument value and retained receipts
        -> measurement / drawing / other unchanged consumers
Native codec -> existing complete snapshot validation -> same value
```

## Contracts and Invariants
All stored fields, access levels, initialization defaults, Sendable conformance
and internal receipt initialization retain their original meaning. Public manual
initialization keeps validatedBRep, incremental state and validated source receipt
absent. Native coding keys and complete validation remain unchanged. Codable is a
native transport capability; Embedded uses the identical stored value and owner
contracts. Configuration and metrics retain identical fields and isolation on all
targets, with only native Codable conformance conditional.

## State, Ownership, and Lifecycle
The snapshot retains the same original value/COW owners and optional immutable
receipts for its whole lifetime. A source file move changes no storage layout,
mutation entry point, concurrency contract or release responsibility. Consumers
borrow their incoming execution separately; the snapshot stores no execution.

## Failure, Concurrency, and Constraints
Native decode/encode preserves complete validator failures. Unsupported coding
runtime capability does not substitute a partial snapshot or an unchecked owner.
No platform branch removes synchronization or Sendable requirements.

## Verification and Change Impact
Compare the moved declaration, all stored fields and initializer bodies against
the original KernelProtocols source. Compile actual Native consumers and codecs,
and the genuine Mass input/value closure on ASAN, normal WASM and Embedded. The
Mass fixture must use this production value and the existing Modeling curve values;
shadow document declarations or source-string extraction cannot prove this path.
Recheck default initialization, COW/receipt retention and native codec behavior
within the changed snapshot boundary. Parent Kernel design owns the existing
complete evaluation/cache-validation policies.

### Direct dependency visibility

The actual complete-value source closure includes IncrementalEvaluationGraphState
and DictionaryDelta. Those files and the Mass consumer explicitly import the
already-declared HashTreeCollections dependency when reading its PersistentMap
operations. An import supplied by an unrelated source file is not their portable
visibility authority. This binding changes no fields, collection algorithms,
mutation/isolation entry, Sendable contract or target-specific state. The actual
Embedded compiler's three missing-member diagnostics identify this requirement;
all target Kernel compile/link and actual Mass behavior verify the binding.
