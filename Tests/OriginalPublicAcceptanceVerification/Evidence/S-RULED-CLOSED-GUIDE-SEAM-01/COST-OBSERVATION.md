# Same-Ledger Pair and Stage Diagnostic

This additional observation attributes the original raw work stop without replacing the frozen O result. `STOP.md` and its 162-file `raw-manifest.json` remain unchanged. This diagnostic is not production acceptance, a completed raw product, or a passed equality/seam oracle.

The sole diagnostic runtime completed the first 48 ordered pairs and exhausted work during decomposition of the last zero-based pair `(6,6)`. The result distinguishes cumulative consumption across the complete 49-pair request from a first-pair resource failure.

| Pair / boundary | Cumulative work | Cumulative storage bytes |
|---|---:|---:|
| (0,0) start | 69,278 | 767,732 |
| (0,0) compile complete | 69,823 | 793,204 |
| (0,0) decompose complete | 403,050 | 12,406,775 |
| (0,0) select complete | 407,044 | 12,411,072 |
| (0,0) project complete | 543,528 | 17,048,386 |
| (6,5) project complete | 8,195,372 | 261,116,192 |
| (6,6) start | 8,195,372 | 261,116,728 |
| (6,6) compile complete | 8,196,094 | 261,146,660 |
| (6,6) decompose: next work unit refused | 8,388,608 | 267,135,414 |

The last logged request is exactly one additional work unit. The original typed error remains `ExactParametricRelationFailure.cell(ExactRealCellFailure.scalar(ExactScalarFailure.resourceLimit(.work)))`. This does not measure the uncompleted pair's total cost or prove the remaining work below any hypothetical ceiling.

## Accounting and Source Premises

Preparation, source assertions, cover, graph family, ordered iteration, and all caller limits remain identical to the O fixture: one ledger, work 8,388,608, storage 400,000,000, value/coefficient depths 32, full 49 ordered pairs, maximumPairs 256, cell/topology limits as recorded in STOP. There is no per-pair ledger reset, skip, retry, or cap change. The successful two-body `RuledObservationAdapters` module was reused; no production or lower module was compiled.

The diagnostic transcribes the admitted current `DefaultOriginalIssuedGraphRelationResolver.resolve` body and the admitted `ExactParametricRelationDomain` graph `resolve` body. Driver assertions establish that the former is the suffix of the existing generated `DraftZeroRuledPort` compiler input, and that the latter's complete resolution extension equals its admitted `PublicLiftPlane` compiler-source snapshot. The original method bodies and exact instrumentation diffs are preserved. Concrete type substitutions identify precisely the existing generic instantiation; qualified nominal names resolve the admitted owners. `@testable` imports access the existing internal result initializers and unchanged domain topology/storage/depth helpers. They do not issue new authority or introduce a replacement lower algorithm.

The operations and accounting remain in the original order:

```text
same family admission / pair-array storage
  -> pair consumeWork(1)
  -> existing domain.compile
  -> checkpoint / source-depth admission / retained Cells
  -> existing cells.decompose
  -> existing cells.select
  -> existing topology.project
  -> original relation storage / depth / checkpoint
  -> original pair append
```

Read-only markers emit the cumulative ledger values after each stage; `consumeWork` prints the refused request and rethrows the exact failure. Diagnostic bookkeeping/logging is outside the CAD work/storage accounting. It adds ordinary process overhead, so diagnostic wall time is not a production performance benchmark.

## Terminal Runs and Failure Preservation

A first compile stopped before runtime in 0.535 seconds because the transcribed concrete helper retained an unqualified, ambiguous `NativeExactRelationFailure` and a generic `Base` name. Its failed receipt, generated proof, compiler log, and exact fixture/driver/generator snapshot are retained under v1. The sole causal correction qualifies the existing DraftZeroRuledPort error and substitutes the concrete field F; no stage, limit, or arithmetic changes. v2 then compiled and executed the diagnostic once. There was no earlier diagnostic runtime and no per-pair retry.

| Run | Wall seconds | Sampled CPU seconds | Peak owned RSS KiB | Exit |
|---|---:|---:|---:|---:|
| v1 transcription compile diagnostic | 0.535 | 0.18 | 168,752 | 1 |
| v2 diagnostic compile/link | 2.454 | 0.98 | 424,992 | 0 |
| v2 sole runtime | 5.580 | 4.90 | 32,240 | 1, expected resource stop |

Swift 6.4.0-RELEASE, arm64-apple-macos15.0, macOS27.0 SDK and two compiler threads are unchanged. Every process retains the 120-second wall/per-process CPU limit. No run timed out or left an owned descendant. Exact expanded commands, generated input, logs, monitor observations, and pre/post source/product/log admission are retained in the diagnostic raw receipts. All post-run admission checks passed.

The current driver is `Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamCostObservation.py`; generated-input assembly is preserved in `.build/create-guide-cost-observation.py`. The driver was executed once for v1 and once after the concrete compile correction for v2. The immutable generated inputs and command JSONs, rather than a new execution, reproduce their exact historical scope.

| Artifact | SHA-256 |
|---|---|
| Diagnostic fixture | `60496407daaeff617133ef0c52e6877c047dca6bb75728c6ac52e8e5a7eb255f` |
| Diagnostic driver | `c7d48883f7a0b3e5e4100611eef9d7f7a870d5f201afcb25a235f3f6c48e2c5c` |
| v2 terminal receipt | `132aa29f03276bcd9b0cdd1d66a055c156a51fb8c525ab983ec41159c55d2da2` |
| Separate 30-file text manifest | `f62bd6d1857a15e9dd8900ea0bbb637e6c5b539cd81f1dede0f6835439c98401` |

The receipt explicitly states `diagnosticOnly:true` and `cellComplete:false`. Its procedure success means the exact stage/cumulative failure was observed and admitted, not that the raw relation completed. Original O fixtures, receipt bytes, STOP, and raw manifest remain preserved. No production fix, additional runtime, or review is part of this diagnostic.
