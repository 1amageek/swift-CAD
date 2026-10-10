# M6.G First-Power Performance Verification

## Scope and Invariants

The measured production change is L3 specialization/evaluation of a first power.
`x^1` now imports the retained exact scalar instead of constructing one and
multiplying. The public field importer validates lineage, retained value/context
depth and cancellation. Higher powers and all source equations, root/UV coverage,
caller limits and immutable lifetime contracts are unchanged.

The unchanged real M6.G fixture constructs rational CS and positive-normal-offset
graph relations, refines retained L5 cells, and checks exact third boundaries,
algebraic descendant queries, foreign fields, auxiliary/empty results,
work/storage exact boundaries, source/value depth, entry/final cancellation and COW.
Its accounting changes only because the omitted arithmetic is no longer performed.

## Measurement Method

`profile.json` and `profile.sample.txt.gz` record the initial generation-admitted
Native process and its first15s CPU sample. The sample contains2230 stacks,
1645 beneath offset graph construction; this fraction describes only that window.
Nested scalar/admission forwarding and polynomial evaluation prompted the local
first-power optimization; no lower foundation redesign was required.

`benchmark.py` compares unchanged GraphProof inputs using Swift6.4.0 debug settings.
Three pairs run serially in alternating order, each in a fresh process with a120s
timeout. Generation admission and post-run hashes are outside the timed interval.
Both elapsed and process CPU time are retained. Other independent Swift builds
were present during initial observations, so the profiled45.471s and first
candidate52.790s are diagnostic runs, not the accepted speedup comparison.
Baseline source overrides must equal the committed3e540921 generation snapshot;
compiler, emitted modules/objects/product and logs must retain their exact hashes.
The candidate admits current source bytes. No stale product is relabeled current.

## Reproduction

Generate new lanes without overwriting repair evidence:

```sh
python3 Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/run.py native --output <fresh-output>
```

Compare the preserved generation receipts:

```sh
python3 Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/benchmark.py --baseline Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/repair/native/generation.json --candidate Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/performance/native/generation.json --baseline-commit 3e540921 --output <fresh-comparison-output> --repeats 3
```

## Acceptance

The accepted serial Native comparison (`comparison/receipt.json`) records:

| Metric | Baseline | Candidate | Reduction |
|---|---:|---:|---:|
| Median elapsed seconds | 29.287 | 27.160 | 7.3% |
| Median process CPU seconds | 29.067 | 26.593 | 8.5% |
| Refinement admitted work | 523773 | 455718 | 13.0% |
| Refinement admitted storage bytes | 15440329 | 14351449 | 7.1% |

All six processes pass identical behavioral assertions. Elapsed runs in order are
baseline51.639, candidate29.560, candidate27.160, baseline29.287, baseline26.916,
candidate22.640 seconds. Timing varies materially across this session; this is a
small local improvement, not a universal whole-CAD latency claim. Storage denotes
admission-accounted cumulative payload, not resident process memory. Initial
concurrent-build runtime and CPU sampling are excluded from these medians.

Portable/sanitizer acceptance and independent main delivery follow actual checks. No CADCore/CADGeometry/Kernel or
L6 production target is built. This isolated M6.G performance result does not
establish M7/M8 or whole-seven/full87 completion.

## Diagnostic Package Contention

The first concurrent ASAN/normal-WASM attempts stopped before compilation:
SwiftPM's shared package-inspection scratch lock wrote a waiting message before
JSON on stdout. `failed-asan-package` and `failed-wasm-package` preserve these
logs and successful metadata-command exit codes; neither is accepted build or
runtime evidence. The two lanes were retried serially with fresh output paths.
Portable/sanitizer timing is verification timing, not part of the serial Native
speedup comparison. Independent artifact generation remains scoped to L0-L5,
DI/source and refinement, without CAD production targets or L6.

## Target Acceptance and Review

All four current source/compiler/artifact/log bindings match (`acceptance.json`).
The generation validator admits each lane before runtime. The same actual fixture
passes in each lane; ASAN instruments all isolated modules. Verification runtime
is distinct from the accepted serial comparison above:

| Lane | Runtime seconds | Result |
|---|---:|---|
| native | 52.790 | PASS |
| asan | 21.267 | PASS |
| wasm | 39.217 | PASS |
| embedded | 27.038 | PASS |

`review.json` records the one scoped review with no findings. Public import keeps
coefficient lineage and retained depth/cancellation authority, without new shared
state, unsafe access or platform-specific ownership. Main delivery remains a
separate integration gate; no further review cycle is required by this source.
