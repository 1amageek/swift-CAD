# P0 Exact Kernel Work-in-Progress Checkpoint

## Purpose

This checkpoint preserves the complete exact-kernel work in progress before the
implementation is separated into independently verifiable change sets. It is a
recovery point, not an integration-ready or release-ready revision.

## History boundary

- Upstream baseline: `origin/main` at `1060739e94adb52bd107cd8284b2153cc787f1ea`
- Exact architecture commit: `a875eeb8c1c1e8a0db9ae34555f0c21a418ff28f`
- Checkpoint branch: `codex/p0-swift-cad-checkpoint`

The architecture commit replaced string-based persistent topology names with
stable subshape references and explicit geometry signatures. It also made
modeling tolerance an explicit evaluation input. This checkpoint builds on that
contract and must not be treated as compatible with the older Rupa integration
contract that used `PersistentName` and `SelectionReference.topology`.

## Preserved implementation clusters

1. Capability catalog and goal-contract checker split.
2. Certified analytic and implicit surface-intersection truth.
3. Exact topology pcurve integration and trimmed volume evaluation.
4. Surface, curve, and direct-edit feature schemas and evaluators.
5. Boolean arrangement, classification, materialization, and query validation.
6. Exact STEP, IGES, and native-package transfer support.
7. Roadmap, specification, capability ledger, CI, and evidence contracts.
8. Canonical rational B-spline representation and specialized-type removal.

Tracked edits and newly introduced files in these clusters form one preservation
closure. Omitting the newly introduced capability extensions, certified geometry
types, topology integrators, or tests produces a non-self-contained revision.

## Verification snapshot

The following checks were run on the complete checkpoint content on 2026-07-22:

| Check | Result |
|---|---|
| Capability ledger structural check | Passed: 55 capabilities, 52 envelopes, 422 fixture bindings |
| Goal contract structural check | Passed structurally; goal remains 0 of 8 gates achieved |
| `CADGeometry-Tests` | Failed: 224 passed, 18 failed, 0 skipped, 242 total |
| `CADKernel-Tests` | Failed: 416 passed, 48 failed, 0 skipped, 464 total |

The failures are explicit checkpoint state. They include surface-intersection
certification and resource limits, Boolean classification and volume, projection,
sweep and loft support, topology pcurves and stable identity, trim and extend,
selection and measurement, and strict unit-vector validation.

## Extraction order

Future integration should extract and verify changes in this dependency order:

`CADGeometry -> CADTopology -> CADIR/CADModeling -> CADKernel -> CADExchange`

The Rupa stable-selection and persistence migration is a separate downstream
change set and must not be hidden behind a compatibility fallback in this package.
