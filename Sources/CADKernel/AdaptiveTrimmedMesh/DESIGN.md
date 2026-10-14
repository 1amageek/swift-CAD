# Adaptive Trimmed Mesh

## Purpose and Scope
Child of [CADKernel](../DESIGN.md). Owns retained triangle-interior refinement for general trimmed parametric faces and coherent face-local fidelity selection.

## Responsibilities and Boundaries
MeshTessellator composes the source face and retains preflight plans. Geometry owns original closed-box derivative certificates. CADIR owns geometric options and storage limits. Exact topology and pcurves remain unchanged.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Kernel](../DESIGN.md) | parent | checked invocation admission/publication | Publishes FaceRun and original geometry | All preflight plans precede output allocation |
| [Geometry](../../CADGeometry/DESIGN.md) | depends on | original whole-cell derivative bounds | Bounds facet interiors | One 262144/depth32 allowance is shared |
| [IR](../../CADIR/DESIGN.md) | depends on | faceOverrides and caller limits | Preserves local settings | Shared boundaries use the strictest incident options |

## Architecture
```text
Original trim -> boundary triangulation -> complete triangle bound
    -> shared midpoint refinement -> retained parameter/index plan
    -> invocation storage admission -> original positions/normals/publication
```

## Contracts and Invariants
- Normalized original construction-chart curves use the common original
  edge-cell sampler and relative normalized trim resolution. Classification
  metadata does not replace their retained chart with a fitted spline.

Pole preparation retains the complete ordered stack of original chart images and
flat spatial-word images. Chart images map exact native UV boxes; spatial words
leave UV unchanged. Canonical collapsed positions are issued for the complete
stack, while original pole-normal receipts move outward through each exact
cofactor action in reverse source order. Each stack descendant and exact word
normal operation consumes the same tessellation proof owner. Factor count is
independent of source nesting depth.
Pure spatial-word images of native B-spline trims retain the original UV partition
and owning-span tokens. Each selected original seven-field panel is transported
through invocation-prepared exact quantitative word actions before facet refinement.
Corner normal fields are issued on the transformed support for the selected owner;
raw source normals cannot be published unchanged. Exactly identity-UV binary affine images join the same ordered quantitative
transport stack as flat spatial words. They preserve the source owning partition
and do not count as a relocated knot chart. Their full original support remains
the position and unit-normal authority at publication. A chart image that relocates
native knots still requires its separate retained foreign-knot partition receipt.
Trim boundary preparation retains each original UV station together with its
canonical shared edge point. Periodic charts use the original bounded loop
unwrapper before station evaluation; nearest-period shifts of sampled coordinates
do not authorize the chart. Facet publication retains these boundary points and
the exact positions used by its final whole-triangle fidelity proof.
The final trim proof combines original D2 interpolation bounds with the complete
corner displacement from those retained physical positions. It compares each
actual triangle plane against the original complete normal field and checks all
three physical edge lengths. Native children keep their original one-sided owner;
parent differential bounds may be reused only on contained child triangles.
Refinement shares the unchanged work, depth and record ceilings. Emission uses
only the positions and normal directions retained by this proof. Triangle normals
must also stay in the source-oriented hemisphere, independently of a coarse
requested angular tolerance.
Certified grid and trim emission retain every prepared source normal. They never
invoke the flat-normal replacement helper. Their already admitted source-oriented
triangle plane determines the native index order; exact face/shell orientation
selects its reversal. The original mesh area/adoption gate still refuses invalid
triangles before indices are retained, without sampled normal votes changing the
source winding or adding unplanned duplicate corners.
Every retained triangle passes position, angular and all-edge bounds. A conforming refinement wave shares midpoints by original indexed edge; no hanging vertex is introduced inside a face. Curvilinear boundary fidelity remains the original complete-interval sampling owner. Every active face preflight shares one invocation-owned `TessellationProofBudget`, with the same Mutex state on Native/WASM/Embedded. Closed original station inverse receipts bind the directed curve trim and original pcurve; normalized fractions must progress in one connected directed order. A singular homogeneous pole uses its structural direct chart law. Original tensor pole normals are prepared before output admission, using the exact clamped coefficient row/column and the one-sided original normal-coefficient receipt. Emission consumes retained normals; it never selects a nearby regular parameter as a pole normal. Higher-order vanishing normal coefficients and whole-facet factored normal bounds remain Geometry-owned required ports. One invocation retains each edge's forward spatial station buffer once, under the strict incident-edge policy. Every directed use consumes that retained canonical buffer; reverse uses reverse the stored coordinates rather than reevaluating opposite floating-point parameter arithmetic. Line and circular stations also honor the caller maximum edge length under the original 65536-segment ceiling. Face overrides are resolved before preparation, unknown face IDs fail, and interior refinement retains that face's own requested geometric setting. Canonical spatial edge sampling joins only the linear tolerance, angular tolerance and maximum edge length of that edge's incident faces. Rectangular/native graph plans still require propagation of canonical edge station partitions; their independent interior counts do not establish shared-edge conformity.

## Failure, Concurrency, and Constraints
Original source, finite arithmetic, shared proof/work/depth and storage bounds retain explicit failures and cancellation. A partial mesh map is never published.

## Verification and Change Impact
Public trimmed nonconvex/hole/C0/periodic/pole fixtures must measure whole-triangle fidelity, boundary identity, face settings and cumulative resource refusal after the implementation batch completes.

For a face with an original singular boundary, half of its requested angular allowance bounds facet normal variation and the other half admits the retained pole-normal receipt. Pole preparation lowers the original Geometry angular tolerance when necessary; it never widens a tolerance. A receipt exceeding its reserved allowance fails before mesh output admission.

Nested original surface images retain every exact chart gain, swap and affine map. Pole stations map to complete native parameter boxes, including non-singleton tangential intervals. One original native owning panel supplies the whole normal-coefficient cone, and each image layer transports that cone with its exact cofactor and chart parity. The retained foreign receipt must contain the requested station before its normal is emitted. A rounded native midpoint is never used as the station authority.

Generic procedural and original tensor grids use the same outward station-gap and complete facet bounds. The two-axis path bounds every diagonal edge as well as grid sides. Each examined representable axis station debits the invocation allowance before evaluating it; an independent procedural count path cannot omit diagonal length or rounded station spacing.

Canonical stations evaluate the original spatial curve at its retained directed native parameters, including lines and exact collapsed boundaries. Stored topology vertices establish incidence and finite trim projection for unbounded untrimmed edges; their tolerated positional drift cannot replace the original curve position. Every station retains its original parameter, and reverse uses retain the same spatial buffer.

Analytic rectangular charts use the same complete seven-field facet policy as original parametric charts. Axis-only circular counts cannot authorize a diagonal maximum edge length or a facet normal-turn bound; the original support differential proof and invocation ledger authorize the complete grid.

Analytic sphere/cone pole stations retain the complete original normal field through the same generic panel receipt and nested image cofactor transport. A cone apex selects a nappe from the retained face plan whose complete facet boxes already satisfy the one-sided chart contract; a plan using both nappes cannot authorize one shared apex normal. This selection is a source chart decision, without a nearby normal sample.

The exact pole-factor adapter admits original rational algebra through the same invocation proof budget. Exact cell depth is the intrinsic ordered-field/root depth, capped at 32 independently of original source nesting and facet subdivision. Its visit debits work at the current proof owner without interpreting algebra depth as a geometric descendant. Facet and original source walkers retain their own explicit depth ceilings. Requested exact work and retained temporary storage debit the existing 262144-unit ledger before computation or retention. Original factor polynomials are retained per owning native span, boundary and direction and reused for stations. A native grid passes its owning token so C0 knot sides cannot be mixed into one normal authority.

A trimmed pole station on a native join retains every source-owning panel and normalizes their bound-checked union. That union asserts a complete normal cone at the station, not smoothness across the join. Complete trimmed triangle bounds use the original seven-field support producer for every surface family, including analytic sphere/cone frames.

An exact collapsed boundary is a quotient of the original parameter chart. Preflight retains its source boundary key and canonical spatial image at each parameter-local station. A grid cell incident to that boundary emits one regular triangle fan; the zero-area interpolant is omitted only for two stations with the same retained original collapse proof. Distinct collapse boundaries or unproved geometric degeneracy fail. Normals remain parameter-local, so cone generators never share a fabricated apex normal. Trimmed plans use the same retained collapse keys and preserve every noncollapsed triangle.

Original native trimmed triangles are clipped at every retained knot plane before facet proof. Each indexed crossing is retained once per edge and knot plane, so adjacent triangles consume the same representable intersection. Exact expansion orientation discards only parameter-zero pieces. Every nonzero triangle retains exactly one native owning span; refinement inherits that span and output retains its one-sided corner normals. A maximum over disjoint native panels does not authorize smoothness across a C0 join. Foreign nonrepresentable knot charts require the Geometry retained image-partition producer before this path can cover those image families.

A foreign pole station whose exact native tangential interval crosses a knot is covered by original owning subpanels. Each panel retains the same collapsed coordinate and its actual closed tangential intersection. Geometry's complete station receipt proves an exact gap-free cover and unions the one-sided unit normal cones; only that point receipt is transported through images. It does not aggregate a smooth normal derivative across the native join.

Original revolution poles use the retained rational generator endpoint germ and raw-axis incidence. The invocation caches one exact normal-factor preparation per original source endpoint and evaluates complete original station boxes through that germ. Native and nested image point normals use the same generic station receipt and reserved angular allowance. Analytic/transformed non-rational generator germs remain Geometry-owned required domains.

Canonical collapsed boundary positions consume Geometry’s source-bound position receipt once per original boundary and reuse its point at every tangential station. Its complete deviation is admitted within half the requested linear allowance; the remaining half belongs to facet interpolation. Tensor, cone and retained original revolution boundaries, including images, follow this law. Sphere canonical angular endpoint authority consumes Geometry’s coherent ideal analytic angular phase, shared by original position, closed jets and analytic pole panels. Fixed canonical quarter-turn roles retain one complete physical position receipt, including outward center-plus-radius arithmetic. A foreign image requires an exact singleton native role; a rounded midpoint cannot establish it. Parameter-local normal records remain distinct even when their physical coordinates coincide.

Original Coons charts consume the same original differential and whole-facet producer as other retained procedural surfaces. Their four retained boundary root spans remain Geometry source authority; mesh preparation never substitutes a fitted tensor surface.

Original tensor basis, knot multiplicity and positive-weight admission visits debit the invocation proof ledger before reading each coefficient. Pole preparation charges clamped knot roles and exact image bounds through the same ledger, rather than treating collection predicates as unaccounted phases.

### Canonical Original Curve Cells

Canonical generic edge sampling uses prepared closed original jets and their exact owning native cuts. A positive-width native owner supplies its own one-sided derivative field; zero-width neighboring endpoint owners never manufacture cross-knot smoothness. Each source cell bounds the whole second derivative for chord displacement and compares the whole original first derivative box with the actual published endpoint chord for angular fidelity. Complete original endpoint position uncertainty joins the chord-deviation bound. Native preparation, owning-cell visits, exact bounds and retained stations share the invocation proof ledger; the original 65536-segment ceiling and depth32 remain. Lines, circles and analytic arcs use this same complete source-cell proof. A theoretical segment count or rounded point evaluation alone cannot authorize a published chord. The original speed bound and the actual retained chord length both satisfy the maximum edge limit; endpoint uncertainty is not omitted from either publication decision. Degenerate or uncertifiable tangents require subdivision or typed failure, never a sampled derivative fallback.

### Original Face Boundary Station Requests

Before final face admission, each retained rectangular/native grid contributes its original iso boundary stations to the invocation's canonical edge buffer. The reverse original correspondence supplies a native edge interval and uniqueness receipt, then complete original closed source-position boxes independently bound the physical discrepancy at the requested grid UV station. This bound consumes the original shared linear allocation; a rounded normalized-fraction proposal alone never establishes incidence. Existing canonical samples and admitted native requests become forced original cuts for the same curve-cell proof, and affected incident face preparations are regenerated before preflight publication. General retained UV inverse charts, critical branch atlases, graph-native and nonuniform tensor boundary publication remain required domains until their source producers and consumers are connected.

Trimmed plans also contribute their retained UV vertices to the same boundary
request pass. Exact iso sides accept only points on their original fixed
coordinate and directed extent. The reverse original correspondence and complete
position boxes then admit a native shared station. Newly refined trim boundary
midpoints therefore join the canonical edge buffer before any incident face is
published; changed edges rebuild every incident face under the same invocation
ledger. General curved trim inverse charts remain a separate required producer.
Full directed spatial-word pcurves are transparent only after exact target/source
support binding; UV and original directed endpoint roles remain unchanged.
Identity-UV original image pcurves use the same exact source-bound axis endpoint
receipt for grid station collection. Both full forward and reverse fraction roles
retain their directed UV extent; neither inverse-gain rounding nor affine
endpoint multiply-add authorizes station ownership.
Axis-side recognition also consumes authored affine sides with an exactly zero
fixed derivative, and original polylines with one exact fixed coordinate and
strictly directed control stations. Their UV station proposals still require the
same original lifted-curve inverse and independent source position discrepancy
proof before a physical shared point is admitted. A proposal is never original
native knot, root, or station authority.
Canonical station installation uses that same unchanged-UV word recognition.
An original word curve/lift and matching word-hosted pcurve retain direct native
station identity only when every operation word, support and full fraction role
matches; reversal is applied to the directed use before checking the binding.
Structural source comparisons admit every retained payload through Geometry's
original structural-comparison work port before equality is evaluated. Shared
source identity does not exempt arbitrary public words or curves from the
invocation's original work ceiling.

### Boundary Discrepancy Composition

For rectangular source plans the requested linear allowance is partitioned before
preparation: one half authorizes complete original facet interpolation, one quarter
bounds the shared original curve chord, and one sixteenth admits each direction of
original curve/pcurve station transfer. These are mesh displacement bounds, not a
change to the existing eight-distance BRep junction validity rule. Canonical endpoint
uncertainty is included by the curve-cell proof. Publishing a boundary corner requires
an independent complete source position box to lie within the station allocation of
the retained shared point. The actual published triangle normal must separately pass
its original angular bound: linear discrepancy alone does not authorize normal fidelity.
Nonuniform tensor axes retain all original shared-edge requests. Opposite boundaries
and native owning-panel interfaces consume their joined axes; request propagation
continues to a fixed point under the same invocation work/storage ceilings. The entire
source remains immutable and no partial mesh is returned on failure.

One invocation also retains a deterministic vertex buffer keyed by the original
VertexID. Every incident original edge endpoint consumes that same spatial value.
Changed endpoint coordinates are forced into the original curve-cell proof; its complete
endpoint deviation and actual chord angle must pass the allocated edge policy before
station transfer or publication. Topology's tolerated stored vertex is not substituted
as geometry authority. Re-tessellation preserves all forced shared coordinates.

Final rectangular preflight retains every emitted position. Regular C1 point normals
consume the prepared original unit-normal box and admit its complete cone against the
stored unit-vector representative before emission. Poles consume the existing factored
receipt; native C0 grids retain their selected owning-side normal law. The emission
path consumes these retained records and never evaluates an off-boundary normal to
repair a missing pole receipt.
All nonplanar faces must publish either their retained grid, native owning-grid,
graph or complete trimmed-facet plan. Emission does not reconstruct a fresh trim
polygon or revalidate an immutable support outside the invocation owner. The
unreferenced private trim reconstruction and sampling helpers are removed after
reference and retained-source verification. Production routes and mesh
capabilities are unchanged. Geometric rectangular recognition precedes
the specialized U-graph route, so native axis-side pcurves retain the same rectangle
policy as their equivalent constant-coordinate representation.

Exact singular edge incidence unifies the mesh vertex buffer for its endpoint IDs
without rewriting source topology. A collapsed face boundary consumes that buffer only
when its retained original native boundary key matches the singular coedge's source
chart role. The complete collapsed-boundary position receipt must enclose the selected
shared point within the station displacement allocation. Coincidence by distance alone
never establishes that boundary identity.

Canonical native station normalization requires a finite nonzero directed parameter span and exact containment of each retained native station. Parameter units do not borrow a fixed machine-ulp length threshold: a legal tiny UV interval can describe a large physical edge under the original support derivative law. Authored endpoints publish normalized fractions exactly zero/one; interior candidates retain their original native parameter and all physical bounds.

Original edge classification in canonical station, singular incidence, pole preparation and UV station paths forwards the same tessellation visit/depth owner into the Topology classifier. Callback arguments represent original proof depth rather than work counts. Compatibility helpers without an invocation owner retain their explicit legacy status; they do not issue complete-budget authority.

The raw-model public tessellation entry creates its original proof owner before bounded modeling validation and passes that same owner into retained preflight and emission preparation. Validation and mesh preparation never reset the invocation cell allowance. Validated-model callers derive the source from their immutable receipt and create one preparation owner. Lower incomplete source families continue to propagate their explicit failures.

Raw-model bounded validation also forwards original retained-byte requests into
the same proof owner before allocation. Checked ceiling division by the actual
UInt32 word stride converts those byte requests to the existing retained-word
admission unit; no separate storage allowance is created. This byte callback
is forwarded through GeometryStore and original pcurve/source validators.

Native Taylor byte admission through the exact mesh adapter uses the actual primitive storage word of Geometry's ExactNaturalMagnitude: UInt32. The adapter exposes MemoryLayout<UInt32>.stride and converts lower byte requests upward into that many retained-word units before charging the unchanged ledger. This is an admission unit, not a claim that every higher-level polynomial object has that stride; their existing retained-item and original limb charges remain separate. It never reinterprets retained word counts as proof depth.

Exact singular edge samples retain one point chosen from a complete original position enclosure over their directed trim. Structural collapse proves constancy; the complete position-box discrepancy against that published point must independently fit the edge linear allocation. Rounded evaluation at one endpoint cannot bypass the displacement proof. Scaled original magnitude bounds avoid intermediate square overflow without changing any linear or angular allowance.

Canonical transported-sphere poles retain exact intrinsic latitude authority
while longitude may use authored physical radians. Pole XYZ uses Geometry's
original collapsed-boundary issuer; the normal comes from the complete final
support's prepared harmonic/cofactor field at the retained station. Source image
layers remain in that query. A periodic native chart is not inferred from the
physical longitude, and a midpoint raw cross product cannot authorize the pole
normal. Its complete direction cone must meet the existing angular allocation.

Pole preparation derives native chart boxes from the already admitted complete
world-surface BRep source. Each retained original image maps the box through its
exact gain/offset/axis receipt using the same tessellation work and UInt32-slot
BYTE admission. It does not recursively revalidate raw local source geometry
under a stricter world-space pole-angle tolerance. Whole-source admission and
normal factor/transport receipts remain independent requirements. The raw-model
mesh entry explicitly supplies the unchanged independent algebra cap 32.

Original station-position discrepancy uses Topology's shared outward scaled
coordinate-gap norm. Scaling prevents intermediate squared overflow/underflow
without normalizing away the physical length error; the unchanged mesh linear
allocation is checked after restoring the original magnitude.

### Native Partition Orientation
Native trim partitioning asks the existing exact RobustPredicates orientation contract with determinant tolerance zero. Work and exact coefficient bytes consume the same invocation TessellationProofBudget before triangle retention; a limit failure propagates atomically. It does not import or duplicate the Geometry-owned expansion engine. Checked interval-to-coordinate adapters retain both outward endpoints. Verification distinguishes exact nonzero tiny/overflow-prone determinants from zero and exercises independent work/storage refusal.

Focused prerequisite contract tests: [KernelIntersectionPrerequisiteTests](../../../Tests/CADKernelTests/KernelIntersectionPrerequisiteTests.swift).
