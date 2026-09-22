# Involute Gear Source

## Purpose and Scope

Child of [CADIR](../DESIGN.md); no children. Owns persisted external gear
dimensions, not sampled teeth or a separate history model.

## Responsibilities and Boundaries

Stores tooth count, circular root conditions, dimensional expressions and
approximation budgets. CADModeling owns geometry and feasibility. Expressions
may reference pressure-angle parameters through the existing cosine expression
in base radius; resolved SI radii define the profile builder's input contract.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | FeatureOperation and dependencies | Native graph source | No generated control points persisted |
| [Gear modeling](../../CADModeling/InvoluteGear/DESIGN.md) | used by | Resolved section construction | Existing bounded profile and Sweep | Circular fillets are not hob-generated roots |

## Architecture

```text
CADExpression dimensions -> native gear source -> existing Profile + Sweep
                        -> dependency invalidation -> regenerated B-rep
```

## Contracts and Invariants

One feature has no feature inputs and one body output. Every named dimension
is required. Dimensions encode as string-keyed objects, not unordered enum-key
arrays. A finite source origin supports document rebasing; product occurrence
transforms remain independently owned. Lengths resolve to positive SI values; twist is a signed angle,
and pitch tooth thickness a positive angle. Separate profile and sweep error
allowances retain their respective owners; neither is a display tolerance.
Double-helical twist is zero at both ends and reaches the specified twist at
half width. Single-helical twist reaches that value at full width. Zero twist
uses the same source to produce a spur gear. Root feasibility belongs to the
existing profile builder, not to persistence or UI.

## State, Ownership, and Lifecycle

Source is Codable value data. The owning native document retains it across
Undo, save and reopen. Generated profile and path exist only during evaluation.

## Verification and Change Impact

Verify persistence, parameter-driven regeneration, all three twist choices,
invalid dimensions and atomic refusal through the existing document evaluator.
UI and Agent creation must converge at existing Core staging. Implementation
integration and runtime proof remain pending; source presence is not completion.
