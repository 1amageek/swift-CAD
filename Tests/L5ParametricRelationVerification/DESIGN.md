# L5 Parametric Relation Verification

## Purpose and Scope
Independent actual production L0-L5 composition; no upper CAD builds.
Parent: [component design](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactParametricRelation/DESIGN.md). No children.

## Responsibilities and Boundaries
Owns public behavioral fixtures, dedicated build paths, bounded commands and exact
compiler-source provenance. It does not certify native producer extraction or geometry APIs.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [L5](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactParametricRelation/DESIGN.md) | test owner | Map/compiler/resolver protocols | Real exact parameter relations | No upper geometric dimension claim |
| [L4 evidence](../L4TopologyVerification/VERIFICATION.md) | depends on | Byte-identical lower contracts | Reuse prior 29702a63 evidence | Current compiler input hashes must match |

## Architecture
Fixtures -> generic L5 requirements -> production L0-L4; identical synchronous
fixtures execute in Native Swift Testing and both WASI proof executables.

## Contracts and Invariants
Weighted/repeated CS, multiple UV, closed/singleton/unbounded, denominator guard,
empty/continuous, folded SSI, retained lifetime and explicit invalid/resource/cancel
failures must execute through the implemented public requirement paths.

## Verification and Change Impact
Swift6.4.0, matching normal/Embedded SDKs, timeout120 seconds and two compiler jobs.
Native/ASAN and both WASI run the same synchronous fixtures. Record exact production
inventories, raw artifacts and source hashes. Lower sources remain unchanged.
