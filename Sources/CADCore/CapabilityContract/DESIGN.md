# Capability Domain Contract

## Purpose and Scope

Child of [CADCore](../DESIGN.md), with no children. Owns immutable public
capability values, domain descriptions and source-backed limitation records for
requirement C3 in [the register](../../../OCCT_REQUIREMENTS.md).

## Responsibilities and Boundaries

The contract exposes a capability's declared accepted inputs and known remaining
conditions by support surface, boundary curve, connection and degeneracy, plus
other relevant dimensions. It does not evaluate geometry or predict success.
CADCapabilities owns the catalog and its links to production implementations.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Immutable capability domain | Publishes value types | No shared mutable state |
| [CADCapabilities](../../CADCapabilities/DESIGN.md) | used by | Domain and limitation records | Binds source conditions to operations | A declaration does not prove geometric coverage |
| [Failure Contract](../FailureContract/DESIGN.md) | depends on | Typed failure codes | Describes failure obligations | No diagnostic text parsing at runtime |
| [Native Codec Capability](../NativeCodecCapability/DESIGN.md) | coordinates with | Native/normal Codable and unavailable Embedded codec boundary | Preserves common values while isolating codec interfaces | No change to shared state, typed failures or geometric support |

## Architecture

```text
Source implementation conditions -> CADCapabilities generated records
Declared capability inputs ------> KernelCapabilityCatalog.domain(operation:)
                                      -> KernelCapabilityDomain -> caller
```

## Contracts and Invariants

- A domain retains the original capability and its accepted-input descriptions.
- Known limitations have nonempty unique IDs, explicit affected operations,
  dimensions, condition text and an original source location.
- Surface, boundary, connection and degeneracy filters expose relevant conditions;
  an empty result is not a claim that every input succeeds.
- Domain lookup rejects unknown operations. Native/normal Codable transport preserves all records; Embedded retains the common records without that unavailable adapter.
- Source comments own condition text; generated records must match those comments.
- New markers, removed markers and changed conditions fail source consistency
  verification until the generated catalog is refreshed.

## State, Ownership, and Lifecycle

All values and catalog arrays are immutable and Sendable, without locks,
platform branches or a live dependency on the source checkout.

## Failure, Concurrency, and Constraints

Catalog validation rejects duplicate IDs, unknown affected operations, empty
dimensions, invalid source locations and empty condition text. A domain query
reports existing catalog status, including partial support; it never converts a
limitation into evidence of success.

## Verification and Change Impact

CADCapabilitiesTests/KernelCapabilityDomainTests verifies real catalog lookup,
filtering, serialization and malformed-record refusal. The source projection
checker verifies every current incomplete-implementation marker. SwiftCADTests
checks that the published oblique-extrusion condition matches actual refusal and
that a normal drafted extrusion still succeeds. Source changes affecting any
condition require regeneration and review of operation/dimension bindings.
