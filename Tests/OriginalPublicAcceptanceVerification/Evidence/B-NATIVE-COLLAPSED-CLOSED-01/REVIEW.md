# B-NATIVE-COLLAPSED-CLOSED-01 Scoped Conformance Review

Verdict: **PASS for the frozen finite Native parameter/material cell and scoped
mapping changes. No unresolved findings.**

This is one comprehensive review against baseline
`d5fbba40a836e288d458c527c76d92ebf46fd281` plus the frozen fixture, driver,
evidence and documentation delta, followed by one focused confirmation of F1.
The reviewer changed only this report. No production, fixture, driver, design or
PROGRESS edit, additional reviewer, build or runtime execution was performed.
Main integration, commit and delivery remain task-owner work.

## Contract and fixed artifacts

The applicable AGENTS instructions, PROGRESS
`DIA.4.I.M6.B.COLLAPSED01.O/V/R/D` and the Geometry/Kernel boundary designs
require complete original parameter/material selection, retained raw-cell
correspondence, every boundary incident, owner lifetime and explicit failure.
Image/fiber dimensions are the independent oracle's meaning, not asserted
Kernel geometric publication fields. Production sources are unchanged by this unit.

| Artifact | SHA256 |
|---|---|
| NativeCollapsedBoundaryAcceptance.swift | `7eada5e589a04127f2b5486af2ad444cb4693cd61212f2e1d3bb93111d9275af` |
| NativeCollapsedBoundaryAcceptance.py | `79f43d60737fb2abcb662cb1d64115ed7d793f02ffde852f9c422a1387013204` |
| VERIFICATION.md | `da2de3190c79794c810a88150bddd13b6a5a08179dd2747b55f417ce166a2f2a` |
| evidence-manifest.json | `c40941444a34d572198e4ff13713f04fc249a825ef5bc2b7cc7ee364c7e5bbcd` |
| summary.json | `f7b1bdd90b6c63b0a9676cb9f887a885e3254347651ac40f8242256874041f50` |

## Actual path and independent oracle

```text
actual original Native curve/surface + complete original DI covers
  -> actual DefaultCurveSurfaceIntersector.exactParameterRelations
  -> current Native family resolver / retained L5 raw relation
  -> exact-validated original face and directed pcurves
  -> actual Kernel exact face issuer / sealed Geometry boundary domain
  -> original winding predicate / retained L4 pullback refinement
  -> all raw/refined ordinals and boundary spans
  -> final allocation / cancellation checkpoint / immutable face result
```

The fixture uses actual degree-one Native constructors with closed unit supports.
Exact source-map polynomial comparison establishes C(t)=origin and
G(u,v)=(uv,v,0), both with denominator one. It checks source layout, parameter
counts and identity inverse transports, rather than accepting a matching sampled
point. The actual face constructor retains four forward coedges and authored
bottom/right/top/left constant-U/V pcurves for [1/4,3/4] x [0,1], validates its
sheet/body at `.exact`, and calls the production Kernel overload with `.closed`.

The independent equality law forces v=0 and leaves t/u free. Material therefore
selects exactly {(t,u,0): 0<=t<=1, 1/4<=u<=3/4}. The fixture requests proved
whole-cell sign invariants for t,t-1,u,u-1,v,v-1 and the two material U cuts.
Every raw terminal cell's selected status and every refined terminal cell's
included status is compared iff with this oracle, including excluded cells.
Each refined terminal must appear exactly once; checked terminal count equals
the result's complete cell count. Maximum selected dimension is two. This is a
complete partition comparison, not point-membership sampling.

The retained pullback must preserve coordinateMap [0,1,2] and the exact ordered
raw cell list. For each included refined cell, its raw ordinal must be valid and
its complete six-sign signature must equal that raw cell's signature. The raw
signatures are checked injective. Thus assigning another valid raw ordinal is
rejected, including at endpoints; index-range checking alone is insufficient.
Excluded cells require ordinal -1.

Every selected cell must retain the bottom span. The U=1/4 and U=3/4 cells must
add the left and right spans respectively. Exact span counts and membership in
the expected distinct set reject omissions, duplicates and wrong references.
Native/ASan/WASM report raw terminal27/selected9, refined terminal63/selected9,
bottom9/left3/right3. Embedded executes the same assertions with static markers.
All t/u coordinates survive although XYZ is constant; image0/fiber2 describes
the oracle and does not merge original parameter identity.

The oracle runs after prepare() releases its original curve, surface, raw and
face-construction locals. The result still retains the exact-validated model,
face/loop IDs, original raw source, complete partition/refinement and incidences.
This checks the actual retention chain used by result readers.

## Implementation and evidence composition

The actual current family resolver prepares the selected original chart laws and
finite closed domains, verifies owners/transports, and resolves every chart-pair
product under one admission. The only source difference from the admitted prior
32-file recipe is its extracted appendPrepared helper. Inspection of the historical
source diff confirms the unchanged Native body receives the same field and
admission; the current complete source is freshly compiled here.

Kernel verifies the stored Native support against the retained selected source,
retains all original loops/coedges/pcurves, and creates the sealed boundary domain.
Geometry derives authored UV through checked DI transports, compiles exact directed
segment/winding predicates and refines the original L5 selection. Boundary span
annotations consume original whole-cell signs, including retained singleton
reduction authority. No intersection is solved again by a cached legacy consumer.
Kernel rejects a consumer's foreign sealed domain/policy and checks cancellation
after final result allocation. Errors preserve their original cause.

| Lane | Final receipt SHA256 | Terminal result |
|---|---|---|
| Native | `2fb5a30d5cd3b4cdc3e64b01071a018300ed7425df139985e4239ed3c78d428c` | full fixture succeeds |
| ASan | `3920e9060dd0ec016a7b9ae249c167cad109db54860ce6aa4e25f7922d439a74` | full fixture succeeds |
| Ordinary WASM | `290a0d29aae074b476ce1483f9fac11e2d282e62b2ef7fd6c5c3ca16346ad63d` | full fixture succeeds |
| Embedded WASM | `1a6e27c6acbf3545cc99d09695a1eaf01ae1ce36bb39ebfbfd558a80a1c81943` | full fixture succeeds |

All 147 saved manifest artifacts, totaling31,987,976 bytes, match their recorded
digests. All four final receipts and reused successful current-module receipts
match summary bindings. Every lane's32 current source hashes match current bytes;
module and final-proof source mappings agree. The reviewer recomputed4,919 unique
admitted source/product/log identities with zero mismatches, including lower
modules/archives, source/DI adapters, cached Native DTO/Topology validation,
unchanged Kernel products and final executables.

The actual commands prioritize and link each lane's receipt-bound current
NativeDomainAdapters module/archive. Verification imports explicitly select the
existing Native DTOs and source/DI nominal namespaces. SourceGeometryAdapters and
NativeKernelAdapters retain their admitted original contracts. This is a selected
component assembly; it is not a whole current CADGeometry/CADKernel package build
or proof of its complete production module graph. No lower or broad rebuild is
claimed. Historical membership logs remain historical, and intermediate weaker
ordinal assertions are excluded from final fixture acceptance.

Fixed Swift6.4.0 release commands use matching WASM resources. Normal WASM selects
swift_static; Embedded selects swift resources, the Embedded feature and WMO.
ASan is present in both current-module and proof commands. Actual final portable
executables run through the admitted Node/WASI runtime. Current-module compiles,
final compile/link and runtimes exit zero without timeout. Runtime durations are
0.997/0.996/0.737/0.537 seconds. The Embedded compiler's8.06GB RSS observation is
separate from the caller's1GiB admission and is not a geometric storage claim.

## Failure, lifetime and state scope

| Invariant/control | Evidence and limit |
|---|---|
| Work/storage cause | Same positive clip source refuses work0/storage0 with original scalar/domain resource cause and resourceLimitExceeded normalization |
| Entry cancellation | Same positive source with canceled ledger preserves scalar cancellation and CancellationError normalization |
| Final cancellation | Successful same-input clip measures retain-call count; a separate invocation cancels there and fails before Kernel publication |
| Complete empty | Exact request T={2} is outside authored [0,1]; issued family has no pieces, clip has no refinements and original-coordinate membership is false |
| Historical failure premises | Unchanged consumer/compiler, sealed Kernel issuance, scalar failure mapping and lower owners retain admitted plane-fixture depth/foreign-owner/failure evidence |
| Lifetime | Complete independent raw/refined/incidence oracle succeeds after original preparation locals leave scope; ASan executes that path |

Zero budgets do not establish minimum viable budgets or whole-cost N/N-1.
The empty control is out-of-support coverage, not a nonempty-family solver
exclusion. Empty final cancellation/budgets, overflow/minimum boundaries and
concurrent queries are not new runtime claims. No broader completeness inference
is made from the historical failure or membership fixtures.

| State owner | Native / ASan | Ordinary WASM | Embedded WASM | Access and release |
|---|---|---|---|---|
| BoundaryPublicationAdmission | Noncopyable invocation-local ledger/counter | Same | Same | Exclusive mutating calls; no shared state or escaped callback |
| Compiler/refinement workspace | Invocation-local buffers | Same | Same | Borrow same caller admission; no retained admission |
| Published model/source/results | Immutable Sendable owners | Same | Same | Retained through result; local source release exercised |

There is no new shared mutable state, target-specific raw-state substitution,
weakened Sendable contract, unsafe owner or extension-only existential operation.
Embedded fixture conditionals change diagnostics only. This cell claims no new
multithreaded runtime semantics.

## Mapping review and finding confirmation

The physical arc candidate uses mathematical pi and gain1+2pi for the physical
phase. Its two roots pi/(2g),3pi/(2g) and target UV follow the source basis and
full phase interval. Binary64 B=2*Double.pi is kept separately: intrinsic child
labels are exact field fractions B/4 and3B/4, not rounded libm expressions.
Existing actual angular constructors/issuers support the recorded source/DI
premises; ordinary runtime remains unobserved.

The ruled closed-guide recipe defines one parent and a directed whole positional
seam. Its triangle is otherwise injective; subtracting the authored diagonal and
forward seam leaves only the reverse seam. Endpoint derivatives(4,0,0)/(0,-4,0)
refute any germ/smoothness inference. The recorded Native-selection-only identity
declaration restriction is visible in the actual signature; constructor/source
product/checked issuance/public residual remain explicitly unobserved.

The sphere-cone candidate preserves the exact authored radian and stored radius:
mathematical tan(alpha), rather than rounded libm tan, defines the original-pair
formula. It does not assume slope1 or radius-squared3. The actual stored certified
curve instead uses Double coefficients/trigonometry and stored2*Double.pi T;
the document correctly leaves original parameter/position/positive-root authority
unresolved. Its original-pair two-point formula is not promoted to a stored-curve
acceptance oracle or observed failure. Corresponding PROGRESS items remain open.

F1: the6-B6 crosswalk initially called this collapsed whole-cell comparison
unobserved despite the updated dedicated section and four-lane evidence.
The owner corrected only that stale claim. One focused recheck confirms it now
states scoped observed parameter/material/raw-ordinal/bottom-corner/lifetime
acceptance, while preserving historical membership and general pole/apex/
multicycle limitations. F1 is closed; no other findings remain.

The observed cell's O/V conditions are supported. Review supplies R's evidence;
commit/main integration/delivery and the parent remain task-owner completion
steps. This PASS does not complete general M6/M7 geometry, other source families,
whole M4-M8, whole-seven or full87, and does not authorize a further review cycle.
