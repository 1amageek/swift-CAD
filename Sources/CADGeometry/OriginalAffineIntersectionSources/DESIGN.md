# Original Affine Intersection Sources

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), with no children. Owns the bounded exact
homogeneous checkpoint for one finite, aperiodic, positive-weight Native rational
surface span under a retained rational original affine operation word. It issues
three-variable CS and four-variable SSI equations with unchanged parameter
ownership. Public intersection dispatch, result publication and whole-domain
chart composition remain with the parent; an equation checkpoint is not a
complete intersection or exclusion receipt.

## Responsibilities and Boundaries
`OriginalAffineSurfaceIntersectionSource` retains the complete original image,
prepared word, Native span receipt and local rational source law. The word's
original factors own coefficient authority; Native controls, weights and knots
own the intrinsic homogeneous law. The checkpoint does not obtain a numeric
transform, fit a new surface, flatten normalized directions or change UV.
`OriginalAffineIntersectionEquations` retains the participating source values,
raw coincidence equations and both original denominator guards. Its CS order
is (t,u,v), and its SSI order is (u1,v1,u2,v2), with the affine image first.
Normalized algebraic words and non-Native/periodic descendants fail explicitly
until their genuine ordered-field/domain issuers compose this checkpoint.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | original image composition | Owns dispatch and publication integration | Source issuance does not close public SC or all seven families |
| [Original Affine Image](../OriginalAffineImage/DESIGN.md) | depends on | retained image and unchanged UV | Supplies original source/word binding | Numeric evaluation is not coefficient authority |
| [Original Affine Operation Word](../OriginalAffineOperationWord/DESIGN.md) | depends on | validateOriginal and prepared exact rational coefficients | Reuses exact forward/inverse action | No midpoint or normalized-field conversion |
| [Original Rectangle Tessellation](../OriginalRectangleTessellation/DESIGN.md) | depends on | OriginalNativeSpan.validate | Supplies source-bound one-span authority | The caller selects the span under its original allowance |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | OriginalRationalSurfacePolynomial and exact operations | Supplies original homogeneous Native law | Same cumulative work/storage admission |
| [Intersection Algebra](../IntersectionAlgebra/DESIGN.md) | depends on | ExactIntersectionPolynomial embedding and exact cross products | Issues raw equations in the original coordinate ring | Real coverage remains a separate lower resolver obligation |

## Architecture
```text
original image + caller-admitted native span/domain
  -> original word/source revalidation
  -> exact rational prepared coefficients + original Native homogeneous H/W
  -> H'image[row] = sum(A[row,column] H[column]) + translation[row] W
  -> unchanged W and original UV/domain receipts
  -> CS(t,u,v) / SSI(u1,v1,u2,v2) equations and W guards
```

## Contracts and Invariants
The input must retain a direct Native B-spline descendant and a finite closed
box contained by its original span. Native source validation proves finite
controls, positive weights and lawful knots; span validation binds the exact
source and preparation tolerance. One image consumes one remaining source
level. Word algebraic depth is supplied independently and forwarded unchanged.
The original prepared word supplies twelve exact rational coefficients in
row-major [A00,A01,A02,Tx,...] order, including exact cofactor inversion for inverse
factors. Every transformed numerator uses all four original homogeneous laws.
W is retained verbatim: no cancellation, normalization, tolerance coincidence
or changed multiplicity. The denominator is nonzero as a polynomial and is
explicitly excluded from every issued equality system. Raw coincidence equations
are Ha_i Wb - Hb_i Wa, with no solver or partial coverage claim.

## Runtime Flows
Admission and cancellation precede source traversal. Original factors and Native
source/span are validated under the same caller ledger. Exact coefficients,
polynomial output arrays, domains and retained metadata are admitted before
creation. All loops and exact operations continue on that ledger. A final
zero-work checkpoint and cancellation check precede atomic publication. Equation
issuance follows the same rule and never resets the caller allowance.

## State, Ownership, and Lifecycle
All published values are immutable Sendable and retain COW source buffers,
original word coefficient owners and the native span receipt. There is no new
mutable cache or callback storage. Synchronous lower preparation callbacks
borrow the caller ledger; releasing or changing the caller's input copy cannot
change issued laws. Common Native/WASM/Embedded values use identical ownership.

## Failure, Concurrency, and Constraints
Non-Native/periodic descendants and normalized algebraic words produce typed
unsupportedCapability. Exhausted source/algebra depth, work or physical storage
and cancellation propagate without publication. Invalid source/span/domain
bindings remain explicit lower typed failures. No fabricated denominator or
rounded action replaces unavailable source authority. Foundation input allocation
is outside this source checkpoint; its own arrays, polynomial limbs and retained
metadata use checked UInt32 storage admission.

## Verification and Change Impact
[OriginalAffineIntersectionSourceTests](../../../Tests/CADGeometryTests/OriginalAffineIntersectionSourceTests.swift)
own independent original-coefficient forward/inverse homogeneous equality,
varying weights, nonunit domains, unchanged W/UV/source receipts, CS/SSI raw laws
and guards, lifetime after input release, unsupported normalized/family inputs,
invalid binding, depth/work/storage refusal and final cancellation.
The SSI comparison fixture uses a degree-one Native patch with positive weights;
its exact center point preserves the asserted parameter correspondence while
meeting the lower Native surface's positive-degree validation contract.
Changes to word or Native-law contracts require this checkpoint's regression tests; shared
public dispatch and full SC/seven acceptance remain parent verification scope.


## Planned Composition Consumer Migration

Status: design only; current implementation guarantees above remain unchanged.
Affine intersection preparation will consume homogeneous-only child laws and retained exact word fields, including normalized words; no rational rounding or differential preparation is authorized.
The [common consumer handoff](../OriginalSourceIssuance/DESIGN.md#composition-consumer-handoff-design)
owns coefficient transport, complete-cover, publication and migration acceptance.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
