# Intersection Portability Smoke

## Purpose and Scope

This executable verifies the public original native curve/surface and surface/surface
isolated-point publication paths, including the bounded original Native curve/ruled
public checkpoint. Parent: [Swift-CAD](../../DESIGN.md).
Child: [Original Point Relation Proof](OriginalPointRelationProof/DESIGN.md).

## Responsibilities and Boundaries

The executable composes the complete production CADCore and CADGeometry modules;
it does not select source subsets or replace unavailable geometry producers.
The same public requirement witnesses are invoked on Native, normal WASM and
Embedded WASM using Swift 6.4.0 and its matching SDKs. Runtime output records
actual successful proof, and failure terminates the executable.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../CADGeometry/DESIGN.md) | depends on | Public original result and admission requirements | Owns actual producers and retained receipts | Complete module compilation is required |
| [CADCore](../CADCore/DESIGN.md) | depends on | Typed failure and cancellation | Owns target-common failure meaning | Cancellation remains a failure |
| [Original Point Relation Proof](OriginalPointRelationProof/DESIGN.md) | child | Public behavioral proof | Owns fixtures and comparisons | Marker follows all checks |

## Architecture

```text
async entry -> joined local proof -> public existential requirements
                                    -> complete CADGeometry -> complete CADCore
```

## Contracts and Invariants

Every target uses the same source fixtures, immutable result owners, Sendable
requirements and Mutex accounting. Native and normal WASM additionally verify
their original source Codable capability; Embedded requires no codec capability.
Optimized execution cannot establish unoptimized lowering:
Embedded proof requires -Onone with WMO and retains its raw WASM artifact.
The recipe uses -gnone to avoid DWARF generation cost while preserving the
unoptimized lowering and the raw artifact needed for function-name lookup.
Normal WASM -Onone and -Osize receipts remain distinct, including engine limits.
Embedded links the matching SDK's actual libswiftUnicodeDataTables.a for Core
string normalization and hashing. The recipe records its path and SHA-256;
no ASCII-only replacement or weakened common String semantics is used.

## Runtime Flows

The entry runs the synchronous public proof, joins the cancellation task, then
prints the final marker. Any unexpected failure exits without that marker.

## Failure, Concurrency, and Constraints

The recipe uses one fixed release compiler and a clean registered Collections
1.5.1 checkout. It snapshots every production source and records its SHA-256.
Builds use two jobs, a caller-selected deadline within 900 seconds, and runtime
within 120 seconds. Timeouts terminate the owned process group.

| Recipe lane | Swift SDK | Lowering | Runtime |
|---|---|---|---|
| `native` | Native release toolchain | `-Onone -gnone` | actual executable |
| `wasm` | `swift-6.4.0-RELEASE_wasm` | `-Onone -gnone` | Node WASI Preview 1 |
| `embedded` | `swift-6.4.0-RELEASE_wasm-embedded` | `-Onone -gnone` and WMO | Node WASI Preview 1 |
| `wasm-osize` | normal matching SDK | `-Osize -gnone` | separate optimized evidence |

Run `Scripts/verify_intersection_portability.py` with `--lane`, `--swift`, and
`--collections-checkout`. Embedded also requires `--unicode-data-tables` pointing
to that matching SDK's WASI Embedded library. Each lane retains its receipt,
build/runtime logs and raw artifact under `.build/intersection-portability/`.

The original affine public checkpoint uses the same immutable receipt and ledger
contract on Native, normal WASM and Embedded WASM; target evidence is scoped to
the executed common source snapshot.

## Verification and Change Impact

The bounded recipe compiles the complete modules using registered dependency
sources, invokes Node WASI Preview 1 on the raw WASM and records source hashes,
SDK, command and exit status. Native runs the same executable. Parent owns
integration with implementation work and target-specific completion claims.
