# CAD Kernel Requirements

Swift-CAD must expose the modeling kernel that Rupa, UI tools, and automation agents can share. The kernel is the source of geometric truth; UI controls and agent commands should call the same typed operations rather than maintaining separate approximations.

```mermaid
flowchart LR
    Rupa["Rupa UI"] --> API["Swift-CAD public API"]
    Agent["AI Agent"] --> API
    Exchange["Exchange import/export"] --> API
    API --> Kernel["CADKernel operations"]
    Kernel --> IR["CADIR geometry and topology"]
    IR --> Mesh["Derived meshes"]
```

## Rupa Requirement Breakdown

| Requirement layer | Rupa need | Kernel stance | Implementation pressure |
|---|---|---|---|
| Exact geometry | Curves, arcs, circles, NURBS curves, NURBS surfaces, and UVN frames must remain editable after each operation. | CADIR owns exact parametric geometry; mesh output is derived and cannot be the modeling truth. | Add exact primitives before UI affordances depend on them. |
| Curve-on-surface | Face trims, bridge edges, surface matching, projected curves, and sweep guides need parameter-space curves linked to surfaces. | Trim and continuity tools must consume typed UV curves instead of sampled polylines where exact input exists. | Promote rational UV B-spline curves into `SurfaceParameterCurve`. |
| Subobject operation | Users and agents must select bodies, faces, edges, vertices, spans, knots, CVs, and trims with stable references. | Selection references belong to the kernel and must survive feature recomputation. | Extend stable naming from generated bodies and faces into trim and surface-output references. |
| Continuity diagnostics | Bridge, match, fillet, patch, curvature combs, and zebra-style checks require measurable G0/G1/G2 quality. | Continuity is a typed request/evaluator contract, not a viewport-only overlay. | Feed exact surface parameter curves into surface continuity sampling. |
| Feature parity | Rupa UI controls and AI agent commands must call the same operations. | Public SwiftCAD operations wrap the same FeatureOperation and validation path; builder APIs cover sketch, extrude, sweep, bridge curve, curve edit, exact line/circle/arc curve offset, exact curve trim, PolySpline, FaceLoopOffset, and FaceKnife; Codable agent command schemas can append shared feature operations through the same graph validation path. | Continue exposing new kernel operations through builder/facade APIs and agent command schemas as they are added. |
| Performance | Large models and WASM execution need allocation-light evaluation and explicit ownership. | Evaluators should avoid materializing homogeneous control nets or sampled replacements in hot paths. | Keep rational evaluation loop-based; add borrowed/COW buffers for dense data later. |

## Product-Parity Kernel Workstreams

Plasticity-class parity is not a UI checklist. Swift-CAD must expose the exact
geometric contracts that let Rupa and agents perform the same high-level edits
without replacing CAD behavior with display-mesh approximations.

```mermaid
flowchart LR
    Request["Typed feature request"] --> Validate["Validation and diagnostics"]
    Validate --> Evaluate["Exact evaluator"]
    Evaluate --> Names["Stable topology names"]
    Evaluate --> Analysis["Measurement and continuity"]
    Names --> Rupa["Rupa UI and Agent"]
    Analysis --> Rupa
```

| Workstream | Kernel contract | Rupa dependency | Verification requirement |
|---|---|---|---|
| Robust filleting and blending | Fillet, chamfer, and blend features must carry affected edge/face references, radius/chord law, continuity target, setback/overflow policy, and typed failure diagnostics. | Rupa can expose edge/face blend affordances only when the kernel reports the supported subset and stable generated names. | Exact supported-subset evaluator tests, topology-name stability tests, and explicit unsupported-case tests. |
| General booleans | Boolean features must operate on exact B-rep operands with operation kind, keep-tools policy, tolerance policy, result-body naming, and non-manifold/tangent/coincident diagnostics. | Rupa sweep, direct modeling, pattern, and primitive workflows need booleans that do not degrade to mesh exchange. | Union/difference/intersection/slice fixture tests, result topology tests, and failure-diagnostic tests. |
| Direct topology editing | Face offset, move face, delete face, move edge, move vertex, shell, draft, and thicken requests must resolve from stable topology references to editable source or kernel-owned feature edits. | Rupa selection modes and agents must mutate the same source contract for object, face, edge, and vertex scopes. | Selection-reference resolution tests, source-rewrite tests, and unsupported-source rejection tests. |
| NURBS and surface source foundation | Curves and surfaces must expose degree/order, knot vectors, weights, spans, CV identity, trim loops, UVN frames, and G-continuity diagnostics. | Rupa cannot ship surface extension, CV editing, xNURBS-like blending, or broad PolySpline workflows without source-owned parametric data. | Differential geometry tests, UVN frame tests, trim/pcurve tests, CV/knot/span identity tests, and continuity tests. |
| Drawing and inspection output | Hidden-line, section, measurement, hatching, stroke style, and view metadata must be structured analysis/export output, not screenshots. | Rupa needs deterministic technical drawings, section analysis views, and Agent-readable inspection results. | Deterministic hidden-line and section fixtures plus export round-trip tests where applicable. |
| Pattern and array evaluation | Linear, radial, grid, curve-driven, and placement-copy repetition must preserve source instance identity, transform precision, and generated topology names. | Rupa needs efficient repetition without duplicating heavy source state or losing downstream selection references. | Transform precision tests, instance identity tests, generated-name tests, and performance-budget tests. |
| Performance and zero-copy data flow | Dense meshes, tessellation output, imported byte ranges, and control nets must use borrowed or copy-on-write buffers where public API ownership allows it. | Rupa viewport, exchange, and Agent batch operations need allocation-light reads and predictable cache invalidation. | Allocation/timing budget tests on dense geometry paths and API tests proving evaluated data can be reused without recomputation. |

## Rupa Implementation Requirements

```mermaid
flowchart LR
    Select["Subobject selection"] --> Measure["Selection measurement"]
    Measure --> Dimension["Editable dimensions"]
    Measure --> Edit["Contextual modeling operations"]
    Edit --> Recompute["Feature recomputation"]
    Recompute --> Select
    Agent["Agent commands"] --> Measure
    Agent --> Edit
```

| Requirement | Consideration | Current target |
|---|---|---|
| Subobject selection | Object, edge, face, vertex, curve point, span, CV, knot, and trim selection must resolve to stable kernel references, not view-only hits. | Keep all pick results as `SelectionReference`; extend missing generated names as features emit new subobjects. |
| Selection measurement | CAD UI affordances need a single way to turn selection references into measured points, tangents, normals, distances, and angles. | `SelectionMeasurementEvaluator` resolves topology, edge, curve, surface, span, CV, curve-knot, and trim selections into reusable measurement results, while ambiguous body and surface-knot selections fail with typed errors. |
| Editable dimensions | Dimension labels must bind to exact references and feed the same solver/operation path used by agents. | `CADDocument.selectionDimensions` persists document-level distance and angle dimensions over `SelectionReference` pairs; `SelectionDimensionEvaluator`, `CADPipeline`, and `CADCommand`/`CADAgentQuery` expose shared add/evaluate paths. General constraint solving from these dimensions remains the next kernel step. |
| Contextual operations | Offset, trim, bridge, sweep, match, patch, and face edits require the selected subobject plus local frame information. | Reuse measurement point/tangent/normal output before adding operation-specific request types. |
| Agent parity | An agent must not use a separate geometric approximation from the UI. | `CADAgentMeasurementQuery` and `CADAgentSelectionDimensionEvaluationQuery` call the same selection measurement and dimension evaluators used by public SwiftCAD APIs. |
| Diagnostic overlays | Curvature combs, UVN frames, tangency, and continuity overlays need exact differential geometry. | Continue feeding curve/surface derivative and curvature evaluators into shared diagnostics. |
| Performance | Interactive snapping, selection, measurement, and agent batch edits happen frequently. | Keep queries allocation-light and resolve directly from evaluated CADIR/B-rep tables instead of storing duplicated snap geometry. |

## Completion Matrix

| Requirement | Why it matters | Current state | Completion target | First implementation slice |
|---|---|---|---|---|
| Parametric curve model | Sketching, sweep paths, bridge curves, tangent snaps, and dimensions need editable curves with stable parameters. | Lines, circles, arcs as exact circles with finite domains, and rational B-spline curves are modeled with evaluation, derivatives, curvature, domains, knots, weights, exact sketch line/circle/arc curve outputs, exact line/circle/arc curve offsets, exact curve trim features, exact/fallback curve projection queries, and history-preserving B-spline CV/knot/weight edit features. Generated-curve constraints need expansion. | Lines, arcs, circles, Bezier, B-spline, and rational NURBS curves with evaluation, derivatives, domains, knots, spans, weights, and projection references. | Add generated-curve constraints and continuity-ready endpoint frames. |
| Parametric surface model | NURBS surfaces are the foundation for Plasticity-class loft, bridge, sweep, patch, continuity, and curvature tools. | B-spline surfaces support degree/order, knots, control points, positive weights, rational evaluation, differential geometry, surface trim references, UV trim-curve queries for face loop edges, rational B-spline UV parameter curves, exact pcurve storage on oriented edge uses, PolySpline boundary pcurve emission, and planar FaceLoopOffset/FaceKnife generated pcurves. Trim loop topology still needs broader feature evaluators to emit exact parameter curves. | NURBS surfaces with degree/order, knot vectors, control nets, positive weights, rational evaluation, derivatives, normals, UVN frames, and trim-ready parameter domains. | Connect projection, topology repair, and additional feature evaluators to exact parameter curves. |
| Differential geometry and UVN frame | Curvature combs, zebra diagnostics, surface snapping, continuity matching, and deformation need first and second derivatives. | Surface differential geometry uses rational B-spline derivatives for position, tangents, second derivatives, normals, curvature, face-based surface query frames, closest-point projection, direction-based projection, and planar line-loop trim bounds back to UVN frames. | Shared evaluators for position, tangent U/V, normal, principal curvature, principal directions, and orientation-stable UVN frames on analytic and NURBS surfaces. | Add curve-on-surface trim domains and projection diagnostics over non-planar trims. |
| Continuity contracts | Bridge, fillet, blend, and surface matching need explicit G0/G1/G2/G3 targets rather than visual-only alignment. | Curve G0/G1/G2 and surface G0/G1/G2 requests are represented as kernel contracts with position, tangent/normal angle, curvature deviations, surface boundary/trim sampling helpers, an initial G0/G1/G2 bridge-curve solver, and bridge curve feature output. Blend and patch solve inputs still need expansion. | Typed curve and surface continuity evaluators with deviation metrics, tangent/curvature constraints, and solve-ready diagnostics. | Add continuity-driven solve inputs for blend surfaces and patch construction. |
| Topology and stable naming | Object, face, edge, vertex, CV, knot, span, and trim selection must survive feature recomputation and agent operations. | B-rep tables, generated persistent names, evaluated curve output tables, curve subobject references, face-based surface subobject references, and indexed surface trim references exist for basic feature, curve, surface, and trim-edge selection. | Stable references for bodies, faces, edges, vertices, trims, surface spans, curve spans, knots, and control vertices. | Extend generated names and selection references to trims and generated surface outputs. |
| Solid and sheet B-rep robustness | CAD edits must preserve watertight solids, sheet bodies, trim loops, and validation semantics. | Basic B-rep validation exists for planar/cylindrical/B-spline boundary cases, oriented edge uses can store exact surface parameter curves, and validation checks endpoint plus sampled 3D edge consistency for stored pcurves. | Manifold validation, trim loop validation, orientation repair diagnostics, and exact curve-on-surface constraints. | Move generated feature trim checks from endpoint approximations toward parameter-space trim curves. |
| Feature evaluators | Users and agents need high-level operations: extrude, revolve, sweep, loft, bridge, fillet, chamfer, shell, boolean, and patch. | Extrude, face loop offset, knife, sweep contracts, source-owned Loft, poly-spline surface generation, and bridge curve generation are represented. Loft evaluates closed profile sections into ruled or smooth cubic section-direction B-spline B-rep faces, supports finite positive global and per-section smooth tangent scales plus automatic/zero section tangent modes for section-direction handles, interpolates section scales for guide-inserted intermediate rings, supports solid/open-sheet/closed-section-loop sheet output, seam locking, and multi-section multi-guide rail-following intermediate section rings. PolySpline, FaceLoopOffset, and FaceKnife now emit exact pcurves for supported generated trims. Bridge curves produce exact B-spline curve outputs that downstream features can consume as paths or guides. | Feature evaluators that produce exact B-rep or exact curve/surface outputs with stable subshape names, with mesh as derived output. | Add continuity-driven loft/bridge surface solvers and use higher-order NURBS surfaces for advanced sweep/loft/bridge instead of temporary mesh-like approximations. |
| Snapping and dimensions | Accurate sketching and construction workflows need exact snapping and editable dimensions. | Sketch dimensions exist, solver-ready constraint graph equations preserve dimension target values, sketch dimension evaluation reports measured values and residuals, a direct sketch dimension solver handles line length, point-to-point distance, line angle, arc span, radius, and diameter dimensions, the SwiftCAD facade can apply sketch dimension solves to document features with downstream invalidation, and kernel query APIs expose evaluated curve endpoints, midpoints, parameters, tangents, curvature, closest-point and direction-based curve projection, B-spline spans, knots, control points, B-rep edge endpoints/frames/projection, surface UVN/knot/span/CV queries, closest-point surface projection, direction-based surface projection, planar trimmed-face projection bounds, intent-filtered snap candidates for vertices, edges, generated/evaluated curve projections, generated/evaluated curve keypoints, and faces, plus selection measurement queries for points, distances, and angles from shared `SelectionReference` values. Document-level selection dimensions now persist distance and angle targets in `CADDocument`, affect source fingerprints, round-trip through `.swcad`, and evaluate through the shared kernel/facade/Agent path. | Kernel queries for endpoints, midpoints, centers, tangencies, projected points, construction planes, distances, angles, persistent dimension annotations, and editable dimension constraints. | Connect persisted selection dimensions to general editable dimension constraint solving and construction-plane-aware annotation placement. |
| Performance and memory | WASM and large models require avoiding unnecessary copies at byte, mesh, and control-net boundaries. | ByteSource/ByteSink boundaries are explicit; control nets currently use value arrays. | Borrowed or copy-on-write views for dense points, weights, indices, and imported byte ranges where API ownership permits. | Keep rational evaluation loop-based and allocation-light; avoid temporary homogeneous control nets. |
| Exchange boundary | USD mesh exchange, STEP/IGES CAD exchange, and native documents must map into the same kernel model. | USD mesh exchange and pure Swift USD readers exist as trait-gated modules. | Mesh exchange remains mesh exchange; CAD exchange maps to exact curves, surfaces, trims, topology, units, and metadata. | Preserve USD as mesh exchange while strengthening NURBS/B-rep for native CAD workflows. |

## Rupa Priority Map

| Rupa workflow | Kernel requirement | Current state | Next gap |
|---|---|---|---|
| Subobject selection | Bodies, faces, edges, vertices, curve spans, surface spans, knots, and CVs need stable references. | Bodies, faces, edges, vertices, generated persistent names, typed edge parameter references, curve output references, curve span/knot/CV references, face surface span/knot/CV references, evaluated curve tables, shared intent-filtered snap candidates for topology and curve outputs, edge projection queries, curve projection queries, and face-to-UV projection queries exist for core feature outputs. | Extend references to trims, generated surface outputs, and topology-to-parameter projection references. |
| Curve authoring | Lines, arcs, circles, Bezier, B-spline, rational NURBS, offsets, bridge curves, tangent snaps, and dimensions must share exact curve types. | Lines, circles, finite-domain arcs, rational B-spline curves, sketch splines, curve continuity, bridge curve output, exact line/circle/arc offset operations, exact curve trim operations, exact/fallback curve query and projection APIs, and typed B-spline CV/knot/weight edit operations are available. | Add sketch constraints over generated curves. |
| Surface editing | Sweep, loft, bridge, patch, PolySpline, continuity matching, UVN frames, and curvature diagnostics must be exact geometry first. | Rational B-spline surfaces, rational B-spline UV parameter curves, oriented-edge pcurve storage, PolySpline boundary pcurve emission, planar FaceLoopOffset/FaceKnife pcurve emission, surface continuity checks, surface sampling, sweep, Loft ruled and smooth cubic section-direction B-spline surfaces with global and section-level tangent-scale and tangent-mode control, PolySpline surface generation, surface query frames, and UV trim-curve queries are partially available. | Add feature evaluators that emit exact trimmed surfaces beyond planar generated loops, continuity-driven loft/bridge surface solvers, and diagnostic projection APIs. |
| Operation parity | UI tools and AI agents must call the same typed operation requests. | FeatureOperation is the shared IR, generated curves flow through the same evaluation context as sketch curves, the SwiftCAD builder exposes bridge curve, curve edit, curve offset, curve trim, sweep, Loft, PolySpline, FaceLoopOffset, FaceKnife, and selection dimension operations, Codable agent commands append shared feature operations or document-level selection dimensions through graph/document validation, Codable agent queries can resolve shared snap candidates, selection measurements, and selection dimension evaluations, and the SwiftCAD facade exposes intent-filtered snap queries, selection measurement queries, persisted selection dimension evaluation, and document-level sketch dimension solving. | Keep public SwiftCAD-level builder APIs, agent command schemas, and agent query schemas aligned with every new feature operation and document-level source operation. |
| Performance | WASM, interactive editing, and agent batch edits need allocation-light geometry evaluation. | Curve and surface evaluation uses typed arrays and avoids homogeneous control-net materialization in the hot path. | Add borrowed/copy-on-write buffer views for dense imported meshes, control nets, and tessellation output. |

## Milestone Direction

```mermaid
flowchart TD
    M1["M1 NURBS Geometry Core"] --> M2["M2 Continuity and UVN Diagnostics"]
    M2 --> M3["M3 Stable Subobject Selection"]
    M3 --> M4["M4 Exact Feature Evaluators"]
    M4 --> M5["M5 Agent and UI Operation Parity"]
    M5 --> M6["M6 Exchange Mapping to Exact CAD"]
```

| Milestone | Definition of done |
|---|---|
| M1 NURBS Geometry Core | Rational curves and surfaces evaluate position, derivatives, curvature, normals, domains, knots, spans, and weights with typed validation. |
| M2 Continuity and UVN Diagnostics | Curves and surfaces expose shared G-continuity checks, UVN frames, curvature data, and diagnostic samples. |
| M3 Stable Subobject Selection | Object, face, edge, vertex, CV, knot, span, and trim references survive recomputation and are usable by UI and agents. |
| M4 Exact Feature Evaluators | Sweep, loft, bridge, patch, fillet, chamfer, shell, and booleans produce exact B-rep where supported and fail with typed errors otherwise. |
| M5 Agent and UI Operation Parity | Every user-visible modeling action has a typed operation request that agents can call with the same validation path. |
| M6 Exchange Mapping to Exact CAD | CAD exchange maps exact geometry into curves, surfaces, trims, topology, and units; mesh exchange remains explicitly mesh-only. |
