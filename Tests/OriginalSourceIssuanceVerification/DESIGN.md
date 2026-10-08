# Original Source Issuance Verification

## Purpose and Scope
Verification-only SwiftPM package. Parent: [package](../../DESIGN.md).
No children. Compile actual linked issuer sources independently of upper CAD.

## Responsibilities and Boundaries
Own the source inventory gate, exact behavioral fixtures, timeout-bounded runtime
and evidence for the [issuer contract](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md).
Actual geometry-provider conformance and whole-seven acceptance are separate.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Issuer](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md) | verifies | Binding and exact Native local laws | Production symlinks only | No copied implementation |
| [L0](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/DESIGN.md) | depends on | Exact arithmetic and resources | Unchanged lower source | Reuse lower evidence |
| [L1](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactPolynomial/DESIGN.md) | depends on | Exact polynomial operations | Unchanged lower source | No new root solver |

## Architecture
```text
linked L0 -> linked L1 -> linked SourceIssuer -> independent fixtures -> proof/tests
```

## Contracts and Invariants
The first build admits only L0/L1 and issuer contract sources. Manifest, actual
compiler-input lists and resolved symlinks must exclude every upper source.
Fixtures verify original whole-law identities, ownership and explicit failure,
not only declarations or numerical samples. All lanes use the same actual files.

## Verification and Change Impact
Use pinned Swift6.4.0, matching WASM/Embedded SDKs and a dedicated build path.
Separate bounded build from runtime; tests/proofs have a maximum120s timeout.
Native/ASAN and normal/Embedded compile/link/runtime are independent lane evidence.
No build of upper CADGeometry or another production target is authorized here.

Stable four-lane behavior, compiled-input boundary and scoped review are recorded in [VERIFICATION](Evidence/VERIFICATION.md). [fixtures](Sources/Fixtures/SourceFixtures.swift) own the five exact behavior groups; [tests](Tests/SourceTests.swift) and the proof executable run those same groups. The injected NativeProvider verifies primitive snapshot assumptions; production Geometry provider migration is not established.
