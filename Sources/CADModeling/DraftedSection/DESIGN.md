# Drafted Section

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. Owns the original
oblique extrusion ruling and its certified section curves.

## Responsibilities and Boundaries

The section plane, extrusion vector and pull direction are independent inputs.
The source retains the original curve and evaluates the ruling through its native
derivative port. Conversion fits that law and proves position, tangent and
curvature bounds over every retained trim. Topology, corner clipping and source
persistence belong to their existing feature owners.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Original Plane Derivatives](../../CADGeometry/OriginalCoons/PlaneDerivatives/DESIGN.md) | depends on | Original supporting plane equation | Section planarity uses the same chart support | Authored U retains its exact cofactor; nil-U retains its existing normal law |
| [CADModeling](../DESIGN.md) | parent | Extrusion evaluation | Publishes admitted wall sheets | Publication requires topology admission |
| [OriginalDraftedSection](../../CADGeometry/OriginalDraftedSection/DESIGN.md) | depends on | Persistent original quadratic curve and ruled wall | Supplies final source geometry | Candidate sections cannot replace the original law |
| [GeometryConversion](../../CADGeometry/GeometryConversion/DESIGN.md) | depends on | Native derivative jet and certified conversion | Proves the original ruling law | Conversion failure remains explicit |
| [OriginalAffineOperationWord](../../CADGeometry/OriginalAffineOperationWord/DESIGN.md) | depends on | Exact normalized frame conjugation | Retains original cap translation | Original projected cap pcurves remain a separate publication requirement |

## Architecture

```text
original boundary + section normal + extrusion axis + pull direction + angle
    -> native tangent jet -> oriented quadratic ruling
        -> section curves on one shared cubic basis
            -> whole-range conversion certificate -> wall construction
```

## Contracts and Invariants

Drafted face sections consume retained original directed edge charts directly.
The face Profile facade supplies metadata, not the original curve law. Each
construction span's raw persistent normalized chart is prepared under the same
extrusion admission before both height sections are converted. Original source
line incidence may select the straight-joint construction; fitted control nets
alone cannot select it. Final wall publication retains the persistent original quadratic ruling. Curved
sharp-joint intersections remain a separate finite-trim publication premise.
Closed drafted curve sections retain the same raw span carrier through the
region facade. Their original whole line integral selects material orientation;
half-domain splitting retains the original native trim rather than publishing
rounded trimmed controls as a new source. Non-thin draft consumes these raw
charts directly at both heights. The facade's display points and spline images
serve compatibility metadata only. Thin material offsets still require their
separate retained original offset-boundary/joint producer.

`PlanarOffsetCurveSource` owns the unchanged original law `C + shift (T cross N)`.
N is the normalized original supplied plane normal. The source encloses that
normalization from the raw components with outward arithmetic; the candidate's
rounded unit vector is not substituted as its original normal authority.
Raw direction normalization first divides by its largest finite nonzero
component; model distance does not impose a direction magnitude threshold.
This preserves the same original normal law for very small or large authored
plane-normal scales while its candidate unit vector remains only a fit input.
The shared offset approximator uses its native derivative certificate for every
span and requested shift, including an explicitly requested finite extension.
Endpoint extensions consume the original spatial rational endpoint-span law,
never a fitted offset or a projected continuation. The denominator and tangent
remain subject to the same outward whole-range proof. Greville interpolation generates candidates only;
sampled position or derivative maxima do not authorize an offset result.
The cubic Greville candidate uses one banded collocation factorization and
three right-hand sides. Its storage is seven scalars per row, rather than a
quadratic dense matrix whose dynamically enlarged allocation cap could exceed
the shared conversion storage allowance. The clamped endpoint rows and strict
interior Greville support are checked before factorization; nonfinite or
inconclusive pivots fail. This solver supplies candidates only; the unchanged
original-law certificate determines publication. Authored clamped endpoint
knots are copied directly into endpoint stations.
Interior candidate averages divide terms before addition to avoid overflowing
an otherwise finite average, and remain inside their original knot convex hull.
Candidate arithmetic cannot establish offset correspondence or relax its proof.
The same planar offset-law source accepts an original `Curve3D` for bounded
analytic and image curves. It prepares original closed native jets directly;
no analytic-to-rational candidate becomes the input offset law. The shared
approximator publishes `basis(for: Curve3D, normal: reach: over:)` and
`offset(_: Curve3D, normal: shift: knots:)` for these raw laws. It prepares
each requested shift once, proposes Greville coefficients on the authored
native trim, and applies the same whole position/tangent/curvature certifier
to every final candidate interval. Endpoint values and refined knots only
propose candidates; no geometric family is relabeled as a native spline
before the offset law is evaluated. The unchanged native B-spline overload
retains its original endpoint-continuation route. Closed owning
side jets are hulled only as derivative bounds, without asserting smoothness
at source joins. Whole-query subdivision proves positive speed and preserved
offset traversal under the existing 65536 work and depth-32 refusal ceilings.
The caller-admitted source prepares original native coefficients once and
forwards complete closed jets under the minimum of these historical ceilings
and the composing admission. Fixed-field normalized tangent formulas compute
offset D0-D2 from original C0-C3; no dynamically allocated derivative algebra
or aggregate smooth-join authority is required. A preadmitted DFS buffer has
at most depth+1 live cells. Singular speed, lost traversal and unresolved native
joins still fail explicitly. Finite continuation beyond a native support needs
the owning continuation allocation port and cannot call the legacy unmetered
constructor through a bounded route.
The profile extrusion retains one caller admission for lower and upper section
offsets, including every shared-basis refinement and final candidate proof.
Native offset-joint localization remains a separate original-contact contract;
its legacy proposal cannot establish the source of a constructed offset trim.

For unit boundary tangent T, section normal N and extrusion axis A, the ruling is
`A + k (T cross N)`. Its wall normal is `T cross A - k N`.
The quadratic solves the retained wall angle to the pull direction; the inward
branch is selected for positive draft and outward for negative draft. The
angle is enclosed by the existing certified trigonometry. A zero angle produces
the wall perpendicular to the pull direction. No sampled normal authorizes a
successful conversion. Endpoint sections use identical knots and unit weights,
so interpolation in extrusion height preserves the affine original ruling law.
Raw finite nonzero normal, axis and pull inputs are normalized with outward
arithmetic in the original source. Their largest raw component scales the
norm calculation before division, avoiding magnitude overflow or underflow.
Model-space distance tolerance is not a minimum length for a direction value.
Callers retain the authored pull components rather than feeding a previously
rounded unit vector into the original proof. An explicitly supplied pull takes
the native ruling path even when its candidate direction appears parallel to
the extrusion axis.
The original general ruling receives the resolved authored angle directly.
Reconstructing it with atan of a rounded tangent cannot define the retained
source. Only an exactly zero authored angle selects zero draft; angular tolerance
does not erase a nonzero value. Legacy tangent-based normal-axis construction is
a candidate path until its final original-angle comparison is integrated.
Closed non-thin extrusion with an authored nonzero angle selects the original
ruling even on a normal axis. An explicitly supplied pull also selects it at
zero angle. The thin material-boundary offset route retains its separate original
joint and final-angle proof obligation.
Circular profile arcs keep their original circle and angular trim as draft
authority. Reversed arcs use the original signed parameter image. A rational
construction image is not the original input to a curved draft certificate.
Open general curve sheets likewise consume their original native law directly
for both endpoint sections. A previously composed or fitted construction spline
cannot become the input draft law. The existing exact straight/circular normal
axis route remains separate; all other source families use the shared-basis
original ruling converter even when the pull defaults to the axis.
Caller-admitted draft sources retain one prepared original curve and fixed-field
closed D0-D3 jets. Normalization and the quadratic ruling use scalar value/first/
second fields, without temporary derivative arrays. Each owning native side is
evaluated separately; unresolved speed or quadratic clearance subdivides under
the existing request depth and work allowance. Lower and upper heights and all
shared-basis attempts retain the same feature admission. Singleton midpoint
values only generate interpolation candidates; complete original distance,
tangent and curvature certification admits each final section.

Closed section construction consumes the same native ruling. Adjacent straight
walls meet at the exact intersection of their translated lines in each cap
plane. The two corner positions therefore define the exact intersection ruling
of those wall planes. Curved boundaries retain one certified basis at both
heights and tangent joints retain their original common ruling. A sharp joint
requiring a curved wall intersection remains an explicit incomplete failure;
neither endpoint snapping nor independently sampled sections authorize it.

`PlanarOffsetJointResolver` consumes bounded offset laws on their unchanged
section plane. It isolates all discrete intersections in the exact rational
chart and chooses the nearest retained corner only when interval distance
bounds of the retained original offset sources distinguish it from every other
root. Candidate-chart roots must also prove original spatial coincidence;
fit residuals cannot replace the original offset-law root admission. It returns parameter trims rather
than moving controls, so the existing whole-law offset certificate survives.
No intersection outside an original curve support is invented. A missing,
non-discrete or unresolved intersection fails explicitly; continuation and
curved draft tracks remain separate required construction work.

## Failure, Concurrency, and Constraints

Inputs and prepared curves are immutable and Sendable. Missing tangents,
infeasible pull direction, nonpositive quadratic clearance and conversion
exhaustion throw typed errors. Shared conversion limits remain 4096 controls,
eight candidates, 65536 certification boxes and the existing work/memory limits.
Section planarity checks cancellation after the last admission callback before
both its exact identity return and its complete closed-cover return. A callback
that cancels and returns normally cannot publish successful support admission;
these final checks do not charge additional work or storage.

## Verification and Change Impact

Behavioral verification belongs to extrusion tests and must compare wall normals
with the retained independent pull direction, including curved boundaries and
failed angle feasibility. Source-only implementation does not assert verified
behavior. Corner clipping remains owned by the complete extrusion request.

## Persistent Draft Publication

Cap supports retain the original section plane and the raw authored axis/height.
An original normalized axis placement F conjugates an identity local-Z height
translation: F inverse, original height translation, F forward. The flat original
word owns the exact normalized direction action; a rounded axis-height product
does not become a cap origin. The reference Cartesian direction is selected by
the smallest absolute raw axis component and is retained without normalization.
Cap inverse pcurves must consume this same word-plane support and the original
drafted boundary source before a capped request can be published.

Uncapped profile and face extrusion retain every original material loop through
the persistent wall builder. Each loop forms its own sheet shell; holes retain
their directed original boundary instead of becoming holes in an invented cap.
All shells share one feature admission and one generated-body contact validator.
The profile facade never supplies a replacement law for original face edges.
Each retained generator must remain within the original section-plane distance
allowance. Original homogeneous plane identities provide a complete exact fast
proof; other supported laws use closed original position bounds over a paid
depth-first cover. For an authored-U section plane, both paths consume the same
exact original support equation. The distance path encloses its cofactor with
outward intervals and uses the existing interval normalization under the same
admission. It never substitutes the stored raw N for the chart support normal.
Nil-U section planes retain their existing raw-normal fallback. This support
admission does not change the separate supplied normal law of offset or draft
construction. Endpoint or display planarity alone cannot admit a wall.
Material loop direction is selected by the existing original whole line integral
before constructing the raw ruling; reversal transports the retained chart.

Caller-admitted section conversion now consumes the persistent original draft
source and retains its raw lower/upper values with the original ruled wall. One
original traversal is prepared under the same invocation admission for both
heights; fresh conversion certificates bind each candidate. Open curve sheets
publish original wall supports and four original isoparametric lifts, not the
ruled tensor assembled from fitted section controls. Multi-span sheets retain
the original span charts and their native directed traversal. Sewing and final
regularity/embedding admission remain publication requirements. Closed cap and
sharp-corner paths require original projected cap pcurves and actual retained
wall intersections; successful candidate joining does not prove these sources.

The final drafted-wall regularity issuer uses closed original tangents and their
cross product under the same native-sheet thresholds: both tangent lower bounds
exceed distance tolerance and angular clearance exceeds the original angular,
relative and ulp floor. Its historical native-sheet limits remain 18 subdivision
levels and 262144 cells, reduced by caller caps; no sampled normal supplies a
positive certificate. Original embedding is separately owned by the shared
symmetric self-contact atlas.

The open drafted-curve public route prepares the persistent original wall under
one source admission, proves original regularity and consumes the shared original
self-contact session through the sewn-body admission before publication. The original support and isoparametric lifts
are the stored geometry. Existing bSplineSurface semantic identities are retained
for compatibility; no surface feature DTO is synthesized from candidate controls.
Nonsmooth owning-span joins and between-wall contact require the separate complete
finite-contact producer before a multi-wall output can be published.

The shared single-chart embedding request takes the conservative minimum of
the former native-sheet local limits (14 levels, 65536 cells) and the caller.
It does not enlarge these limits to the separate pair-search ceilings. A future
complete multi-wall pair adapter must retain its own original pair authority.

Draft direction inputs retain the original SketchPlane normal and ExtrudeDirection
vector, with nil pull sharing the identical raw extrusion axis. Rounded numerical
normalization is construction metadata only. Persistent sources normalize the raw
components with outward arithmetic; at large heights no previously rounded unit
vector becomes the authored direction. Numerical normalization scales by the
largest component and rejects exactly zero/nonfinite directions without imposing
a modeling-distance threshold on direction magnitude.

Generated original wall sheets pass the actual sewn `ValidatedBRepModel` and
owned body identifier to the injected `OffsetResultValidating` bounded entry
before publication. That entry retains the same feature conversion admission
for self-contact, unordered wall pairs and original finite trim containment.
For one wall, an evaluator without an injected body validator consumes the same
shared original self-embedding session directly, under its former native local
ceilings; this preserves standalone single-wall composition. Multi-wall
publication requires the injected body validator and its absence is an explicit
capability failure; neither raw patch value
validation nor successful sewing establishes between-wall contact freedom.

Native B-spline draft walls partition at every original positive-width knot span.
Each generator binds the original span index and authored trim endpoints, so
closed endpoint derivatives retain their owning side. Exact negative parameter
images reverse those same generators and their order; a rounded trimmed spline
does not replace the source. Generic source families retain their complete
original traversal, and unresolved owning joins fail through the source producer.
All resulting walls share the existing extrusion admission and are admitted
together through the sewn-body contact entry before publication.

Plain open curve extrusion consumes the same exact zero-angle translation arm:
normal, axis and pull all retain the identical authored extrusion vector and
angle is exactly zero. This supplies `C(u)+height*A` without requiring a sketch
normal for spatial/in-plane translations. The auxiliary equal normal does not
change the translated law; its clearance is positive identically and final
original regularity independently rejects a generator tangent parallel to A.
The plain route retains sideFace/edge/vertex semantic roles, while drafted
compatibility roles remain bSplineSurface patch roles. Both routes publish only
after the same original generated-body admission.

Caller-admitted authored straight profile boundaries also consume the persistent
original draft source. Their shared raw degree-one traversal is prepared once
for both heights; endpoint representatives propose straight candidates and each
final straight candidate is freshly certified against that persistent source.
The legacy numerical draft adapter remains solely for callers without bounded
admission and cannot override the bounded production source.

Closed curve extrusion's non-thin sheet branch consumes the original winding-
selected span charts from its material-region resolution. A clockwise source
becomes an explicitly retained original reversed traversal; display coefficients
do not select direction. This is material-boundary orientation, independently
of Loft's declared section correspondence traversal lock. Original drafted
walls replace the prior tensor between converted endpoint sections. Capped thin
material and sharp original wall-joint retrimming remain separate premises.

`AdmittedDraftedSectionCurveSource` is deprecated and has no production caller:
caller-admitted `DraftedSectionPairBuilder.pair` returns through the persistent
source path before its legacy construction branch. The retained adapter is only
for migration comparison until the deferred source-wide behavioral verification;
its final retain/remove decision is required before the task release.

Original curve-sheet selection consumes `OriginalEvaluatedCurveGeometry` under
this same admission. A full periodic source retains its declared authored turn;
an unbounded source retains its authored finite directed parameter endpoints.
Descending authored endpoints reverse the original owning traversals and their
order, independently of fitted candidates. The wall partition's additive directed
flag changes traversal only, preserving the same physical source coefficients,
source depth and original height/draft law.

The [authored section planarity tests](../../../Tests/CADModelingTests/OriginalAuthoredDraftedBoundaryPlanarityTests.swift)
exercise complete closed native traversals on the chart, raw-normal-plane curves
outside the authored chart allowance, and typed independent admission failures.
They verify section support admission, not final extrusion publication.
