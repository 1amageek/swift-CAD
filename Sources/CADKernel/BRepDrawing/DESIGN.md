# B-rep Drawing

## Purpose and Scope
Child of [CADKernel](../DESIGN.md), with no children. Owns D1-D3 composition from
current evaluated original B-rep topology to retained geometric drawing uses,
visibility partition and section material regions. The implemented edge
projection entry is the D2 source path; it does not claim D1 visibility or D3
material-region completion. Page layout, line styles, dimensions and hatching
belong to the document drawing owner; serialization belongs to CADExchange.

## Responsibilities and Boundaries
This owner traverses actual body/shell/face/loop/coedge ownership and retains
original curve, directed native trim, vertex IDs and source snapshot. Geometry
owns whole curve enclosures and silhouette/line-of-sight algorithms; Topology
owns original projected edge admission and source validation. A mesh is never
a source of geometric projected edges or hidden-line authority.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | EvaluatedDocument and exact source | Supplies current B-rep | Source admission precedes traversal |
| [OrthographicCurveProjection](../../CADGeometry/OrthographicCurveProjection/DESIGN.md) | depends on | immutable frame and retained original projected curve | Keeps parameter derivatives and whole enclosures | Projection may collapse a tangent |
| [OrthographicEdgeProjection](../../CADTopology/OrthographicEdgeProjection/DESIGN.md) | depends on | source-bound directed original edge | Retains trim and original identities | Closed/seam edge domain remains required |
| [DocumentDrawing](../../SwiftCAD/DocumentDrawing/DESIGN.md) | used by | geometric edge publication | Supplies drawing data | Edge-only publication is not hidden-line completion |

## Architecture
```text
Current evaluated source/B-rep -> owned bodies/shells/faces/loops/coedges
 -> original directed edge projection -> complete retained geometric uses
 -> whole visibility/section composition -> document drawing/export
```

## Contracts and Invariants
Every projected use names its actual body, shell, face and loop and retains
coedge orientation. Original edge projection admits actual spatial endpoints
and native trims. The projection is a geometric function of the entire original
curve law; no polyline replaces it. Caller use-count capacity is checked before
projecting or appending the next use. A failed topology reference or geometric
projection propagates; no omitted edge, truncation or empty success fallback is
permitted. The returned source and configuration remain bound to the exact
input snapshot. Coordinates use original canonical internal SI units. Scale
and page transform are not applied by this owner.

## State, Ownership, and Lifecycle
Projection results own immutable source values and current geometric curves.
Traversal collections are local to one invocation, with caller-supplied finite
capacity. No shared cache, I/O or target-specific isolation is introduced.

## Failure, Concurrency, and Constraints
Missing topology, invalid source, exhausted projected-use capacity and
cancellation fail before publication. Full D1 silhouette/visibility partition
and D3 material-region producers remain separate implementation gaps; neither
is inferred from this edge-only producer.

## Verification and Change Impact
After source implementation, exact public edge projection must cover every
Curve3D family, closed edges/seams, reversed uses, native parameters and source
provenance. Whole interval derivatives and collapsed projected tangents require
lower Geometry evidence. D1 and D3 require their own complete public execution
paths and cannot be certified by edge count or source structure.

### Original plane section producer

BRepDrawingSectioning constructs a temporary exact plane sheet that covers the
entire selected original face positions. DefaultFaceParameterBoundsResolver
and SurfaceDifferentialEnclosing provide whole trimmed-chart coverage; outward
linear projection establishes the rectangle, enlarged beyond the bound. No
mesh bounds or fixed samples determine cutting extent. The existing complete
Boolean intersection graph and UV splitter own boundary contacts and clipping.
Outputs retain every curve/point/coincident component and source body/face and
material IDs. This geometric intersection publication does not yet claim
assembled material regions, hole nesting or page hatching. Explicit source-face
and retained-component capacities fail before append; cancellation propagates.

### Original section hatching

Geometric edge projections also retain the immutable original evaluated B-rep
snapshot. `BRepDrawingProjection.validateCurrent` compares complete source,
configuration and original B-rep before occurrence/page consumers reuse it.
Equal IDs or source revisions alone do not admit a foreign evaluated model.


Hatching consumes source-bound section components and their retained whole
position bounds. Each finite hatch row intersects every retained original curve
against the row's extrusion plane using the complete curve/surface result,
including continuous overlap endpoints. All resulting events partition the row
before a prepared original-solid classification is queried. A midpoint is used
only inside an event-free interval; it is not evidence of an unpartitioned
curve's membership. Coplanar source-face contours participate explicitly. Holes
and separate material components therefore create separate classified spans.
Rows, boundary curves, events and output segments have explicit caller capacities.
Hatch coordinates use the supplied section frame; angle is expressed by that
frame, spacing is original internal metres. Failed completeness remains failure.
This does not yet publish contour loop nesting or drawing page composition.

Original section results retain the complete original B-rep and the admitted
temporary cutting model, tool face and complete split graph for downstream
material arrangement. validateCurrent compares the original source, B-rep and
configuration before hatch or region publication. Retained COW values share the
already admitted geometry; downstream consumers do not reconstruct a sampled
cutting model or infer tool/source face identity.

### Original material region composition

Material regions consume the retained original cutting model and complete UV
split graph. The Boolean owner's plane-side classifier prepares only original
solid targets, retaining the original adaptive clearance contract. Inside plane
sectors are kept and outside sectors discarded; unresolved boundary sectors fail.
Original pcurves feed the existing halfedge arrangement, which extracts all
bounded cycles and certified containment holes. Coincident cap loops contribute
original trim curves; exact original cap containment makes their closed material
admission independent of the cutting plane's normal orientation. Shared cap
seams with material on both sides are inactive, not new region boundaries.
Caller boundary/region capacities precede retained output allocation; lower
arrangement/classification budgets remain unchanged. Their legacy sample,
clearance, crossing/subdivision and patch-validation paths do not yet accept the
composing page's live work/byte admission. This route is not a complete bounded
D3 material-region producer until those actual lower operations share that
owner and the independent source, subdivision and algebra capabilities. The
output retains original body/material identity, exact sewing patch loops and
their source provenance.
No render mesh, degree-two-only stitching or sampled point polygon owns regions.

### Original silhouette trim admission

Silhouette extraction shares one caller SurfaceSilhouetteUsage with every
original pcurve enclosure and retained-curve query. Whole UV boxes are admitted
only after all original face boundary curves are interval-excluded from that box;
prepared exact UV containment then classifies the connected branch without
sampling its membership. Unresolved crossing/contact boxes are refined within
the same depth/cell/storage budget and fail all-or-nothing when authority is
insufficient. Exact paired periodic seams are identified by the existing seam
validator rather than treated as artificial material boundaries. Entire zero
normal-projection face domains are explicitly retained as coincident face IDs.
Critical source, complete boundary events and full visibility remain marked
source gaps; returned original spans do not claim a full hidden-line result.

Original face silhouette envelopes retain component incidence and join kinds,
including certified transverse crossings and cusps. Published trimmed spans carry
their original curve ordinal as well as component ordinal; consumers cannot
infer adjacency from projected endpoint proximity. Singular stations are admitted
by separating their complete original rational UV enclosure from every original
face trim. A classifier station classifies only the whole event-free box; it is
not the geometric cusp position. Inseparable rational cusp/trim incidence remains
an explicit source gap. The exact rational station and outward projected spatial
enclosure remain retained. The raw source graph is provenance, not permission
to draw its untrimmed curves as a complete drawing result.

### Retained drawing result authority

Material regions and hatch segments retain one shared immutable source snapshot
per producer invocation. The snapshot preserves the complete source document,
evaluation configuration and original BRep. Every public `validateCurrent` call
checks all three and cancellation. Exporters admit each supplied region and
segment independently, preventing old geometry with reused body/face identifiers
from being mixed into a current section. The snapshot is not publicly constructible
and its retained source buffers use immutable value ownership.

Isolated original silhouette contacts consume the lower exact-station and
whole-cell definiteness receipt. The prepared original UV membership admits
each contact before its original spatial interval is projected with outward
frame arithmetic. Contacts, spans and complete zero-face domains share the
producer's immutable source authority and cumulative caller usage. An empty
curve array does not imply an empty silhouette when contacts or zero domains
remain. The facade and application forward the same usage object without reset.

### Retained algebraic silhouette contacts

The drawing result carries original SurfaceSilhouetteAlgebraicContact receipts
separately from exact-station contacts. Trim admission excludes every original
pcurve boundary from the entire original contact parameter enclosure before
using UV containment on that connected event-free box. If separation is too
coarse, the same caller usage refines the retained algebraic root; no solver
or budget is restarted. Projection bounds map the original spatial enclosure
outward through the authored frame. Unresolved contact/trim coincidence is
explicit failure, never an empty silhouette or midpoint point substitution.

## Placed Original Curve Publication
`BRepDrawingPlacing` accepts immutable original projection and authored body
placements, under separate caller placement and projected-use capacities. Each
placement preserves its original occurrence identity, source body and full affine
columns. It transforms the original curve source and reprojects at the same native
parameter; no mesh fit or unit/page scaling occurs. The immutable result retains
original topology use and placement per curve. Current evaluation validation
proves original CAD source/configuration/B-rep equality; the application scene
owner separately proves that authored placements match its current scene.
Duplicate occurrence/body placements and foreign bodies fail. CADExchange consumes
this placed receipt directly, retaining unclassified geometric layers until the
visibility producer supplies a complete partition. This contract does not claim
hidden-line, section or page completion. Deferred verification covers repeated,
reflected/nonuniform occurrences, reversed/closed original curves, stale sources,
foreign placements and capacity refusal through the actual export route.

The section protocol also exposes explicit original target body IDs. Whole source
validation and source-face capacity remain unchanged; only original selected body
faces contribute cutting extent and Boolean targets. Empty selection is accepted
only for an empty original model, and duplicate/foreign IDs fail. This producer
supports per-occurrence composition without rebuilding or relabeling original
B-rep source. Exact world-plane pullback through general affine occurrences remains
a required geometry dependency before complete placed section publication.

A native silhouette chart with a nonzero parameter interval can have a constant
original spatial image at a canonical pole. Whole spatial first-derivative bounds
of exactly zero certify that image; admitted original trim cells publish
`BRepDrawingSilhouetteCollapsedCurve` point-class receipts, preserving curve,
component, native range, spatial enclosure and projected enclosure. They do not
become regular edges or empty silhouettes because of parameter width. Inseparable
original trim events still fail rather than infer pole membership from a rounded
chart or snapped endpoint.

### Placed section source and working geometry

A placed section retains the immutable complete original evaluated BRep for
freshness and a separate body-closure working BRep for world-plane intersection,
material classification and coincident contours. The working model preserves
original topology IDs, native trims and UV pcurves, and wraps every original
curve/surface in the same authored affine forward law. It never pulls a plane
back using rounded inverse coefficients or fabricates an evaluated document.
An exact original determinant sign rejects singular placement and reverses face
orientation for reflections; shell roles and directed native UV loops remain
unchanged. Source-entity and preparation-work capacities are admitted before
retention, share one placement invocation, and report consumed work. Every result
retains occurrence placement separately from original body identity. Original
source validation precedes working-model validation and complete Boolean SSI.
The bounded originalImage/world-plane SSI lower route remains a source dependency;
adding this composition does not certify that lower route. Deferred behavioral
evidence must cover reflections, nonuniform/sheared placements, repeated bodies,
coincident caps, holes, stale evaluation and cumulative capacity refusal.

The explicit placed path accepts a zero remaining component allowance: it may
publish an actually empty section, but fails before retaining any component.
This allows cumulative occurrence composition to inspect later empty placements
without resetting a full allowance. The legacy unplaced positive-capacity
precondition is unchanged.

`BRepDrawingSection.visitCoincidentContours` admits current original source and
selected coincident component before visiting the world working model's actual
directed native loop curves. The caller's `consumeUse` runs before projection
and its nonescaping `visit` receives original loop ID, coedge ordinal and retained
projected edge. Exchange never reconstructs coplanar contours from unplaced
evaluation geometry, and no intermediate contour array or independent allowance
is introduced.

Section-derived regions and hatch spans also retain the immutable section
invocation identity. `validateCurrent(_:for:)` checks that identity and exact
placement, in addition to whole original source freshness. Reused body/face IDs
and the same placement cannot mix geometry derived from a different cutting
plane. Copies of one retained section preserve the identity across all targets;
it owns no mutable state or platform-specific synchronization.

Section component ordinals are unique across the complete retained section
array: the producer assigns `components.count` immediately before each append.
They are not face-local Boolean component ordinals. Coincident contour selectors
consume this immutable global ordinal authority.

The preparation receipt counts topology visits, retained image records,
original image constructor visits and bounded original BRep validation callbacks
under one Mutex-backed invocation. Source and subdivision caps retain the lower
16/32 baseline; lower byte retention consumes the same remaining preparation
allowance before allocation. This receipt does not relabel Boolean SSI work as
one preparation step. Remaining original correspondence/seam/chart-lift callbacks
and aggregate SSI work stay explicit lower source dependencies; no complete
invocation guarantee is inferred while those lower ports are incomplete.

### Original plane-atlas station trim admission

BRepDrawingSilhouettes.atlasStations retains each admitted original plane-atlas
station, its face/body and atlas/station ordinals, the refined original algebraic
contact used for whole-box trim separation, and the outward projected spatial
box. Original incidence/end flags and germ counts stay in the retained lower
station, not reconstructed from numeric projected points. Stations and isolated
contacts share one trim-admission algorithm and the same extraction usage.
Outside stations remain in originalFaces provenance but are excluded from the
trimmed drawing station array. An unresolved exact station/boundary incidence
fails before result publication. Every station also consumes the existing
aggregate projected-entity allowance, including all other contact/span families.

### Original Placed Cutting Support
The additive section path retains BRepDrawingCuttingSupport: the authored local
Plane3D, flat original affine operation word, and source identity. Its cutting
surface preserves the original plane UV chart under that exact word. A supplied
projection frame maps output only and never becomes the cutting authority.
Whole original target position boxes pass through the retained inverse word,
then through the exact inverse of the original plane parameter basis. This
bounds native U/V even when accepted authored basis vectors are not exactly
orthonormal; dot products with approximate unit axes do not own chart recovery.
Tool edges retain local SurfaceLiftCurve3D laws and the same original word and
pcurve support. No rounded world plane or rounded matrix composition is authored.

Cutting preparation uses one common Mutex-backed work/byte admission; UInt32
algebra words are converted to checked bytes before allocation. Source depth,
curve subdivision depth and algebraic depth are explicit distinct caller values.
The source section retains this support for region/hatch/publication consumers.
Complete general SSI, chart correspondence and aggregate lower producer
allocation callbacks remain explicit source dependencies. Deferred evidence
covers nested transforms, inverse factors, shear/reflection, original UV hatch
rows, stale selected planes, exact whole bounds and finite caller refusal.

Hatch segment `originalCurve` validates exact section invocation and current
source before retaining its original cutting-chart endpoints in a degree-one
UV B-spline lifted on the local plane and transported by the retained word.
The normalized directed range is [0,1]; it is not inferred from output frame.
Existing frame-only sections retain the authored frame columns as one exact
forward factor. Endpoint/knot/weight and wrapper storage is admitted before
allocation under the caller RationalAlgebraAdmitting ledger. Export/page owners
project this retained world curve and apply paper scale once. This publication
port does not complete original hatch event discovery or generic SSI.

Drawing placements may carry an original operationWord alongside their numeric
transform. When present, that word is the geometric authority and transform is
only a display binding candidate. Original projection and body-image preparation
transport source curves/surfaces/vertices through the same retained word. Exact
word orientation reverses face orientation for reflection while native UV loops
and shell roles remain unchanged. Legacy direct-affine construction preserves
its prior source meaning. Source freshness includes the whole placement value;
export consumers must never promote the candidate transform over a retained word.

### Exact Silhouette Trim Partition Composition
When whole original branch boxes cannot exclude every face boundary, the drawing
producer obtains complete exact curve/boundary partitions from the Geometry
trim provider using the same extraction usage. It retains each original endpoint
expression and merges all cuts using exact comparison, not outward Double bounds.
Each positive native sector retains OriginalSurfaceSilhouetteTrimmedCurve.
Coincident sectors belong to the closed original face boundary; other sectors use
a strictly interior normalized witness only after its whole UV query box is
separated from all original trims. Membership then classifies that event-free
box, never substitutes for the source curve or exact endpoints. The result carries
whole lower partition provenance and projected D0 bounds; regular native spans
and exact-endpoint spans are distinct carriers under one aggregate capacity.
Analytic/general implicit boundary lower gaps remain marked failures. Deferred
evidence includes tangent/endpoint/cusp/coincident trim roots, mixed-boundary
cut ordering, sub-Double separation, cancellation and resource refusal.

An exact-endpoint silhouette span separately retains a certified constant spatial
enclosure when all components of its whole [0,1] original first derivative are
exactly zero. This is a point-contour event with complete original endpoint
provenance, not a regular edge inferred from parameter width. Absence of that
certificate does not assert regularity or nonzero tangent; the original curve
and its whole-jet proofs remain authoritative.

### Original Cutting-Chart Hatch Rows
The additive preparation-bounded hatch invocation builds one exact flat word
from the original local plane chart columns/origin followed by the retained
scene factors. A row is the canonical original plane (0,y,0), normal Y, U=X,
transported through that word. Its native U is the original cutting-chart U;
row intersection surface coordinates, not projected world points, partition
hatch intervals. Classification witnesses apply the same exact prepared word
to original (u,y,0). Published segment endpoints retain cutting UV and the
section invocation identity. The output frame has no cut/row authority.

One Mutex-backed preparation ledger owns explicit raw source and array
allocations, chart/word preparation, row sources, event/output records and
classification witnesses. Source, subdivision and algebra depths stay distinct.
The returned receipt records that preparation work/storage. Original
intersector/classifier session internals still require complete same-caller
callbacks before the whole lower invocation can claim aggregate resource
closure; this remains marked on the callable bounded branch. Original
section ranges/capacities, cancellation and failure propagation are preserved.
Deferred verification covers sheared/reflected nested cuts, UV/output-frame
difference, coplanar boundaries/holes, stale support, cumulative rows/events
and failure before publication.

Trim membership refinement retains each returned exact endpoint isolation receipt
and its attained depth across query iterations and adjacent sectors. Refining a
query cannot reset a source root's path depth; the same extraction usage
continues to own all sign/isolation work and storage.

The preparation owner retains the caller's independent algebra ceiling. Its
`visitCoefficientCell` checks that same ceiling and consumes the same work counter;
coefficient/root depth is not reinterpreted as cutting UV or source depth. Reusing
a word prepared with a larger capability cannot exceed a smaller drawing caller
cap during later inverse/enclosure queries. Assembly adapters likewise forward
coefficient visits to their existing explicit algebra authority and same owner.


### Silhouette Shared Preparation Admission

The silhouette producer retains the original `SurfaceSilhouetteUsage` live owner
through its preparation callbacks. Original BRep validation, finite face bounds
and the injected containment session share scalar work and byte retention with
extraction, trimming and retained span queries. The callback depth denotes actual
geometric proof depth; structural source traversal remains independently bounded
by the usage's explicit source capability (at most the intrinsic 16 levels),
and coefficient operations receive
the usage's explicit algebraic depth. Parameter membership is requested through
the provider's nongeneric `FacePointContainmentSession.containsParameter`
requirement; absent UV capability is a typed failure, never a legacy projection
fallback. Ordered source keys and retained preparation adapters are admitted
before allocation. Original document semantic authority is supplied by
[Original Evaluation Source Binding](../OriginalEvaluationSourceBinding/DESIGN.md),
which the engine and cache materializer preserve without semantic/hash/equality
replay. Manual and Native-decoded artifacts without that binding fail before
silhouette preparation; their genuine bounded semantic validation remains an
explicit lower gap. Remaining BRep/containment markers also prevent complete
all-domain invocation accounting. Deferred verification must exercise preparation
exhaustion, provider UV refusal and current original trimmed-face success using
the same live invocation owner.


Silhouette seam suppression calls the bounded `PeriodicFaceSeamValidator`
original pair proof with the same live preparation callbacks and independent
source, subdivision and algebra capabilities. Reversed/periodically shifted
materialized candidate pcurves are never the drawing suppression authority.
Unsupported whole-source equality fails before a complete silhouette result;
no false seam result silently publishes a missing boundary.



Upper silhouette source maps, returned contacts/spans and pending trim cells
admit their actual typed record stride in UInt32 storage words before insertion
or append. A record does not stand for one word. Existing retained original
source buffers are shared; this admission accounts for new descriptors and
owned pending/output records rather than copying their source limbs. Work and
storage counters stay cumulative through the same extraction owner and preserve
the original selected ceilings.

### Original Placed Silhouette Extraction

The placed silhouette overload derives one original body closure from the current
producer-bound evaluation, admits every retained topology/geometry map entry,
validates that closure with the same live usage, and consumes ShapeOperating's
flat exact original word image. Silhouette extraction runs on the resulting
world-space original support, not on a transformed silhouette of the base body.
This matters because the zero-normal view law changes with the original affine
placement. All native UV/coedge/face roles remain the transformed producer's
contract; reflected material orientation belongs to that lower producer.

The returned receipt retains the original evaluation snapshot and placement
identity/word alongside the world-space original envelopes. Current-source
validation never substitutes the derived image model for the document's BRep.
Whole original validation and body-image lower gaps remain explicit; placed
silhouette extraction alone is not visible/hidden foreground-depth proof.

Regular admitted native silhouette ranges may be wrapped as exact authored-endpoint
trim receipts on the SAME SurfaceSilhouetteUsage. Algebraic partition endpoints
continue to use their retained expressions; outward boxes are never authored cuts.

Algebraic contact and admitted atlas point localization can be refined under an
explicit positive native maximumParameterWidth on the same silhouette Usage.
The returned immutable receipt retains original snapshot/placement and source
root; narrower subsets preserve the prior trimmed-face admission. Native outward
projection is rebuilt from the refined original spatial enclosure.

### Original projected curve contact preparation

The projected-contact preparer consumes every native owning span of the retained
placed edge law against every admitted exact/regular silhouette traversal. It
retains the original placed projection, silhouette packets and all lower exact
partitions. Span endpoints remain source knot/trim values; contact cuts remain
original algebraic endpoint expressions. Parameter-preserving image families
retain their full original source, not transformed control nets. The same supplied
SurfaceSilhouetteUsage pays source preparation, pair proofs and retained typed
capacities before allocation. This is screen-incidence preparation only. Point
contours, trim boundaries, positive-dimensional overlap and line-of-sight depth
coverage are separate mandatory visibility inputs; an empty curve-pair list
does not prove visible/hidden status.

Each owning edge cell additionally merges all retained pair cuts by exact endpoint
comparison, retaining contributing partition indices. Only a cell with no whole
projected overlap yields these silhouette-event-free open sectors and exact
interior witnesses. This merged cover is still not a trim-event or depth-order
certificate, and it is never a visible/hidden classification.

Projected-contact entries also retain the actual lower contact's exact original
edge-minus-silhouette depth sign, including zero and whole-edge-fiber results.
The same live silhouette owner pays field sign queries and retained contact
capacity before allocation. This sign concerns a screen-incidence event; it is
never a visible/hidden receipt or a replacement for complete foreground LOS.
Whole-edge fibers remain distinct from isolated events in the upper carrier.
