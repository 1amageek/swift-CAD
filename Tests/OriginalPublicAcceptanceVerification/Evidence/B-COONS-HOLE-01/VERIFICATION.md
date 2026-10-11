# Issued-graph Coons face boundary verification

The acceptance scope is the three frozen M6 parameter/material cells in
[OriginalDomainCoverage](../../../../Sources/CADGeometry/OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md).
The original stopping input and diagnostic receipt are retained in
[the stopping-input checkpoint](../B-COONS-HOLE-01-stop/).
Delivery status is recorded only in the project PROGRESS.md.

## Public input and complete oracle

The real four-cell planar Coons constructor is
`PolylineAtlasLiftProof.shape(multi: true)`. The degree-one Native line has
knots `[0,0,1,1]` and controls `(0,1/2,0)`, `(1,1/2,0)`. The exact-validated
original Coons face retains outer `[0,1]^2`, inner `[1/4,3/4]^2`, eight original
constant-U/V pcurves and reversed coedges. The full incidence relation is
`(T,U,V)=(t,t,1/2)`, `0 <= t <= 1`.

| Public cell | Independent complete material oracle |
|---|---|
| B-COONS-HOLE-CLOSED-01 | T = [0,1/4] union [3/4,1] |
| B-COONS-HOLE-STRICT-01 | T = (0,1/4) union (3/4,1) |
| B-COONS-HOLE-BOUNDARY-01 | T = {0,1/4,3/4,1} |

Each of the four raw pairs retains all refined cells and original coordinate
laws. Whole-cell certified signs check the complete oracle, including excluded
cells and ordinal -1; boundary spans identify the actual outer-left,
inner-left, inner-right and outer-right authored pcurves. The fixture does not
infer equality, complete exclusion or boundary ownership from sampled XYZ.

## Changed public path

```text
Actual Native line / original Coons source
  -> existing source-DI issued graph and retained complete raw relation
  -> sealed source/support binding for selected CS or SSI role
  -> exact-validated original face / retained loops and pcurves
  -> existing retained graph L4/L5 refinement with material conditions
  -> DefaultOriginalFaceBoundaryClipper issued-graph overload
  -> immutable face-bound parameter/material result and membership query
```

The boundary consumer uses original forward rational UV laws, explicit nonzero
and sign-correct denominator guards, and each pair's real variable placement.
It does not invert parameter maps, regenerate a Coons producer or re-solve the
original intersection. The old Native affine adapter and loop extraction reuse
the same exact winding compiler. All original owners and auxiliary coordinates
remain retained. Final XYZ/image/fiber publication is a separate M7 obligation.

## Admitted changed-path evidence

| Evidence manifest | Accepted scope |
|---|---|
| [accepted.json](accepted.json) | Ten Native/ASAN/ordinary-WASM/Embedded controls and extras receipts, exact compiler snapshots, commands, products and logs |
| [modules.json](modules.json) | Four fresh changed-module compile recipes/products and their actual compiler input bytes |
| [shared-native-regression.json](shared-native-regression.json) | Four target regressions of shared Native source/domain/Kernel bodies: holes, nonconvex, selected sides, seam/pole and failures |
| [finding-confirmation.json](finding-confirmation.json) | Eight focused runs: all three CS policies and SSI first-side annotations on each of four targets |
| [review-snapshot.json](review-snapshot.json) / [REVIEW.md](REVIEW.md) | One stable 15-body production review and its single verification finding F1 |

The fixed compiler is Swift 6.4.0 release. Native and ASAN use the recorded
Apple SDK/target; ordinary WASM and Embedded use the matching release SDKs,
recorded targets, linked products and admitted Node/WASI runner. Exact toolchain,
SDK metadata, commands and hashes are in the receipts. Independent changed-path
assemblies reuse admitted unchanged lower products. No broad CADCore,
CADGeometry, Kernel or L2-L6 rebuild was performed.

Controls exercise exact and one-less work/storage, count and independent depth
limits, entry/mid/final-publication cancellation, foreign source/face/consumer,
invalid query arity/pair, subsequent membership admission and COW. Extras
exercise detached source/field/model lifetime, independent concurrent readers,
foreign scalar fields, complete empty refinement and final empty cancellation.
Direct exact winding probes preserve nonlinear two-preimage UV and negative
or zero denominators. Actual SSI retains
`(U0,V0,U1,V1)=(t,1/2,t,0)` for the closed policy. SSI is a changed-API
regression, not another newly completed acceptance catalog cell.

F1 corrected only the independent annotation oracle: an otherwise valid-index
outer-bottom span at T=1/4 must be rejected in favor of the inner-left owner.
The repaired CS and SSI oracles and explicit fabricated-owner rejection passed
on all four targets. Production hashes remained equal to the reviewed snapshot;
unchanged resource/cancel/lifetime and lower evidence was reused. No second
comprehensive review or repeated unchanged target execution was added.

## Diagnostic and completeness boundaries

[diagnostics.json](diagnostics.json) records earlier fixture failures and wall
timeouts; those are not accepted executions. [harness-timeout.json](harness-timeout.json)
checks owned process-group cleanup, not geometric acceptance. The longer final
wall windows retain the original compiler/runtime CPU limits and all public
admissions, tolerances and depth/count contracts.

Historical orchestration edits are distinguished from archived actual compiler
inputs. A module-only receipt does not claim a later fixture run passed.
Successful empty output is backed by every raw pair's complete excluded
refinement. Missing pcurves and unsupported general boundary laws still return
explicit failure; these frozen constant-U/V cells do not complete rational,
implicit or nonrational pcurve coverage. Other source families, symbolic infinite
families, M5 composite identity, general self-contact, M7 final publication and
M8 full integration remain open. Whole-seven completion remains 1/7 and full87
is not complete. Latest-main composition is bound separately by integration.json.
