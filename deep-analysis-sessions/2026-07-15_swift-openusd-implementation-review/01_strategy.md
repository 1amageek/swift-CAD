# Review strategy

## Decomposition

| Perspective | Question | Evidence |
|---|---|---|
| Architecture | Is one typed representation canonical? | Public types, readers/writers, stage mutation paths |
| Interoperability | Do authored files work in official OpenUSD? | `usdchecker`, `usdcat`, reverse conversion oracle |
| Correctness | Do critical byte, writer, and composition paths pass? | Focused Xcode test suites |
| Security | Are size, depth, nesting, and work bounded? | Decoder traversal and public reading options |
| Performance | Are copies and regressions controlled? | Borrowed storage, benchmarks, CI threshold |
| Portability | Do supported platforms build with coherent contracts? | macOS and fresh WASM builds, concurrency types |
| Integration | Can swift-CAD adopt the current revision? | Dependency pin, adapter protocols, direct typecheck |
| Maintainability | Is responsibility split reviewable? | Source/test line distribution and policy checks |

## Inference method

Claims are accepted only when supported by a source trace or executable verification. Passing a format oracle is treated as evidence of the covered operations, not proof of complete OpenUSD parity. A successful package build is not treated as proof that swift-CAD adapters compile against the new public API.

## Priority model

- P1: blocks swift-CAD adoption or permits unbounded processing of untrusted input.
- P2: risks invariant divergence, cross-platform contract mismatch, misleading diagnostics, or high maintenance cost.
- P3: local warning or cleanup without behavioral impact.
