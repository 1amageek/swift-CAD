# Heap and PSC Verification

## Purpose and Scope
Test owner for L1 sparse-product/PSC and L3 projection consumption. Parent:
[system](../../DESIGN.md). Children: none. Production L1-L4 sources are direct
relative directory symlinks, with import-only isolated flags. L0 is the existing
verified isolated closure; no substitute polynomial or cell implementation.

## Responsibilities and Boundaries
Compare exact independent product/determinant values, all PSC indices and failure
paths. Execute unchanged lower topology fixtures and actual public Native routes.
No source semantics, variable order, caps, topology, L0 or new solver change.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [L1](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactPolynomial/DESIGN.md) | test owner | Product and complete PSC | Exact values and one admission | Forced reference and PRS are test comparisons, no runtime fallback |
| [L3](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactRealCell/DESIGN.md) | test owner | Full projection/partition | Same witnesses/coverage | Zero PSC indices retained |
| [Native](../NativeExactRelationVerification/DESIGN.md) | coordinates with | Public relation fixtures | Full production integration | Native and both WASI SDKs are distinct evidence |

## Architecture
Independent product/determinant oracle -> L1 -> L3 -> unchanged L4/L5 -> Native.

## Contracts and Invariants
Original coefficient/basis/owner and complete values are identical; algorithm
work/storage may decrease, but bounds, cancellation and inherited depth remain.
Benchmark setup and independent checks are outside timed regions. Compare fixed
source snapshots and same input/result guarantees, not different publication work.

## Verification and Change Impact
Focused Native P1/P2 tests precede the complete lower suite and four production
Native/ASAN/WASM/Embedded runs. Runtime watchdogs are at most 120 seconds; portable
full WMO compilation uses the existing separately bounded build-only watchdog.
No additional review after the stable integrated review unless a scoped concrete
counterexample changes the verified premise.

## Target Timing Boundary
ContinuousClock benchmark helpers are Native/normal-WASM-only under the pinned
runtime's actual API availability. Embedded proof products keep the identical
exact/failure fixtures. Public performance is measured externally in fresh
processes on every lane. No production field or synchronization contract changes.
