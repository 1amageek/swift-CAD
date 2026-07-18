# swift-OpenUSD implementation review brief

## Objective

Evaluate whether the large swift-OpenUSD rewrite is materially correct, sufficiently robust, and ready to be consumed by swift-CAD.

## Scope

- Repository state at `2c943c75ef9c0c32974663b13441a0972bec7d3e`.
- Typed Sdf architecture, USDA/USDC/USDZ codecs, composition, performance, security, portability, diagnostics, tests, and swift-CAD integration.
- File/data compatibility is evaluated. C++ OpenUSD source/API compatibility, Hydra, Imaging, and non-core schema completeness are outside the declared implementation scope.

## Decision questions

1. Is the improvement substantive and supported by executable evidence?
2. Can swift-CAD update its dependency revision without source migration?
3. Are readers sufficiently bounded for untrusted CAD assets?
4. Which corrections should precede broader feature work?

## Evidence standard

Repository inspection is combined with fresh macOS and WASM builds, focused tests, public-symbol verification, parity inventory, and an installed official OpenUSD toolchain oracle.
