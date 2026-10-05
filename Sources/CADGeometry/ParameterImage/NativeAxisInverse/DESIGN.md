# Native Axis Inverse

## Purpose and Scope
Child of [Parameter Image](../DESIGN.md), without children. Owns the immutable
inverse of an original native rational B-spline 2D pcurve whose complete image
is a nonconstant, monotone, axis-aligned line.

## Responsibilities and Boundaries
Preparation retains the original 2D controls, weights, knots and each positive
native owner. Geometry's surface-lift facade composes this receipt with the
original surface chart; Mesh owns its tessellation and selected surface owner.
No synthesized 3D spline, fitted curve or rounded normalized station is authority.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parameter Image](../DESIGN.md) | parent | original chart retention | Composes the inverse receipt | Exact affine normalization remains source law |
| [Rational Bivariate Algebra](../../RationalBivariateAlgebra/DESIGN.md) | depends on | original basis, exact GCD and Sturm roots | Proves whole-owner monotonicity and original target roots | Source, spatial and algebra depth remain independent |

## Architecture
```text
original native 2D pcurve -> positive-owner homogeneous laws
    -> constant other-axis identity + derivative odd-multiplicity root proof
    -> common strict orientation on every owner
exact native UV target -> original scalar equation -> retained native real root
    -> exact (root - original lower knot) / original domain width
    -> outward numeric enclosure for caller localization
```

## Contracts and Invariants
Every native owner is admitted by the same caller ledger. The derivative
numerator must be nonzero; a plateau is rejected. Its complete odd-multiplicity
root set may contain native endpoints only. Even-order derivative zeros do not
change orientation and do not require dividing the tangent by scalar velocity.
The exact constant other-coordinate identity holds on every owner. Original
C0 knot position and global orientation are checked across adjacent owners.
Every target root retains its original homogeneous equation and native owner;
a shared knot retains both owning sides. Exact rational normalization follows
the full original native domain, without a rounded Double subtraction/division.
Outside the proved image returns nil; contradictory multiple roots fail.

## State, Ownership, and Lifecycle
Prepared values are immutable Sendable COW snapshots. No callback, mutable
allowance or asynchronous lifetime is retained. Every query borrows its caller's
algebra admission; no private work or storage budget is introduced.

## Failure, Concurrency, and Constraints
Invalid source or policy, nonaxis images, plateaus, nonmonotone images and
inconsistent knot joins fail explicitly. Caller work, optional byte policy,
maximum positive span count and selected algebra depth are preserved. Source
depth admits the raw leaf at depth zero; spatial subdivision is not charged for
native owner enumeration. Algebra isolation and refinement use the selected
algebra depth. No default byte callback is fabricated.

## Verification and Change Impact
After the source phase verify increasing/decreasing rational pcurves, even
derivative zeros, odd sign changes, common-knot roots, outside-image nil,
nonaxis/plateau failure and lowered budgets through the public lift and Mesh
paths. Verify exact normalized endpoints on nonrepresentable native differences.
These are pending behavioral evidence, not current completion claims.
