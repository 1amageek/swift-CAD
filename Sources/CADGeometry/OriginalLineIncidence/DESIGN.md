# Original Line Incidence

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns exact incidence of
original represented Cartesian points and original parametric line coefficients.

## Responsibilities and Boundaries

Consumes original point, origin and nonzero direction. Modeling owns axis use and
revolution construction. No normalized or constructed second axis point is used.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | exact floating point expansions | Preserves original dyadic coefficients. | Indeterminate expansion arithmetic fails. |

## Architecture

```text
original point-origin exact expansion × original direction
    → all three exact cross-component signs → incidence Boolean
```

## Contracts and Invariants

Success requires all three cross products to be exactly zero. A nonzero sign
proves nonincidence. Finite source validation and a nonzero direction precede
expansion evaluation. A tolerance or nearest-point residual supplies no authority.

## Failure, Concurrency, and Constraints

The predicate uses bounded degree-two expansion scratch and one caller work
charge per coordinate. Cancellation and indeterminate finite arithmetic propagate.

## Verification and Change Impact

After source freeze, verify exact translated axis endpoints, oblique dyadic axes,
near-axis off-line points, degenerate directions and cancellation in Revolve.

The sibling point-plane side port evaluates the exact dot product of original
point-minus-origin and original normal coefficients. Sign zero proves incidence;
positive/negative signs can certify positive-weight control hull half-spaces.

Affine volume scaling exposes a determinant interval from exact original column
rational arithmetic. Every input Double is an exact dyadic coefficient; cancellation
is resolved before outward conversion. Singular source matrices fail explicitly.
The same caller callback admits all exact work/storage with lexical lifetime;
no rounded determinant or independent exact-algebra allowance is substituted.
