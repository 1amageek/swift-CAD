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
