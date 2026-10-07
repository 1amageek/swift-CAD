# Independent Original Parametric Relation Verification

Date: 2026-10-08. Branch: `codex/exact-parametric-relation`. Lower baseline:
`29702a63`. Source-bound homogeneous CS/SSI composition only; no upper CAD build,
native B-spline extraction, geometry publication, main merge or whole-seven claim.

## Implementation and public paths

[Component contract](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactParametricRelation/DESIGN.md)
owns the source/equation/domain/retention/admission contract. Construction and
resolution use generic protocol requirements with the concrete L3 Cells and L4
Topology injected. The result retains original maps, raw equations, exact guarded
division witnesses, complete predicate/partition/selection and all incidence and
components. Exact tuple membership uses source-bound cell identity.

| Public execution | Behavioral evidence |
|---|---|
| map -> compile -> resolve | Weighted CS two closed endpoint roots, repeated tangency, two distinct UV at one XYZ, continuous relation, no intersection and identically zero denominator |
| full guarded equation compilation | For W=t, raw -tu/-tv become -u/-v only with exact zero-remainder division witnesses and unchanged t!=0; every retained identity is checked publicly |
| complete domains | Strict endpoint roots are excluded with complete empty evidence; singleton surface axis and unbounded curve/surface axes retain exact tuples at t=100 |
| SSI maps -> L3 -> L4 | Folded four-parameter original equality retains 45 selected cells, 108 directed attachment pieces, one component and exact true/false tuple queries |
| input release -> contains | Map/domain/field creators leave scope; retained relation still exposes original laws and answers exact membership |
| failure paths | Exact work/storage boundary and one-less typed failure, malformed map and kind, unrelated coefficient family, independent L3 cell/L4 closure/component limits, cancellation during work and first/final allocation |
| terminal publication | Both compile and resolve refuse cancellation triggered by their final storage callback; no partial or empty-success receipt escapes |

## Fixed snapshot results

| Lane | Actual behavior |
|---|---|
| Native Swift 6.4.0 | Four tests / four fixture groups pass, 12.019s runtime |
| Native Address Sanitizer | Same four groups pass, 27.921s runtime; no sanitizer findings |
| Ordinary WASM 6.4.0 SDK | Compile/link and all four synchronous fixture groups pass in Node24.19.0 WASI Preview1 |
| Embedded WASM 6.4.0 SDK | Onone/WMO compile/link and same four groups pass in Node24.19.0 WASI Preview1 |

Every CS group contains eight independent query cases, each with its original
200M work / 700M admitted-byte / 400 value-depth / 400 coefficient-depth allowance.
The allowance is never restarted inside a query. Folded SSI uses that same unchanged
independent lower-fixture allowance. Caller count limits remain explicitly supplied.
This does not prove an upper geometry caller's separate 80M admission contract.

| Input | Native/ASAN work / admitted bytes | Both WASI work / admitted bytes |
|---|---|---|
| denominator-zero excluded CS including exact division identity checks | 594751 / 27130907 | 591456 / 13641891 |
| folded SSI including exact tuple queries | 15641604 / 580194166 | 15463359 / 291731758 |
| CS compilation exact-boundary fixture | 363 / 20104 | 362 / 10064 |

Before guarded division, the W=t input alone exhausted the existing 700M storage
allowance (`Evidence/cs-focused.log`). The earlier `Evidence/native.log` also used
one incorrect shared fixture allowance across different queries. These two logs
are historical diagnostics, not current-snapshot passing evidence. The final
sources normalize only by proved nonzero original W factors; lower sources and
limits remain unchanged. No exhaustion fallback or coefficient approximation.

## Ownership, scope and review

| State | Native | Ordinary WASM | Embedded WASM |
|---|---|---|---|
| map/source/result/topology evidence | Immutable retained owners | Same | Same |
| remapping/equation/witness/domain buffers | Invocation-local exclusive mutation | Same | Same |
| cumulative caller admission | Same inout requirement | Same | Same |
| publication and later-query lifetime | Terminal checkpoint; retained sources | Same | Same |

No shared mutable state, unsafe pointers, target-dependent Sendable, raw Embedded
state, cache or new production dependency was introduced. Conditional imports
exist only for isolated verification modules. One stable whole review confirmed
exact guard equivalence, complete-empty proof, parameter/fiber identity separation,
checked payload admission, inherited fields/depths, final cancellation and lifetime;
no unresolved scoped finding remains. No extra lower review cycle was run.

`sources.json` binds 195 production sources (184 byte-identical L0-L4 plus 11 L5),
all fixtures/package and the unchanged WASI runner. `run.json` binds exact commands,
toolchain, matching SDK IDs, target, raw WASM artifacts, log hashes and all 24
actual compiler input lists (six layers in each of four variants). Every list
matches its production inventory. Original lower verification evidence, including depth and ordered-coefficient
contracts, is reused only for unchanged sources. New L5 behavioral fixtures use
rational coefficients in retained field owners; an algebraic-tower L5 fixture is
not claimed by this packet. Both WASM builds report only the unused -rdynamic
warning; no function-signature mismatch occurred. All commands have explicit
120-second timeout and two compiler jobs; dedicated build paths are retained.
