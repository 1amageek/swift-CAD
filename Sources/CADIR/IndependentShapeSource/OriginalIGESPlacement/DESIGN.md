# Original IGES Placement

## Purpose and Scope
Owns immutable original Type124 decimal coefficients, Type408 scalar/matrix/translation order and subsequent authored world adjustments. Parent: [Independent Shape Source](../DESIGN.md). No children.

## Responsibilities and Boundaries
Raw lexical values and actual shared matrix FrameID own the placement source. Numeric frame/instance placement is a derived display candidate. Geometry owns exact rational affine action; this component produces its original factors under the caller ledger without axis normalization or rounded matrix multiplication. The global admitted IGES length unit owns normative model coordinate conversion; Native LengthUnit arithmetic is unchanged.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Independent Shape Source](../DESIGN.md) | parent | source frame/instance sharing and graph validation | Stores these nullable source families | STEP and IGES source families are exclusive |
| [Original Affine Operation Word](../../../CADGeometry/OriginalAffineOperationWord/DESIGN.md) | depends on | rationalForward/rationalInverse and exact action | Retains original coefficients and order | Same work/storage/algebra allowance |
| [Independent Shape Exchange](../../../CADExchange/IndependentShapeExchange/DESIGN.md) | used by | literal ingress/egress and actual matrix identity | Legal Type124/408 transport | Decimal values are not binary frame witnesses |

## Architecture
```text
Original decimal tokens + normative unit -> exact rational factors -> original operation word
                                       -> derived finite numeric view
Type408: scale -> original shared Type124 -> parameter translation -> world adjustments
```

## Contracts and Invariants
Matrix source owns twelve row-major original literals, actual form0/1, length unit and ordered adjustments. Exact original Gram entries equal the identity; the determinant sign agrees with the original form. Translation alone consumes normative length gain. Instance source owns required nullable matrixFrameID, original scale literal, three original translation literals, length unit and adjustments. Its positive scale, matrix and translation remain separate factors in the specified order. Original decimal D exponents are interpreted exactly through the decimal owner while lexical spelling survives. Matrix references remain shared source IDs. Nullable absence is explicit and strict Native decoding never creates an identity matrix record.

World conjugation prepends the inverse authored displacement and appends its forward operation; an ordinary source translation appends only its forward operation. Every factor and raw source value remains retained. Numeric views never replace original operation words.

## Failure, Concurrency, and Constraints
Malformed counts/literals/forms, nonpositive scale, nonorthogonal original matrix, mismatched source units/identities, nonfinite numeric view, source depth and cumulative work/storage/algebra exhaustion fail explicitly. All preparation uses the supplied RationalAlgebraAdmitting owner; immutable sources contain no shared mutable state. Native serialization is unavailable in Embedded mode while the semantic values remain available. Native record and typed-array admission reuses the original placement decoding contract: explicit coding-path source depth, semantic visits at exact depth zero, and the same cumulative work/cell/storage owner. Source depth never becomes the algebraic ceiling.

## Verification and Change Impact
After full source authoring, literal .6/.8 rotations, reflected frames, nonbinary normative units, matrix sharing, scale/matrix/translation ordering, defining matrices, translation conjugation, strict required-nullable decoding and two-generation legal output own behavioral verification. Recheck parent graph reachability, Geometry word action, Native schema and exchange publication. Source authoring is not verification evidence.
