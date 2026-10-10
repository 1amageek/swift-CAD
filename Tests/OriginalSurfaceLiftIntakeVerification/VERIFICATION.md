# Native surface lift source and domain intake

This unit completes the finite nonperiodic Native surface/rational B-spline pcurve
source-to-DI capability. General/periodic surfaces and pcurves, priority images,
out-of-exact-support control hulls, rolling-ball consumption of lifted rails,
M5 identities, M6 general consumers, M7/M8 and whole-seven/full87 remain open.

## Actual implementation path

`OriginalNativeSurfaceLiftSnapshotProvider` retains the actual lift and validates
the Native surface and original 2D pcurve under the same caller admission. The 2D
reader directly exposes original controls/weights/knots, never a fitted XYZ image.
Sealed complete Native families supply all surface/pcurve chart pairs. The source
producer embeds original surface XYZ/D in auxiliary UV and retains exact pcurve
normalization tau=a+(b-a)T plus U*Dp-NpU=0 and V*Dp-NpV=0. UV bounds and all source
and transport denominators remain guards. The existing DI graph binder retains
normalized T requests and every auxiliary witness without a nonlinear inverse.

The focused driver compiles all new source/DI bodies and the actual fixture against
receipt-admitted unchanged Core/Geometry/collection modules and objects. In
particular actual `SurfaceLiftCurve3D`, `BSplineCurve2D`, Native evaluation and
bounded child validation source hashes match the cached products. Imports are the
only assembly transformation. Unselected old solver/identity/consumer bodies and
later additive query overloads are explicitly excluded from this proof. No broad
CADCore/CADGeometry/Kernel or L2-L6 rebuild occurs.

## Accepted verification

| Lane | Inputs | Products | Compile/link/archive/runtime seconds | Runtime seconds |
|---|---:|---:|---:|---:|
| Native | 1665 | 46 | 7.178 | 0.861 |
| Changed-source ASAN | 1665 | 46 | 7.483 | 1.153 |
| Normal WASM | 1670 | 1864 | 7.095 | 1.041 |
| Embedded WASM | 1670 | 1865 | 56.419 | 0.198 |

Receipts are `Evidence/<lane>/receipt.json`; immutable products remain at
`.build/m4-lift-intake-<lane>-final`. Exact Swift 6.4.0 release compiler and matching
SDK/toolset configurations are bound. Embedded uses WMO/-Onone and the admitted
Unicode library; WASI retains the existing 64 MiB stack configuration. Every
compile/archive/link/runtime command has a 120-second timeout. Inputs, imported
modules/objects and old artifact/log receipts are checked before and after use.
ASAN instruments new source/DI/fixture code; unchanged cached children are not
instrumented. These concurrent correctness runs are not performance benchmarks.

| Behavioral obligation | Independent expectation / actual path |
|---|---|
| Original equality | Weighted Native surface and weighted pcurve with authored [2,4] parameter support; exact independent 2/5 and 3/5 XYZ fractions agree with actual public lift evaluation |
| Complete sides | Two pcurve spans times four surface charts; all eight incidents at a knot/tensor corner, endpoint and wrong-UV exclusions |
| Nonlinear / singular correspondence | Quadratic nonmonotone pcurve retains distinct T=1/4 and 3/4 at the same UV/XYZ; constant pcurve retains every T and all surface sides |
| Exact selection | Strict exact 1/3 cut, singleton, disconnected and empty requests; no enclosing-T box substitutes for UV guards |
| Authority / failures | Foreign child/source/frame, wrong coordinate role, incomplete frame support, invalid template/arity, one-short chart limit, source depth, invalid weight/control domain and unproved priority image refuse |
| Scalar transfer | Importable independent-field rational tuple normalizes before selection/graph evaluation; foreign sqrt(2) rejects even on empty selection |
| Resources | Native exact source work 24,235/storage 161,712 bytes; WASM exact work 24,188/storage 85,308; exact allowance succeeds, one-less work and storage fail |
| Cancellation | Entry, final source-storage callback, empty-query entry/final callback and exact empty-query allowance |
| Lifetime / COW | Returned helper family outlives original input scope; mutating a copied 2D control array leaves retained original source and proof unchanged |

Three independent package manifests include the new pure source contracts and
exclude the four concrete CAD adapters. `Evidence/package-manifests.json` binds
the exact package files, compiler tool and successful dump-package commands. This
checks package configuration only, not a new whole-target build.

## Scoped review and finding confirmation

One stable scoped review covers the source owner/evaluator, complete child families,
original polynomial composition, DI binding, resource admission, failure paths,
package adapters and target ownership. Two concrete findings were corrected:

1. A pcurve control U=-1e-14 passes legacy tolerance admission and the numerical
   surface evaluator clamps it to U=0. Publishing that input as a whole exact lift
   would silently lose a defined numerical endpoint. The source port now refuses
   control hulls outside exact Native support with unsupportedRepresentation.
   Positive weights prove that accepted hulls cannot require legacy UV clamping.
   General out-of-support hull correspondence stays required unfinished work.
2. A compatible rational tuple from another base field passed import validation
   but its unnormalized values then failed selection evaluation. The domain query
   now imports each coordinate once into a separately admitted three-value scratch
   buffer and uses those values throughout. Foreign algebraic fields still fail.

`Evidence/diagnostic-native-boundary-red` and `diagnostic-native-import-red` retain
producer assembly input hashes, commands and runtime failures. A pre-execution
fixture hash was not persisted for these failing runs; they are diagnostic,
not acceptance. Earlier Native compile/fixture diagnostics and intermediate four-
lane products are also not final acceptance. Finding-only confirmation passes on
all four final lanes. No remaining blocker is known within this finite capability.

| State owner | Native / WASM / Embedded storage and isolation | Read / mutation / release |
|---|---|---|
| New source snapshots, complete graph families and domain covers | Identical immutable Sendable value/retained owners | Read-only queries retain original source and COW storage |
| Producer and query scratch arrays | Identical invocation-local arrays under exclusive inout admission | Checked work/storage, discarded on failure, no shared access |
| Existing source proof admission | Unchanged scoped nonescaping forwarding borrow | Same caller ledger; no new unsafe boundary or ownership change |

Edited-source scans confirm no target-specific stored state, conditional Sendable,
Mutex bypass, unchecked conformance or unsafe isolation. No new shared mutable
state or concurrency mechanism is introduced. Existing admitted ownership evidence
is reused; this unit does not claim a new parallel stress test.

## Delivery boundary

A coherent implementation commit and independent latest-main verification close
this finite unit. Delivery evidence is recorded after actual integration. Complete
M4-M8 and whole-seven/full87 completion are not asserted; whole-seven remains 1/7.


## Latest-main delivery

Implementation commit `702dd84e` was independently composed with latest main
`e7b570ff` without source adjustment. `Evidence/main-integration/integration.json`
binds 7,180 unique source/tool/package/artifact/log premises, checked before and
after fresh Native (0.283 seconds) and Embedded (0.704 seconds) execution. All
four accepted lane evidence sets remain identical. No rebuilding or additional
aggregate review was performed. Main normally fast-forwarded to the exact verified
implementation, followed by the accompanying progress/delivery-record commit.
Original source-owner drafts, pending consumer merge and protected publisher patch
were not edited. Unrelated unpushed main history prevents automatic push. All
remaining M4-M8 and whole-seven/full87 obligations stay open.
