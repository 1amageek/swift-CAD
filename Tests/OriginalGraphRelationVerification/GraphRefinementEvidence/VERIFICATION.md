# Issued Graph Parameter Refinement

## Scope

The production `OriginalIssuedGraphParameterRefining` port and its immutable result
consume the concrete source/DI-bound issued collection. They refine the retained
L5 **lifted** selection through unchanged L4 `refinePullback`. All original
parameters and auxiliary variables remain present. The result retains the entire
issued collection, pair ordinal and every raw lifted-cell ordinal. Predicates do
not establish face authority or structural identity.

Only IssuedGraphs, GraphFixtures and GraphProof are compiled here. Lower L0-L6,
source issuance, DI and geometry artifacts are reused after source, module,
object and accepted-product hash checks. No full CADCore, CADGeometry or Kernel
build, nor L2-L6 rebuild, was run. ASAN instruments the changed three modules;
it does not newly instrument the retained lower objects. Prior unchanged lower
ASAN evidence remains limited to its original snapshot and instrumentation.

This is an independent component proof of actual production source files. Native
source snapshots in these fixtures use the sealed source-reading contracts; this
is not new runtime evidence for the actual BSpline geometry adapter, face issuer,
Kernel route, general pcurve compiler or self-identity compiler.

## Behavioral Coverage

| Obligation | Counterexample exercised |
|---|---|
| Continuous parameter refinement | The real sealed rational curve `(t, 1/2, 0)` against a plane is restricted by `1 < 3t < 2`. Exact thirds are excluded; interior/exterior membership is checked independently. |
| Auxiliary retention | A positive-normal offset relation has four lifted variables and three projected parameters. The positive normal witness remains; the negative witness is rejected and its negative-only selection is completely empty. |
| Correspondence | Every included refined cell retains its raw lifted-cell ordinal; excluded cells retain -1. Full coordinate maps have arities three and four. |
| Binding failures | Invalid pair ordinals and a predicate missing the auxiliary variable are rejected. L4 owns coefficient-field compatibility validation. |
| Resources | Measured work and storage succeed exactly; one unit short fails with the original resource cause. Source-depth and result-proof-depth refusal are checked separately. |
| Cancellation | Entry, final refinement publication, and final membership query checkpoints fail explicitly. |
| Lifetime | Producers and setup admissions leave scope before membership queries; COW ordinal-array edits do not change the receipt. |

The adapter never solves the original intersection again. New refinement scratch,
coordinate-map and result storage are charged to the caller admission. Region
depth is explicitly admitted on membership, including empty/excluded outcomes.

## Review and Findings

One scoped source-path review found missing admission of the refined region's
value/coefficient depth. The result now admits that retained proof depth before
membership; a targeted admission rejects precisely that additional check.

Embedded failure verification exposed double wrapping of already-classified
`NativeExactRelationFailure` values. A work shortage became `geometry(scalar(work))`;
a source-depth refusal became `geometry(domain(sourceDepthLimit))`. The new adapter
and the retained collection's `admitProof` boundary now rethrow the concrete typed
failure before the general preserving conversion. The existing error enum is
unchanged. Naming its switch cast explicitly did not fix the observed boundary
and was reverted. The final targeted cases verify the original classifications.

The standalone refinement proof uses a nonthrowing entry with explicit failure
exit. Earlier entry/diagnostic runs are not acceptance. The two retained
`diagnostic-*` directories and `prior-concrete-failure-embedded` are historical
failure evidence only; final acceptance is exclusively the four lane receipts.
Other owned diagnostic attempts remain outside Git in `.build/m6-graph-refinement/history`.
No additional general review cycle or lower algorithm change was performed.

## Ownership and Targets

| Target | Storage | Isolation / concurrency | Release |
|---|---|---|---|
| Native | Immutable issued collection and L4 owner, shared COW arrays | Sendable values; independent mutable caller admission | Retained value lifetime |
| Ordinary WASM | Same production declarations | Same contract | Same owner lifetime |
| Embedded WASM | Same production declarations | Same contract; no target-specific raw state or weakened conformance | Same owner lifetime |

The changed production paths introduce no mutable stored state, unsafe pointer,
lock, target-dependent Sendable conformance or callback. Conditional imports are
verification module adapters only. Compile/link/runtime uses fixed Swift 6.4.0
and matching WASM SDK, with Node.js 24.19.0 WASI for both WASM modes. Successful
runtime proof does not generalize to a different threading backend.

## Receipts and Reproduction

Run `python3 Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/run.py <lane> --cache-root <accepted-checkout>`
from the repository root. The accepted checkout used here is
`/Users/1amageek/.codex/worktrees/di-protocol-responsibilities/swift-CAD`.
Each receipt binds the actual production/compiler inputs, reused modules/objects,
compiler executable, exact commands and timeouts, product, runtime logs and driver.
All inputs are rehashed after runtime. The driver compiles every production source
in the changed module; modified sources are never accepted as unchanged lower
premises. Cached paths are read only, and all outputs use the owned refinement
build directory. Archive a lane's evidence before rerunning it.

M6.G is parameter refinement only. Required M4/M5 issuance, general boundary and
self-contact consumers, actual public Kernel integration, M7/M8 and whole-seven /
full-87 completion remain separate and incomplete.

## Final Acceptance

| Lane | Bound inputs | Runtime seconds | Result |
|---|---:|---:|---|
| native | 1151 | 43.537 | PASS |
| asan | 1151 | 53.765 | PASS |
| wasm | 1159 | 58.932 | PASS |
| embedded | 1159 | 30.317 | PASS |

All four final receipts match the current source and driver. Prior failure logs
are excluded from acceptance. Latest-main delivery is recorded separately in
`integration.json` after the implementation commit.
