# CADCore

## Purpose and Scope

This module owns unit-bearing expression source values. Parent: [Swift-CAD](../../DESIGN.md).
Expressions have no child designs. Typed kernel failure normalization is owned
by the [Failure Contract](FailureContract/DESIGN.md) child component.
Public capability domains are owned by the
[Capability Contract](CapabilityContract/DESIGN.md) child component.

## Responsibilities and Boundaries

CADCore owns expression structure, literal validation and dependency discovery.
It also owns stateless current-task cancellation observation; consumer routing
and domain failure mapping remain outside that child component.
Its Native/normal-WASM Codable capability boundary is owned by
[Native Codec Capability](NativeCodecCapability/DESIGN.md).
Evaluation and kind checking belong to CADIR and CADModeling.
The source envelope number is owned by [SchemaVersion.current](SchemaVersion.swift);
the current source baseline is 0.16.0. CADIR's required nullable independent
shape field retains the complete original source graph, including required
curveLinearSources with original LINE/VECTOR records and curveSplineSources /
surfaceSplineSources with original spline declarations and shared named control
points. Group records also require original family and actual backPointerMembers; ordered
traversals and inverse membership remain source meanings. Prior envelopes
through 0.15.0 are rejected without migration.
The active development independent shape graph also requires
`originalSTEPGroups`, retaining every actual STEP GROUP owner including owners
without assignments. Assignment records refer to that distinct source identity;
the owning contract is [Original STEP Group](../CADIR/IndependentShapeSource/OriginalSTEPGroup/DESIGN.md).
ProductAttributes requires both the
itemCharacterizations and shapeElementDescriptions arrays, preserving the
separate nullable physical description and required shape-element description
contracts. Definition-qualified
body/face targets retain their existing selector authority. CADIR owns required
source payloads and CADExchange owns strict native transport admission.
A baseline change must verify those contracts together without implicit migration.
PAR.SDESC1 verifies this source baseline through current strict Native admission,
independent source/resolution fixtures and public STEP generations.


The target-common explicit original-value source framing is owned by
[Portable Source Encoding](PortableSourceEncoding/DESIGN.md). It is independent
of Native Codable and supplies complete IR fingerprint bytes, cumulative
resource admission and canonical ordering without reflection.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Failure Contract](FailureContract/DESIGN.md) | child | Typed failure normalization | Owns diagnostic context and cause categories | Never converts failures to success |
| [Capability Contract](CapabilityContract/DESIGN.md) | child | Domain descriptions | Owns immutable capability records and validation | Declared coverage is not geometric proof |
| [CADIR](../CADIR/DESIGN.md) | used by | Parameter validation | Validates kinds and values | New cases require exhaustive handling |
| [CADModeling](../CADModeling/DESIGN.md) | used by | Expression resolution | Evaluates source and variables | Preserve evaluation equivalence |
| [Portable Identity](PortableIdentity/DESIGN.md) | child | Foundation-free 128-bit identity and strict UUID text codec | Supplies the storage and textual identity contract used by tagged persistent IDs; `TaggedID` owns explicit Native UUID/Codable adapters | CADExchange owns strict Native/STEP wire and schema admission; Embedded does not claim Codable support |
| [Current Task Cancellation](CurrentTaskCancellation/DESIGN.md) | child | Foundation-free current-task cancellation check | Preserves typed `CancellationError` across supported targets | Consumer placement and domain mapping remain outside this component |
| [Native Codec Capability](NativeCodecCapability/DESIGN.md) | child | Common Core values and explicit Native/normal codec adapters | Separates genuinely unavailable Embedded codec capability without changing value storage or meaning | Complete CADCore target proof is required; full document/A2 portability remains separate |
| [Numeric Work Admission](NumericWorkAdmission/DESIGN.md) | child | Caller-owned work, typed storage and checkpoint requirements | Connects the existing three Bezier producers to the same incoming execution | Ordinary unbounded authoring is explicit; direct calls never fall back to it |

## Architecture

```text
CADExpression -> CADIR parameter validation -> CADModeling evaluation

PersistentIdentity -> TaggedID<Tag> -> CADIR / CADModeling / CADExchange consumers
CurrentTask -> CurrentTaskCancellationChecker -> bounded Core consumers
```

## Contracts and Invariants

`TopologyLineage` retains canonical parent identities in original strict order.
The package initializer accepting `canonicalParents` validates every identity,
strict ordering, output exclusion and relation cardinality without constructing a
set or sorting. It retains the supplied immutable array through COW ownership.
Invalid canonical input returns `nil`; it is never silently repaired. A caller
performing admitted canonicalization owns its traversal/comparison cost before
entering this finite validation boundary. `isStructurallyValid` performs the same
allocation-free canonical check for both ordinary and admitted construction.
The caller also admits the boundary's linear visits and variable role comparisons;
this metadata contract grants no original-geometry identity or correspondence.

The unchanged canonical constructor and check are verified by
[TopologyLineageCanonicalTests](../../Tests/CADCoreTests/TopologyLineageCanonicalTests.swift).

`hypot(left, right)` accepts two quantities of the same kind and returns their
nonnegative Euclidean magnitude in that kind. It uses native hypot to avoid
intermediate square overflow. Incompatible kinds and nonfinite results fail
through existing UnitError validation. Zero returns zero; normalization by zero
fails through division's existing contract. Both operands participate in literal
validation, parameter dependency discovery and strict Codable round trips.
Existing serialized expressions keep their meaning; older readers reject the new
kind explicitly rather than treating it as a constant.

Kernel failure classification and diagnostic presentation follow the
[Failure Contract](FailureContract/DESIGN.md#contracts-and-invariants).

### Portable identity boundary

`PortableIdentity128` owns two UInt64 words, their existing big-endian UUID byte
order, RFC 4122 version/variant generation, and strict canonical
`8-4-4-4-12` text parsing/formatting. `TaggedID<Tag>` owns the phantom tag,
comparison, hashing, and deterministic high/low constructors over that value.
Foundation `UUID` conversion and the Native Codable adapter belong to
`TaggedID` in CADCore. CADExchange owns strict Native/STEP wire and schema
admission. The common identity contract does not add a conditional or
placeholder `Codable` conformance for Embedded Swift; source-envelope
serialization remains a separate capability and migration boundary.

## Verification and Change Impact

RupaCore regression checks exercise both CADIR validation and CADModeling
resolution, references, units, zero/nonfinite cases and serialization. Expression
text readers/formatters and all visitors must handle the new binary case.

## Natural Bezier expression contract

Natural, Shaped and CurvatureProfile producers use the
[Numeric Work Admission](NumericWorkAdmission/DESIGN.md) contract. Their
ordinary wrappers and direct `using:` APIs execute one generic numeric body.
The existing ordinary no-resource-limit/no-cancellation authoring policy is
explicit; admitted expression evaluation forwards the caller's admission
through validation, quadrature, Newton, blossom and array publication.

CADCore owns pure numeric Bezier polynomial continuation and the persistent `bezierNaturalExtension` expression. Its interleaved coordinates and distance all have length kind; its coordinate index selects one of the degree new points in the oriented end span. It returns a length and discovers every input dependency. The degree is bounded to 1...11 and coordinates/index/distance are validated before numeric work. Both CADIR and CADModeling evaluate the same numeric implementation. CADKernel retains its public continuation adapter and delegates to CADCore. Invalid tangent, non-finite data, nonpositive distance and nonconvergence throw explicit errors; no cached coordinate fallback is allowed. JSON and Rupa editable text retain all operands. Tests cover parameter changes, units, both evaluators, round trips and invalid data.

## Shaped Bezier extension contract

CADCore owns Extend Curve's Arc, Soft and Reflective shapes and their persistent
`bezierShapedExtension` expression, so the new control points stay expressions of
the curve's own points and the length instead of stored numbers.

| Shape | Stored operands | Evaluation | Fixed structure |
|---|---|---|---|
| `.arc(spanCount:)`, `.soft(spanCount:)` | the end Bezier segment (degree 3...11) and the length | the end's point, unit tangent and signed curvature from the segment's derivatives; `CurvatureProfileExtension.cubicSpans(…, spanCount:)` (κ₀ held, or fading linearly to zero, integrated by composite Gauss–Legendre, the first span G2 at the end, each span ending on the profile and joining the next with a continuous tangent), each span raised to the segment's degree | the span count chosen when the extension is made (the fewest within the modeling distance, `profileSpanCount`); stored spans that stray further than the modeling distance after an input change throw `resourceLimitExceeded` |
| `.reflective(degree:coversCurve:)` | the curve's last Bezier segments back to the one the reflected length starts in, and the length | the tail of that length (arc length by composite Gauss–Legendre, start by bisection with Newton steps) split by de Casteljau, mirrored across the end's normal and reversed | the stored segment count (`reflectiveSegmentCount`); a tail that starts in a later stored segment, or runs past them unless they are the whole curve (`coversCurve`, which then mirrors all of it), throws `resourceLimitExceeded` |

Every operand has length kind; the coordinate index selects one of the new
points (span count × degree for Arc and Soft, the stored points less one for
Reflective). The form is validated on decode, encode, kind inference and
evaluation; CADIR and CADModeling evaluate the same `BezierShapedExtension`. No
cached coordinate stands in for a failed evaluation.
`BezierShapedExtensionTests` (CADCoreTests) and
`BezierShapedExtensionExpressionTests` (CADIRTests) own it.


PAR.CIWR2 replaces the physical-only characterization source name with the
independent item metadata name and required array. The semantic current baseline
is0.11.0 even though the record payload stays target/name/nullable description.
Strict Native refuses0.10 and earlier versions and every old array key; an absent
required itemCharacterizations array is invalid. The source semantics authority
is [ProductAttributes](../CADIR/ProductAttributes/DESIGN.md).
