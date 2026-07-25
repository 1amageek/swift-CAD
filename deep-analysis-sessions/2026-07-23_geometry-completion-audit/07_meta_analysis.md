# Meta Analysis Log

## Iteration 1 - 2026-07-23T05:28:40+09:00

### Structural Gaps

- Geometry has two partial capabilities and therefore cannot satisfy the catalog-completion requirement.
- `G1` lacks the required property, oracle, intersection-matrix, implicit-representation, and predicate-adversarial evidence artifacts.
- The exact intersection matrix is not yet represented as a closed, auditable matrix.

### High-Centrality Topics

- `GEO-INTERSECTION-002` feeds topology, Boolean modeling, exact exchange, and the G1 verification gate.
- General torus-torus tracing is a representative coordinate-atlas problem: a geometric branch may remain regular while a chosen meridian coordinate becomes singular.

### Contradictions

- The source-of-truth contract requires exact or certified-implicit continuation, while the current general torus-torus fixture accepts a typed failure for an orthogonal symmetric case without first proving that the geometric intersection itself is singular.

### Runtime Finding

- Converting both complete tori to rational B-spline surfaces and invoking the generic bounded-surface intersector exceeded the five-minute test limit. This path is not a viable production fallback for the symmetric fixture.
- For congruent centered tori, subtracting the two implicit equations factors exactly into the two axis-bisector planes. In the orthogonal fixture the four plane-section branches meet at second-order contacts on the shared perpendicular axis; this is a geometric branch singularity, not merely a meridian-coordinate singularity.

### Next Actions

1. Implement the congruent-centered exact bisector-plane factorization using the existing certified plane-torus curve implementation.
2. Preserve explicit second-order branch contacts and exact pcurves for both source tori.
3. Keep the current procedural certificate for noncongruent simple-root cases and continue the broader intersection-matrix audit separately.

## Iteration 2 - 2026-07-23T06:00:00+09:00

### Verified Resolution

- The congruent-centered torus specialization was implemented through the exact two-bisector-plane factorization and committed as `5990bba95f4bc63109ae9f53f22175821d036ff8`.
- Focused torus-torus behavior, the full CADGeometry suite, the capability contract, and the capability ledger passed before the checkpoint was pushed.
- This closes the declared symmetric torus-torus envelope, but does not close the full partial `GEO-INTERSECTION-002` capability.

## Iteration 3 - 2026-07-23T06:19:30+09:00

### Contradiction and Root Cause

- A plane at a ring torus's inner support was previously classified as a typed singular-system failure because its quartic discriminant has a double root.
- Direct evaluation shows that the zero set is defined and complete: two self-loop components share one nodal point, and four distinct one-sided half-branches meet there.
- Treating the double root as absence of geometry therefore discarded valid topology and contradicted the public exact-intersection contract.

### Implemented Resolution

- Arithmetic-gated inner-support recognition constructs two bounded certified analytic branches instead of entering the simple-root solver.
- Endpoint differentials use the exact one-sided double-root limits, while dual pcurves retain unwrapped angles and decode revalidates the nodal certificate.
- Focused verification executed all 16 `SurfaceSurfaceIntersectionTests`, including axial, oblique, nearby non-nodal, derivative, pcurve, serialization, and tamper cases; all 16 passed.

### Remaining Scope

- The full CADGeometry suite passed in 301.912 seconds on the current worktree.
- Compiling the capability contract exposed six non-exhaustive downstream Topology switches. Their new branch semantics are now explicit, and the regular-pcurve area path returns typed `unsupportedCapability` for the nonregular nodal graph until a dedicated double-root variation certificate is implemented.
- The focused analytic-pair Topology suite passed 9/9 and the capability contract passed 10/10 after that correction.
- Geometry remains incomplete overall because `GEO-INTERSECTION-001`, `GEO-INTERSECTION-002`, and the eight completion gates still require broader closure evidence.

## Iteration 4 - 2026-07-23T07:10:00+09:00

### Contradiction and Geometric Classification

- The declared parallel-offset torus-torus envelope rejects a same-major-radius, coplanar-axis pair at radial offset equal to the sum of the minor radii as `singularGeometry`.
- Direct horizontal-circle analysis proves that the locus is not absent: the inner secondary branch has a node at primary tube angle zero and the outer secondary branch has a node at angle pi.
- Each secondary radial family contains two signed self-loop interiors sharing its node. The complete graph therefore has two nodes, four bounded self-loop edges, and four distinct incident half-branch rays at each node.

### Required Invariants

- Recognition must be arithmetic-gated by equal major radii, zero axial offset, and radial offset equal to the minor-radius sum; tolerance-near inputs must remain on the regular certification path.
- Endpoint evaluation must use the exact one-sided limits of the double-root square root, including first and second derivatives.
- All four components must retain exact analytic truth, mandatory pcurves on both tori, mixed contact classification, deterministic operand ordering, and decode-time reconstruction of the component kind.
- Inputs outside this certified nodal family retain typed singular or resource diagnostics; no sampled or mesh fallback is introduced.

### Implemented Resolution and Verification

- Added an arithmetic-gated nodal certificate, four bounded nonperiodic self-loop components, exact one-sided first/second endpoint differentials, mixed-contact classification, strict decode reconstruction, and mandatory pcurves on both tori.
- The bounded spline representation deliberately remains nonperiodic even though each component's endpoints coincide. Periodic central differences would average distinct incident rays across the node and exceed the certified surface residual.
- The focused parallel torus-torus suite passed 8/8, the capability contract passed 10/10, the capability ledger validated 55 capabilities, 55 envelopes, and 432 bindings, and the ontology validator accepted 19 Factor nodes in 6 groups.
- The full CADGeometry run passed every new and related torus test. One pre-existing cone-torus operand-order test reached its four-minute limit under full-suite parallel contention; an exact isolated rerun executed the test body and passed in 141.963 seconds. This is recorded as an execution-capacity limitation, not as a full-suite green claim.
- Geometry remains incomplete overall: the goal contract still reports 0/8 and this checkpoint closes only ENV-055 within the partial surface-surface intersection capability.

## Iteration 5 - 2026-07-24T16:45:00+09:00

### Responsibility Contamination and Root Cause

- Several valid singular analytic intersections were classified by regular-root preconditions and surfaced only as typed diagnostics: cone apex nodes, a ruling-parallel cone-cylinder family, the near-nodal parallel torus transition, and cone-torus apex contact.
- The first cone-torus apex correction delegated pair-specific topology to the generic bounded rational B-spline intersector. That preserved truth but mixed responsibilities and timed out because a four-parameter graph proof was recomputed for a generator polynomial whose apex root is known analytically.
- Bounded B-spline exact contact logic also duplicated domain mapping, exact expansion arithmetic, and plane-height contexts inside the marching implementation.

### Implemented Resolution

- Singular analytic pairs now own their topology classification and direct certified curve evaluation. The public curve layer holds the pair certificate; exact analytic-pair pcurves reconstruct both source surfaces without using a singular surface parameterization as 3D truth.
- Cone-torus apex contact factors the universal apex root from the generator quartic. Simple roots of the reduced cubic's constant coefficient split the nodal branch into two loops, while simple discriminant roots delimit each generator-fold loop. Fold first and second derivatives use the analytic square-root limit.
- The bounded B-spline layer now depends on an exact-certificate protocol and separate default resolver. Shared expansion arithmetic and plane-height state have one owner, and ineligible higher-order contacts fail explicitly.

### Current Evidence and Remaining Scope

- The cone-torus apex regression completes both operand orders, Codable, pcurve, point, and differential behavior in under one second after the responsibility correction.
- The capability ledger remains partial and the goal contract remains 0/8. Full integrated Geometry, policy, ledger, and completion-contract verification is still required before this checkpoint can be reported as finished.

## Iteration 6 - 2026-07-24T17:23:00+09:00

### Verification Outcome

- The integrated P0/P1 Geometry regressions and the complete CADGeometry suite passed, including exact success and typed-failure behavior through both operand orders.
- The complete package build passed after every downstream `Curve3D` responsibility boundary was classified explicitly.
- A final call-path audit found the CADIR curve/source translation helpers had no caller. Removing them eliminated duplicated reconstruction ownership rather than extending an inactive path.
- Aggregate package tests compile completely. Runtime failures remain tied to the repository's existing feature-completion gate, which is consistent with the independently verified 0/8 goal status.

### Completion Boundary

- This iteration closes the audited P0/P1 Geometry implementation scope and its downstream type integration.
- It does not establish the repository-wide Geometry completion goal. Capability families remain partial, and the eight release gates remain unsatisfied.

## Iteration 7 - 2026-07-24T17:51:00+09:00

### Responsibility Boundary

- General surface-lift root isolation correctly found stationary contacts but owned both proof search and result construction, then terminated with `singularSystem`.
- Result verification is now isolated behind `SurfaceLiftTangentIntersectionResolving`. The default implementation owns target reprojection, requested parameter-range resolution, geometric residual verification, normalized incidence verification, and tangent-result construction.
- The root isolator retains subdivision, stationary refinement, and resource accounting. It does not fabricate a result when the resolver rejects range, residual, or contact kind.

### Contract and Inventory Correction

- The compiled catalog incorrectly marked Surface Trim and Surface Match as supported even though their public evaluators explicitly reject non-rectangular or multi-face sheets as `unsupportedCapability`. Both statuses were restored to partial so the compiled catalog and `ROADMAP.md` agree at 23 supported and 32 partial capabilities.
- The policy checker contradicted its documented tolerance contract by rejecting `.standard` inside split `KernelCapabilities+*.swift` metadata files. Its exception now covers only those named capability-definition files.
- The new `ENV-057` records the bounded analytic surface-lift stationary-contact slice. The capability remains partial because this envelope does not prove the complete public curve-surface domain.

### Verification

- `CurveSurfaceIntersectionTests` passed all 42 tests, including the new public tangent-success behavior and the existing explicit resource and non-discrete failures.
- The capability contract passed all 11 tests. Its new regression requires Surface Trim and Surface Match to remain partial, and rejects their use through `requireSupported`, until their general public inputs are implemented.
- The capability ledger validates 55 capabilities, 57 envelopes, and 438 bindings. Zero-copy, explicit-tolerance, and tolerance-contract policy checks pass.
- The full CADGeometry run passed all changed and related tests. One unrelated torus-cylinder operand-order test reached its 120-second per-test limit under full parallel load; the complete isolated torus-cylinder suite executed the test body and passed in 61.965 seconds.
- Completion remains 0/8 gates and 32 partial capabilities. This iteration advances one curve-surface envelope and removes two false supported claims without claiming general completion.

## Iteration 8 - 2026-07-25T13:55:24+09:00

### Responsibility Boundary

- Certified intersection curves previously entered the generic adaptive curve-bounds path, even though source-surface coincidence is certificate ownership metadata rather than a numerical root-isolation concern.
- Source-surface identity is now isolated behind `CertifiedIntersectionCoincidenceResolving`. The default resolver exhaustively classifies the two retained sources for all five public certified-curve kinds.
- The public intersector maps a retained source to typed `nonDiscreteIntersection`. It maps every third surface to typed `unsupportedCapability` before generic bounds until a dedicated certified subcurve-bounds and root-isolation implementation exists.

### Incomplete Implementation Contract

- The source tree contained no `FIXME(INCOMPLETE_IMPLEMENTATION)` marker before this audit, despite callable partial branches.
- The newly exposed third-surface branch now carries the required production-path and completion-condition marker. This does not prove that every other callable incomplete branch is marked; a repository-wide branch inventory remains required.
- The capability is intentionally still partial. ENV-058 closes one exact-source coincidence envelope but does not claim general certified-curve intersection against arbitrary surfaces.

### Verification and Completion Boundary

- Five behavioral fixtures obtain genuine certified curves from the public surface-surface intersector, covering sphere-cone, cone-cone, cone-cylinder, cone-torus, and parallel torus-torus certificates.
- Both retained source surfaces return typed continuous coincidence and a distinct third plane returns typed unsupported capability for every curve kind. The combined curve-surface suites passed 47/47.
- The capability contract passed 12/12. The ledger validates 55 capabilities, 58 envelopes, and 439 bindings. The compiled catalog remains 23 supported and 32 partial, and completion remains 0/8 gates.

## Iteration 9 - 2026-07-25T16:55:00+09:00

### Algebraic Reduction Boundary

- Certified sphere-cone, cone-cone, cone-cylinder, and cone-torus curves now intersect an exact analytic plane by reducing one source surface against the plane and intersecting every resulting analytic section curve with the remaining source surface.
- Source-plane selection, section orchestration, and normalized source-parameter recovery are separate injected responsibilities. The public curve-surface dispatcher only selects the certified-plane path.
- Every recovered parameter is re-evaluated on the original certified curve. The result is then reprojected to the requested plane, checked against curve and plane parameter ranges, classified as transverse or tangent, and deduplicated only after the final model-space residual passes.

### Explicit Remaining Boundary

- Parallel torus-torus certified curves against a third plane remain typed unsupported because the current reduction has no complete plane-torus section intersection against the remaining torus with certified component recovery.
- Every certified curve against a non-plane third surface remains typed unsupported until a complete pair-specific algebraic reduction or interval-local certified bounds exist.
- A plane section continuously coincident with the remaining source surface remains typed unsupported until the exact certified component identity is proved. Both callable partial branches carry direct `FIXME(INCOMPLETE_IMPLEMENTATION)` markers.

### Verification and Performance Evidence

- Four genuine certified-curve fixtures verify transverse and tangent plane intersections, recovered normalized parameters, requested curve-range preservation, curve and plane reconstruction residuals, and exact empty results outside certified bounds. Source coincidence, non-plane typed failure, and parallel torus-torus plane failure remain covered.
- The combined curve-surface suites passed 47/47. The capability contract passed 12/12. The ledger validates 55 capabilities, 59 envelopes, and 439 bindings. The catalog remains 23 supported and 32 partial, and completion remains 0/8.
- The complete CADGeometry run passed every changed and new path but did not finish green: two pre-existing heavy general torus-cylinder and cone-torus tests reached their 120-second and 240-second test limits under concurrent Xcode load. A correctly enumerated isolated rotated torus-cylinder test passed in 87.721 seconds. The torus-cylinder operand-order test exceeded a strict 120-second external hang guard and is retained as an open performance-verification defect, not reclassified as success.

## Iteration 10 - 2026-07-25T17:26:00+09:00

### Parallel Torus Plane Boundary

- Every certified regular-closed, nodal-self-loop, and near-nodal-closed-loop parallel torus-torus component now reaches an exact-plane-specific path instead of the generic uncertified adaptive curve path.
- A dedicated polynomial builder owns the common-axis tangent-half-angle elimination of degree at most eight. The public curve-surface dispatcher only selects the pair-specific intersector.
- The pair-specific intersector owns polynomial and candidate budgets, repeated-root-preserving real-root isolation, explicit verification of the omitted half-angle pole, source-parameter refinement, final plane reconstruction, requested range filtering, residual verification, and contact classification.
- The certified curve owns component-aware inversion from the primary tube angle to normalized curve fractions. The shared certified-parameter resolver consumes that contract and directly re-evaluates every recovered point.

### Verification and Remaining Boundary

- Seven focused tests pass in one suite, the combined curve-surface suites pass 49/49, and the capability contract passes 12/12. The three parallel-torus cases cover all ten certified branches: four regular closed, four nodal self-loops, and two near-nodal closed loops.
- Each branch verifies six direct source-parameter recoveries, transverse and tangent exact-plane intersections, curve and plane range filtering, exact empty results, source coincidence, and non-plane typed failure. The regular branch also verifies the half-angle pole omitted by the finite tangent-half-angle substitution. Degree and candidate budget exhaustion return typed resource diagnostics.
- The ledger now records 55 capabilities, 60 envelopes, and 439 fixture bindings. The catalog remains 23 supported and 32 partial, and completion remains 0/8 gates.
- Non-plane third surfaces remain behind the direct `FIXME(INCOMPLETE_IMPLEMENTATION)` boundary. This slice does not close the general curve-surface matrix or the Geometry completion goal.

## Iteration 11 - 2026-07-25T17:57:00+09:00

### Target-Neutral Reduction Boundary

- The plane-specific reduction contracts were generalized to a target-neutral certified reduction. The public dispatcher owns only explicit curve-target pair registration, the resolver owns source-surface decomposition, and the reduction intersector owns candidate construction and final target verification.
- ENV-061 registers certified sphere-cone curves against a distinct exact analytic sphere. The target sphere intersects the retained source sphere into an exact circle or isolated tangent point; the resulting curve or point is then intersected with or verified against the remaining source cone.
- An audit of the isolated-point path found that tangent section points were accepted without checking membership in the remaining source surface. Point candidates now require an explicit remaining-surface residual check before source-parameter recovery, preventing a tangent sphere-sphere point outside the cone from becoming a false success.

### Verification and Remaining Boundary

- The focused certified curve-surface suite passed 7/7, the combined curve-surface suites passed 49/49, and the capability contract passed 12/12.
- Public behavior covers transverse and tangent sphere targets, recovered normalized source parameters, target reconstruction, requested curve and surface ranges, exact empty targets, rejection of an isolated section point outside the cone, retained-source coincidence, and typed failure for an unregistered cylinder target.
- The ledger records 55 capabilities, 61 envelopes, and 439 bindings. The catalog remains 23 supported and 32 partial capabilities, and completion remains 0/8 gates.
- Continuous coincidence between a target section and the remaining source still requires an exact component-identity proof. That callable branch retains its direct `FIXME(INCOMPLETE_IMPLEMENTATION)` marker and typed non-discrete failure; sampling is not accepted as identity evidence.

## Iteration 12 - 2026-07-25T18:10:09+09:00

### Target-Dependent Source Decomposition

- ENV-062 registers a certified sphere-cone component against an exact cylinder whose axis is coincident with the retained source-cone axis.
- The dispatcher owns the coaxial pair predicate using the canonical target cylinder and retained source cone. The reduction resolver now receives the target kind and selects the source cone as the section surface only for cylinder targets; the shared reduction intersector remains unaware of pair eligibility.
- The target cylinder and source cone produce two exact circles. Each circle is intersected exactly with the remaining source sphere, after which the shared component-aware parameter recovery and final target verification path constructs the public results.

### Verification and Remaining Boundary

- One certified component returns two transverse points for the regular radius and one tangent point at the limiting radius. A larger radius proves an empty result.
- Curve-range and cylinder-V-range filtering, translated cylinder-axis origin, reversed axis direction, curve and cylinder reconstruction, residual bounds, and typed unsupported behavior for a non-coaxial cylinder are verified.
- The focused certified suite passed 7/7, the combined curve-surface suites passed 49/49, and the capability contract passed 12/12.
- The ledger records 55 capabilities, 62 envelopes, and 439 bindings. The catalog remains 23 supported and 32 partial capabilities, and completion remains 0/8 gates.

## Iteration 13 - 2026-07-25T18:32:41+09:00

### Coaxial Sphere Reduction and Singular-Frame Ownership

- ENV-063 registers a certified cone-cylinder component against an exact sphere whose center lies on the retained source-cylinder axis.
- Pair eligibility remains in the public dispatcher. The target-neutral reduction intersector reuses the retained source cylinder as the section surface and owns candidate construction, source-parameter recovery, requested-range filtering, final reconstruction, and contact classification.
- The coaxial sphere-cylinder section produces exact circles. The tangent case is a great circle that crosses both sphere parameter poles, so the surface-surface verifier now selects the existing exact spherical-great-circle pcurve before attempting a generic cubic UV fit.
- The circle parameter basis has one shared owner used by both 3D circle evaluation and the exact sphere pcurve. Analytic surface-normal resolution is isolated behind `SurfaceNormalResolving`, allowing final contact classification from the verified model-space point without depending on a singular UV differential frame.

### Verification and Remaining Boundary

- Public behavior covers one transverse result, one tangent result through the sphere poles, exact empty and requested-range-excluded results, recovered normalized source parameters, curve and sphere reconstruction, and typed unsupported behavior for a non-coaxial sphere.
- The integrated curve-surface, certified-reduction, and surface-surface suites passed 66/66; the capability contract passed 12/12.
- The Swift forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policies passed for every changed production file. The ledger records 55 capabilities, 63 envelopes, and 440 bindings; the catalog remains 23 supported and 32 partial capabilities, and completion remains 0/8 gates.
- The catalog remains partial. Arbitrary non-coaxial sphere targets for certified cone-cylinder components still lack the required interval-local second-derivative proof and remain behind the direct incomplete-implementation marker rather than a sampled or silent fallback.

## Iteration 14 - 2026-07-25T19:22:04+09:00

### Arbitrary-Center Sphere Elimination

- ENV-064 extends a certified cone-cylinder component to an exact sphere with an arbitrary finite center.
- A dedicated context expresses the source cone and target sphere as quadratics in retained-cylinder height. A separate polynomial builder forms their exact resultant and applies tangent-half-angle substitution, producing degree at most eight.
- The pair-specific intersector owns finite-coefficient checks, polynomial and candidate budgets, repeated-root-preserving real-root isolation, the omitted half-angle pole, sphere-height reconstruction, and direct cone/sphere candidate residuals.
- Final component-parameter recovery, requested range filtering, curve/target reconstruction, residual verification, deduplication, and contact classification are shared with the existing certified-reduction path through an injected candidate verifier.
- Existing coaxial sphere targets retain the stronger exact-circle reduction and pole-safe target-pcurve path. The new resultant path handles the remaining arbitrary-center inputs.

### Degeneracy and Responsibility Guarantees

- A zero resultant is handled as an algebraic branch relation rather than a discrete root set. Multiple interior witnesses on the same certified analytic branch distinguish continuous overlap from the disjoint companion branch.
- Nonzero coefficients inside the forward-error envelope are normalized and solved; they are not silently rounded to an empty result.
- The polynomial fixture independently compares the emitted degree-eight numerator against the original quadratic resultant at seven angles. A second fixture verifies typed continuous overlap and exact empty behavior for the disjoint branch.
- The new implementation consists only of immutable value types and pure functions. Native, WASM, and Embedded therefore share the same storage, isolation, read, mutation, and shutdown contract: immutable storage, no synchronization boundary, pure reads, no mutation entry point, and no shutdown ownership.

### Verification and Remaining Boundary

- The integrated curve-surface, certified-curve, polynomial-builder, and surface-surface suites passed 67/67.
- The capability contract passed 12/12. The ledger validates 55 capabilities, 64 envelopes, and 441 fixture bindings.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production file.
- The compiled catalog remains 23 supported and 32 partial capabilities, and the Geometry completion contract remains 0/8 gates. ENV-064 closes this pair-specific envelope but does not establish general certified-curve/third-surface or repository-wide Geometry completion.

## Iteration 15 - 2026-07-25T19:42:30+09:00

### Parallel-Cylinder Reduction

- ENV-065 registers a certified cone-cylinder component against a distinct exact cylinder whose axis is parallel to the retained source-cylinder axis.
- The existing reduction resolver retains the source cylinder. Exact parallel-cylinder intersection produces zero, one tangent, or two transverse generator lines, and the existing algebraic line-cone solver intersects those generators with the remaining source cone.
- The shared candidate verifier owns component-aware source-parameter recovery, requested curve and target-cylinder range filtering, final reconstruction, residual verification, deduplication, and target-normal contact classification.
- Public behavior verifies transverse and tangent intersections, exact empty results, curve and target-surface ranges, reversed target-axis representation, and typed unsupported behavior for a non-parallel target cylinder.

### Audited Boundary

- An attempted non-parallel registration reached a certified analytic-pair surface lift and failed explicitly because that representation has no interval-local second-derivative bound. The dispatcher therefore registers only the complete parallel-axis envelope; non-parallel cylinders remain at the direct incomplete-implementation boundary.
- No new mutable storage or synchronization boundary was introduced. Native, WASM, and Embedded retain identical immutable configuration and pure dispatch behavior.

### Verification and Remaining Boundary

- The integrated curve-surface, certified-curve, polynomial-builder, and surface-surface suites passed 67/67, and the capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production file.
- The ledger validates 55 capabilities, 65 envelopes, and 441 fixture bindings. The compiled catalog remains 23 supported and 32 partial capabilities, and the Geometry completion contract remains 0/8 gates.
- ENV-065 closes the exact parallel-axis cylinder envelope only. Certified non-parallel analytic-pair surface lifts still require rigorous interval-local parameter and derivative bounds before they can enter the structural reduction solver.

## Iteration 16 - 2026-07-25T21:39:30+09:00

### Root-Free Skew-Cylinder Responsibility Boundary

- ENV-066 registers a certified cone-cylinder component against an exact non-parallel target cylinder only when the target/source cylinder classifier proves a strictly positive radicand over the complete angular domain.
- Pair eligibility is isolated behind `CertifiedCylinderCylinderReductionEligibility`. Its default implementation reuses the canonical ordering and exact radicand classification owned by the general cylinder-cylinder intersector; the public dispatcher does not duplicate the section mathematics.
- `CertifiedCylinderCylinderIntersectionCurve` owns conservative full-branch spatial first- and second-derivative magnitude bounds. The analytic-pair pcurve wrapper owns forward or reverse trim scaling, `SurfaceLiftDifferentialBounder` converts local second-derivative bounds back to the parent parameter, and the curve-surface intersector consumes the local first-derivative bound to form spatial subdivision boxes.
- The generic structural surface-lift solver retains root isolation, requested-range enforcement, tangent refinement, resource budgets, and final residual verification. It does not decide which analytic pair can provide a certificate.

### Correctness Boundary and Shared-State Review

- Only positive and negative root-free full branches are registered. A bounded cylinder-cylinder component reaches a typed unsupported boundary because its endpoint square-root cancellation still requires an endpoint-regularized interval parameter and derivative certificate.
- The direct differential fixture verifies both full-branch signs, forward and reverse trims, local interval rescaling, and sampled first/second spatial derivatives against the structural bounds. The public fixture fixes one analytic target representation, verifies both source cone-cylinder components, transverse reconstruction, target-axis reversal, and curve and target-parameter range exclusion.
- All added production types are immutable value types or stateless protocol implementations. Native, WASM, and Embedded therefore share the same matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner.

### Verification and Remaining Boundary

- The final related Geometry integration passed 77/77 with zero failures and zero skips under the default parallel test configuration. The capability contract passed 12/12 with zero failures and zero skips.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 66 envelopes, and 443 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, and the Geometry completion contract remains 0/8 gates.
- ENV-066 closes only the root-free full-branch skew-cylinder envelope. Bounded analytic-pair endpoint regularization and the remaining certified curve/third-surface matrix stay explicitly incomplete; no sampled, empty-result, or silent fallback was introduced.

## Iteration 17 - 2026-07-25T22:02:14+09:00

### Canonical Analytic Source Equivalence

- The certified-source coincidence path previously compared retained source surfaces by stored-value equality. A geometrically identical cylinder with a translated axis origin or reversed axis direction therefore bypassed source coincidence and entered an unrelated third-surface reduction.
- ENV-067 separates geometric representation equivalence behind `AnalyticSurfaceEquivalenceResolving`. Its default implementation validates both inputs and classifies canonical planes, spheres, cylinders, cones, and tori using the explicit modeling tolerance.
- `CertifiedIntersectionCoincidenceResolving` consumes the equivalence contract for both retained source surfaces. The public curve-surface dispatcher only consumes the resulting source-membership decision and preserves its existing typed non-discrete result.
- Exact, tolerance-equivalent, axis-reversed, axis-translated, and genuinely non-equivalent representations are covered independently. The public certified-curve fixtures verify the same behavior for every certified intersection-curve kind.

### Responsibility and Shared-State Review

- Analytic representation equivalence is owned by one focused resolver; certified-curve source membership owns exhaustive retained-source selection; the public dispatcher owns only path selection and error construction. No reduction implementation duplicates canonical surface comparison.
- The new production implementations are stateless or contain immutable injected dependencies. Native, WASM, and Embedded share the same matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner.
- Malformed surfaces propagate validation errors, non-equivalent surfaces return `false`, and equivalent retained sources return typed non-discrete coincidence. No validation failure or unsupported reduction is rounded to a successful empty result.

### Verification and Remaining Boundary

- The focused analytic-equivalence and certified curve-surface suites passed 8/8. The related Geometry integration passed 78/78 with zero failures and zero skips. The capability contract passed 12/12 with zero failures and zero skips.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 67 envelopes, and 444 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, and the Geometry completion contract remains 0/8 gates.
- ENV-067 fixes representation-independent source coincidence only. The four direct incomplete-implementation markers and the remaining general certified curve/third-surface boundaries remain explicit; this slice does not claim Geometry completion.

## Iteration 18 - 2026-07-25T23:41:01+09:00

### Bounded Skew-Cylinder Endpoint Regularization

- ENV-068 extends the certified cone-cylinder component against an exact non-parallel target cylinder to bounded cylinder-cylinder sections whose positive intervals have simple radicand roots at every retained endpoint.
- `CertifiedCylinderCylinderIntersectionCurve` owns the stable bounded-branch parameterization and its spatial differential certificates. It evaluates the endpoint-vanishing radicand after subtracting its endpoint chord, regularizes the residual by the two endpoint factors, and reconstructs the signed square root without dividing two independently rounded near-zero values.
- Interior interval bounds combine a direct quotient certificate with endpoint integral-form derivative certificates. Either proof is independently conservative, so selecting the tighter valid upper bound preserves correctness while avoiding endpoint cancellation.
- `CertifiedAnalyticPairSurfaceParameterCurve` owns local trim and reversal scaling, `SurfaceLiftDifferentialBounder` converts the certified local bounds to the parent parameter, the injected eligibility service delegates section classification to the general cylinder-cylinder implementation, and the public curve-surface dispatcher only selects the registered path. The generic structural solver retains subdivision, root isolation, requested-range enforcement, resource budgets, and final residual verification.

### Correctness and Responsibility Review

- Direct fixtures cover exact endpoints, near-endpoint cells, interior cells including the prior cancellation regression interval, forward and reverse trims, first- and second-derivative magnitude bounds, lift bounds, and reconstruction on both source cylinders.
- Public fixtures cover a bounded skew-cylinder reduction, transverse reconstruction, and typed failure outside the registered simple-endpoint envelope. Unsupported analytic-pair definitions remain behind direct incomplete-implementation markers; no empty-result, sampled, or silent fallback was introduced.
- No mutable shared storage was added. Native, WASM, and Embedded use the same review matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner.

### Verification and Remaining Boundary

- The focused bounded-cylinder, certified curve-surface, full-branch regression, and general cylinder-cylinder suites passed 17/17. The capability contract passed 12/12.
- The full CADGeometry scheme reached three pre-existing per-test time limits under parallel load. The analytic B-spline suite then passed 7/7 in isolation. The two cone-torus cases that timed out in the full run passed in the isolated suite at 220.163 and 113.212 seconds; a different wide-cone case that timed out while that isolated suite was still parallel passed alone in 99.824 seconds. No failing behavior remained after resource isolation.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 68 envelopes, and 444 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, the four direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. ENV-068 closes the certified bounded skew-cylinder envelope only; other analytic-pair lift definitions and the remaining certified curve/third-surface matrix are still incomplete.

## Iteration 19 - 2026-07-26T05:43:01+09:00

### Arbitrary-Cylinder Reduction for Certified Sphere-Cone Curves

- ENV-069 registers a directly evaluable certified sphere-cone component against an exact cylinder in an arbitrary finite axis pose.
- The target cylinder and retained source cone first produce exact certified cone-cylinder sections. `CertifiedIntersectionSectionCurveResolving` owns the conversion from analytic-analytic section truth to its directly evaluable certified intersection curve, so the reduction does not discard the exact certificate by routing a derived surface lift into a structural solver that lacks the required bound.
- The existing cone-cylinder/sphere resultant then intersects each exact section with the remaining source sphere. The shared candidate verifier retains requested-range enforcement, source-parameter recovery, target reconstruction, residual verification, deduplication, and contact classification.
- Cone-cylinder candidate recovery previously projected onto the stored input cylinder frame even though curve evaluation uses a canonical axis and axis-origin representation. `CertifiedConeCylinderIntersectionCurve` now owns canonical cylinder-angle recovery; the parameter resolver only maps that angle to component-aware normalized fractions.

### Correctness, Responsibility, and Shared-State Review

- The public fixture obtains both the sphere-cone source component and the cone-cylinder reduction sections from the public surface-surface intersector. It verifies transverse reconstruction, curve-range inclusion, cylinder-range exclusion, exact empty results, direct certified section consumption, and equivalence under simultaneous target-axis reversal and axis-origin translation.
- The dispatcher owns only pair registration, the section resolver owns exact-truth selection, the cone-cylinder curve owns its canonical parameter frame, the parameter resolver owns angle-to-fraction mapping, and the final verifier owns residual and range acceptance. No layer duplicates the cone-cylinder equation or silently converts a structural-solver failure into an empty result.
- All new production types are stateless or contain immutable injected dependencies. Native, WASM, and Embedded use the same review matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner.

### Verification and Remaining Boundary

- The certified curve-surface suite passed 8/8. The related cone-cylinder surface, cone-cylinder/sphere polynomial, full-branch skew-cylinder, and spatial differential-bound suites passed together at 21/21. The capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 69 envelopes, and 444 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, the four direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. ENV-069 closes only the certified sphere-cone/exact-cylinder pair; the remaining certified curve/third-surface matrix and analytic-pair lift definitions remain explicit work.

## Iteration 20 - 2026-07-26T06:00:23+09:00

### Certified Spatial Separation

- ENV-070 closes the exact-empty envelope for every directly evaluable certified intersection-curve kind against an exact sphere or torus whose complete bounded support is spatially separated from the complete certified curve bounds.
- `CertifiedIntersectionCurve3D` owns exhaustive dispatch to each component's certified bounding box. `CertifiedIntersectionSpatialDisjointnessResolving` separates proof policy from the public curve-surface dispatcher, and its default implementation constructs outward-rounded sphere bounds or a conservative isotropic torus box with extent `majorRadius + minorRadius`.
- The resolver returns `true` only when the two conservative boxes are separated by more than the requested modeling tolerance. Unbounded targets, unsupported target representations, non-finite target boxes, and overlapping boxes decline the proof and continue through the existing pair-specific or typed unsupported path.

### Correctness, Responsibility, and Shared-State Review

- Public fixtures verify exact empty results for all five certified curve kinds across both bounded target kinds. Existing plane, sphere, cylinder, resultant, and skew-cylinder paths continue after the broad-phase check, while an overlapping unregistered torus still reaches the direct typed unsupported boundary.
- The curve certificate owns complete source bounds, the disjointness resolver owns target support bounds and the separation decision, and the dispatcher owns only path ordering. No sampled point, mesh, or fallback empty result is used.
- The new protocol and default implementation are stateless, and the dispatcher stores the injected dependency immutably. Native, WASM, and Embedded therefore retain the same storage, isolation, read, mutation, and shutdown matrix.

### Verification and Remaining Boundary

- The certified curve-surface suite passed 8/8, covering the five certified curve kinds, both bounded target kinds, supported-pair regressions, and an overlapping unsupported target. The capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 70 envelopes, and 444 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, the four direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. ENV-070 proves only globally separated bounded targets; overlapping unregistered pairs still require complete algebraic reduction or interval-local differential bounds.

## Iteration 21 - 2026-07-26T06:18:22+09:00

### Non-Degenerate Cone-Cylinder-Cone Elimination

- ENV-071 registers a directly evaluable certified cone-cylinder component against a distinct exact cone when the complete cylinder-angle resultant is finite and non-degenerate. The same solver composes through exact section reduction for certified cone-cone components against exact cylinders when every retained section satisfies that eligibility contract.
- `ConeCylinderConeIntersectionContext` owns canonical cylinder-frame construction and the two cone height quadratics. `ConeCylinderConePolynomialBuilding` owns the degree-at-most-sixteen tangent-half-angle resultant and its forward-error scale. `ConeCylinderConeIntersecting` owns eligibility, root isolation, candidate recovery, and resource budgets. The existing candidate verifier retains certified-component membership, requested ranges, target reconstruction, residual verification, deduplication, and contact classification.
- Degenerate resultants do not enter the new solver and remain behind the existing direct incomplete-implementation boundary. No witness sampling or near-zero polynomial is converted into a successful empty result.

### Correctness, Responsibility, and Shared-State Review

- The public fixture verifies a transverse cone target, an even-multiplicity tangent cone target, curve-range exclusion, polynomial-degree failure, and composed cone-cone/cylinder reduction. Independent fixtures compare the generated polynomial with the original quadratic resultant at five distinct cylinder angles and prove that a degenerate resultant declines eligibility and fails explicitly if the solver is invoked outside that contract.
- Every new production type is a value type with immutable stored dependencies or coefficients. Native, WASM, and Embedded share the same matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner.

### Verification and Remaining Boundary

- The certified curve-surface suite passed 10/10, the related cone-cylinder polynomial and general cone/cone-cylinder regressions passed 17/17, and the capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 71 envelopes, and 444 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, the four direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. ENV-071 closes only finite non-degenerate cone-cylinder/cone resultants and their cone-cone/cylinder composition; degenerate resultants and the rest of the certified curve/third-surface matrix remain explicitly unsupported.

## Iteration 22 - 2026-07-26T07:08:39+09:00

### Non-Degenerate Cone-Hosted Quadric Elimination

- ENV-072 registers a directly evaluable certified sphere-cone component against a distinct exact cone and a certified cone-cone component against a distinct exact sphere or cone when the complete cone-ruling resultant is finite and non-degenerate.
- `SecondOrderTrigonometricPolynomial` and `TrigonometricHeightQuadratic` own the shared coefficient representation. `HeightQuadraticResultantPolynomialBuilding` owns the degree-at-most-sixteen tangent-half-angle resultant and its forward-error scale. `HeightQuadraticTripleSolving` owns eligibility, strict real-root isolation, even-multiplicity stationary-root recovery, candidate reconstruction, and resource budgets.
- `ConeCylinderConeIntersectionContext` and `ConeHostedQuadricIntersectionContext` separately own cylinder-frame and cone-ruling coordinate construction. Pair-specific intersectors only select their context and delegate final certified-component membership, requested ranges, target reconstruction, residual verification, deduplication, and contact classification to the shared candidate verifier.
- A fixed residual relaxation recovered the new tangent sphere but degraded an existing tangent-cone classification. The final implementation keeps ordinary root isolation strict and uses the resultant forward-error envelope only to accept accurately isolated stationary points as repeated-root candidates. This preserves both detection and contact-classification precision.
- Finite degenerate resultants decline eligibility and defensive direct solver use returns typed `intersectionFailure`; they are not converted into empty or non-discrete success.

### Correctness, Responsibility, and Shared-State Review

- The public fixtures verify sphere-cone/cone and cone-cone/sphere-or-cone transverse and tangent intersections, requested curve- and target-surface-range exclusion, typed polynomial-degree failure, and final target residuals. An independent fixture compares the generated cone-hosted polynomial with the direct quadratic resultant at five angles and verifies the degenerate-resultant contract.
- The existing cone-cylinder/cone adapter now consumes the same algebra and solver protocols. Its polynomial identity, tangent classification, range, budget, and degenerate behavior remain covered.
- Every new production type is a value type with immutable coefficients or injected dependencies. Native, WASM, and Embedded share the same matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner. The final conditional-compilation and mutable-state scan found no target-specific storage or concurrency contract.

### Verification and Remaining Boundary

- The certified curve-surface suite passed 11/11. The combined certified, general sphere-cone, general cone-cone, general cone-cylinder, cone-cylinder polynomial, and full-branch regression selection passed 36/36; the capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 72 envelopes, and 444 fixture bindings. The structural scan indexed the new protocols, contexts, builder, solver, and pair adapter; parser error-node diagnostics were treated only as navigation signals because the production build and behavioral tests are authoritative.
- The compiled catalog remains 23 supported and 32 partial capabilities, the four direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. ENV-072 closes only finite non-degenerate cone-hosted quadric resultants; coincident reduced-section component identity, degenerate resultants, non-quadric third surfaces, and analytic-pair lift definitions remain explicit work.

## Iteration 23 - 2026-07-26T07:47:43+09:00

### Certified Reduced-Section Component Identity

- ENV-073 closes the reduced-section ambiguity where one exact target/source section is continuously coincident with the remaining source surface. The public query now distinguishes whether that section is the selected certified component or a different component of the same source-surface intersection.
- `CertifiedReducedSectionIntersectionBoundResolving` owns the algebraic proof budget. Its default implementation multiplies the certified intersection curve degree by the exact target-surface degree, giving the Bézout upper bound for isolated complex intersections.
- `CertifiedReducedSectionComponentClassifying` evaluates one more distinct witness than that bound and uses exact certified parameter recovery against the selected component. Complete membership proves identity; any rejected witness proves that the section is a different component. Unsupported target degree, duplicate physical witnesses, or failed recovery remain typed intersection failures.
- `CertifiedIntersectionNodeCandidateResolving` separately recovers endpoint-encoded shared graph nodes. The reduction intersector only selects identical-versus-distinct behavior, while the existing final verifier retains requested-range enforcement, reconstruction, residual verification, deduplication, and contact classification.

### Correctness, Responsibility, and Shared-State Review

- Direct fixtures verify target-degree-dependent bounds for plane, cylinder, and torus targets and typed failure for an uncertified B-spline target degree.
- A real cone-cylinder apex fixture proves that two certified components are classified as distinct while their shared apex is preserved as one candidate. A coaxial sphere-cone fixture proves that a plane containing one circular component produces typed non-discrete behavior for that component and exact empty behavior for the other.
- Every new production type is a value type with immutable injected dependencies or no stored state. Native, WASM, and Embedded share the same matrix: immutable storage, no isolation primitive, pure read entry points, no mutation entry point, and no shutdown owner.

### Verification and Remaining Boundary

- The certified curve-surface suite passed 15/15. The combined certified, general sphere-cone, general cone-cone, general cone-cylinder, and curve-surface selection passed 79/79; the capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed for every changed production Swift file. The capability ledger validates 55 capabilities, 73 envelopes, and 444 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, the three direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. ENV-073 removes the reduced-section component-identity marker only; the remaining certified curve/third-surface matrix and analytic-pair lift definitions remain explicit work.

## Iteration 24 - 2026-07-26T08:01:22+09:00

### Bounded Plane-Cone Spatial Differential Certificates

- ENV-074 registers exact bounded plane-cone hyperbola and parabola surface-lift components against distinct exact analytic planes, including transverse intersections and even-multiplicity tangent contacts.
- `CertifiedBoundedPlaneConeIntersectionCurve` owns interval-local spatial first- and second-derivative magnitude bounds. Hyperbolic bounds use the maximum absolute source parameter and orthogonal-axis derivative norms; parabolic bounds use the exact affine first derivative and constant second derivative. Every arithmetic boundary is expanded outward and non-finite arithmetic becomes a typed resource failure.
- `CertifiedAnalyticPairSurfaceParameterCurve` applies local trim and reversal scaling. `SurfaceLiftDifferentialBounder` only converts the local certificate to the parent parameter, and `DefaultCurveSurfaceIntersector` only consumes the first-derivative bound for local spatial boxes and the second-derivative bound for scalar root isolation.
- The previous analytic-pair UV-enclosure marker represented the wrong responsibility: certified analytic-pair pcurves can only validate on their exact analytic source surfaces, so they never require B-spline support localization. Remaining incomplete analytic-pair definitions are now declared once at the spatial certificate owner.

### Correctness, Responsibility, and Shared-State Review

- Direct fixtures cover complete and trimmed hyperbolas and parabolas, forward and reverse trim directions, source-bound scaling, local lift-bound scaling, and dense differential containment.
- Public fixtures construct the exact bounded source curves through the bounded surface-surface intersector, then recover a transverse third-plane root, an even-multiplicity tangent third-plane root, and exact empty output when the transverse root is excluded by the requested curve range.
- All changed production types are value types with immutable stored data or stateless extensions. Native, WASM, and Embedded use the same storage, isolation, read, mutation, and shutdown matrix.

### Verification and Remaining Boundary

- The focused bounded-conic suite passed 2/2. The combined bounded plane-cone, bounded-conic differential, cylinder differential, and curve-surface selection passed 51/51; the capability contract passed 12/12.
- Forbidden-construct, zero-copy, explicit-tolerance, and tolerance-contract policy checks passed. The capability ledger validates 55 capabilities, 74 envelopes, and 445 fixture bindings.
- The compiled catalog remains 23 supported and 32 partial capabilities, two direct incomplete-implementation markers remain, and the Geometry completion contract remains 0/8 gates. The remaining analytic-pair definitions still require definition-owned interval-local spatial differential certificates before the general certified curve/third-surface boundary can be removed.
