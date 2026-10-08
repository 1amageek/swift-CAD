# Native Exact Relation Verification

## Purpose and Scope
Test owner for [NativeExactRelations](../../Sources/CADGeometry/NativeExactRelations/DESIGN.md).
Compile the complete production CADCore and CADGeometry through relative source
symlinks, without isolated layer flags or substitute geometry implementations.
Reuse the resolved swift-collections 1.5.1 source. No production dependency change.

## Responsibilities and Boundaries
Execute the new public intersector protocol witnesses, source extraction, L0-L5
composition and immutable source/tuple queries. This proof does not claim legacy
XYZ publication migration or all shape/domain family completion.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Native owner](../../Sources/CADGeometry/NativeExactRelations/DESIGN.md) | test owner | exactParameterRelation | Source-to-topology integration | Full production sources |
| [L5 proof](../L5ParametricRelationVerification/DESIGN.md) | coordinates with | Lower exact relation fixtures | Unchanged lower evidence | New optimized composition checked here |

## Architecture
Public Native inputs -> existing intersector -> Native source adapter -> L0-L5 ->
retained exact tuple query. Swift Testing and a synchronous WASI executable share
identical behavior fixtures.

## Contracts and Invariants
Manifest all actual Core/Geometry source hashes and preserve fixed toolchain/SDK,
compiler input lists and raw WASM artifacts. Verify exact tuples, complete empty,
continuous topology, source lifetime and atomic independent resource failures.

## Verification and Change Impact
Bounded commands run fixed 6.4.0 Native, ASAN and matching WASM/Embedded. Only the
owning changed path is tested; lower untouched proofs and caches are reused.

## Homogeneous Preparation Verification
Preparation fixtures compare homogeneous coefficients and original span/domain
authority against the existing differential issuer, including weighted, nonclamped
surfaces; degree-zero surfaces retain the existing source-validation failure. Ordered-construction fixtures compare the unchanged
arbitrary-term constructor and reject invalid exponents, zero/duplicate/order,
foreign coefficients, resource/depth limits and final cancellation. Public CS/SSI
fixtures stay identical for before/after measurements; optimized proof adds a
separate preparation group. Measure fresh-process wall time and admitted counters
per target; admitted bytes are not allocation counts, peak RSS or copied bytes.
Historical connection evidence remains untouched in Evidence/. Optimization
evidence lives in PreparationEvidence/, with current compiler inventories.
