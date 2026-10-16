# Original Boundary Clipping

## Purpose and Scope
Parent: [CADGeometry](../DESIGN.md). No children. Own the source-bound parameter clipping consumer for complete Native and issued-graph CS/SSI receipts. This component does not publish geometric image strata or a maximal geometric overlap result.

## Responsibilities and Boundaries
The issuer supplies every authored directed pcurve and loop role, bound to one retained raw receipt and one original surface side. The consumer retains all original source laws, denominator guards, requested/native domains and derivative-closed raw cell conditions. Neither a cell sample nor a tolerance authorizes inside, absence, cell identity or source equality. CADKernel owns original face/coedge identity; this component owns exact boundary laws, parameter refinement and raw-cell correspondence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [IntersectionAlgebra](../IntersectionAlgebra/DESIGN.md) | depends on | Complete original sign selection, closure, incidence and components | Existing Q5 engine performs the full refinement | Original ring, source and independent depth admission remain bound |
| [Native CS](../CurveSurfaceOverlap/NativeRelation/DESIGN.md) | depends on | Complete raw chart/domain receipt | Retains original T/UV cells | Native samples do not represent cell ranges |
| [Native SSI](../NativeSurfaceSurfaceRelations/DESIGN.md) | depends on | Complete raw UV receipt | Retains both original sources and UV fibers | Parameter components are not image components |
| [Source issuance](../OriginalSourceIssuance/DESIGN.md) | depends on | Sealed original surface binding and forward UV laws | Retains original source authority | A matching callback cannot issue source identity |
| [Issued graph relations](../NativeExactRelations/DESIGN.md) | depends on | Complete retained graph relation and L4 pullback refinement | Refines material in the original lifted ring | All auxiliary witnesses and original guards remain retained |
| [Kernel issuer](../../CADKernel/OriginalBoundaryClipping/DESIGN.md) | used by | Immutable face-issued boundary domain | Face/source binding precedes clipping | Authored pcurves are already directed |

## Architecture
```text
retained Native/issued-graph raw cells + face-issued directed loops
    -> original source/domain and parent-path sign laws
    -> exact directed segment boundary/crossing laws
    -> original Boolean selection in the same T/UV ring
    -> retained exact refinement/closure/incidence/components
    -> parameter receipt + whole-cell original raw identifiers
```

## Contracts and Invariants
- A boundary domain retains its particular raw receipt, surface side, source surface and the complete loop buffer. Another equal-valued receipt does not replace its owner.
- The initial issuer supports constantU, constantV, affine and authored polyline pcurves on a nonperiodic native B-spline support. Every endpoint is computed over the original binary-rational coefficients, including affine parameter multiplication; no rounded evaluation is used.
- Each directed segment contributes exact half-open upward/downward ray-crossing predicates. Their signed sum defines nonzero winding, with an independent closed-segment zero predicate for boundary membership. Outer material is the union of outer loop interiors; inner loop interiors are removed. Closed selection retains hole and outer boundaries, strict selection excludes every boundary, and boundary-only selection keeps only retained material boundaries.
- Authored pcurve traversal is used unchanged. Topological coedge orientation is retained by the issuer and never applies a second reversal.
- Raw selected cells are identified by their full derivative-closed parent-path sign conjunction, including original domain bounds. The combined law list also retains the raw source equations/guards. Refined-cell correspondence evaluates complete sign conditions; it never classifies a sample.
- The selected result is fully decomposed before publication. Complete empty selection is valid only after the same original predicate is resolved over the whole original requested domain. Every selected refined cell has exactly one original raw-cell owner.
- Parameter/component identity is receipt-local. Original raw owners, source input and boundary buffers outlive all result queries.

## Runtime Flows
Preparation, Boolean compilation, Q5 refinement, correspondence and result allocation borrow the same caller work/storage/cell/coefficient-cell owners. Retained source depth is admitted before descendant work; descendant visits preserve that baseline. The final normal-return callback is followed by current-task cancellation before publishing a domain, result or membership value.

## State, Ownership, and Lifecycle
All receipts and backing buffers are immutable. There is no global cache, shared mutable state, conditional target storage or independent quota. A result retains its raw receipt and issued boundary domain. Query-local admissions never outlive the call.

## Failure, Concurrency, and Constraints
Checked capacity arithmetic and storage admission precede generated buffers. Invalid source/domain binding, missing or unclosed directed trims, exhausted caller resources, independent depth failures and cancellation propagate without a success value. General rational spline and implicit/nonrational trim charts remain incomplete branches with explicit code markers and typed failures; the checked positive single-span quadratic capability below is additive. The legacy Q5 route additionally leaves periodic/pole chart authorities and refined image/fiber strata incomplete; the additive M6 Native family route below consumes existing finite DI seam/collapse authority. General issued-family migration remains open and is not counted as whole requirement-4 acceptance.

## Verification and Change Impact
[Kernel tests](../../../Tests/CADKernelTests/OriginalFaceBoundaryClippingTests.swift) execute the public raw receipt -> original face issuer -> exact consumer route for holes, nonconvex loops, corners, endpoint/boundary coincidence, strict/closed/empty selection, original raw-cell ownership, source-release lifetime, foreign binding and independent admission/cancellation failures. Native CS/SSI raw receipt behavior and Q5 are unchanged lower premises. Changes to boundary meaning require the Kernel issuer and result correspondence proofs to be revalidated. Whole source-family/domain acceptance and image clipping remain requirement-4 integration work.

## M6 L5 Consumer

The additive exact boundary route consumes the complete Native family collection,
selected surface role and original directed loops. Its source owner retains all
ambient source/support/request/effective covers, chart sides and integer lifts.
The sealed domain is created by the Kernel face issuer after exact stored-source
comparison and full loop/coedge validation. The legacy Q5 route remains compatible.

```text
face-issued lifted pcurves + retained Native L5 family
    -> checked DI affine coordinate view
    -> exact local winding/material predicate for every pair
    -> NativeExactParameterRefining (L4 whole-cell pullback)
    -> complete raw/refined cell correspondence with all UV owners
```

No periodic or collapsed-source rejection is needed when DI already supplies
complete finite chart occurrences and exact lifts. The boundary compiler uses
constant-U/V, affine and polyline source laws in authored traversal order; it
does not normalize lifts, infer missing curves or apply coedge reversal again.
Each new guard is refined once over its retained raw L5 selection. The result
retains every source chart pair, including complete excluded regions. Every
included refined cell has the L4-issued raw cell ordinal. Equal XYZ never merges
owners. Closed, strict and boundary policies preserve original endpoint meaning.

All compilation/refinement/query work uses one caller noncopyable admission,
explicit DI limits and unchanged L3/L4 ceilings. Terminal cancellation and any
failed pair invalidate the complete publication. The exact face consumer tests
own holes, nonconvex loops, strict/boundary/empty policies, seam lifts, collapsed
surfaces, original-source lifetime and independent refusal cases.

[M6 boundary fixtures](../../../Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures/M6ExactBoundaryFixtures.swift)
execute the actual Core/Geometry/Topology plus Kernel boundary component. The
runner binds compiled inputs, artifacts and terminal runtime markers to one
immutable snapshot. This is component verification, not full CADKernel or
Modeling acceptance. Query compilers have invocation-local mutable buffers;
published results and their retained source owners are immutable Sendable values
on every target. There is no target-specific synchronization or owner contract.

Boundary annotations consume L3's proved original-input signs. A singleton
seam/pole box can specialize a guard to a constant, so a projection cut receipt
alone is insufficient. Each requested law is transported through the retained
L4 singleton-domain reduction receipts by exact polynomial equality, then
matched exactly to the partition's retained original law ordinal. Original cell
signs classify every included cell over that complete box. No derivative/sample
signs or representative matching establish a boundary incidence. The result
retains the raw selection, partition and complete reduction owners.

### Latest-main Native intake verification

The independent consumer assembly recompiles the actual Native consumer and its
source/DI/L5 adapters against current independently verified lower modules. It
reuses receipt-bound unchanged Native DTO/validation products; numerical CS/SSI,
Coons construction and cached old DI/L3 consumers are outside that reuse path.
Verification-only imports select these DTOs explicitly, preventing old cached
relation types from satisfying the new consumer signatures. Native and isolated
builds retain identical consumer bodies, immutable owners and failure semantics.
Actual face issuer/Topology acceptance remains separately bound to its retained
source and compiler receipt. No broad CAD production module is rebuilt.

### Authored-coordinate query field

Exact Native boundary membership accepts an optional query field, defaulting to the
prepared source field. All authored coordinates are validated before piece visits,
including an empty raw family. The same field reaches DI selection membership,
checked inverse-transport evaluation and retained-L5 refinement membership. New
algebraic coordinates do not require rebuilding the original source or relation.
Foreign fields/coordinates and query resource/depth/cancel failures propagate.

## Issued graph face boundary connection

The frozen Coons-hole cells extend the same parameter consumer to retained issued
graph relations. Their [initial public binding stop](../../../Tests/OriginalPublicAcceptanceVerification/Evidence/B-COONS-HOLE-01-stop/VERIFICATION.md)
establishes the need for this connection; the existing Coons producer is reused.

```text
sealed original surface binding + issued graph relation + validated face loops
    -> exact source-owner and stored-support comparison
    -> retained graph coordinate layout and forward rational original UV laws
    -> shared exact winding compiler in the relation's coefficient field
    -> existing issued-graph L4 pullback refinement, without intersection solving
    -> face-bound parameter result retaining every raw pair and boundary span
```

OriginalFaceSurfaceBinding has sealed factories for the actual retained Coons
snapshot and Native surface source. Its source binding and literal Surface3D
value remain together; callers cannot supply an unchecked matching callback.
OriginalIssuedGraphBoundarySource checks that the selected first/second source
owner is that binding's owner and that its role is a surface. Kernel compares
the stored support using the existing metered structural comparison contract.
The retained graph proof and stored Coons traversal source-depth ceilings are
admitted before that comparison; the model's existing validation is retained.

The shared winding compiler is generic over the retained coefficient base. Native
affine UV and graph rational UV feed the same segment, winding, policy and span
algorithms. A graph pair uses L5's actual first/second coordinate placements; its
auxiliaries remain in the full lifted ring. Forward UV numerators and denominators
are transported exactly, with nonzero guards and sign-correct denominator clearing.
No inverse correspondence or positive-denominator assumption is introduced.

Each pair is refined once through DefaultOriginalIssuedGraphParameterRefiner.
The result exposes its retained raw graph source and per-pair pullback/span
correspondence, including empty refinements. Membership is explicitly a lifted
coordinate query with compatible query-field validation, not invented original
UV inversion. The frozen Coons input has identity authored parameter transport;
its public tests verify that correspondence and all required T sets independently.
Final XYZ/image/fiber refinement remains the separate M7 obligation.

All new owners are immutable Sendable values, and compiler buffers remain local
to one caller admission on Native/WASM/Embedded. Resource refusal, invalid source
binding, missing pcurves and cancellation fail the complete publication. Existing
Native APIs remain compatible. Nonlinear boundary pcurves and other unissued
surface binding factories remain open mandatory coverage, not inferred completion.
The public Coons cell fixtures own changed-path success/exclusion, role/source
refusal, raw/refined ordinals, count/depth/work/storage/cancel and detached lifetime;
unchanged lower and validator evidence is reused only with matching premises.

The changed first-surface SSI branch is checked with the same original Coons
face and a degree-one Native tensor surface `(x,y,z)=(u,1/2,v)`, both with full
unit-square requests. Its independent closed material oracle is
`(U0,V0,U1,V1)=(t,1/2,t,0)` for `t` in `[0,1/4] union [3/4,1]`. Certified
whole-cell signs check every refined cell, raw ordinal and incident span rather
than sampling that curve. This changed-API regression also exercises the sealed
Native support factory; it does not complete general SSI/material coverage.

The shared compiler's new denominator clearing is checked directly with
`U=x^2,V=1/2,D=-1` on `[-1,1]^2`, preserving both preimages and the unused
coordinate fiber, and with `D=0` requiring complete exclusion. These probes own
the newly introduced arithmetic branch only; they add no source producer or
prerequisite for the three frozen Coons policy cells.


## Rational Quadratic Directed Winding

The [observed public rational-quadratic refusal](../../../Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01/native-observation-v1/receipt.json)
fixes this change to the existing winding/material consumer. The source-owned
[positive quadratic authority](../OriginalSourceIssuance/DESIGN.md#positive-rational-quadratic-boundary-authority)
is prepared once for each original pcurve at boundary-domain issuance. Immutable
prepared loops retain that exact source/chart/support/proof and are shared by
all raw-pair compilers; original directed loop buffers remain retained. Straight
segments keep their existing predicate meanings. The same preparation and
compiler serve exact rational-base Native relations and original-exact-base
issued graph relations. New source/owner payloads and loop buffers are metered
with the same caller admission before publication.

```text
face-issued original pcurves
  -> once-prepared directed segment/checked quadratic arc owners
  -> each raw pair's exact forward UV numerators/denominator
  -> original arc boundary + chord crossings + signed cap correction
  -> existing nonzero winding/policy DAG
  -> retained L5 refinement and original span/raw ordinals
```

For a checked quadratic, substitute actual UV into its three affine barycentric
laws and conic E. Clear lambda signs with the actual UV denominator and conic
signs with its square; a zero denominator excludes the tuple. The actual
boundary predicate is E=0 with all three lambda_i>=0. The replacement chord
is used only for winding and never becomes a boundary incident. Its ordinary
half-open ray crossings plus the checked cap contribution sign(D) reproduce
the original directed arc's winding, so reversing traversal changes signs while
preserving material, and inner/outer/overlapping loops retain existing nonzero
winding semantics.

The cap correction uses E>0 and lambda0,lambda2>=0. Interior lambda1>0
contributes. On the artificial open chord lambda1=0, contribution follows the
existing ray convention: for chord delta=(du,dv), include iff D*dv>0 when
dv!=0, or D*du<0 for a horizontal chord. The former is the +U-side limiting
value and the latter the above-chord lower-inclusive/upper-exclusive value.
Arc endpoints are handled by the actual closed arc boundary. This convention
prevents a false boundary or material gap on the artificial chord. It is checked
with direction, chord, horizontal/vertical and rational-UV denominator controls.

Original boundary span ordinals refer to the actual pcurve and its sole span;
no fitted parameter, endpoint projection or polygon is published. Raw source
cells, chart/lift/auxiliary layout and source owners are retained by the existing
refinement result. Complete empty, resource/depth/coverage failure and entry,
processing, final-publication and subsequent-query cancellation preserve their
original cause. All new backing is immutable and query scratch stays local;
Native/WASM/Embedded have one owner and Sendable contract.

The dedicated cell verifies the complete public tuple iff [t,t,7/32] with
1/4<=t<=1/2, exact original curved/right incidents, raw/refined ordinals,
complete exclusion, source and material controls, budgets, cancellation and
detached lifetime on the four fixed lanes. Strict/boundary policies are regression
controls, not additional whole-family acceptance. General rational multispan,
implicit/certified/nonrational pcurves, unissued surface bindings and final
geometric image/fiber publication remain open mandatory requirements.


### Native raw-equation scope reduction

The fixed quadratic cell's first changed Native public run reaches L4 refinement
but fails the unchanged value-depth32 allowance. Its complete UV predicate still
contains a two-variable conic even though the retained raw equality already fixes
V=7/32. L4 builds the ambient sign arrangement before selecting the raw cells;
changing Boolean instruction order cannot remove this extra arrangement.

The initial constant-UV substitution and target singleton restriction still fail
at root splitting depth33. The fixed raw relation also proves U=T. Leaving the
conic in U causes another nonlinear root-union isolation at the dependent U
stack, after its cuts were projected onto T. For a quadratic boundary, the
Native adapter consumes affine equations from the retained L5 source's
`rawEquations`, choosing each equation's highest nonzero variable. It obtains L3's
whole-cell sign invariant for the actual equation and requires zero on every
selected raw cell. Ascending-axis substitution then expresses that coordinate
in lower axes only, with exact nonzero division and polynomial identity. These
acyclic correspondences pull the forward UV boundary laws into independent raw
coordinates while preserving the full parameter layout. A nonempty selected raw
set and the original domain containing a constant replacement also authorize
restricting that target coordinate to the exact closed singleton.
An absent invariant or any nonzero selected sign leaves that axis unrestricted.
Empty raw selections do not authorize a vacuous constant. The checked invariants
and original raw selection remain owned by the published refinement.

The target singleton makes existing L4 reduction substitute the constant into
all target atoms and raw-cell definitions before decomposition. Its retained
reduction receipts transport the original boundary laws for incident queries.
The compiler retains the scoped pullback of its forward UV laws, all source axes, guards,
raw ordinals and source maps. No lower solver change, multi-variable elimination,
approximate coordinate or model-specific constant is introduced.

This equality is scoped to the retained raw relation and is never issued as a
global surface parameterization. The resulting L4 pullback still intersects that
same complete raw selection and retains its L5 owner, original equations and
all source maps through the existing refinement result.
Thus both the original source theorem and the scope authorizing substitution
outlive every material and boundary-span query. The fixed cell reduces to
lambda=(4U-7/8,7/4-4U,1/8) and E=16(U-1/4)(7/4-U), preserving the full original
T/U/V layout and both actual boundary incidents under the original limits.
The dedicated public oracle and resource/cancel/lifetime checks own this changed
Native scope. General elimination and issued-graph constant reduction remain
outside this change.

### Checked affine factorization of a scoped conic

Reversing the same complete quadratic loop exposes a second root-depth stop.
Ordering the input laws does not close it and is not part of the implementation.
L3's existing nonlinear root-union route requires interval splitting even when
an exact factorization into affine cuts can supply all roots directly.

For each actual quadratic arc, evaluate its retained original homogeneous law
at the exact midpoint of its authored support using the existing polynomial
producer's public evaluation contract. Each exact UV coordinate is only a factor
candidate. For the actual pulled-back conic P, try L=H_axis-m_axis*W. Accept a
factorization only if L has total degree1, exact polynomial division gives zero
remainder and quotient Q of total degree at most1, and P=L*Q holds coefficient
by coefficient. A failed factor identity leaves the original conic expression;
all evaluation/admission/division failures propagate. No scalar root extraction,
approximate candidate or additional intersection solver is introduced.

With a checked factorization, compile P=0 as L=0 or Q=0 and P>0 as the two
same-sign combinations. The original barycentric, branch and denominator guards
remain unchanged. P is absent from active cut laws and retained in an immutable
factorization receipt with L,Q and the checked zero remainder. Both Native and
issued refinements retain these receipts with the original source/arc/scope owners
for their complete lifetime. Original node and boundary-span ordinals remain
unchanged. All buffers, exact evaluation and factor checks use the same admission.
The fixed line passes through the exact authored arc midpoint, giving
P=(T-1/4)*(28-16T) in either traversal direction. The complete public oracle,
direction/artificial-chord controls and four-target changed paths verify this
specialization; it does not claim rational factorization for other inputs.


## Retained predicate conjunction

The compiler imports a sealed retained predicate by its original sign program,
exact coefficient field and interval guards. Variable roles remain unchanged.
Each source domain's open/closed/empty condition participates explicitly; a raw
bounding box cannot substitute for those conditions. This operation compiles
new conjunction only and performs no decomposition. Native material self-contact
uses it to combine the already proved self residual with both face predicates.
The existing raw relation, both boundary compilers and their scope proofs remain
retained in the resulting correspondence. Recheck ordinary clipping compatibility
when this shared compiler contract changes.

### Direct retained source consumers

Original Native boundary clipping and membership receive the original inout execution. Immutable baseline parameter/coefficient depths open local proof scopes on this execution; no callback usage or copyable descendant ledger is created. Internal polynomial compilation uses the same generic ExactScalarAdmission. Full raw-cell/source correspondence and retained depth translation remain unchanged.
