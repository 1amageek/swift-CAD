# Coons hole boundary: reproduced public input binding stop

This is a Native diagnostic checkpoint for the three frozen Coons hole policy
cells. It completes their initial stopping-input observation, not their material
clipping acceptance, M6, M7 or M8. Whole-seven completion remains 1/7.

## Input and independent oracle

[CoonsHoleBoundaryProbe](../../CoonsHoleBoundaryProbe.swift) constructs the actual
four-cell original Coons surface with the previously accepted
`PolylineAtlasLiftProof.shape(multi:true)`. It builds a real exact-validated BRep
face on that same Coons support, with outer [0,1]^2 and inner [1/4,3/4]^2 loops,
four constant-U/V authored pcurves per loop, and reversed coedges. Lifted edge
curves retain the Coons support; there is no replacement Native plane.

The degree-one Native query curve runs from (0,1/2,0) to (1,1/2,0). Full source
requests produce the retained graph relation with four chart pairs. The original
incidence oracle is (T,U,V)=(t,t,1/2), 0<=t<=1. Its material expectations are:

| Cell | Required T set |
|---|---|
| B-COONS-HOLE-CLOSED-01 | [0,1/4] union [3/4,1] |
| B-COONS-HOLE-STRICT-01 | (0,1/4) union (3/4,1) |
| B-COONS-HOLE-BOUNDARY-01 | {0,1/4,3/4,1} |

These material sets are independent oracles, not accepted clipping results.

## Actual path and stopping operation

| Operation | Observation |
|---|---|
| Real Topology validator with original Coons support and retained pcurves | PASS |
| Existing source issuance, complete domain binding and graph relation preparation | PASS: one curve graph, four surface graphs, four retained pairs |
| Identical fixture with the rejected boundary input construction omitted | Typecheck PASS |
| `OriginalExactNativeBoundarySource.curveSurface(raw)` required by the public Kernel clip entry | Compiler rejects the actual issued Coons graph relation; the argument requires `NativeExactParametricRelations<BSplineCurve3D,BSplineSurface3D>` |
| Public material clipping and its three output oracles | Not executed; no accepted result |

The public source-input constructor is the reproduced stop. The unchanged
Kernel issuer's B-spline-only stored-support check and the boundary compiler's
fixed rational coefficient field are additional inspected connection limits,
not separately reproduced runtime failures.

The causal change must bind the retained issued graph and actual Coons surface
authority, transport its original UV correspondence into the retained lifted
solver coordinates, then reuse the existing winding and L4 refinement path.
The existing complete Coons source/DI producer passes this input. A new producer,
whole-M4 completion, unrelated M5 proofs or a repeated intersection solve are not
prerequisites established by this diagnostic.

## Evidence and limits

`receipt.json` binds the fixture, driver, parent receipts, admitted inputs,
compiler input, commands, immutable product and archived logs. `admission.json`
binds the retained 3,559-path admission and existing parent maps without
duplicating their full content. Reused Core, original Topology/DTO, Coons/source/DI
and graph products were admitted before use and rechecked after execution.
Four historical public-point inputs and six unused Native lower-generation
premises are explicitly excluded: their changed bodies are neither selected nor
executed. Native lower modules supply only the rejected Native source signature;
the executed graph path uses the separately admitted PublicLiftPlane assembly.

The fixed Swift 6.4.0 release compiler performs the two typechecks (1.177s and
0.414s), fixture-only compile/link (26.321s), and original-input runtime (2.773s).
Each command has a 120-second timeout. There is no broad CAD or L2-L6 rebuild.
This checkpoint supplies no ASAN/WASM/Embedded acceptance or clipping resource,
cancel, lifetime or complete-output claim; those remain the public-cell gate.

The initial import ambiguity, failed parent-premise admission and repeated-error
collector check are diagnostic attempts only. The scoped checkpoint review
strengthened the fixture to check the actual validated Coons support, both loop
roles, all eight retained directed pcurves, every reversed coedge and the raw
source's original host. The final v5 compile/link/runtime and control/rejection
logs correspond to that stable fixture; no earlier failed attempt is accepted.

One scoped checkpoint review confirms the actual original constructor, complete
request, public input type, unchanged validator path, expected compiler refusal
and evidence locality. No production API or runtime behavior was changed.
