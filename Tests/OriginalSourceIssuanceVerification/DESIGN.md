# Original Source Issuance Verification

## Purpose and Scope
Verification-only SwiftPM package. Parent: [package](../../DESIGN.md).
No children. Compile actual linked issuer sources independently of upper CAD.

## Responsibilities and Boundaries
Own the source inventory gate, exact behavioral fixtures, timeout-bounded runtime
and evidence for the [issuer contract](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md).
The separate adapter proof compiles only concrete source providers/readers and
the existing AnalyticBasis source against validated cached geometry modules.
Whole-seven acceptance and public CS/SSI solve behavior are outside this proof.
The separate Native consumer proof owns the common-law preparation handoff.

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

The original foundation evidence remains at [VERIFICATION](Evidence/VERIFICATION.md).
[Fixtures](Sources/Fixtures/SourceFixtures.swift) and [tests](Tests/SourceTests.swift)
now share seventeen behavior groups: original Native laws, selected/tensor spans,
periodic laws, primitive images, ownership, typed failures, resources, exact
physical-angle arithmetic/ordering, angle resources, cone images, heterogeneous ruled laws,
spatial action, parameter-image correspondence, sealed endpoints/Coons, retained
decision depth, retained-root extensions and directed traversal laws. The
[adapter proof](Sources/GeometryProof/GeometryProof.swift) uses actual Native and
analytic inputs, existing validators/basis authority and the same issuer laws.
The [spatial proof](Sources/SpatialGeometryProof/SpatialGeometryProof.swift) also
uses the current original-word provider, retained exact normalized frame and
actual line/tensor child laws. Its import-only source overlays use one cached
lower nominal identity without new root isolation.
The [Coons proof](Sources/CoonsGeometryProof/CoonsGeometryProof.swift) uses actual
weighted nonunit directed boundaries and sealed algebraic root endpoints. It
checks whole HXYZW laws, eight endpoint owners in a common coefficient field,
exact selector reuse and source/depth/work/storage/cancel failures. Each compiler
input is read once: those same bytes produce its immutable copy and recorded
hash. Import prefixes are the only overlay additions. Receipt publication checks
current originals against the captured hashes, rejecting edits after capture.
The shared [input snapshot helper](Scripts/VerificationInputs.py) owns this
boundary; [deterministic regressions](Scripts/TestVerificationInputs.py) verify
overlay/proof edits during copying and unchanged publication. Its geometry
evidence is [TraversalEvidence](TraversalEvidence/VERIFICATION.md).
The copy/hash race fix is recorded in [SnapshotFixEvidence](SnapshotFixEvidence/VERIFICATION.md).
The main/domain composition is recorded in [MainIntegrationEvidence](MainIntegrationEvidence/VERIFICATION.md).
Its [Native runner](Scripts/VerifyMergedPreparation.py) recompiles current source
and domain adapters against checked lower caches, and executes preparation plus
the existing public parameter CS/SSI fixtures without an upper-target build.
Its script verifies cached runtime artifact hashes and source-provider premises
before linking. It records every reused object and every compiled adapter.
The verification-only dual admission conformance reconciles cached and separately
compiled module identities; it forwards the identical scoped noncopyable L0
borrow. Production has one legacy admission protocol and needs no such shim.

| State | Native / ASAN | WASM / Embedded | Ownership and access |
|---|---|---|---|
| Source/angle/polynomial owners | Immutable Sendable owners | Identical declarations | Read-only retained COW payloads; no mutation entry |
| Caller admission | Exclusive inout ~Copyable ledger | Identical declarations | Query-local, never retained or shared |
| Sign refinement | Invocation-local mutable value | Identical declarations | Cannot escape its exclusive call; no shared cache |

There is no target-specific synchronization or Sendable branch in issuer sources.
Changes to cached validators, gauge/basis authority or compiler inputs invalidate
the affected adapter evidence. Root-solving, full requested-domain coverage and
existing CS/SSI public consumer behavior are not inferred from these tests.

The Native/primitive/physical-angle extension is recorded in
[NativeImageEvidence](NativeImageEvidence/VERIFICATION.md).

The Native preparation handoff is recorded in
[NativeConsumerEvidence](NativeConsumerEvidence/VERIFICATION.md). Its import-only
overlays compile current consumer sources against one validated cached lower
identity. Current DI0 interval composition remains a final integration obligation;
no cached L2 solver execution is used as evidence for that newer implementation.
