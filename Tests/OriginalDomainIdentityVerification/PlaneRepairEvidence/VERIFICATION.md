# Stored-N Plane Reference-Axis Repair

The authoritative source remains stored finite nonzero N and origin. The public
OriginalPlaneBasisIssuing.referenceAxis requirement and Default issuer share the
exact original-component comparison documented in the source design. Candidate
lengths remain caller-owned exact values; no root solver or upper CAD dependency
is added. Previously retained basis receipts preserve their original U/V.

The new regression fails on the old implementation with invalidChart for N=(0.5,0,0).
The repaired Native suite passes all 16 tests. After adding direct axis-query work
and terminal-cancel checks, the changed test is recompiled and passes in native-final;
all other test bodies are unchanged. The final deterministic Native proof also passes.
ASAN runs all 16 final tests. The owning SourceIssuer suite passes all 5 tests.
Normal and Embedded WASM compile/link and execute the same final synchronous fixtures.

The plane regression covers 21 axial/oblique inputs: positive/negative/nonunit
normals, least-positive subnormal and greatest-finite components, both reference
axes, exact basis coefficients and position/UV round trips. Existing algebraic
sqrt(2), incorrect rounded root, off-plane, retained depth, storage and final
cancellation tests are preserved. Work, storage and depth caps are unchanged.

Swift 6.4.0 release with matching normal/Embedded WebAssembly SDKs;
wasm32-unknown-wasip1, Node 24.19.0 WASI Preview 1. Test/build commands have 120s
external limits; proof executions have 30s limits. Dedicated cloned build paths
preserve the original historical products. Copied WASM Clang module caches first
failed because of absolute cache paths; only the new derived module caches were
removed before the successful builds. No full CADGeometry/CADCore/L3-L6 build.

One finding-specific review checks actual binding, axis selection, candidate-length
validation, immutable ownership and typed failure propagation. No open scoped finding.

| State | Native / normal WASM / Embedded storage and access |
|---|---|
| Source/basis | Same immutable Sendable source/field owners, retained exact coefficients |
| Axis/local buffers | Invocation-local values, no shared mutable state or new unsafe boundary |
| Admission | Same exclusively borrowed inout caller, charged work and terminal checkpoint |

DI.4 remaining consumers/source families and seven/full87 acceptance remain open.
The old CompletionEvidence remains pinned to 0b52e18c. This evidence independently
binds the repaired production inputs, actual compiler lists, proof products and logs.
