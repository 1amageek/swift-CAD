# L2 Isolated Verification

## Purpose and Scope

Independent SwiftPM verification package for the actual L2 production sources.
Parent authority: [ExactRealRoot](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactRealRoot/DESIGN.md).
No higher CAD target is compiled.

## Responsibilities and Boundaries

Own public behavioral fixtures, Native tests and portable proof execution.
Symlink L0/L1/L2 production sources; maintain no substitute arithmetic.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [ExactRealRoot](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactRealRoot/DESIGN.md) | verifies | All public root and extension contracts | Required success/failure/lifetime paths | Compile success alone is insufficient |

## Architecture

```text
Tests / L2Proof -> L2Fixtures -> L2 -> L1 -> L0
                                -> L0
```

## Contracts and Invariants

Fixtures execute real production operations and reject unexpected success or
failure. Inputs and exact reference identities are constructed outside timed
operations. Each fixture owns its mutable admission; parallel tests share no
mutable state. Evidence is target/snapshot-specific.

## Verification and Change Impact

Use Swift 6.4.0, matching WASM SDKs and dedicated build paths with guarded
commands. Run Native tests, ASAN and both portable proofs. Record source hashes,
compiler inventories and actual behavior. Changes to a fixture or affected
production source invalidate only dependent evidence.
