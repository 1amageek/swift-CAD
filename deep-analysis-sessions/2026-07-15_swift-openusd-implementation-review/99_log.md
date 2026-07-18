# Analysis log

| Time | Action | Result |
|---|---|---|
| 2026-07-15 | Checked repository state and recent commit range | `main` clean at `2c943c7`, equal to `origin/main` |
| 2026-07-15 | Inspected typed Sdf, codec, composition, byte-storage, and safety paths | Major architectural rewrite confirmed |
| 2026-07-15 | Built macOS package | Passed |
| 2026-07-15 | Built for testing | Passed; one non-mutated variable warning |
| 2026-07-15 | Ran four focused suites once with external 30-second timeout | 67 passed, 0 failed |
| 2026-07-15 | Built from a fresh WASM scratch path | Passed |
| 2026-07-15 | Verified public symbol graph | 1630 symbols |
| 2026-07-15 | Verified upstream fixture inventory | 59 rows, 79 tests, 107 fixture patterns |
| 2026-07-15 | Required installed official OpenUSD oracle | USDA, USDC, USDZ and reverse conversions passed |
| 2026-07-15 | Typechecked swift-CAD adapters against latest modules | Reader conformance, `USDCLayer`, `readLayer`, and error-switch incompatibilities confirmed |
| 2026-07-15 | Traced reader recursion and options | Missing end-to-end byte/entity/nesting/time budget confirmed |
