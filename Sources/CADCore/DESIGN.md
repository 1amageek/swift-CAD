# CADCore Expressions

## Purpose and Scope

This module owns unit-bearing expression source values. Parent: [Swift-CAD](../../DESIGN.md).
There are no child designs for expressions.

## Responsibilities and Boundaries

CADCore owns Codable expression structure, literal validation and dependency discovery.
Evaluation and kind checking belong to CADIR and CADModeling.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../CADIR/DESIGN.md) | used by | Parameter validation | Validates kinds and values | New cases require exhaustive handling |
| [CADModeling](../CADModeling/DESIGN.md) | used by | Expression resolution | Evaluates source and variables | Preserve evaluation equivalence |

## Architecture

```text
CADExpression -> CADIR parameter validation -> CADModeling evaluation
```

## Contracts and Invariants

`hypot(left, right)` accepts two quantities of the same kind and returns their
nonnegative Euclidean magnitude in that kind. It uses native hypot to avoid
intermediate square overflow. Incompatible kinds and nonfinite results fail
through existing UnitError validation. Zero returns zero; normalization by zero
fails through division's existing contract. Both operands participate in literal
validation, parameter dependency discovery and strict Codable round trips.
Existing serialized expressions keep their meaning; older readers reject the new
kind explicitly rather than treating it as a constant.

## Verification and Change Impact

RupaCore regression checks exercise both CADIR validation and CADModeling
resolution, references, units, zero/nonfinite cases and serialization. Expression
text readers/formatters and all visitors must handle the new binary case.
