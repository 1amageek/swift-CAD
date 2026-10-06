# Section Resolution

## Purpose and Scope

This component belongs to [CADModeling](../DESIGN.md). It resolves source
profiles and curves for feature evaluation and preflight. It has no children.

## Responsibilities and Boundaries

Own profile-index admission, source identity agreement, curve cardinality and
the distinction between resolving geometry and requiring a planar section.
Own the internal `ResolvedFaceSection` carrier independently of the legacy Profile facade.
Its ordered loops retain original Curve3D lifetime owners, directed authored native
trim endpoints, original edge IDs and coedge traversal. Construction spans are
produced from those retained laws; the facade candidate cannot replace them.
`ResolvedBoundaryRegion` retains a constructed placement of a resolved Profile
or Face with its actual original reference, original source value, directed
parameter charts, outer/hole order and complete rigid placement sequence.
`ResolvedModelingSection.constructedRegion` is an internal closed-region arm;
the persistent Profile remains a compatibility facade. Placement creates new
raw image-curve owners while retaining exact fraction expressions and source
provenance. Its final construction spans receive fresh correspondence proofs
under the composing admission, independently of facade coefficients.
Outer and hole directions are selected by a complete original spatial signed-area
integral about the resolved plane normal. Closed native position/first-jet bounds
cover each original directed trim; interval integration preserves all owning
sides without assuming smoothness across joins. Display samples supply no winding
authority. An unresolved or zero signed integral fails explicitly.
Sweep publication applies this same original integral to each span's retained
persistent parameter chart on its normalized domain. A fitted candidate's
Gaussian area estimate cannot select outer/hole orientation. Original face
segments and constructed charts share the same integral owner without fabricated
topology IDs. Face-request construction retains the composing admission for its
new geometry payloads; legacy standalone callers do not supply a full request
allocation receipt.
The original resolved source is immutable and survives reversal and internal
Sweep/Loft routing; persistent Profile DTOs are unchanged. Final construction
coefficients require their own position/tangent/curvature correspondence receipt
bound to the retained chart and actual candidate, including trim/reversal rounding.
The existing conversion ceilings apply; bounded source and candidate preparation
must share the composing request ledger before aggregate source closure.
Own immutable original parameter charts retained with construction spans. A
rounded rational construction image never becomes the original coefficient or
arc-length authority. Affine charts retain directed original endpoints and
construction-domain endpoints; normalized station transport uses outward
arithmetic before converting to native scalar bounds. Circular and hyperbolic
rational charts retain their original analytic law and angular endpoints.
Circular construction stations use OriginalCircularRationalParameterLaw: its
ideal cosine half-weight and sine half-angle share Geometry's canonical
continuous conic phase. For t in [0,1], X = c + 2(1-c)t(1-t),
Y = s(2t-1), W = 1 - 2(1-c)t(1-t). The positive X chart admits
the physical angle atan(Y/X), and the intrinsic source label divides that
angle by the original canonical phase gain. The identity X²+Y²=W²
gives label derivative 2s/(gain W); differentiating this retained rational
law gives closed derivatives through order five. Restriction and reversal
compose the original fraction law, preserving signed gains and endpoint labels.
Directed first/last construction fractions retain exact rational coefficients
computed from the original restriction labels and domain bits. Outward interval
caches are enclosures of those coefficients, never their source identity.
Each restriction applies A + (B-A)(label-domainLower)/(domainUpper-domainLower)
in the same caller's exact algebra allowance; reversal swaps the exact endpoints.
The intrinsic algebra depth remains 32 independently of source nesting and
curve subdivision. Exact coefficient UInt32 words pay physical bytes through
the invocation admission. Persistent source consumers may retain these exact
fractions with the raw curve, directed angular labels and mapping law; an
interval midpoint cannot substitute for the resulting original chart.
Original curve-owner preparation forwards the caller's explicit algebra depth
independently of source and subdivision caps. Nil preserves the lower producer's
existing algebra authority; it does not derive an algebra allowance from native
curve subdivision. Reused preparation remains immutable and query caps are
retained by the original lower owner.
Guide traversal chains and guide endpoint corrections enter the same original
source conversion route. Their authored normalized charts and exact retained
corrections remain input authority; spline construction images are freshly
certified and do not become the guide law.
`OriginalCurveSpanParameterChart.persistentCurve` publishes the actual Geometry
neutral construction-chart family under the same invocation admission. It passes
the raw curve, authored source labels, mapping kind and exact fraction values;
the shared Geometry law owns its normalized original point and derivative jets.
The candidate, interval cache and chart reference identity are absent from this
persistent geometric source. Native/portable codecs retain the original fields.
Rounded candidate weights/controls never define that parameter law.
The chart's immutable `parameterSource` exposes this same exact source expression
to original coedge fraction transport. Native labels and exact restriction
coefficients are retained together; consumers cannot reconstruct a nonlinear
mapping from outward endpoint bounds.
Hyperbolic construction charts consume the neutral original cosh/sinh rational
mapping and complete atanh tail proof. Both conic mappings retain original
directed fraction coefficients through restriction and reversal.
`OriginalCurveSpanSource` retains one immutable original curve for all derived
construction spans of that producer invocation. Restriction and reversal carry
the same owner; replacing the original spatial law creates a new owner.
The circular parameter proof charges fixed primitive visits and actual retained
scalar-array payloads through the composing caller callbacks. Its positive
half-weight and one atan branch must cover the entire original fraction box;
uncertainty fails explicitly rather than choosing a midpoint angle.
OriginalCurveSpanChartIdentity binds a prepared traversal to the same immutable
chart value; restriction, reversal and source replacement create a new chart
identity. Equality of outward endpoint bounds cannot identify two parameter laws.
Reference identity identifies reusable preparation lifetime only and is not
geometric equality, continuity, correspondence or a serialized source identity.
Native and converted spline splitting share that owner before constructing any
rounded trimmed candidate coefficients.
`OriginalCurveConstructionSource` transports complete original D0-D2 through
the retained chart into the actual candidate domain. A final candidate receives
an immutable `OriginalCurveSpanCorrespondence` only after the differential
converter certifies all requested position, tangent and curvature bounds.
Native degrees retain their authored degree admission while the existing control,
box, work and scalar ceilings remain unchanged. Reversal and restriction must
create a new certificate rather than inheriting a prior candidate allowance.
Candidate span metadata uses exact original clamped endpoint control values
when their repeated native knot law proves the endpoint identity. Other
endpoints use a complete closed native point enclosure under the same admission;
its candidate position must fit distance/64 before becoming topology metadata.
This point is candidate metadata, not an original chart endpoint expression.
The source adapter provides exact scalar point queries only where the chart
proves an authored singleton; certification uses closed enclosures and never
chooses an interval midpoint as source geometry.
Final certificates consume GeometryConversionAdmission: source validation, owning
coefficient preparation, chart queries, candidate queries and certification cells
share its actual work-unit and byte callbacks with unchanged span/depth/source
ceilings. OriginalSpanConstructionOwner retains one admission for the builder lifetime.
Derived charts retain that construction admission independently of the original
curve owner. Exact fractional restriction therefore uses the composing allowance
even when an admitted face preserves an earlier source lifetime owner.
An already prepared original curve owner can enter `sectionSpans(sourceOwner:
lower:upper:)` directly. This port checks native domain and source tolerance,
then constructs and freshly certifies actual candidates under the builder's
admission. It has no display-point validation or EvaluatedCurve facade replay.
Evaluated path and sheet-section inputs enter through the bounded
`EvaluatedCurve.validateOriginalGeometry` receipt. The builder forwards its
existing admission's independent source, geometric and algebra capabilities,
work visits and physical bytes. Display samples do not authorize construction.
Each path segment prepares its retained original owner once, and all of its
spans and directed reversals share that owner and the same invocation ledger.
Candidate reversal uses exact knot negation and reversed coefficient order;
the resulting negative parameter domain does not change the raw directed law.
Explicit requested-point path clipping remains a separate original endpoint
localization requirement; a candidate projection cannot supply its authority.
Curve-reference trimming and reversal borrow this same admission. Signed
parameter reversal retains the raw source under gain -1 and exactly negated
endpoint labels; bounded original validation pays for the new image level.
Its compatibility display points come from the bounded CurveTrim sampler,
independently of the raw curve's directed source authority.
The face compatibility facade obtains general-curve spline pieces from this
same prepared owner port. Original topology vertices describe line/circle
facades; other candidate pieces retain separate display samples. Sampling and
reversal of the facade use the composing callbacks but never replace retained
original segments or establish their orientation.
Face resolution admits the retained loop, segment and presentation buffers before
allocation. Presentation stations append into one preadmitted buffer, without
per-segment sample arrays. Directed original loop reversal mutates the admitted
segment buffer in place; its source owners and authored native labels remain
unchanged. Construction-piece concatenation pays both retained capacity and
copy visits through the same invocation admission.
The shared span builder accepts a complete normalized original chart and
constructs and certifies a new candidate directly from its whole differential
law. This port does not obtain a native endpoint from a candidate or midpoint.
Its lazy creation uses the same Mutex storage and access on every target; external
callbacks execute after the lock is released. No I/O, await or callback occurs
inside that initialization lock. A composing feature may inject its own admission.
One original owner may retain its prepared coefficients and admission
for derived spans; restriction/reversal reuses that source lifetime but prepares
and certifies the actual new candidate. Feature invocation owners must pass the
same admission through builders; a fresh default per builder is not evidence
for an aggregate multi-builder or retry allowance.
An affine identity chart restricted in the identical native construction
domain retains the authored restriction bounds directly by algebraic identity.
`authoredEndpointParameter` supplies an endpoint only when the original chart
proves an exact scalar singleton. Original conic chart endpoints at fractions
zero/one retain their raw angular labels. A nonlinear restricted interior or
nonrepresentable foreign endpoint supplies no authored scalar capability;
its interval midpoint cannot authorize a new original trim.
Do not extract sketches, evaluate documents, create source features or bodies, infer a plane
from tessellation, or choose which input the user intended.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | FeatureEvaluating | Supplies admitted sections to existing builders. | Resolution is not geometric construction or whole-shape validation. |
| [CADIR](../../CADIR/DESIGN.md) | depends on | ProfileReference, EvaluatedCurve | Reads exact source values. | Identity and array position are different concepts. |
| [CADGeometry OriginalCurveConstructionChart](../../CADGeometry/OriginalCurveConstructionChart/DESIGN.md) | depends on | exact construction fractions and original conic jets | Preserves original nonlinear chart laws independently of the candidate net. | Persistent chart evaluation uses the same lower law; interval endpoints supply no source identity. |
| [CADGeometry ParameterImage](../../CADGeometry/ParameterImage/DESIGN.md) | depends on | Original signed parameter image | Retains the original curve and jets while reversing traversal. | Derived parameters are not source-reference parameters. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | Sweep preflight | Uses the same admission as evaluation. | Preflight still owns fetching source geometry. |

## Architecture

```text
evaluated source arrays + reference
    -> ResolvedModelingSection admission
        -> profile / retained face loops / curve value
            -> exact construction or Sweep preflight
```

## Contracts and Invariants

A face Profile facade defines its own deterministic plane chart from the proved plane origin and oriented normal. Its world-space boundary points and retained original segments do not inherit the supporting surface UV basis. Constructed-region consumers use retained loop charts through the shared span builder rather than the Profile facade as original source.


Closed-curve extrusion winding uses the same original line-integral issuer as
face sections, borrowing its prepared source and directed native endpoints.
Display samples never select a loop's traversal direction. Conversion to a
legacy Profile facade does not establish correspondence for a subsequently
trimmed or reversed construction image.
Face-loop construction owns one preadmitted span buffer per loop. Reversing a
face use constructs the exact negated native knot chart with reversed original
controls and weights, reverses its retained original fraction law, and obtains a
fresh correspondence certificate. It does not reflect knots about a rounded
endpoint sum or allocate a second reversed span buffer.

- Profile resolution checks the index before subscripting, including negative,
  count-equal and Int.max inputs. Missing values throw missingProfile.
- A resolved value must belong to the referenced source feature. A mismatched
  source identity throws invalidGraph rather than using unrelated geometry.
- A curve reference without a segment index requires exactly one source curve;
  empty or ambiguous input is rejected, never truncated to its first element.
- Plane metadata is required by planar consumers, not invented by resolution.
- Curve interval selection reuses CurveTrimFeatureEvaluator's exact restriction
  and source-domain admission. It preserves source identity, plane and exact
  curve geometry while updating display samples, closure and parameter domain.
  No display polyline is used to reconstruct the selected curve. Extrude,
  Revolve, Loft and Sweep evaluation/preflight consume the same restricted value.
- Reversed sections are restricted first, then retain the original curve in a
  signed parameter image with gain -1 and offset zero. The selected original
  interval [a,b] becomes [-b,-a], using exact representable negation rather than
  a rounded a+b endpoint offset or a fitted rational curve. The image keeps the
  original position and derivative law, including analytic angular parameters.
  Reference bounds remain in source coordinates; generated display points and
  parameters belong to the reversed image. Plane, closure and identity survive.
- Native construction images of a zero-offset signed negation reuse the source
  exact span conversion and reverse its ordered rational spans. This preserves
  existing rational conic and spline representations without fitting the image.
  Their construction parameters do not replace the retained original image
  chart or authorize algebraic boundary roots.
- Native spline construction splits at every distinct original interior knot.
  Model-space distance tolerance cannot merge parameter intervals or remove
  source continuity boundaries. Only repeated identical knots deduplicate.
  Finite native trim admission requires a positive representable width; an
  angular tolerance does not reject a nonangular source parameter interval.
  Original source validation and differential proof retain their own native
  parameter-resolution and resource failures.
- Input arrays and values retain Swift value semantics; whole-section admission
  returns the original value. Interval/reversal results own derived sample and
  immutable original image values without mutating the source. The resolver stores no state.
- These rules and Sendable conformances are unconditional across targets.
- Face boundaries preserve coedge traversal and source endpoints. Analytic conics
  use exact rational conversion. Native implicit and lifted curves use bounded
  differential conversion certified over the complete source trim, with position
  error at most one quarter of the modeling distance tolerance and tangent and
  curvature errors bounded by the modeling angle and distance tolerances.
  A failed certificate remains a failure; display samples never define geometry.
- Rigid and affine image span construction certifies the complete transformed
  original curve directly in its original native parameter interval. Applying
  an image to an already bounded construction net cannot carry its former
  position/tangent/curvature guarantee: rounding and affine error amplification
  belong to the transformed-source proof. The existing differential converter
  retains its degree, candidate, work, scalar and error ceilings; failure is not
  replaced by a transformed uncertified candidate. Resulting spans retain the
  transformed original image law independently of their construction controls.

Extrude admits a shared section before construction. Closed profiles retain the
existing prismatic builder and topology roles. Curve sheets reuse the exact
Sweep patch/sewing path with ruled surfaces between translated exact spans.
An undrafted face extrusion consumes `ResolvedFaceSection` directly. Its
original loops, directed native trims and holes survive span construction; the
Profile facade is not a construction input. Its authored plane origin anchors
both endpoint translations, including the full lateral start offset of an
oblique vector. Sweep's default orthogonal anchor remains its separate policy.
Explicit vectors work for spatial curves without plane metadata. Normal and
symmetric directions require a source plane because an arbitrary spatial curve
has no unique plane normal; missing metadata fails instead of inventing a plane.
Translation retains rational weights and boundary parameters. Generated geometry
passes whole-domain interval regularity validation and existing exact BRep
admission before publication.

## Failure, Concurrency, and Constraints

Resolution is synchronous with no I/O or persistent mutable state.
Face loop integration prepares immutable source coefficients once per segment
and shares one invocation-owned Mutex budget for work, native-query byte payloads
and depth across all outer/hole orientation proofs. Source preparation and proof
failures propagate; the returned face carrier contains no mutable state. Whole-curve admission is constant-time; an
explicit trim owns the bounded sample allocation of the existing trim evaluator.
Reversal retains the original curve value and at most 33 display samples;
it is performed during section evaluation, never during hover.
Missing and mismatched
inputs remain explicit failures. The construction owner validates geometric
regularity and topology; resolution does not claim these properties.

## Verification and Change Impact

[SectionResolutionTests](../../../Tests/CADModelingTests/SectionResolutionTests.swift)
owns direct bounds, identity, ambiguity and plane behavior.
Existing SheetExtrude, CurvedRevolve, Loft and Sweep preflight/kernel tests
own construction and admission parity. A resolution-contract change requires
reviewing each of these consumers; source extraction remains outside this owner.

`OriginalSweepPathLinearity` owns straight-path dispatch authority. Original
line laws and whole rational homogeneous owner incidence authorize straight
arms. Rational native endpoints define the projective axis without rounding a
point or direction into a Double. All three original incidence numerators must
vanish identically. Image actions retain their ordered source transcript. A
whole directed speed numerator is nonnegative at both original endpoints and
every exact original derivative-critical root. These endpoint/critical values
prove monotonic traversal; a line incidence identity alone cannot flatten an
original backtracking path. Adjacent native owners prove exact original C0
endpoint equality. Reversal includes the signed exact construction-fraction
gain. Neutral parameter-law chart images transport the original directed axis
without deriving it from their candidate net.
A common transcript preserves incidence. Different unresolved image fields and
unknown lift/implicit charts cannot become a straight success from candidate
control proximity. The existing source-depth guard and shared exact work and
physical storage owner remain separate from intrinsic algebra depth.

Original polyline source curves retain the Euclidean-length parameter clock and
original adjacent-point ownership. Shared span conversion consumes that raw source
through the bounded original converter and certifies each final candidate; it
does not assign uniform vertex-index parameters or promote a degree-one image to
source authority. Trim preserves the same original curve and native labels.

Straight-path selection for an original polyline proves every authored adjacent
point displacement is collinear and forward along one exact original endpoint
axis. With its original Euclidean-length clock this establishes the same complete
straight locus and direction on every retained subinterval. Closed or backtracking
polylines do not use this arm. Exact rational endpoint differences are retained;
no rounded displacement or uniform-index clock supplies the decision. Root and
ordered-field depth remains the caller's selected algebra allowance, default 32,
independently of source descent and spatial subdivision.
