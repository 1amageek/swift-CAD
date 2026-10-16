# Geometric Measurement

## Purpose and Scope
Child of [CADKernel](../DESIGN.md), owning public closest-pair classification and density/unit/placement mass composition.

## Responsibilities and Boundaries
Topology owns original bounded geometry integration and extrema. Kernel resolves document selections, classifies solid containment and publishes measurement values with units and errors. Neither representative points nor rendering triangles certify an integral or minimum.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Kernel](../DESIGN.md) | parent | public evaluated document | Connects production selection and body IDs | Atomic result publication |
| [Extrema](../../CADTopology/GeometricExtrema/DESIGN.md) | depends on | distance enclosures and support witnesses | Supplies actual minima | Classification is a separate body topology contract |
| [Moments](../../CADTopology/VolumeMoments/DESIGN.md) | depends on | V/X/Y/Z/XX/YY/ZZ/XY/XZ/YZ intervals | Supplies integrated material moments | Unit powers and density apply after integration |

## Architecture
```text
Document selection/body -> topology extrema/moments
    -> containment or density/unit/placement -> typed public measurement
```

## Contracts and Invariants

An authored measurement direction is nonzero exactly when at least one of its
finite original components is nonzero. A rounded Euclidean norm is not its
validation authority: subnormal directions may underflow that norm and large
finite directions may overflow it. Angle evaluation uses a positive component
scale and outward normalized dot/cross bounds before proving its requested
angular error; that gauge does not replace the authored direction in the result.
Surface angle directions consume the prepared complete unit-normal field, including
source-bound analytic and arbitrary-order native pole factors. A raw zero cross
product at a collapsed boundary is not a normal authority. Native join side fields
must all fit the same requested angular enclosure; an ambiguous cone nappe or
incompatible one-sided normals fails explicitly.
An explicitly selected surface station needs original position and a proved normal
field, rather than a complete curvature frame. Surface angle evaluation therefore
does not request a regular metric or principal curvatures at a valid collapsed
boundary solely to measure its normal direction.
`MassPropertyQuery` carries original body occurrences, integration options and an SI inertia reference. It validates finite placements, explicit density and the original request ceilings before dispatch. Its public query route uses the document's declared geometry unit. Native request/result codecs retain every field, validate shape and numeric coherence, and reject unexpected keys. Result validation checks three-dimensional tensor/enclosure shape, positive mass, finite centroid inside its published bounds, symmetric overlapping tensor entries, ordered principal enclosures, and the published frame/residual bounds against the actual retained axes and tensor. These checks do not replace the original integral producer's proof.

All public closest-pair entry points use the same body-material distance semantics. Finite contact comes from the complete original face-pair intersection and UV trim graph. A contact alone establishes boundary contact; intersecting material requires an actual point classified inside both solid operands. Contact coordinates are reevaluated on both original supports rather than manufacturing identical approximate witness points. Density is finite nonnegative. A request-supplied component density is explicit measurement authority. Otherwise only the ProductAttributeResolver effective density assignment supplies density; an appearance material or an unassigned descriptor never fills a missing density. Model length to metres scales volume/first/second moments by powers 3/4/5. Rigid placement rotates moments and translates using the full parallel-axis identity. Explicit affine placement applies the complete linear map and its certified absolute determinant to material moments; singular maps fail because volumetric mass would lose its domain. Translation remains in model units and is rounded through the same SI interval conversion. The result publishes canonical SI unit identifiers for mass, length, first moments and inertia, plus the original model length unit and requested raw integration accuracy. Every numeric error is an enclosure propagated through density, signed nonsingular placement and unit powers. The inertia tensor remains symmetric. Jacobi iteration supplies a candidate frame only. Original interval tensor reconstruction residual and frame Gram defect bound the eigenvalue error through a polar-frame perturbation bound. Publication includes the measured frame orthogonality error and each original tensor eigenvector residual; repeated eigenvalues do not manufacture a unique principal direction.

## Verification and Change Impact
Independent global minima, touching/overlap/containment and volume/centroid/inertia/density/placement fixtures exercise the production caller after source completion.

Containment additionally excludes an opposite boundary component inside the proposed container subject: an enclosed cavity boundary can invalidate containment even when every subject boundary vertex lies inside the other material. A zero body witness must be admitted by both original material classifiers.

Selection distance overview publishes the document length unit. The scalar `SelectionDistanceMeasurement` publishes its certified minimum interval, midpoint estimate, original absolute/relative request and consumed work when created by the public evaluator. Its vector remains the retained closest-witness vector. Legacy directly constructed point-pair records explicitly have no certified minimum interval or inferred length unit.

Native distance codecs accept historical point-pair payloads with absent certification fields as explicitly uncertified records. Stored vector and scalar distance must agree with the point pair and, when present, the certified interval midpoint. Codecs reject incoherent derived values rather than admitting a fabricated minimum. Embedded keeps the identical value and concurrency contract without native Codable transport.

Distance composition binds one original request allowance before resolving the selections. Boundary proof, complete contact traversal and solid classification share its work and depth ceilings; publication reports the complete invocation consumption. Lower callbacks run outside the allowance's short Mutex critical section. No classification stage resets the caller allowance.

The mass overload without an explicit original length unit reads the document's declared length unit. The explicit-unit overload binds the caller's original BRep coordinate unit, permitting a producer whose internal geometry has already been converted to metres. Effective density resolution receives only the remaining invocation work allowance and its reported consumption is deducted before any body integration. Attribute hierarchy depth retains its independent source-owner ceiling; it is not an integration subdivision depth. Density-target scans debit the same remaining allowance.

A finite set of offset contact candidates can locate a material-interior witness, but its exhaustion cannot distinguish boundary-only contact from a narrow overlapping material sector. The body relationship caller preserves an explicit classification failure until the original complete local material-side proof is available; it must not publish boundary contact from absent samples.

Affine volume scale uses Geometry's original exact rational determinant enclosure. Near cancellation cannot be judged by a naive rounded six-term determinant. Every requested exact coefficient work/storage visit consumes the remaining composition allowance before it runs; exact singularity and nonrepresentable finite enclosure failures propagate.

Identical solid selection searches the retained original spatial bounds for a common material interior point. Stored topology vertices and rounded lifted boundary coordinates cannot substitute for that point. The immutable identical solid establishes material identity; both retained sessions must classify the published candidate as inside.

Mass body integration passes the retained exact `ValidatedBRepModel` directly to the moment provider when present. It uses that receipt’s model as source authority and requires the configured tolerance to match. Manually constructed evaluated documents without a receipt use the explicit original validation path; validation traversal must share the caller allowance before their complete budget can be certified.

Original solid relationship classification passes the retained immutable exact model receipt directly to the injected session producer. The source model and tolerance come from that receipt; a foreign tolerance or modeling-only receipt is refused. Each operand’s prepared session is retained once and all actual classification visits consume the outer distance ledger.

### Original Selection Angle Authority

Solid boundary-component relationship probes include closed loop-free faces.
They select a finite original support parameter from the retained face extent,
then admit the complete singleton position enclosure within the same physical
localization allowance as edge endpoints. Such a probe only locates a material
classification candidate; an empty edge list cannot prove absence or separation.
Zero material distance still requires the identical candidate to be inside both
retained original body sessions.
Relationship edge stations use the original raw-ID edge query provider under
that complete model admission. Native endpoint projection is owned by that
provider; the caller does not replay the legacy numeric projection allowance.

The additive bounded angle entry receives independent subdivision, source and
algebra ceilings and borrows the caller's work and optional byte admission. It
resolves original finite curve/edge selectors before preparing their station
position and all owning derivative sides. Explicit surface stations use the
original complete unit-normal field, including source-bound pole factors.
Representative face projection and exact trim-knot clocks remain lower producer
dependencies; this entry never replaces them with a UV midpoint or display data.
At a direct original polyline station the original Euclidean-clock issuer's
first retained owner supplies its declared preceding-segment tangent. Native
spline knot selections retain both owning sides. Outward wrapper localization
alone cannot select a unique polyline side through a parameter transport.
Fixed angle arithmetic uses value fields and visits the caller before each
composed scalar action. No separate allowance or target-dependent state exists.

The selection angle route retains the existing representative station rules and tangent-before-normal precedence. Original curve derivatives, lifted trim derivatives and surface partial cross products supply complete direction intervals. A native knot includes both owning sides; a discontinuous or singular direction cannot become a sampled unique tangent. Polyline output retains its authored segment law. The public result stores radians, original direction intervals and the requested modeling tolerance. Outward dot, norm, cosine and cross-product angle ranges jointly bound the angle; intersecting a cosine enclosure with its mathematical [-1,1] domain is lawful, whereas clamping a rounded dot is not a certificate. A finite error larger than the unchanged absolute-angle plus relative-angle goal fails. Native codecs reject inconsistent derived fields and Embedded retains identical Sendable storage without Codable transport. Original selection-resolution/projection preparation must also join the query ledger before complete work accounting is claimed.

Original boundary-distance preparation consumes the evaluated document's exact retained BRep receipt directly when present. That receipt supplies both the model and tolerance to Topology; borrowed original loop predicates retain the shared query visit/depth allowance. Modeling-only or foreign-tolerance receipts fail explicitly. The raw-model compatibility path remains separately incomplete for bounded manual-source admission.

Solid relationship samples use complete original curve endpoint position enclosures at the directed native trim stations. Stored topology vertices may have tolerated junction drift and never substitute for those boundary positions. Each representative is admitted by its entire original position enclosure within the mesh-independent distance/16 localization goal; strict containment additionally relies on the complete boundary-separation lower bound, which exceeds that localization uncertainty. This fixes false containment from a stored vertex moved across a nearby foreign boundary.

Angle arithmetic rescales each finite original direction box by one positive exact stored scale before norm/dot/cross operations. Directed angle is invariant under these positive gauges. Endpoint interval division rounds outward directly, avoiding an overflowing reciprocal or squared norm. Cross-direction fields likewise use independently positive source gauges; they certify the direction without claiming the original area or derivative magnitude. Singular fields still require a strict positive complete norm lower bound.

Solid distance overview retains one exact source receipt for its entire invocation. Manual evaluated models enter bounded exact validation under the same request work and byte owner; the resulting receipt is reused by extrema, both classification sessions, and the original finite face-pair graph. Caller-selected cumulative byte ceilings remain independent of work/depth policies, and missing lower allocation ports remain explicit completion dependencies.

The immutable original classification-pair producer owns both body sessions and
the exact model receipt. Its finite face-pair graph retains that same owner.
Transverse whole-trim/normal proof proposes an adaptive inward point; publication
of a zero material minimum requires both retained sessions to classify that
identical point as inside. A positive overlap proof without a spatial witness
cannot substitute for the closest-pair result. Inconclusive tangent, coincident
or straddling cells retain the existing failure contract and completion markers.
Containment and identical-solid zero witnesses obey that same spatial membership
contract. A numeric boundary-box midpoint with tolerance-near boundary status
cannot substitute for a common interior point, even when source identity proves
the scalar material minimum is zero. Their shared classification-pair producer
searches the intersection of retained original spatial bounds under the same
work, subdivision and optional byte admission. Only both-inside candidates
publish a zero closest pair; exhausted candidates prove no absence. Classifier
allocation and combined search/source-depth admission remain lower dependencies.

Identical BodyID operands publish their actual common-interior witness immediately
after retained pair preparation, before relationship endpoint localization or
finite face-pair enumeration. Their complete boundary-separation result remains
available independently. Removing those irrelevant phases preserves the same
original source receipt, work owner and both-inside publication condition.

Distance request validation precedes selection preparation and budget consumption.
Invalid caller work/depth/byte options retain their typed input failure rather
than being mistaken for exhausted valid proof work.

Original curve distance selection consumes Kernel's immutable original geometry
query receipt before resolving native spans. Its directed finite parameters and
retained curve supply the extrema domain without replaying display-point
projection validation or materializing transformed spline nets. Current feature
identity, original source, knot scans and optional bytes share the existing
query ledger; source16 and algebra32 remain independent of caller subdivision.
Surface and point selection preparation still require their corresponding
original provider connections before whole selection accounting is complete.

Solid pair preparation forwards optional byte admission to the additive original
classifier requirement, along with independent source16/algebra32 and caller
subdivision. Nil remains absent through finite-face/bounds/normal preparation.
Selected-byte CS and projection scratch still require their concrete lower ports;
this connection alone does not certify the complete allocation envelope.

Surface knot/span distance selections resolve the immutable original support and
stable current face once, then inspect native parameters with the same request.
Parameter-preserving source wrappers retain the native knots; no transformed
construction net or uncharged stable-reference fallback becomes authority.

Whole stable subshape, edge and surface distance operands use the non-generic
original topology requirement with the same request work/bytes. Direct identity,
lineage and stored-signature candidates preserve the original equality contract;
a legacy uncharged topology resolution is not a bounded selection receipt.

Curve parameter and knot selections retain singleton original curve domains.
The extrema engine bounds the original station position and publishes its native
parameter witness; a rounded evaluated point is not promoted to exact point
support. Finite authored selection-domain membership remains mandatory. Legal
position-only stations do not acquire an unrelated tangent/curvature requirement.

Selected whole-trim distance operands consume the immutable original coedge
receipt, retaining its support and pcurve under the existing query admission.
Native trim-span selection resolves the original knot endpoints first. Its
normalized construction chart retains the raw lifted source, original zero/one
labels and exact rational first/last fractions. The extrema operand uses this
chart's normalized domain without rounding either native ratio. Source16,
selected subdivision and independent algebra32 plus optional BYTE admission
reach the retained original preparation. Scalar normalization, including a
single trim knot, still requires exact representability until its separate
constant-station carrier exists. Neither path promotes a rounded quotient to
original source authority; generic owning-cover/localization dependencies remain.

Explicit surface parameter distance selections retain the original surface and
stored U/V station after current-reference resolution and native domain checks.
Their singleton support domain does not acquire face-trim restriction or a
normal/curvature requirement. Trim-knot selections likewise retain original
pcurve knot stations and lift support; exact scalar normalization follows the
same original native-chart proof used by trim spans.

Prepared original curve and surface distance sources retain the independently
selected algebra32 policy through nested lift and source-wrapper preparation.
Polyline source clock admission cannot be replaced by an absent optional algebra
policy or by the caller's spatial subdivision depth.

Direct point-pair measurement without a certified minimum interval evaluates its original vector norm with scaled C `hypot` composition. Intermediate squared underflow/overflow does not change a finite representable length to zero or infinity. This legacy direct value carries no integration or optimality accuracy receipt; certified minima retain their published interval authority.

Public selection distance and overview overloads accept composing work-depth and
optional typed-BYTE callbacks before original selection resolution. They attach
to the one request-bound Topology distance budget and cover selection providers,
manual model admission, boundary extrema and material classification. Existing
overloads delegate with absent external admission. A drawing/page owner can
therefore retain its own invocation ledger without snapshot/copy-back accounting
or using topology display summaries as exact geometry. Each local reservation
precedes the external callback, which runs outside the budget Mutex; a callback
failure aborts publication and remains consumed. Optional storage stays nil when
no local or composing owner selects it. Existing lower producer limitations
remain explicit and this bridge does not certify a whole physical heap ceiling.

Body relationship preparation retains paid original edge/face ID arrays and
in-place ordering/deduplication under the distance ledger. Original boundary
point appends request typed storage before growth. Opposite-body classification
retains fixed inside/all-inside summary fields, preserving every classification
visit while avoiding derived classification/index arrays. This preparation does
not replace the complete containment/intersection authority.

Boundary station localization restores the original magnitude of the shared
Topology scaled norm before comparing to its unchanged physical localization
allowance. A raw squared coordinate sum is not the error authority for tiny or
large finite source positions. Mesh station-discrepancy admission consumes the
same primitive with its separate mesh allocation.

## Canonical Caller Binding
Selection distance uses one OriginalQueryExecution created by the ordinary
Topology distance entry, or borrowed by the direct entry. The unchanged option
ceilings attach as a contribution before selection resolution. Native trim
ratios, original differential bounds, boundary extrema and material classifiers
receive that same execution. Removed callback/budget adapters are not retained.
The existing unsupported selectors and classification conditions remain; this
binding does not add a measurement family or certify unimplemented coverage.


### Canonical Angle Caller Binding

The angle API borrows one `OriginalQueryExecution`; its ordinary entry creates one root and delegates. Explicit bounded ceilings restrict that execution through its existing contribution mechanism. OriginalSelectionAngleBounds consumes that same execution at the original arithmetic operations. Prepared curve/surface jets, unit-normal fields, image-chart bounds, face extents and source lookup receive the same exclusive execution instead of removed OriginalSourceProofAdmission or callbacks.

The ordinary selector path remains separate from the bounded resolver: whole curves retain their original Euclidean-clock midpoint, including the existing unbounded-output selector, whole faces retain centroid projection with the existing parameter fallback, and trim/span/knot selectors retain their original station formulas. Existing bounded unsupported branches remain explicit. Angle preparation does not use representative samples as original direction proof. Ordinary query-helper direct overloads preserve existing validation, source identity and projection algorithms, including display-only selector proposals and existing numeric fallback semantics; they forward actual source proof through the retained lower owner.

The extracted candidate must compile and verify its own angle call chain. Existing worktree receipts are not proof of this integration. Distance prefix and other measurement algorithms are owned separately and unchanged by this angle binding.


| Extracted angle source | Forced concrete call edge |
|---|---|
| `../SelectionMeasurementEvaluator.swift` angle suffix only | Ordinary station selectors -> direct query helpers -> prepared owning curve/surface jets/unit normals; bounded resolver retains explicit unsupported cases |
| `OriginalBoundedSelectionAngleResolver.swift` | OriginalGeometryQuery lookup, PreparedCurve/SurfaceDifferentialEncloser, FaceParameterExtentResolver and image bounds -> same execution |
| `OriginalSelectionAngleBounds.swift` | Original interval dot/cross/acos/atan2 math -> direct canonical work admission; ordinary one-root wrappers |
| `../SelectionAngleMeasurement.swift` | representative/measure/coherence validation -> same execution |
| `../CurveQueryEvaluator.swift` | resolve/midpoint/point/span/knot and required polyline/B-spline helpers -> EvaluatedCurve validation and original Geometry direct calls |
| `../EdgeQueryEvaluator.swift` | resolve/midpoint/frame + edgeParameterRange -> original topology/source validation and Curve differential direct calls |
| `../SurfaceQueryEvaluator.swift` | resolve/frame/closestPoint/span/knot/trimCurve and their existing projection/trim helpers -> direct original source/projection calls |

The general legacy point-selector helper closure used by distance fallback is not converted by this angle scope. No direct general point(for:in:using:) is introduced. Lower query methods retain their previous branches, station formulas, trim approximation selectors and supported inputs; no new geometry case or success branch is imported.

The Mass native API binding uses the original volume-moment execution factory
and one selected maximumWork/depth contribution across attributes, moments and
affine determinant proof. Remaining work is a view of that contribution, not a
resettable counter. Existing tensor composition, Jacobi iterations and outward
formula order are preserved; this does not add a Mass algorithm or performance
change. Transport validation forwards the same execution at each public/codec
entry and retains its original failure conditions.
