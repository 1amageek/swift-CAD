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
