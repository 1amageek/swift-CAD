# Lower-Layer Performance Verification

## Baseline

Production baseline: `36db4d7c`, Swift6.4.0 Native debug (`-Onone`), dedicated
`.build/l3-native`, two build jobs. The unchanged weighted original-equivalent
closed TUV fixture and actual three-stage coefficient tower each run three times
per fresh process, in three processes. All original checks and caller limits run.
Weighted elapsed batches: 6.620089334, 6.802033875, 6.642807584 seconds; median
6.642807584. Tower: 1.573528875, 1.599913208, 1.552997292; median1.573528875.
Weighted work2409963, generated-storage103174098, depth28/0, full245/isolated1.
These are admitted generation totals, not allocator bytes or peak memory.

An independent eight-query process was sampled for five seconds at 1ms. The
retained compressed macOS sample shows polynomial division/multiplication entering
`ExactAlgebraicScalarDomain.sign`, then `polynomialSign`, root-source binding,
Sturm/Tarski and ancestor scalar operations. Measurement excludes this sampling
process. Inspect canonical unit denominator and constant scalar work at this
existing L2 boundary; preserve selected-root and original-law proofs.

## Scope

No upper CAD build, publication or seven-requirement completion is inferred.
Native debug timings do not establish release or WASM performance.

## Adopted Optimization

L2 uses its sole fraction issuer's existing exact unit-denominator invariant to
avoid multiplication by one and repeated denominator sign proof. Constant
polynomial signs validate root/polynomial owner and causal depth, then delegate
to the retained parent field. Admitted base scalar comparisons call Base.compare.
Nonconstant selected-root sign, modular inverse, original denominator rejection
and common local-law proofs retain their algorithms. No additional cache, mutable
shared state, unsafe boundary, external dependency or solver is introduced.

`comparison.json` records all three fresh-process samples. Weighted median falls
6.642807584 → 6.047367458 seconds (8.96% reduction); actual three-stage tower
1.573528875 → 0.630633167 seconds (59.92%). Every after sample is below every
before sample for each workload. These timings cover the complete unchanged
fixture, including preparation and exact result checks, in Native debug only.
The fixture source bytes are unchanged from the baseline. No release, WASM or
upper CAD speedup is claimed; their performance has not been compared here.

Weighted Native/ASAN work2037096/storage83746622/depth28/0; both WASI builds
work2009160/storage42403698/depth28/0, unchanged full245/isolated1. Original
work16777216/depth32 and fixture storage allowances are preserved. Admitted
storage measures cumulative generated payload, not allocator count or RSS.
Retained unit polynomials share their immutable backing; no new payload is
charged when it is reused. All new generated payload remains admitted.

## Verification and Review

Swift6.4.0 Native71 and ASAN71 pass, including the new public canonical-scalar
fixture; normal and Embedded WASI L3Proof execute all composed fixtures with
Node24.19.0. Matching Swift SDKs/triple wasm32-unknown-wasip1, Embedded WMO/Onone
and Unicode archive match the prior pinned environment. Final logs, actual
compiler inventories, configuration markers and224 project input hashes bind
these results. Scoped runner/guard bytes match their retained prior receipts.

One overall source/behavior review verifies every fraction-storage construction
returns through normalization, all selected-root calculation receipts remain
immutable, polynomial degree validates owner/depth before constant shortcuts,
and original root depths remain admitted. Public base comparison admits both
operands; every path retains entry/terminal checkpoints and the same caller.
CanonicalScalarFixtures independently bind public root-sign queries for zero,
either sign and the original quadratic relation, and check arithmetic restoration,
base comparison, exact work/storage N and rejection at N-1, refined inherited
coefficient depth, final cancellation, sibling rejection and uncancelled zero
divisor. Existing local-law, tower, owner-lifetime, complete-cell and failure
fixtures remain passing. No open scope-owned finding remains.

The reviewed changed production files contain immutable stored values and only
query-local mutable temporaries. Conditional imports solely name the independent
verification modules; Native/WASM/Embedded storage, Sendable and admission
contracts have no conditional split. Existing scoped pointer forwarding is
unchanged and ASAN is clean. L0/L1 production input hashes equal the baseline.
L4–L6, geometry publication, main and Claude working snapshots are untouched.
