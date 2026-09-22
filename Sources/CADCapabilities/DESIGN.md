# Kernel Capabilities

## Purpose and Scope

Child of the [package](../../DESIGN.md), with no children. Owns the immutable
catalog of executable operation envelopes, not feature dispatch or geometry.

## Responsibilities and Boundaries

The catalog binds operation identifiers, inputs, outputs, typed failures and
verification owners. DocumentEditor uses it before accepting public commands.
Evaluators decide whether a specific shape succeeds.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Command admission | Composes the catalog. | No second editor. |
| [CADIR](../CADIR/DESIGN.md) | coordinates with | Operation identifiers | Binds serialized operations. | Codable support is not admission. |
| [Gear](../CADModeling/InvoluteGear/DESIGN.md) | depends on | Bounded external gear evaluation | Supplies the gear envelope. | Not manufacturing certification. |

## Architecture

```text
DocumentBuilder -> DocumentEditor -> requireExecutable -> source validation
                                                      -> native evaluator
```

## Contracts and Invariants

Catalog values are immutable. IDs are unique and bind actual APIs and tests.
Planned operations are rejected. Partial operations retain typed refusal outside
their documented domain. Native gears are partial: circular-filleted external
profiles and straight axial Sweep do not imply hob-generated or internal gears.

## Verification and Change Impact

CADCapabilitiesTests/KernelCapabilityContractTests checks the registered set.
SwiftCADTests/InvoluteGearCommandTests checks builder, command, persistence,
replacement and malformed-input refusal through the actual DocumentEditor.
CADKernelTests/InvoluteGearProfileTests owns evaluated geometry evidence.
