# Section Reference

## Purpose and Scope

Child of [CADIR](../DESIGN.md), with no children. Owns the persistent distinction
between a closed profile and a source curve used as a modeling section.

## Responsibilities and Boundaries

`SectionReference` owns source identity, input role and strict Codable shape.
`CurveSectionReference` identifies a source whose evaluation must produce exactly
one curve. Resolution, coordinates, geometry and output body kind are not owned
here. A curve is not implicitly converted into a closed profile.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | ProfileReference, FeaturePort | Owns source graph values. | Profile and curve roles differ. |
| [SectionResolution](../../CADModeling/SectionResolution/DESIGN.md) | used by | Source admission | Resolves current exact geometry. | Ambiguous curves fail rather than selecting the first. |

## Architecture

```text
section source value -> strict encoding/decoding -> graph input role
                                               -> exact section resolution
```

## Contracts and Invariants

- A profile reference preserves its explicit nonnegative profile index.
- A curve reference contains no profile index; unrelated or unknown fields fail.
- Encoding and decoding validate the reference, not only later graph evaluation.
- Promotion from Sweep ownership does not create a second reference type or a
  compatibility alias. The existing wire representation remains unchanged.
- Values are unconditionally Sendable and own no mutable shared state on any target.

## Verification and Change Impact

`Tests/CADIRTests/SectionReferenceTests.swift` checks round-trips, invalid profile
indexes and mixed reference fields. `SectionResolutionTests` owns runtime source
cardinality and identity checks. Sweep evaluation/preflight, Rupa commands,
selection, remapping, Agent and Automation all consume this one value contract.
Adding face, orientation or range semantics requires updating those consumers
before publishing the changed contract; those capabilities are not implied here.
