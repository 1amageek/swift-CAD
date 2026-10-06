# Original STEP Line

## Purpose and Scope
Child of [Independent Shape Source](../DESIGN.md), retaining the original LINE/VECTOR point, direction, magnitude, unit law and world adjustments. No children.

## Responsibilities and Boundaries
This source owns foreign record identity and the parameter derivative law. Geometry owns exact normalized operation-word preparation and evaluation. Native presentation units never replace a nonnull foreign length source.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Independent Shape Source](../DESIGN.md) | parent | curveLinearSources binding | Complete source publication | No geometry duplication |
| [Original STEP Placement](../OriginalSTEPPlacement/DESIGN.md) | depends on | Named elements and length law | Shared original points/directions/units | Same identity ledger |
| [Original Affine Word](../../../CADGeometry/OriginalAffineOperationWord/DESIGN.md) | depends on | Exact normalized word | Actual native line derivative | No rounded normalization |
| [Independent Exchange](../../../CADExchange/IndependentShapeExchange/DESIGN.md) | used by | Raw LINE/VECTOR ingress and egress | Legal standard source transport | One cumulative caller allowance |

## Architecture
```text
original point/direction/VECTOR magnitude + length chain
    -> exact normalized word -> native unit-X line
    -> original LINE/VECTOR source emission
```

## Contracts and Invariants
The immutable eight source fields retain original identities and exact UTF-8 labels. Positive original magnitude multiplies the normalized raw direction and normative length gain; translations use ordered world adjustments. Native requires every field including nullable originalLengthSource. Source dictionary keys bind to actual original-word curves; geometry/source disagreement fails.

## Failure, Concurrency, and Constraints
Preparation borrows caller RationalAlgebraAdmitting work/storage/depth. Nonfinite, zero direction, nonpositive magnitude, conflicting identities and unavailable standard adjustment publication fail explicitly. Values are immutable Sendable on Native/WASM/Embedded; Codable is Native only.

## Verification and Change Impact
Independent original LINE fixtures must exercise nonunit direction ratios, every length prefix/conversion chain, shared named elements, directed Cartesian/parameter trims, translation and Native/two standard generations. Caller budget/cancellation and exact physical endpoints are required. New source fields require parent Native/portable writer composition; runtime verification occurs after all source authoring.

Native vector IDs use the shared [Native identity adapter](../OriginalSTEPPlacement/DESIGN.md#native-identity-adapter), preserving the original canonical text schema independently of Core Codable capability.
