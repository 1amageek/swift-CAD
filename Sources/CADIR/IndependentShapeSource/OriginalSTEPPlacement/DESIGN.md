# Original STEP Placement

## Purpose and Scope
This child of [Independent Shape Source](../DESIGN.md) retains the original standard axis/operator coordinate law. Its [Length Source](LengthSource/DESIGN.md) child retains the normative foreign unit graph. Original placements are common immutable values; Native serialization is a platform adapter.

## Responsibilities and Boundaries
Retain original point/direction identities, exact names and binary numeric ratios, optional-axis/default presence, original nullable uniform scale and model length unit. Derivation supplies a numeric frame for existing consumers, not a replacement source law. Exchange owns wire parsing and real entity publication. Assembly owns occurrence words and actual world evaluation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Independent Shape Source](../DESIGN.md) | parent | frame/instance identity and validation | Retains nullable original placement witness | Derived placement must match the original interpreter |
| [Document Assembly](../../DocumentAssembly/DESIGN.md) | used by | original placement factors | Shares the original standard law without flattening | Numeric derived columns are not an exact law proof |
| [Independent Shape Exchange](../../../CADExchange/IndependentShapeExchange/DESIGN.md) | used by | parser/producer original carrier | Re-emits real shared point/direction entities | Original identities and null/default presence remain source |

## Architecture
```text
Original point/direction IDs + ratios + defaults + scale + units
  -> immutable original axis/operator source
  -> numeric derived frame for existing numeric consumers
  -> strict binding validation
  -> actual STEP entities / Native source
```

## Contracts and Invariants
Original elements retain source identity independently of equal coordinates. Axis2 source contains location, optional axis and optional reference direction; Cartesian source contains location, three optional directions and nullable scale. Scale is positive finite when present. Every selected original direction is finite and nonzero. Defaults and projections follow the existing normative STEP primitive producer. Original numeric location uses its retained model unit, while derived translation uses internal SI. No rounded matrix inverse or multiplied frame becomes original authority.
Both payloads retain a required ordered adjustments array. Each immutable
adjustment owns the original world displacement and whether the operation is
conjugation. Translation appends an operation instead of changing/dividing the
original foreign model coordinates. An explicit-origin target and a physical
frame append posttranslation; an implicit-origin instance appends conjugation.
The exact normalized-frame producer consumes this same original sequence.
Nonempty adjustments require a legal STEP chain carrier at egress; source-only
Native persistence does not establish that format producer.

## Failure, Concurrency, and Constraints
Values are immutable Sendable. Derivation/validation propagate typed geometry failures and consume the invocation's supplied work callback. Native decoding requires exact keys and explicit nullable fields. An original interpreter witness is not sufficient evidence that an exact downstream spatial image producer exists; that lower source gap remains with Geometry/Assembly.
Native original placement and LINE record adapters charge the shared allowance before decoding retained arrays. Adjustment arrays require a known count; work and physical retained storage are admitted before reserve/append, and each decoded record checks the distinct source nesting authority. These semantic visits use algebra depth zero and retain the original operation's work/cell/storage owner.

## Verification and Change Impact
Source-only authoring precedes verification. Required behavioral evidence includes nonorthogonal proposed reference directions, negative handedness, nonunit raw ratios, absent axes/scale, shared original element identities, strict Native failure and two actual STEP generations. Changes affect parent source validation/translation, Exchange wire producer and Assembly placement evaluator.

`validateOriginal(tolerance:maximumDepth:usage:)` admits the structural records and
actual original normalized affine word on the supplied exact ledger. Numeric
normalization and its finite derived columns are not a legal source admission
criterion. Owners comparing the old numeric binding may do so separately; only
the actual original field producer proves the normalized law.

Foreign unit authority is owned by [Length Source](LengthSource/DESIGN.md). A required-nullable descriptor distinguishes original standard gain from the Native LengthUnit binary convention.
