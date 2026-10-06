# Loft

## Purpose and Scope

This component owns Loft section correspondence, original guide contacts, side
construction and finite cap admission. Its parent is [CADModeling](../DESIGN.md).
It has no child components. S8, S9 and S10 retain their full required domains;
source implementation and behavioral completion are separate states.

## Responsibilities and Boundaries

Loft retains each original exact section span and guide parameterization through
correspondence. Section display points select seams and correspondence only.
They never replace an original curve or prove absence of intersections.
Geometry owns native curve root and enclosure authorities. Topology owns BRep
validation, sewing and finite arrangements. Shared section resolution remains
outside this component.

Guide connector publication consumes [Original Guide Traversal Chain](../../CADGeometry/OriginalCoons/GuideTraversalChain/DESIGN.md).
The selected contact endpoints retain their source scalar roots. Native guide
segments are split at their original owning knots, and each directed RootSpan
retains the raw source parameter and source segment ordinal. The aggregate
rational partition is a newly declared construction chart. It does not alter
an existing polyline's Euclidean parameterization. A candidate built from
numerical contact representatives is construction only; publication requires
fresh correspondence to the retained aggregate source under the same caller
admission. Missing retained endpoints remain explicit source capability gaps.

Tolerance-contact correction consumes [Original Guide Endpoint Correction](../../CADGeometry/OriginalCoons/EndpointConnector/GuideCorrection/DESIGN.md).
Corrected original guide versus raw original guide uses the existing model
position tolerance, with the existing tangent and curvature requirements.
Native fitting against the corrected source retains distance/4. The final
candidate independently receives a direct original-guide comparison at model
tolerance after basis and derivative changes. The raw and corrected original
providers are prepared once per connector and retained across these proofs. These certificates do not add by
triangle inequality. A contact residual within model tolerance is not subject
to the fitting quarter tolerance as source-contact admission.

The body builder retains one canonical connector image per connection/vertex.
Native Hermite construction resolves every connector of a connection to a
shared basis before shared edges and both neighboring sides consume those
images. Original Coons construction retains each connector basis independently
and requires no common denominator or degree conversion. This prevents independent
degree-elevation rounding of the same boundary. Preparation charges the existing
body patch-pair allowance through the common-basis callback and continues with
its remaining count; original guide and contact parameters remain separate.
The common-basis and exact shared-boundary owners still decide image validity.
Non-Hermite side construction retains one immutable original traversal for
each section span and canonical connector, then publishes an Original Coons
source. Its source kind is preserved through whole original embedding,
side-pair contact admission, BRep geometry storage and cap classification.
A rounded transfinite tensor image cannot replace the source during those
steps. Hermite sides retain their authored native coefficient law. Both source
kinds use the same cumulative side-preparation/contact allowance; lower work,
cells and retained storage are paid before they execute. A structural exact
bilinear specialization alone may use stationary planar-support admission.

Section image construction, trim/reversal re-certification, far-section affine
images and guide connector images borrow one conversion admission from the
correspondence invocation. The immutable allowance owner protects the same
262144 combined work/retention counter with `Mutex` on every target; copies and
escaping source-chart callbacks retain that owner, and no span, section or retry
creates a replacement budget. Conversion storage callbacks are bytes and debit
checked ceiling(bytes / 4) UInt32 words. The existing construction source depth
20 and converter-local requirements remain unchanged. Raw face source owner
identity is preserved independently of the callback owner. Legacy standalone
internal facades may create an allowance at their invocation boundary only.
The original guide/contact allowance forwards actual work units and retention
bytes into this same owner while preserving its existing local pair-depth and
cell ceilings. Placed constructed-region sections consume their retained
original charts as persistent normalized source laws, independently of the
Profile metadata facade and freshly certified construction spans.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | Feature evaluation | Publishes the validated result | Source-only edits are unverified |
| [SectionResolution](../SectionResolution/DESIGN.md) | depends on | Exact boundary spans | Resolves original sections | Preserve orientation and trim |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | Original interval roots, shared-boundary reconciliation and embedding | Owns geometric admission for differently represented adjacent side boundaries | Search exhaustion is failure; whole chart injectivity remains required |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | BRep validation and sewing | Owns finite topology | Contact is not shared identity |

## Architecture

```text
LoftFeatureEvaluator
    -> original section resolution
    -> original guide correspondence
    -> unique cyclic and hole correspondence
    -> ExactLoftBodyBuilder
        -> original side embedding and pair separation
        -> finite cap/side admission
        -> BRep validation -> feature publication
```

## Contracts and Invariants

* Different vertex counts use the union of original span partitions. Every
  partition endpoint must remain on the original exact boundary.
* The first section fixes the common origin. Explicit seam and traversal inputs
  constrain the candidate set. Automatic correspondence minimizes the existing
  adjacent squared-distance objective, including the closing connection.
* A second distinct candidate path inside the distance-squared ambiguity band,
  including accumulated outward rounding uncertainty, produces
  `ambiguousSelection`. Candidate iteration order cannot choose the outcome.
* Hole order is representation order, not correspondence authority. Outer loops
  remain outer. Hole mappings must be unique under the declared correspondence
  objective. Different hole counts require an explicit topology event or an
  ambiguity report; they cannot silently lose boundaries.
  The hole objective is the sum of minimum cyclic squared distances of common
  original span-partition rings. Complete injective permutations form the state
  space; original guide contacts constrain them. The first hole order anchors
  identities, and the last-to-first connection is included for closed stacks.
  An apex supplies one terminal vertex, not a hole birth or death declaration.
  A source region with inner loops therefore reports `ambiguousSelection`
  with its original loop count before constructing any apex side. It does not
  classify the missing topological correspondence as an unsupported surface.
* Curve section admission retains the evaluated original curve law and authored
  native trim before any image conversion or reversal. Its immutable contact
  source is independent of image span partitions, cyclic seam rotation and
  traversal. Both curve-reference boolean values explicitly select directed
  traversal; automatic correspondence cannot reverse either value again. Seam
  offsets remain independently automatic unless an explicit seam constrains them.
  Original profile line, circular-arc and spline laws similarly own
  contact domains; rational conic images never substitute their parameters.
* Original guide chains retain every `EvaluatedCurve.exactCurve`, authored trim,
  direction, and original segment identity. Section contacts retain original
  native parameter enclosures independently of connector images. Contact order
  follows directed segment identity, not the parameters of a composed spline.
  Every construction-span reversal and restriction transports its retained
  original chart independently of the image coefficients. Generated far-section
  similarity maps retain an explicit affine image of that original curve;
  circular rational construction parameters are never relabeled as angles.
  Native interval-to-chain order arithmetic rounds outward; authored singleton
  endpoints retain exact joint identity so separate nearby roots never merge.
  Connector generation restricts the original chain between contacts before
  making its geometric spline image. Circle angles consequently remain angles
  through event resolution, even when the connector has rational parameters.
* Contact projections steer search only. Original three-dimensional difference
  enclosures own admission. Stationary speed does not authorize replacing the
  original guide parameterization with a line.
* Whole side embedding and pair separation remain required after correspondence.
  A continuity-constrained Hermite candidate is construction input only.
  Its final original boundary-corrected surface must consume the retained
  incident support, directed coedge parameter law and original section span
  in a fresh bounded continuity proof before publication. An unavailable
  final proof returns typed failure, including for a planar support; a
  construction-only early return cannot authorize the corrected normal field.
  Finite cap contact classification uses both original trimmed regions.
  `LoftFiniteCapContactValidating` is an injected finite-topology authority. It
  enumerates all original support loci, partitions against both authored trims
  including holes, and permits only shared topological edges or vertices.
  Nonincident material contact fails; support contact outside either finite
  region is not material contact. The Kernel implementation owns arrangements;
  Loft supplies the generated model and face identities without copying that
  algorithm. Legacy standalone evaluation retains its marked partial path.
* Existing tolerances, original subdivision limits and caller cancellation remain
  fixed. New correspondence work uses one cumulative bounded allowance before
  storage or transitions; no section resets or discounted repeated work.

## Runtime Flows

Correspondence first enumerates permitted offset/direction states and then keeps
the two best distinct predecessor paths for every state. The final connection
cost is included before comparing the best and second path. A unique winner is
materialized once and passed into the existing original-span body producer.

## State, Ownership, and Lifecycle

All preparation and receipts are immutable, local to an evaluation, and retain
their input values. No cache or shared mutable state is introduced. Native,
ordinary WASM and Embedded use the same value and ownership contracts.

## Failure, Concurrency, and Constraints

Nonfinite scores, numeric enclosure overflow, cancellation and exhausted work
produce typed failure. Multiple valid correspondences produce ambiguity rather
than success. Existing mandatory tangent/coincident contact and general finite
arrangement gaps remain incomplete until their actual producers are connected.

## Verification and Change Impact

Deferred behavioral checks must exercise the public evaluator with unique and
ambiguous seam/direction paths, reordered holes, unequal vertex counts,
stationary and tangent guide parameters, continuous coincidence, both finite
cap trims, and whole side self-intersection. Search and resource failure must
propagate without publishing topology. No build, test or target behavior is
claimed by this source-only batch.

### Invocation Ledger Isolation

The source and native admission paths share one invocation-owned
`LoftSurfacePreparationAllowance`. Its immutable limits and one Mutex-protected
used count replace the former local source counter without resetting it at a
surface boundary. Callback work executes outside the counter critical section.

| Target | Storage | Isolation | Read / mutation | Owner release |
|---|---|---|---|---|
| Native | Same `Mutex<Int>` | `withLock` | Checked cumulative consume | Invocation callbacks retain owner |
| WASM | Same `Mutex<Int>` | `withLock` | Same checked consume | Same retained owner |
| Embedded | Same `Mutex<Int>` | `withLock` | Same checked consume | Same retained owner |

This matrix describes the authored source contract. Target compilation,
linking and concurrent behavior remain deferred, so it is not verification.

The continuous far section retains the explicit original affine image and
reconverts that original directed trim under the same position, tangent and
curvature requirements. A transformed prior candidate cannot carry its error
allowance through scale amplification. A restricted original chart first issues
its persistent normalized source law with exact restriction fractions. Spatial
placement acts on that entire retained law, and fresh conversion uses its real
normalized domain [0,1]. This is a source chart domain, not an inferred angular
endpoint. No interval midpoint or changed candidate supplies original authority.

Generated flat native boundary traversals retain the invocation's existing
native owner ceiling and zero remaining source descendants, because their
persistent source is the newly generated plain B-spline law. Root preparation
forwards actual byte retention as checked canonical UInt32 words to the same
original invocation counter. This preparation receipt is construction-source
authority; it does not substitute for upstream conversion/correspondence proof.

Closed face/profile invocations retain resolved original sections, original loop
candidate charts and original contact laws together. A face's Profile facade
supplies region metadata and display samples; it never replaces original face
edge laws when building spans or guide events. Hole correspondence reorders
these parallel carriers by the exact original facade loop identity before
matching and partition construction. The matching/partition consumers take
retained raw spans explicitly, including their original parameter charts.

Original Coons embedding, pair separation and nominated-boundary admission use
the source-bounded refinement port with the same original construction source
ceiling of twenty. Local and pair subdivision ceilings remain independent;
subdivision zero does not replace that source ceiling. Actual native byte
reservations forward to the Loft invocation's canonical UInt32-word owner.

Final section partition preserves each original parameter chart together with
its actual candidate and correspondence receipt. Progress selection is a
construction choice; trimming, knot normalization and common-basis changes
re-certify the resulting coefficients against the retained chart under the
same invocation admission. The original chart is never reconstructed from a
normalized candidate. Generated connector endpoint authority must likewise
retain the actual original section endpoint law before a raw-source Coons
chart may replace a construction-image boundary.

Final unconstrained Coons sides publish the persistent original construction
chart as each section edge, on normalized [0,1]. The same retained chart is
prepared once as an original boundary. Generated connector curves retain both
original section endpoint expressions and their correction basis, and that
same original connector is published as the edge and consumed by neighboring
Coons sides. Vertex representatives must lie within the unchanged original
endpoint enclosure admission; candidate endpoint proximity alone is insufficient.
Hermite-constrained side tensors retain a separate unfinished source premise:
the original boundary correction must preserve the specified tangent/curvature
field before their construction tensor can replace the original boundary law.

## Hermite Original Boundary Correction

[Original Boundary Correction](../../CADGeometry/OriginalCoons/BoundaryCorrection/DESIGN.md)
retains final section/connector source laws around the native Hermite tensor.
The section transverse D1/D2 source fields remain those of the construction;
Loft checks final tangential/source fields, side embedding and all nominated
shared boundaries before publication. Candidate tensor coincidence alone is
not original boundary authority.

The body side-proof owner preserves its intrinsic cumulative preparation ceiling
while forwarding actual work units and retained UInt32 words (checked bytes)
to the feature's original construction admission. Native/local and feature
allowances are nested constraints, not independent replenishable budgets.
Guide source arrays and event buffers reserve their typed payload before
allocation through that same caller storage entry. Metadata comparison scans
remain work units; original profile callbacks are already canonical UInt32
words and forward those words without relabeling them as work. Event-buffer
growth reserves the new retained capacity and admits copying existing entries.
The original guide contact allowance also forwards the existing construction
source depth, geometric subdivision and scalar algebra capability separately.
Each is bounded by its unchanged intrinsic producer ceiling; callback admission
does not silently restore default recursion or root permission.
The immutable source-face support for each Hermite side remains retained until
the final boundary-corrected surface is certified; a native candidate certificate
cannot authorize a changed final section tangent or curvature field.
For every retained start/end support, the final boundary-corrected side invokes
the source continuity issuer on the same original section traversal at V=0/V=1
before publishing its face. Support cardinality must match the section partition.
The exact planar issuer and the curved supporting-coedge issuer own their
respective failure contracts; Loft does not replace either with a construction
certificate or omit a requested side when its source proof is unavailable.

Exact original-word ordered-field cells use the intrinsic algebraic depth 32,
independently of native side subdivision and source nesting. The exact adapter
checks this named algebraic authority; every native pair/local producer still
checks its own subdivision ceiling before visiting the shared counter. A final
side conversion admission composes those unchanged producer limits with any
lower caller capabilities and forwards work/bytes to the same body owner.

The generated strict-plane path retains the unconstrained position-corrected
connector separately from its final plane-derivative wrapper. A vertex collects
all incident side plane constraints into one canonical original connector. Each
side builds its unconstrained Hermite source from the base connectors, then
constructs the endpoint-coherent derivative surface using the canonical final
connectors. Both changed connector candidates and final surface candidates
receive fresh whole position/tangent/curvature certification on the same
invocation admission. Final original embedding, strict target continuity and
original boundary incidence remain independent publication requirements.

Original guide events retain the exact contact parameter authority when issued by the finite rational/field producer. Chain reversal preserves that immutable source witness. Event localization and candidate point/trim representatives do not become original source endpoints; subsequent exact cut publication must consume the retained parameter root.

Shared section-vertex guide events with retained contact roots merge only after exact first-parameter selected-root equality. Rational scalar GCD/Sturm or ordered-field transport uses the independent event algebra cap under the same invocation counters. Distinct close roots and different loop roles stay separate.
