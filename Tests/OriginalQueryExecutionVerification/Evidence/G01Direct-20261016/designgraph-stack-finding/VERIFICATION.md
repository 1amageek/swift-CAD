# Drawing operation-contract stack finding

The real three-test Drawing fixture built and then failed with SIGBUS in 0.967 seconds. The new Native boundary theorem had already allowed the original curved `DocumentEvaluator.evaluateExact` to finish. The normal-worker `projectEdges` path failed in `DesignGraph.validateOperationContract`, reached through actual `CADDocument.validate`. This was a stack-guard fault, not a solver timeout or empty-result proof. The failed receipt and direct stage/runtime logs remain failed records.

[before-frame-finding.json](before-frame-finding.json) binds the actual IPS and executable to the exact dispatcher prologue. The old Native unoptimized frame reserved 200,176 bytes before dispatching to its selected operation helper. That old function was byte-identical to the latest-main implementation. The existing `FeatureOperationKind` contract already requires tag-first dispatch to avoid copying all operation payloads into one frame.

The fix switches on the original immutable kind and moves eight inline validation bodies into private `@inline(never)` helpers. [case-comparison.json](case-comparison.json) proves all 68 case positions, 60 unchanged case bodies, eight moved validation bodies and initial duplicate-input/output guards are preserved. Three new private extraction guards reject impossible kind/payload mismatches explicitly; public APIs, source mathematics, validations, errors and resource ceilings retain their meanings.

[after-dispatch-disassembly.txt](after-dispatch-disassembly.txt) measures the fresh Native dispatcher at 15,456 bytes. [upper-fixed-receipt.json](upper-fixed-receipt.json) records successful actual IR-through-SwiftCAD generation against receipt-verified unchanged Core/Geometry/Topology. This compilation/frame evidence does not replace the same Drawing caller runtime gate. The fixture, normal-worker queries, expected exact/contact results and original N/N-1/cancellation checks remain unchanged. No stack limit is raised.

The source change is confined to the concrete operation-contract finding. It adds no shared mutable state or target-specific isolation and retains the existing public `Sendable` value contracts. Geometry portable products and unrelated lower/common source proofs are unaffected.

Copied-file hashes and original evidence paths are in [provenance.json](provenance.json). This record does not establish whole Drawing, U1-U4, G01 or the seven requirements.
