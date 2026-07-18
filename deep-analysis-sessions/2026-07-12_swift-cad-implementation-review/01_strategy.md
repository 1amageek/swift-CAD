# Analysis Strategy

## Task structure

The review uses contrastive and structural decomposition: accepted redesign plan versus compiled module graph, runtime evaluation path, topology invariants, public contracts, exchange behavior, and CI evidence.

## Key layers and categories

| Layer | Categories |
|---|---|
| Context | Accepted kernel goal, pre-v1 breaking-change policy |
| Situation | Module graph, capability declarations, implemented algorithms |
| Operation | Command path, evaluation path, validation path, exchange path, CI gates |
| Problem | Parallel geometry truth, incomplete validation, non-executable ledger |
| Issue | Requirement contraction, facade-first implementation, missing vertical slices |
| Solution | Canonical geometry cutover, executable capability contracts, invariant gates |
| Outcome | Deterministic exact kernel readiness and milestone acceptance |

## Decomposition strategy

- Structural: module ownership and dependency direction.
- Funnel: command → IR → evaluator → exact geometry → B-rep validation → lineage → mesh/exchange.
- Contrastive: requested acceptance criteria versus observed implementation.
- Causal: identify why added contracts do not close the runtime capability.

## Evidence-report design

The report leads with a milestone matrix and a severity-ranked evidence table. Repository source at the reviewed commit is primary evidence. Positive controls are included so the assessment distinguishes sound safety boundaries from completed algorithms.

## Chartable data requirements

Each planned milestone is classified as `substantial`, `partial`, `scaffold`, or `not implemented`; this is an ordinal review judgment, not a LOC completion percentage.

## Revision history

- 2026-07-12: Initial strategy established.
