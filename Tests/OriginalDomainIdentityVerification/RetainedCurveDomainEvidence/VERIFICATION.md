# Retained curve domain verification

Scope: DIA.4.I.M4.P.DC consumes the sealed normalized retained curve source from commit6b9a7d20. Full M4/M5/M6 and all seven requirements remain open.

| Executed path | Result |
|---|---|
| Native / ASAN | 42 tests each pass. |
| Ordinary / Embedded WASM | Full DomainProof compile/link/runtime pass using Swift6.4.0 and matching SDKs. |
| Actual source-to-DI | OriginalDerivativeCurveSourceProof passes the genuine Hermite/plane-constraint source-to-DI full/singleton/empty handoff, exact identity T and public point/differential correspondence plus storage/depth/tolerance failures. |

RetainedCurveDomainFixtures calls public frame/issuer/finite-family queries. The exact nonbinary1/3 cut preserves both original closed sides, chart ordinals, original XYZ/D laws and identity T. Full/strict/singleton/disconnected/empty selections, source/law lifetime, foreign owner, malformed tuple/cycle/template and independent work/storage/source/transport/chart/family limits are exercised. Exact measured work/storage budgets pass and one-less limits fail. Entry and terminal success/exclusion cancellation propagate explicitly.

The implementation consumes the complete source witness and assumes its documented original whole-cell/nonzero-denominator positional authority. Existing scalar admission, map restriction/inverse and complete-cover contracts own the lower proof. Immutable family/map/cover owners are retained; no coefficient producer, solver, shared mutable state, unsafe storage or target-specific synchronization is added. The four implementation files contain immutable stored properties, computed views and operation-local arrays only. No unmeasured zero-copy or performance improvement is claimed.

One scoped implementation review found no unresolved violation. Earlier fixture corrections preserved existing production contracts and preceded the stable four-lane snapshot. receipt.json binds420 identical component inputs,1835 current actual compiler premises, two retained generated inputs, five products, eight raw logs and exact commands/toolchain/timeouts. Actual Native compile137.61 seconds completed within its300-second guard; runtime and query budgets are unchanged. No unrelated cached proof file lists are treated as current acceptance. Main delivery is recorded by the accompanying integration commit.
