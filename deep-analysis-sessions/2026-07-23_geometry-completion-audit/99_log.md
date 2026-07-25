# Analysis Log

## 2026-07-23T05:28:40+09:00

- Created a new current-state analysis session; retained the 2026-07-12 session as immutable historical evidence.
- Verified clean revision `a268a4ee21a3b7c4f224a798bfbeb1ed5bad8d83` before new work.
- Ran `Scripts/check_goal_contract.py`: consistency passed; completion remained 0/8.
- Ran `Scripts/check_capability_ledger.py`: 55 capabilities, 52 envelopes, 422 bindings.
- Inspected the Geometry capability catalog: 5 supported and 2 partial entries.
- Used `skltn` to locate the general torus-torus intersector, certified procedural curve, public dispatcher, and regression tests; opened each implementation path in original source.
- Initial hypothesis: the meridian-root condition can be a coordinate singularity rather than a singular 3D intersection. Confidence 0.65 pending direct mathematical and runtime evidence.

## 2026-07-23T05:42:22+09:00

- Tested a whole-surface analytic-to-rational B-spline fallback for the orthogonal congruent torus fixture; the focused test reached its five-minute limit and failed.
- Rejected that fallback as a production solution and removed the exploratory test from the working tree.
- Derived the exact congruent-centered factorization: the difference of the torus implicit equations is the product of the two axis-bisector plane equations.
- Identified four genuine second-order branch-contact points in the orthogonal fixture, disproving the stronger interpretation that every observed failure is only a coordinate singularity.
- Selected a specialized certified bisector-plane representation as the next implementation slice; Geometry remains incomplete and no completion claim is made.

## 2026-07-23T06:00:00+09:00

- Implemented the exact congruent-centered torus factorization into both axis-bisector planes.
- Preserved four mixed closed branches, exact dual pcurves, second-order branch contacts, deterministic operand/axis-sign invariance, residual certification, and strict decode-time branch reconstruction.
- Verified the focused torus-torus suite (5/5), full CADGeometry suite, capability contract (10/10), and capability ledger (55 capabilities, 53 envelopes, 424 bindings).
- Committed and pushed checkpoint `5990bba95f4bc63109ae9f53f22175821d036ff8` (`Support congruent torus intersection graphs`).

## 2026-07-23T06:19:30+09:00

- Audited the former plane-torus inner-support singular diagnostic and derived the actual locus: two self-loop branches sharing one nodal contact with four distinct half-branch tangents.
- Implemented arithmetic-gated inner-support certification, bounded branch domains, exact one-sided first/second double-root differentials, exact 3D evaluation, mandatory dual pcurves, residual certification, and strict decode reconstruction.
- Added axial and oblique nodal graph tests plus nearby non-nodal rejection guards; the full focused `SurfaceSurfaceIntersectionTests` suite executed 16 tests and all 16 passed.
- Retained typed failures for unresolved higher-order cases and did not add mesh, sampled, or silent fallback behavior.
- Ran the full CADGeometry suite successfully in 301.912 seconds.
- The first capability-contract build exposed six non-exhaustive switches in the downstream analytic-pair Topology area integrator. Implemented the new branch mappings and added an explicit typed unsupported boundary because its existing regular-pcurve proof cannot certify the nodal double root.
- Verified the analytic-pair Topology suite (9/9) and capability contract (10/10) after the downstream correction.

## 2026-07-23T07:10:00+09:00

- Re-audited the next undeclared `GEO-INTERSECTION-002` envelope from original source after structural scan.
- Traced parallel-offset torus-torus data through the interval certificate, procedural differential, analytic-pair lift, dual pcurves, derived B-spline cache, and intersection kind.
- Derived the rejected generator-tangency locus as four bounded self-loop edges grouped at two nodes, rather than an empty or unrepresentable singular result.
- Selected an arithmetic-gated nodal certificate and exact one-sided double-root differential as the root implementation; nearby non-nodal inputs and all undeclared tangencies must not be falsely admitted.

## 2026-07-23T07:15:00+09:00

- Implemented ENV-055 as four bounded mixed nodal self-loop edges at two certified contacts, including exact one-sided first/second derivatives, dual pcurves, deterministic operand/rotation behavior, and strict Codable reconstruction with tamper rejection.
- Corrected the derived-spline construction to use bounded rather than periodic endpoint differencing for nodal self-loops; this preserves the distinct half-branch tangents and removes the measured residual violation at the contact.
- Verified the focused parallel torus-torus suite (8/8), capability contract (10/10), capability ledger (55 capabilities, 55 envelopes, 432 bindings), ontology validator (19 Factor nodes, 6 groups), and goal contract consistency (still not achieved, 0/8).
- In the full CADGeometry run, every new nodal test passed. The pre-existing `GeneralConeTorusSurfaceIntersectionTests/operandOrderPreservesDeterministicThreeDimensionalCurves()` alone reached its four-minute time limit under parallel suite load. A correctly matched isolated rerun passed in 141.963 seconds; the earlier zero-test filter attempt was discarded from evidence.

## 2026-07-24T16:45:00+09:00

- Re-audited every current P0/P1 rejection through the public dispatcher, exact truth, pcurve, validation, Codable, and focused-test paths.
- Added direct certified apex-node continuations for sphere-cone, cone-cone, and cone-cylinder; added the exact ruling-parallel cone-cylinder reduction; and retained typed failures for undeclared higher multiplicities.
- Added an analytic near-nodal parallel torus-torus certificate. The inside offset returns two exact closed loops and the outside offset retains four regular branches without falsely claiming the nodal ENV-055 topology.
- Rejected the first cone-torus apex implementation because whole-surface rational B-spline subdivision exceeded the one-minute public regression budget. Replaced it with a pair-specific certificate that factors the common apex root, isolates the reduced cubic's constant-term and discriminant boundaries, and returns two apex-node loops plus the generator-fold loop.
- The cone-torus apex public regression now exercises both operand orders, strict Codable reconstruction, exact dual pcurve reconstruction, regular interior differentials, both generator-fold limits, and apex endpoints. Its runtime changed from a deterministic 60-second timeout to 0.925 seconds.
- Extracted the bounded B-spline domain map, exact-certificate protocol and default resolver, expansion arithmetic, and plane-height context from the general intersector. The public quartic ineligibility regression proves that a near-but-inexact quartic is rejected rather than accepted through a silent tolerance fallback.
- Focused sphere-cone, cone-cone, cone-cylinder, parallel torus-torus, and bounded B-spline suites passed together before the final cone-torus specialization. Final integrated and contract verification remains pending in this log entry; no full-Geometry or goal-completion claim is made.

## 2026-07-24T17:23:00+09:00

- Verified the final integrated P0/P1 Geometry set and the complete CADGeometry suite. The full suite passed in 311.909 seconds; the complete cone-torus suite passed separately in 273.168 seconds, and the final apex classification regression passed again after asserting mixed contact.
- Built the complete SwiftCAD package successfully. Exhaustive downstream classifications now route certified curves to generic evaluation where valid, report them as non-line/non-circle where required, and return typed unsupported errors for unproved rational transfer, mesh-error, and STEP/IGES contracts.
- Removed an unreferenced CADIR curve/source translation helper chain instead of duplicating certified-curve reconstruction in dead code.
- The aggregate package test compiled every production and test target. Its execution remains red on pre-existing feature-completion gates that intentionally raise `unsupportedCapability`; those failures are outside the P0/P1 Geometry envelope and were not converted to success.
- Re-ran the zero-copy, explicit-tolerance, and tolerance-contract policies over every changed production Swift file. The capability ledger passed at 55 capabilities, 56 envelopes, and 437 bindings; the goal contract remained consistently not achieved at 0/8; `git diff --check` and incomplete-implementation scans passed.

## 2026-07-24T17:51:00+09:00

- Recomputed the compiled capability inventory and found two false supported entries. Surface Trim and Surface Match publicly reject non-rectangular or multi-face sheets, so both were restored to partial. The compiled catalog and ROADMAP now agree at 23 supported and 32 partial entries.
- Traced the public surface-lift tangent path from certified scalar isolation through stationary refinement. Replaced the terminal singular diagnostic with an injected tangent-result resolver that independently verifies target UV range, reprojection residual, and normalized incidence before constructing `.tangent`.
- Added `ENV-057` and its focused fixture binding. The capability ledger passed with 55 capabilities, 57 envelopes, and 438 bindings.
- Corrected the tolerance-policy boundary so split `KernelCapabilities+*.swift` metadata files are treated consistently with the documented capability-metadata exception; production code outside that boundary remains prohibited from using implicit standard tolerance.
- Verified all 42 `CurveSurfaceIntersectionTests`. The full CADGeometry run passed every changed and related test; one unrelated torus-cylinder operand-order test hit its 120-second limit under parallel load, while the complete isolated torus-cylinder suite executed and passed in 61.965 seconds.
- Verified all 11 capability-contract tests, including the explicit guard that Surface Trim and Surface Match cannot be consumed as supported while their general public input domains remain unimplemented.
- The goal contract remains consistently not achieved at 0/8. `GEO-INTERSECTION-001` remains partial because ENV-057 is one bounded input/output envelope, not full public-domain closure.

## 2026-07-25T13:55:24+09:00

- Traced every public `Curve3D.certifiedIntersection` case through `DefaultCurveSurfaceIntersector` and found that the generic bounds path classified all five kinds as a B-spline control-hull `intersectionFailure`.
- Extracted exact source-surface identity into `CertifiedIntersectionCoincidenceResolving` and its default exhaustive resolver. The public dispatcher now reports typed `nonDiscreteIntersection` for either retained source surface.
- Added an explicit `FIXME(INCOMPLETE_IMPLEMENTATION)` boundary and typed `unsupportedCapability` for third-surface requests until interval-local certified bounds and complete transverse and tangent root isolation are implemented.
- Added behavioral tests that obtain genuine certified curves through the public surface-surface intersector. The combined existing and new curve-surface suites passed 47/47 across all five certified-curve kinds.
- Verified all 12 capability-contract tests, including the new envelope binding and its explicit partial status.
- Registered ENV-058. The capability ledger validates 55 capabilities, 58 envelopes, and 439 bindings; the catalog remains 23 supported and 32 partial, and the goal contract remains 0/8.

## 2026-07-25T16:55:00+09:00

- Replaced the blanket certified-curve third-surface rejection with ENV-059 for certified sphere-cone, cone-cone, cone-cylinder, and cone-torus curves against exact analytic planes.
- Split source-plane selection, exact section orchestration, and certified source-parameter recovery behind injected protocols. The public dispatcher now owns only path selection, while the dedicated plane intersector performs candidate construction, final range and residual verification, contact classification, and deduplication.
- Added public behavior tests for transverse contact, tangent contact, recovered normalized parameters, requested curve ranges, exact empty planes, retained source coincidence, non-plane typed failure, and the still-unsupported parallel torus-torus plane case.
- The combined curve-surface suites passed 47/47; the capability contract passed 12/12; zero-copy, explicit-tolerance, and tolerance-contract checks passed on every changed production Swift file.
- Registered ENV-059. The capability ledger validates 55 capabilities, 59 envelopes, and 439 bindings. The catalog remains 23 supported and 32 partial, and the goal contract remains 0/8.
- The full CADGeometry run passed all changed and new tests but remained red on two pre-existing heavy timeout cases. A correctly enumerated isolated rotated torus-cylinder test passed in 87.721 seconds. The torus-cylinder operand-order test exceeded the strict 120-second external hang guard, and the cone-torus operand-order test had reached its 240-second per-test limit in the full run. Neither timeout is reported as success.

## 2026-07-25T17:26:00+09:00

- Replaced the retained parallel torus-torus exact-plane failure with ENV-060.
- Separated common-axis tangent-half-angle polynomial construction from root orchestration and final geometric verification.
- Covered all ten certified parallel-torus branches across regular, nodal, and near-nodal component kinds, including direct parameter recovery, transverse and tangent roots, the omitted half-angle pole, curve and plane ranges, exact empty results, and explicit degree/candidate budgets.
- Kept retained-source coincidence and every non-plane third-surface request on their existing typed contracts; no silent or sampled fallback was added.
- The focused certified curve-surface suite passed 7/7, the combined curve-surface suites passed 49/49, and the capability contract passed 12/12. The catalog remains 23 supported and 32 partial, the ledger records 55 capabilities, 60 envelopes, and 439 bindings, and the goal contract remains 0/8.

## 2026-07-25T17:57:00+09:00

- Generalized the certified plane-reduction protocols and implementation into a target-neutral reduction path while keeping dispatcher registration, source decomposition, candidate construction, and final target verification in separate responsibilities.
- Added ENV-061 for certified sphere-cone curves against a distinct exact analytic sphere, including transverse and tangent contacts, normalized source-parameter recovery, target reconstruction, curve and sphere range filtering, exact empty results, and typed failure for an unregistered cylinder target.
- Found and fixed an isolated-point contamination in the reduction path: a tangent point returned by the target-source section must satisfy the remaining source surface before it can be recovered as a point on the certified curve. The regression rejects the north-pole tangent of two spheres when it is outside the source cone.
- Retained typed non-discrete failure and the direct incomplete-implementation marker for continuous section coincidence until exact certified component identity can be proved.
- The focused certified curve-surface suite passed 7/7, the combined curve-surface suites passed 49/49, and the capability contract passed 12/12. The catalog remains 23 supported and 32 partial, the ledger records 55 capabilities, 61 envelopes, and 439 bindings, and the goal contract remains 0/8.

## 2026-07-25T18:10:09+09:00

- Added ENV-062 for a certified sphere-cone component against an exact cylinder coaxial with the retained source cone.
- Kept pair eligibility in the public dispatcher, made source decomposition target-aware in the injected resolver, and reused the target-neutral reduction intersector unchanged.
- Reduced the target cylinder and source cone to two exact circles, intersected each circle with the remaining source sphere, recovered the certified component parameter, and reverified the target cylinder before returning results.
- Verified two transverse points, one tangent point, an exact empty radius, curve and cylinder range filtering, translated and reversed representations of the same cylinder axis, reconstruction residuals, and typed failure for a non-coaxial cylinder.
- The focused certified suite passed 7/7, the combined curve-surface suites passed 49/49, and the capability contract passed 12/12. The catalog remains 23 supported and 32 partial, the ledger records 55 capabilities, 62 envelopes, and 439 bindings, and the goal contract remains 0/8.

## 2026-07-25T18:32:41+09:00

- Added ENV-063 for a certified cone-cylinder component against an exact sphere centered on the retained source-cylinder axis.
- Reduced the target sphere and source cylinder to exact circles, intersected those circles with the remaining source cone, recovered the certified component parameter, applied requested ranges, and reverified the target sphere before returning results.
- Extracted point-based analytic surface-normal resolution behind an injected protocol so final classification does not depend on a singular UV differential frame.
- Reused one circle parameter-basis implementation for both 3D circle evaluation and exact spherical-great-circle pcurve construction. The surface-surface verifier now preserves the tangent great circle through both sphere parameter poles without falling into generic cubic pcurve differentiation.
- Verified transverse, tangent, empty, curve-range, sphere-range, reconstruction, and non-coaxial typed-unsupported behavior.
- The integrated curve-surface, certified-reduction, and surface-surface suites passed 66/66; the capability contract passed 12/12; all four Swift policy modes passed on every changed production file.
- The ledger records 55 capabilities, 63 envelopes, and 440 bindings. The catalog remains 23 supported and 32 partial, and the goal contract remains 0/8.

## 2026-07-25T19:22:04+09:00

- Added ENV-064 for a certified cone-cylinder component against an exact analytic sphere with an arbitrary finite center.
- Separated analytic context construction, degree-eight resultant construction, candidate enumeration, and shared final candidate verification behind focused protocols and implementations.
- Preserved the existing exact-circle reduction for coaxial spheres while routing arbitrary-center spheres through the pair-specific resultant.
- Verified arbitrary-center transverse, tangent, empty, curve-range, sphere-range, polynomial-degree budget, and candidate budget behavior through the public intersector.
- Added an independent polynomial-identity fixture and direct zero-resultant fixtures for typed continuous overlap and the disjoint algebraic branch.
- Corrected the degenerate-resultant contract so nonzero coefficients within the forward-error envelope continue through root isolation instead of becoming a silent empty result.
- Verified the integrated Geometry set at 67/67 and the compiled capability contract at 12/12.
- All four Swift policy modes passed. The ledger validates 55 capabilities, 64 envelopes, and 441 bindings.
- The shared-state review matrix is identical for Native, WASM, and Embedded: immutable value storage, no isolation primitive required, pure read entry points, no mutation entry point, and no shutdown owner.
- The catalog remains 23 supported and 32 partial, and the goal contract remains 0/8.

## 2026-07-25T19:42:30+09:00

- Added ENV-065 for a certified cone-cylinder component against a distinct exact parallel-axis cylinder.
- Reused the exact parallel-cylinder generator construction, algebraic line-cone solver, and shared final candidate verifier without adding a second orchestration path.
- Verified transverse, tangent, empty, curve-range, target-cylinder range, reversed-axis, reconstruction, and non-parallel typed-unsupported behavior.
- Audited the non-parallel path: its certified analytic-pair surface lift lacks an interval-local second-derivative bound, so it remains explicitly outside the registered envelope.
- The integrated Geometry set passed 67/67, the capability contract passed 12/12, and all four Swift policy modes passed on every changed production file.
- The ledger validates 55 capabilities, 65 envelopes, and 441 bindings. The catalog remains 23 supported and 32 partial, and the goal contract remains 0/8.

## 2026-07-25T21:39:30+09:00

- Added ENV-066 for a certified cone-cylinder component against an exact non-parallel target cylinder whose target/source cylinder section is certified as two root-free full branches.
- Isolated pair eligibility behind an injected protocol, retained canonical cylinder classification in the general cylinder-cylinder intersector, and placed conservative spatial first/second differential magnitude bounds on the certified cylinder-cylinder curve.
- Applied forward/reverse trim scaling in the analytic-pair pcurve, local-to-global second-derivative scaling in the lift bounder, and local first-derivative spatial boxes in the generic curve-surface intersector.
- Kept bounded cylinder-cylinder sections at direct `FIXME(INCOMPLETE_IMPLEMENTATION)` branches with typed unsupported behavior until endpoint-regularized interval parameter and derivative bounds are certified.
- Verified both full-branch signs, forward/reverse trims, both cone-cylinder source components, transverse reconstruction, target-axis reversal, curve and target range exclusion, and existing bounded-section typed failure.
- The final related Geometry integration passed 77/77 and the capability contract passed 12/12, both with zero failures and zero skips. All four Swift policy modes passed.
- The capability ledger validates 55 capabilities, 66 envelopes, and 443 bindings. The shared-state matrix is identical immutable storage and pure reads on Native, WASM, and Embedded.
- The catalog remains 23 supported and 32 partial capabilities, and the goal contract remains 0/8.

## 2026-07-25T22:02:14+09:00

- Found that certified source-surface coincidence depended on stored-value equality, so equivalent analytic representations could enter an unrelated third-surface reduction.
- Added ENV-067 and separated canonical analytic-surface equivalence behind an injected protocol and stateless implementation for planes, spheres, cylinders, cones, and tori.
- Kept retained-source selection in the certified coincidence resolver and path selection in the public curve-surface dispatcher.
- Verified exact, tolerance-equivalent, axis-reversed, axis-translated, and non-equivalent behavior both directly and through every public certified intersection-curve kind.
- Malformed surfaces continue to throw typed validation errors, equivalent retained sources produce typed non-discrete coincidence, and distinct targets retain their existing reduction behavior.
- The focused suites passed 8/8, the related Geometry integration passed 78/78, and the capability contract passed 12/12, all with zero failures and zero skips.
- All four Swift policy modes passed. The capability ledger validates 55 capabilities, 67 envelopes, and 444 fixture bindings.
- The shared-state matrix is identical on Native, WASM, and Embedded: immutable storage, no isolation primitive, pure reads, no mutation entry point, and no shutdown owner.
- The catalog remains 23 supported and 32 partial capabilities, the four direct incomplete-implementation markers remain, and the goal contract remains 0/8.

## 2026-07-25T23:41:01+09:00

- Added ENV-068 for certified cone-cylinder components against exact non-parallel target cylinders whose target/source cylinder section has bounded positive intervals with simple radicand-root endpoints.
- Replaced the numerically unstable endpoint square-root quotient with an endpoint-chord residual regularization and certified local first- and second-spatial-derivative magnitude bounds.
- Kept curve evaluation and certificate construction on the certified cylinder-cylinder curve, trim scaling on the analytic-pair pcurve, parent-parameter conversion in the lift bounder, pair registration in the injected eligibility service, and root orchestration in the existing generic curve-surface solver.
- Verified exact and near endpoints, the prior interior cancellation interval, forward and reverse trims, both cylinder reconstruction residuals, spatial differential bounds, lift bounds, and the public bounded skew-cylinder reduction.
- The focused changed and related suites passed 17/17, and the capability contract passed 12/12.
- The full CADGeometry scheme reached three per-test time limits under parallel load. The analytic B-spline suite passed 7/7 in isolation; the two original cone-torus timeouts passed at 220.163 and 113.212 seconds in the isolated suite; and the wide-cone case exposed by that suite's internal parallelism passed alone in 99.824 seconds.
- All four Swift policy modes passed. The capability ledger validates 55 capabilities, 68 envelopes, and 444 fixture bindings.
- Native, WASM, and Embedded retain the same immutable, stateless storage and access contract. The catalog remains 23 supported and 32 partial capabilities, four direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8.
