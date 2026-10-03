# Kernel Capabilities

## Purpose and Scope

Child of the [package](../../DESIGN.md), with no children. Owns the immutable
catalog of executable operation envelopes, not feature dispatch or geometry.

## Responsibilities and Boundaries

The catalog binds operation identifiers, inputs, outputs, typed failures and
verification owners. DocumentEditor uses it before accepting public commands.
Evaluators decide whether a specific shape succeeds.
The catalog also publishes source-backed known limitations through
`KernelCapabilityCatalog.domain(operation:)`. Each record identifies affected
operations, dimensions and the original implementation condition. The source
comments own condition text; Scripts/generate_capability_domains.py generates
the projection and rejects unmapped implementation markers. Domain publication
retains declared accepted inputs and never promises per-input success.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Command admission | Composes the catalog. | No second editor. |
| [CADIR](../CADIR/DESIGN.md) | coordinates with | Operation identifiers | Binds serialized operations. | Codable support is not admission. |
| [Capability Contract](../CADCore/CapabilityContract/DESIGN.md) | depends on | Public domain records | Exposes source-backed limitations | Empty filters do not prove full support. |
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

PUBLIC_CONTRACT_INVENTORY.json binds every FeatureOperationKind case to its
unique catalog entry. The inventory checker rejects omissions, stale entries
and ambiguous catalog mappings. Compiled tests compare those mappings with
the runtime catalog; neither check claims the evaluator supports every shape.

## Verification and Change Impact

CADCapabilitiesTests/KernelCapabilityContractTests checks the registered set.
SwiftCADTests/InvoluteGearCommandTests checks builder, command, persistence,
replacement and malformed-input refusal through the actual DocumentEditor.
CADKernelTests/InvoluteGearProfileTests owns evaluated geometry evidence.
KernelCapabilityDomainTests verifies domain lookup, dimensional filters, transport
and invalid records. KernelCapabilityDomainPipelineTests checks published
conditions against actual drafted extrusion. The source projection checker must
pass after implementation comments change.
