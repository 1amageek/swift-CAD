# Portable Source Encoding

## Purpose and Scope

Parent: [CADIR](../DESIGN.md). This component owns explicit original source writers
and the source fingerprint payload over all targets. It has no children.

## Responsibilities and Boundaries

The payload retains schema, units, parameter values, graph order/dependencies/nodes,
all feature payloads, sketch source entities/order/constraints/dimensions,
selection dimensions, assembly, independent shapes, documentFoundation and every
ProductAttributes value, including manufacturing information and saved views.
The document ID and DocumentMetadata name/timestamps remain outside evaluation
source authority. Revisions remain separate cache authorities. A codec capability
difference must never omit source fields or replace values with unsupported data.

Explicit conformances for CADCore values are owned by CADCore. Explicit source
conformances for CADIR and its consumed public Geometry/Topology values live here;
Geometry/Topology retain sole ownership of their original value definitions and
geometry meaning. No new geometry/source authority or source UUID is invented.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | Validated immutable source | Owns source publication and memo lifetime | Source algorithm identity changes explicitly |
| [Core Portable Source Encoding](../../CADCore/PortableSourceEncoding/DESIGN.md) | depends on | Canonical original-value framing and cumulative limits | Supplies Foundation-free byte encoding | Original values never become random hashes |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | Original public geometry records | Encodes represented source values | No sampled substitute |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | Original B-rep/source signature values | Encodes source geometry/topology references | Full original owner graph must be retained |

## Architecture

```text
DocumentTransaction -> validated immutable CADDocument
 -> complete typed source payload -> Core canonical encoding
 -> Foundation-free SHA-256 -> source fingerprint -> evaluation/cache freshness
```

## Contracts and Invariants

A generated sphere-cone node curve retains its source-issued normalized traversal.
The existing seven-field certified-curve writer cannot encode that authority and
returns `unsupportedCapability` before writing any curve fields. Existing direct
physical-endpoint curves retain the seven-field representation. Source-preserving
serialization of generated node receipts is a separate codec capability; the
writer never serializes them as a legacy curve with a different position law.

Original 3D polylines retain their authored XYZ points and closure assertion. The
certification tolerance and exact Euclidean clock are reconstruction policy and
derived calculation state, respectively, and are excluded from source identity.
Bare original STEP GROUP records retain declaration identity, name and explicit
nullable description independently of assignments.

Original guide traversal chains retain their declared exact station partition,
original source segment ordinals and every original traversal. The common
certification tolerance is derived from those traversals; continuity proofs,
owning caches and calculation caps are excluded.

Original plane-derivative curve sources retain their original traversal and both
ordered endpoint constraint arrays. Surface sources additionally retain the corrected
construction and the complete final Coons boundary authority. Each constraint retains
its original support surface and derivative order. Derived projected endpoint values,
plane bases, construction buffers and preparation capabilities are excluded.


`sha256-cad-source-binary-v1` identifies the target-common binary payload; it is
never confused with historical sorted-key JSON digests. Every source field and
associated enum value has an explicit typed writer. Multiline case declarations
retain every named or unnamed associated value in declaration order. Source
authoring must consume each complete declaration and fail on an unparsed suffix;
a partial match must never manufacture a payload-free enum case. Native package Codable is a
separate adapter. Graph table keys and source node IDs both participate. Graph
order is semantic; dependencies and source sets are canonically sorted. Sketch
entity authoring order remains semantic and must not disappear from the payload.
PMI/view/independent geometry and all original coefficient/parameter fields are
retained without sampling. Nil, empty and exact source text remain distinct.
Original STEP spline source maps retain shared POINT identities/names, curve and
surface form assertions, each three-valued logical assertion, authored knot
specification and rational entity-family distinction. Surface controls preserve
native [v][u] order. The original endpoint connector retains its six authored
construction/endpoint/basis fields; derived preparation caches are excluded.

All children, sorting and SHA-256 share the same source encoding budget. The
historical convenience entry had no caller byte/work/depth allowance; it retains
addressable checked counters rather than silently treating metadata-text limits
as a geometry support cap. Bounded evaluation callers pass their remaining
explicit allowance through the strict overload; those limits never borrow another
phase's work or reset child counters. A cached digest is the immutable document's
source identity, not proof of a smaller caller's encoding allowance. Explicit-limit
calls perform their own admitted computation. Caller resource option ownership
remains with evaluation/transaction composition.

## State, Ownership, and Lifecycle

Validated document copies share one immutable memo owner. Computation remains
outside its Mutex and racing readers publish the same digest. Failure stores no
value. Target capability must not change storage, Sendable or synchronization.
Older Apple systems without Mutex use the existing pure recomputation boundary;
this does not introduce mutable unsynchronized state.

## Failure, Concurrency, and Constraints

Canonical encoding/resource/cancellation errors propagate without a success
prefix. Common SHA-256 borrows completed bytes only for its scoped digest; buffer
owner outlives every read and no pointer escapes. FIPS word arithmetic intentionally
wraps. Length/padding/index arithmetic derives from validated buffer sizes.

## Verification and Change Impact

User-directed source implementation precedes all verification. Later checks own
full source closure, all original enum cases, table insertion invariance, semantic
field changes, fixed SHA vectors, memo publication/failure races and actual
Native/normal-WASM/Embedded paths. Build or declarations alone never prove A2.

Original cyclic translation source framing retains the three authored fields
`originalSourcePeriod`, signed `originalTurnCount`, and `parameterGain`. Derived
native/foreign displacement arithmetic is excluded; the original period and
integer turn source law cannot be replaced by their rounded displacement.

The original gain difference frame retains `originalLower`, `originalUpper` and
`periodicTranslation` as three source fields. The enclosing gain enum retains
its `difference` case and one original Difference payload. Exact coefficient
and outward caches are derived and excluded; neither directed endpoints nor
the original integer-turn law may be replaced by a rounded effective gain.

The original Coons source frame retains exactly the four original traversals
`vMinimumBoundary`, `vMaximumBoundary`, `uMinimumBoundary`, and
`uMaximumBoundary`. Original endpoint enclosure caches remain derived and are
excluded. The procedural enum retains its original Coons case and one source
payload; an approximate tensor image is never substituted into this frame.

An independent selection retains its original shared basis reference, original
trimming selectors and nullable directed traversal source separately. The
five-field item frame includes `traversalSource`; it does not replace the
original geometry CurveID with a generated chart identity. The reference enum
retains the body selector's entire original SubshapeID payload.

An independent representation retains its authored family as a fifth required
source field. The exact original family enum raw value is framed; geometry
members or inferred dimension never replace the declared source family.

An independent geometric set retains its original declared family in the fourth
required source field. `GEOMETRIC_SET` and `GEOMETRIC_CURVE_SET` remain distinct
raw source values; neither members nor their dimension synthesize a family.

Assembly occurrence source retains its original direct placement family. The
four-field occurrence continues framing id, name, definitionID and placement;
placement now frames the explicit rigid or affine case with its complete four
authored transform columns. Expanded root-to-leaf placement words are derived
evaluation artifacts and are excluded from the persistent source identity.

Authored assembly placement words are persistent authority when present as the
placement word case. The original flat factor order, forward/inverse operation
tag and unchanged original direct rigid/affine payload are framed. Evaluated
composite matrices and expanded inherited words remain derived and excluded.

Original STEP placement framing retains every named raw coordinate record,
length unit, optional axis/reference/scale presence and original family. Frame
and instance records include nullable originalSTEPPlacement alongside their
existing derived placement. Exact normalized-frame construction is a Geometry
algebra contract; its derived radicals and numeric matrices are excluded from
the original descriptor's source frame.

Normalized original affine operation words retain their raw factor order and
forward/inverse family, including normalized STEP source descriptors. The
normalized descriptor frames all nine original fields, including exact length
gain, separate exact linear gain and ordered displacement/conjugation adjustments. Derived radicals,
prepared matrices, orientation and preparation depth remain excluded. Assembly
placement retains the explicit `step` family and complete original STEP record.

Foreign length-source framing retains its original unit identifier, complete
metre/conversion chain, prefix presence, record identifiers and original decimal
factor/dimension token strings. Placement descriptors include nullable original
length source. Exact gain arithmetic is derived; neither a binary length-unit
label nor a normalized coefficient replaces original decimal source spelling.

Original affine-word curve, support and pcurve images retain the complete
original source and flat operation word. Pcurve images additionally retain the
original target image and directed start/end fractions. Prepared word and
spatial enclosure caches are excluded; source transforms are not replaced by
midpoint columns or a recomposed matrix.

Original independent length context provenance is also retained in the six-field
context and nineteen-field source container. Associated and actual ambient
length source descriptors remain distinct nullable records; presentation units
never replace either original referenced source chain.

Independent source curveLinearSources retains each original STEP LINE location,
direction, named VECTOR identity/magnitude, original length-unit chain, and
ordered adjustments. The authored numeric parameter law is distinct from a
derived native line and participates in document source identity.

Original construction chart images encode the original traversal or the six original parameter-law fields, including exact first/last fractions. Derived preparation capabilities and coefficient caches are excluded.

Original parameter-polynomial incidence constraints encode their complete canonical original power-to-rational coefficient map. Power coordinates are explicit source fields; dictionary ordering uses the same encoder scratch/output admission as all source maps.

Original independent groups retain all six source fields, including ordered family and actual inverse-member subset. Source membership arrays preserve authored order; neither derived reverse lookup nor unordered canonicalization replaces these fields.

Original boundary-corrected support source frames its native construction and four-boundary original Coons carrier. Prepared native owners, auxiliary construction boundaries, corner residuals and algorithm caps are derived and excluded.

Original drafted curve identity retains generator, raw normal/axis/pull and authored height/physical-radian angle. Its original ruled surface retains start and endHeight. Cached unit directions, trigonometric bounds and construction limits are derived and excluded; enum dispatch is added when the Geometry owner publishes the corresponding actual case.

The actual Geometry originalDrafted enum cases now dispatch the retained raw draft values; no fitted candidate net participates in source encoding.
