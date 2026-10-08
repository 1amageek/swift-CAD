# Domain / Identity Foundation Completion Evidence

## Scope

DI.1 exact affine/periodic parameter transport, DI.2 finite/cartesian Native coverage
and symbolic all-integer families, DI.3 supported source/boundary/period/pole identity.
The source/domain rational chart handoff and the stored-N exact plane basis/UV inverse
are also executed. This is not completion of DI.4 existing CS/SSI/boundary/self consumer
migration, all original shape families, legacy plane point/UV migration or the seven requirements.

## Stable results

| Lane | Behavioral evidence |
|---|---|
| Native | 15 Swift Testing tests and deterministic proof pass |
| ASAN | Same 15 tests pass without sanitizer errors |
| normal WASM | Matching release SDK, compile/link and proof runtime pass |
| Embedded WASM | Matching Embedded SDK, -Onone/WMO, compile/link and proof runtime pass |
| SourceIssuer | All 5 existing owning tests pass after periodic local-law capability change |
| Dependency probe | L0/DI0-only dependency executable passes; full compiler inventory separately bound |

Compiler: Swift 6.4.0 release; WASI target wasm32-unknown-wasip1.
Runtime: Node.js 24.19.0 WASI Preview 1. Each command has a 120-second external timeout.
Dedicated build paths prevent contention. No CADCore/full CADGeometry/L3-L6 target
was rebuilt. L2 is used only by the selected-root plane fixture, not by production DI.

## Review and findings

One scoped review follows the actual construction/query/retention/failure paths.
Unbounded-map proof reuse accepted a retained algebraic coefficient under a zero
coefficient-depth budget: the focused RED reproduces mapDepthAccepted; the GREEN
admits all retained words and the coefficient-field owner. The scope-limited
reconfirmation checks this same path; foreign algebraic coefficient-field owners
are refused even for unbounded selections; no additional broad review was performed.
Intermediate source depth is retained in composed identity evidence. Both original
boundary polynomial owners survive coefficient/ring transfer. Whole declared
boundary tests refuse equal endpoints with an unequal interior; a three-source chain
refuses a lowered source-depth limit even when the endpoint sources have depth zero.
Intrinsic incident transports retain selected longitude scopes. No source equality
is inferred from residuals, sampling, nearby roots or XYZ coincidence.

## Ownership and synchronization matrix

| Logical state | Native / normal WASM / Embedded WASM storage | Access / release |
|---|---|---|
| Source/chart/frame/proof | Immutable Sendable owners and COW buffers | Owner-backed values/views; ARC/COW lifetime |
| Same admission | Exclusively borrowed inout A: ~Copyable | Synchronous query scope; final cancel before publication |
| Temporary construction buffers | Invocation-local mutable arrays | Never shared with concurrent queries; released on return/throw |

No shared mutable state, target-specific lock removal, unchecked Sendable or unsafe
pointer boundary was added. The existing L0/L2 scoped admission bridge is unchanged.
Native immutable-reader/task-cancel test is separate from synchronous WASI proof;
WASI results do not claim multi-threaded runtime scheduling or shutdown semantics.

## Reproduction and binding

receipt.json binds exact source hashes, compiler inventories, toolchain/SDK IDs,
products and logs. compiler-inputs.json is read from actual SwiftFileList files for
each lane, not inferred from declarations. source-hashes.json includes the owning
verification package/config/scripts and all compiled production sources.

Run `python3 Tests/OriginalDomainIdentityVerification/Scripts/VerifyEvidence.py --evidence Tests/OriginalDomainIdentityVerification/CompletionEvidence`.
Historical Evidence remains pinned to the earlier DI.0 snapshot; its hash receipt
is not rewritten to generalize old success to the current foundation.
