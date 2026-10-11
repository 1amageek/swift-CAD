# Changed self-query attribution

This single diagnostic transcribes the admitted v5 self-query/refiner bodies, specializing their generic types to the actual retained ruled family and adding ledger reads/logs only. `QueryOriginalBody.txt`, `RefinerOriginalBody.txt` and their instrumentation diffs preserve the comparison. Every raw pair, diagonal, predicate compilation, exact comparison, refinement and admission stays in production order. It reuses the successful v5 port; no production or lower body was changed.

| Observation | Actual result |
|---|---|
| Same sealed-owner candidates | 22 |
| Complete predicate matches | 22 |
| Reused refinements | 22 |
| Completed unique refinements | 20, costing 7,424,214 work |
| Failing actual pair ordinal | 42: first 6, second 0; canonical key (6,0); 3 raw selected cells |
| Before 21st unique refinement | Work 7,805,460; storage 226,517,908 |
| That refinement's raw readmission | 133 work |
| Failure | `refine-pullback`, work 8,388,608, next request 1, storage 245,113,515 |

The checked alias path is exercised and succeeds. The operation still exhausts the unchanged work ceiling during an independent canonical relation refinement, specifically the reverse endpoint seam. This diagnostic does not publish a complete self result or reach the final residual oracle. It does not establish the cost of the remaining six actual pairs.

The preparation/raw and prepared-query operations keep independent caller-owned admissions, each work 8,388,608, storage 400,000,000, value/coefficient depth 32. No admission is reset inside an operation. Oracle inspection remains after publication and is not reached.

Compile 2.495 s; runtime 8.818 s; runtime peak owned RSS 40,816 KiB. Fixed Swift 6.4.0, 120 s wall/CPU per process, compiler parallelism 2; no timeout or surviving owned descendants. All source/product/log premises were admitted before and after the diagnostic. The actual typed work failure is expected by the diagnostic runner, so its `success: true` means successful attribution only; `cellComplete: false` remains explicit.

- Diagnostic receipt: `9a83842d4fa1d4077b9787a37d89d794fcfc55ada299d35c3e7e75aa229a073f`.
- Reused v5 successful port receipt: `0a6bed7b7927f24e33c6b10696d27de859f9bb72924dddb6b600e412adc33c84`.
- Durable exact text manifest: `equal-residual-cost-manifest.json`, SHA-256 `d87a6e48547202e95902a927d1edade9150b9dbae7c17616e3ceaba1d8e681e2`.

Earlier acceptance failure and all prechange diagnostics remain unchanged. No further execution or production change follows from this attribution without a separate causal assessment.
