# Investigation Log

## 2026-08-23

1. Read the repository completion contract, roadmap, specification, package manifest, public API, implementation paths, tests, and recent worktree state.
2. Mapped the Agent path from Codable commands and queries through document evaluation, exact geometry, BRep validation, persistence, and exchange.
3. Ran the public-contract inventory and capability-ledger checks.
4. Built the SwiftCAD product with the configured Swift 6.4 snapshot.
5. Ran policy, zero-copy, tolerance-contract, and whitespace checks.
6. Reused the same-worktree full CADKernel result (590 tests in 62 suites) and ran a current focused CADKernel capability/loft test selection (35 tests).
7. Attempted facade and exchange test execution. Both test targets failed during compilation because exhaustive switches had not adopted the new same-parameter-image case.
8. Traced the supported surface-surface intersection contract through canonicalization, procedural offset/ruled surface producers, the default intersector, and the Boolean caller.
9. Traced the public curve closest-point query to its finite-sampling and local-Newton implementation.
10. Inspected representative partial feature evaluators and their topology envelopes.
11. Confirmed that formal evidence manifests and an external interoperability corpus are absent.
12. Synthesized the result using capability coverage, compositional closure, and release-gate frameworks.

## Confidence updates

| Claim | Prior | Posterior | Update |
|---|---:|---:|---|
| The Agent-facing substrate is substantial | 0.65 | 0.91 | Public path, product build, inventory, and kernel behavior agree |
| General complex-product generation is achieved | 0.50 | 0.03 | Critical partial capabilities and a direct composition gap refute it |
| The project is release-ready | 0.40 | 0.01 | 0/8 gates, no manifests, and two integration test targets do not compile |
| Constrained alpha workflows are usable | 0.55 | 0.86 | Supported exact foundations and behavioral tests support bounded use |

## Limitations

- No product source edits were made as part of this assessment.
- The worktree contains extensive pre-existing modifications, so findings describe the observed workspace rather than a clean released revision.
- External CAD applications were not used as round-trip oracles because no repository corpus or configured oracle workflow exists.

## 2026-08-23T09:52:00+09:00 — Evidence refresh after implementation changes

1. Re-ran the public inventory, capability ledger, and goal-contract checkers: 75 routes; 67 capabilities with 38 supported and 29 partial; 114 envelopes; 540 fixture bindings; 0/8 gates.
2. Incorporated the current full CADKernel result: 591/591 tests in 62 suites.
3. Re-ran SwiftCAD-Tests with the pinned Swift 6.4 snapshot. The target compiles and executes; 29/31 tests pass, while two complex Boolean tests exceed the one-minute execution allowance.
4. Re-ran CADExchange-Tests with the same toolchain. All 237/237 tests pass.
5. Added the validated-curve performance evidence: 104.326 seconds with timeout to 20.474 seconds for the representative patch-network path, and more than 60 seconds to 24.564 seconds for the merged network path.
6. Replaced obsolete facade/exchange compile-failure claims throughout the ontology, report data, visuals, and synthesis HTML.

## Confidence updates — current evidence

| Claim | Prior | Posterior | Update |
|---|---:|---:|---|
| The Agent-facing substrate is substantial | 0.91 | 0.96 | Public facade execution, 591 kernel tests, and 237 exchange tests agree |
| General complex-product generation is achieved | 0.03 | 0.04 | Six promotions do not close the remaining 29 composition-critical envelopes |
| The project is release-ready | 0.01 | 0.01 | Two facade performance failures, 0/8 gates, no manifests, and a dirty worktree remain |
| Constrained alpha workflows are usable | 0.86 | 0.91 | Current public-path and exchange behavior provide stronger bounded-use evidence |

## Updated limitations

- Product source changes and test-contract fixes are included in the observed worktree; the assessment is still not tied to a clean commit.
- The successful STEP/IGES tests establish the repository's declared subset behavior, not interoperability with an external CAD oracle.

## 2026-08-23T11:50:00+09:00 — Current-worktree execution refresh

1. Re-ran the capability and public-contract checkers: 67 capabilities, 38 supported, 29 partial, 114 envelopes, 545 fixture bindings, and 75 public routes.
2. Built every test product successfully with the pinned Swift 6.4 development snapshot.
3. Ran CADKernelTests from the current build product: 602/602 tests in 62 suites passed in 357.867 seconds.
4. Ran CADExchangeTests from the current build product: 237/237 tests in 12 suites passed in 84.405 seconds.
5. Ran the complete SwiftCADTests bundle under a 900-second process deadline. The run did not complete: a certified-surface-lift join passed in 70.599 seconds, a general torus-torus intersection passed in 308.880 seconds, and the process deadline expired during the following torus-torus difference case.
6. Confirmed 0/8 final gates, zero evidence manifests, and 465 dirty worktree entries at HEAD `10d3416159e4`.
7. Confirmed that no `FIXME(INCOMPLETE_IMPLEMENTATION)` marker exists in `Sources` despite 29 callable partial capabilities; this weakens incomplete-path auditability and must be reconciled before a completion claim.

## 2026-08-23T13:35:00+09:00 — Inventory and Agent-entry refresh

1. Re-ran the capability, public-contract, and goal-contract checkers: 75 routes; 67 capabilities with 38 supported and 29 partial; 115 development envelopes; 546 fixture bindings; 0/8 gates.
2. Confirmed the current worktree has 474 porcelain entries at HEAD `10d3416159e4` and zero `Evidence/G0.json` through `Evidence/G7.json` manifests.
3. Rebuilt the SwiftCAD facade and directly observed `CADCommandPipelineTests.pipelineExposesSharedCapabilitiesAndQueries` and `KernelQueryPipelineTests.allSerializableRequestsRoundTripThroughKernelQuery` pass. Xcode's Swift Testing selection expanded beyond the requested tests, so the broader run was stopped and is not reported as a full-suite pass.
4. Confirmed one explicit `FIXME(INCOMPLETE_IMPLEMENTATION)` now marks the non-contractible periodic pcurve Boolean path. The marker improves auditability but also records a live production limitation.
5. Retained the latest full behavioral evidence with its revision scope: CADKernel 602/602 preceded the latest periodic-topology changes, which have target-build and focused-regression evidence; CADExchange 237/237 remains the latest full exchange result. The most recent complete facade attempt exceeded its 900-second process deadline in high-cost torus-torus Boolean work.

## 2026-08-23T14:18:00+09:00 — Essential periodic Boolean refresh

1. Re-ran the capability, public-contract, and goal-contract checkers: 67 capabilities with 38 supported and 29 partial, 115 envelopes, 546 fixture bindings, 75 public routes, and 0/8 gates.
2. Confirmed `git diff --check` passes and no `FIXME(INCOMPLETE_IMPLEMENTATION)` marker remains in `Sources`.
3. Read the current shared `CADCommand` / `KernelQuery` / `DocumentEditor` / `CADPipeline` / feature-evaluation path and reconfirmed that partial capabilities are executable but not supported-complete.
4. Reconfirmed the supported `GEO-INTERSECTION-002` catalog claim still includes every validated surface representation pair while the concrete dispatcher rejects unrecognized procedural pairs.
5. Ran six focused tests from the current build products: essential periodic cylinder strip materialization; valid seam acceptance; invalid duplicate-edge rejection; upper-period pcurve trim retention; shared capability/query exposure; and serializable KernelQuery round trip. All six passed.
6. Updated the synthesis: the periodic Boolean root defect is materially improved, but the project remains an advanced constrained alpha because 29 composition-critical capabilities and all eight formal gates remain incomplete.

## Confidence updates — periodic Boolean evidence

| Claim | Prior | Posterior | Update |
|---|---:|---:|---|
| The Agent-facing substrate is substantial | 0.96 | 0.97 | Current shared-entry and periodic topology behavior agree |
| Constrained alpha workflows are usable | 0.91 | 0.93 | An essential periodic intersection now reaches exact validated BRep |
| General complex-product generation is achieved | 0.04 | 0.04 | The new envelope does not close 29 partial capabilities or representation composition |
| The project is release-ready | 0.01 | 0.01 | Full regression, G0-G7 manifests, and a clean revision remain absent |

## 2026-08-23T14:49:00+09:00 — Exact representation and global projection refresh

1. Re-ran the public contract, capability ledger, and goal contract checkers: 75 routes; 67 capabilities with 38 supported and 29 partial; 115 envelopes; 546 fixture bindings; 0/8 gates.
2. Confirmed the observed workspace remains at HEAD `10d3416159e40aef24da935ed78be40a29dd3de2`, with 484 porcelain entries, zero formal evidence manifests, zero incomplete markers, and a passing whitespace check.
3. Rebuilt CADGeometryTests and CADKernelTests with the pinned Swift 6.4 development snapshot after the representation and projection changes.
4. Ran six focused current-worktree tests: global B-spline boundary closest point; typed unclosed-bound failure; ruled-plane exact intersection with original-chart JSON round trip; ruled-ruled exact intersection; B-spline document-query projection; and certified ruled pcurve sewing into an exact validated BRep face. All six passed.
5. Updated the ontology and report to distinguish closed ruled-surface behavior from the residual general procedural-offset gap and residual curve/directional query heuristics.

## Confidence updates — representation and query evidence

| Claim | Prior | Posterior | Update |
|---|---:|---:|---|
| The Agent-facing substrate is substantial | 0.97 | 0.97 | The new behavior strengthens an already high-confidence foundation claim |
| Constrained alpha workflows are usable | 0.93 | 0.94 | Exact ruled composition and globally bounded B-spline closest point pass end-to-end |
| General complex-product generation is achieved | 0.04 | 0.04 | General procedural offsets, residual query heuristics, and 29 partial capabilities remain |
| The project is release-ready | 0.01 | 0.01 | G0-G7 remain 0/8 with no clean-revision manifests |

## 2026-08-24T08:55:00+09:00 — Periodic chart ownership and Release behavior refresh

1. Traced the incorrect general torus–torus volume through parameter evaluation, Geometry-owned universal-cover lifting, Topology loop alignment, Green integration, shell flux composition, and the public Boolean result.
2. Removed the second midpoint-based chart normalization from Topology. Geometry now owns within-curve continuity; Topology owns only integer-period translations between complete coedges.
3. Replaced the fixed-sample contract for explicit and certified implicit pcurves with derivative-bounded subdivision, protected the floating-to-integer budget boundary, and made the stored midpoint an exact `t = 0.5` sample.
4. Added balanced outward-rounded interval composition for certified analytic-pair area and flux cells.
5. Re-ran the capability, public inventory, goal, Swift policy, zero-copy, tolerance, package-boundary, and incomplete-marker audits. Current inventory is 67 capabilities, 39 supported, 28 partial, 115 envelopes, 556 fixture bindings, 75 public routes, and 0/8 formal gates.
6. Rebuilt macOS Debug and Release test products with the pinned Swift 6.4 snapshot. Focused Debug suites passed 46/46 across chart lift, general torus–torus differential bounds, general cone–torus periodic lift ownership, trimmed analytic volume, and analytic-pair area/flux.
7. Ran the three public general torus–torus Boolean operations independently in Release: intersection passed in 41.976 seconds, difference in 46.624 seconds, and union in 41.254 seconds.
8. Built and linked the complete SwiftCAD graph for iOS Debug and visionOS Debug. The iOS Release attempt reached its explicit deadline during CPU-bound whole-module optimization and is not reported as a successful Release platform build.
9. Built `CADWASMSmoke` in Release for normal WASM and executed it successfully under Node/WASI. Embedded WASM reached the documented `Foundation` boundary and remains unsupported without target-specific synchronization weakening.
10. Ran the complete optimized SwiftCAD facade bundle. The first run exposed one remaining cone–torus volume error: Geometry supplied a certified continuous lift only for the torus–torus pair, so the torus-role pcurve fell back to fixed sampling after Topology's duplicate normalization was correctly removed.
11. Generalized the Geometry contract to every certified analytic-pair pcurve on a nonsingular periodic elementary chart and added a cell-level 3D equivalence regression. Existing cone–torus expected values and tolerances were unchanged.
12. Re-ran the three public cone–torus Boolean operations in optimized Release; all passed in 7.541 seconds total. The complete SwiftCAD facade then passed 181/181 tests across 69 suites in 244.344 seconds with zero failures.

## Confidence update — periodic ownership evidence

| Claim | Prior | Posterior | Update |
|---|---:|---:|---|
| The Agent-facing substrate is substantial | 0.97 | 0.98 | Public Release Boolean behavior, multi-platform builds, and capability contracts agree |
| Constrained alpha workflows are usable | 0.94 | 0.96 | The most expensive analytic Boolean suite now finishes predictably with certified volume |
| General complex-product generation is achieved | 0.04 | 0.05 | One central periodic Boolean defect is closed, but 28 partial capabilities remain |
| The project is release-ready | 0.01 | 0.02 | Current targeted and platform evidence improved, while G0–G7 and external evidence remain absent |
