# Geometry Completion Audit Strategy

## Task Structure

The objective is binary completion, not a review-only deliverable. The analysis therefore runs as a repeated implementation loop:

1. derive the exact completion requirement from `SPEC.md`, `ROADMAP.md`, and the capability catalog;
2. contrast the declared envelope with the public implementation path and behavior tests;
3. identify a root limitation rather than a downstream symptom;
4. implement exact or certified-implicit behavior with explicit typed failure boundaries;
5. verify focused behavior, the full Geometry suite, capability contracts, and the global goal contract;
6. update the evidence graph and continue until all Geometry requirements are proven.

## Key Layers and Categories

- Context / normative-contract: exact geometry truth, no mesh fallback, binary gate semantics.
- Situation / current-evidence: catalog counts, gate counts, current passing suites.
- Operation / implementation-path: dispatch, analytic intersectors, certified curve truth, pcurves, decoding.
- Problem / incomplete-envelope: partial curve-surface and surface-surface matrices.
- Issue / root-causes: coordinate singularities, algebraic degeneracies, completeness proof gaps, missing oracle evidence.
- Solution / implementation-slices: coordinate atlas or exact fallback, certificate extension, regression tests.
- Outcome / completion-proof: 7 of 7 Geometry capabilities supported and G1 evidence complete on one revision.

## Decomposition Strategy

- Structural decomposition: curve evaluation, surface evaluation, curve-surface intersection, surface-surface intersection, predicates.
- Contrastive analysis: declared accepted inputs versus explicit source rejection and expected-failure tests.
- Causal tracing: typed diagnostic back through certificate assumptions to the mathematical limitation.
- Mechanism decomposition: geometric singularity versus parameterization singularity versus resource exhaustion.
- Evidence decomposition: focused behavioral proof, full-suite regression proof, catalog consistency, external oracle/property evidence.

## Evidence Report Design

Primary claims must be supported by chartable count and matrix evidence:

- Geometry capability closure: supported/partial counts over time.
- Intersection-matrix closure: supported, regular-singular, non-discrete, and unresolved cells.
- Verification closure: focused, full Geometry, property, oracle, and platform outcomes by revision.
- Residual risk: unresolved typed diagnostics grouped by mathematical cause.

The final report will use a capability closure chart, intersection matrix, verification matrix, and implementation timeline. Confidence alone is not completion evidence.

## Initial Support Sets

- Current incompleteness: goal-contract output + capability catalog + ledger counts.
- Next root gap: general torus-torus source assumptions + the meridian-singularity regression fixture + direct runtime behavior.
- Final completion: same-revision source, tests, oracle artifacts, and `Evidence/G1.json` passing the repository validator.

## Revision History

- `2026-07-23T05:28:40+09:00`: Initialized from revision `a268a4e`; selected the two partial intersection capabilities as the first audit frontier.
