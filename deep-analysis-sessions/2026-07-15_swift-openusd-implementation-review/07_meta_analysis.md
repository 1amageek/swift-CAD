# Meta-analysis

## Convergent evidence

The architectural and executable evidence agree that the rewrite is substantive. Typed Sdf storage, byte slices, writers, composition, decoder checks, benchmarks, macOS/WASM builds, focused tests, and the official OpenUSD oracle all converge on a materially stronger implementation.

The integration evidence independently shows that the same rewrite is not a drop-in update for swift-CAD. The public reader requirement moved to `USDByteSlice`, legacy USDC layer APIs became internal, and `USDError` gained cases. Direct adapter typechecking reproduces these incompatibilities.

## Counterevidence and limits

- The focused run covered 67 tests, not the entire test suite.
- Upstream parity inventory contains partial categories and one blocked area; it does not claim a complete OpenUSD runtime.
- The oracle validates representative USDA, USDC, and USDZ paths. It does not prove every value type, schema, or composition arc.
- Performance regression gates exist, but this review did not reconstruct a historical before/after benchmark series.
- Resource hardening is strong inside several USDC paths, but no public end-to-end processing budget covers all formats and composition.

## Confidence update

Initial expectation was that a large rewrite might be mostly structural. Fresh builds, focused tests, symbol verification, and official bidirectional oracle results raised confidence in substantive correctness to high. Direct swift-CAD adapter typechecking and unbounded traversal traces lowered confidence in immediate adoption and untrusted-input readiness.

## Final synthesis

Adopt the rewrite as the new development foundation, but gate the swift-CAD revision update on adapter migration and a shared `USDReadingLimits` budget. Then remove publicly mutable derived transform caches, unify the cache lock implementation, correct diagnostic interpolation, and split the largest parser/test units.
