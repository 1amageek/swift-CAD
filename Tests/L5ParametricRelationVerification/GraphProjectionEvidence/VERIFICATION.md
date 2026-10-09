# Original graph and existential projection verification (B0-B2)

## Scope

This record covers the sealed original rational/offset graph issuers (B1), exact
existential prefix projection in L4, and auxiliary-aware mathematical graph pair
construction/resolution in L5 (B2). B0 fixes their component contracts.
Source-receipt conversion into L5, DI requested-domain composition, and public
CS/SSI geometry publication remain B3/B4. This is not completion of all seven
intersection requirements. No production module or alternative solver was added.

## Reproduction and immutable inputs

Run `python3 Tests/L5ParametricRelationVerification/GraphProjectionEvidence/run.py
<source|relation> <native|asan|wasm|embedded>` from the repository root.
`run.py` records each exact command, deadline and exit status. Dedicated build
paths preserve separate Native/ASAN/ordinary-WASM/Embedded caches. Builds have a
180-second guard; Native tests have a 120-second process guard and one-minute test
limits; each ASAN proof group has a 60-second process guard. Portable proof groups
have a 120-second process guard. Mathematical work/storage/depth limits are
unchanged. Native graph cases and remaining tests are invoked separately to avoid
competition between heavy fixtures. ASAN and portable groups use fresh processes.

The toolchain is Apple Swift 6.4 release at the absolute path in each command;
ordinary and Embedded use matching `swift-6.4.0-RELEASE_wasm` and
`swift-6.4.0-RELEASE_wasm-embedded` SDK identifiers. WASI execution uses Node
24.19.0. Embedded compiles with WMO and `-Onone`. The proof driver's ASCII-only
argument/environment dispatch avoids Unicode-normalization linkage in that driver;
no mathematical or synchronization contract is conditional on Embedded.

Each lane's `inputs.json` hashes the actual compiler source lists and package
manifest; `result.json` records new-run commands and artifact digests; reused B1 lanes
retain their original success logs rather than reconstructing historical commands. Final
`audit.json` binds the retained logs/manifests and checks source hashes against the
working snapshot. The ordinary-WASM run precedes the runner's final Native-only
filter split; its recorded driver digest identifies that exact invocation. Its
compiled inputs and portable invocation sequence are unchanged.

B1 source Native/ASAN/ordinary-WASM evidence is reused from the unchanged committed
B1 implementation, `4e29afdd`; every recorded production input was compared with
that commit and the final working snapshot. Source Embedded was executed directly.
The four source production input sets are identical. L4/L5 final production input
sets are likewise identical across all four lanes. Reuse does not claim coverage
of a changed source, test or mathematical contract.

## Behavioral evidence

| Owner / fixture | Actual behavior checked |
|---|---|
| B1 `GraphFixtures` and existing source fixtures | Sealed rational and offset position graphs; exact coefficient/guard/branch/denominator/correspondence retention; nonowning upper chart boundary exclusion; invalid layouts, lifetime, budgets and cancellation. All 24 source tests or the same full source proof run. |
| L4 `ProjectionFixtures` | Disconnected and free auxiliary fibers; escaping witnesses (`x*q=1` excludes `x=0`); branched lifts; projected dimensions/components and exact membership; complete empty, zero/full prefix, indexed witness lifetime and independent limits/cancel. |
| L5 `GraphRelationFixtures` cases 0-8 | Ordinary CS; multiple auxiliary witnesses yielding one projected point; positive branch; free auxiliary not increasing parameter dimension; false and zero-W complete exclusions; guarded SSI curve including closed endpoints; actual plane-offset equations with exact `TUV=(1/4,0,0)`; both sources carrying auxiliaries with all four lifts retained. |
| L5 guard witnesses | Original equations, exact nonzero-W divisions and `W*E=G*Q+R` identities retained and verified. OR/NOT counterexamples do not admit the conjunction-only reduction. Wrong tuples are rejected by exact membership, not residuals. |
| L5 `failuresAndLifetime` / `GraphCheckpointAdmission` | Exact work/storage/depth thresholds, role/kind/foreign-field rejection, entry and terminal cancellation, original graph ownership and retained witness views after releasing the relation. |
| L5 `GraphDepthFixtures` | A valid tagged rational source has inherited depth 20 while normalization produces a zero law of depth 0. Resolution and result reuse at limit 19 must fail; the relation retains depth at least 20. |
| Existing L5 fixtures | Weighted/repeated/multiple-UV/closed-end/empty/continuous CS; folded SSI topology; original domains/lifetime; typed resource failures. Existing APIs/result types are unchanged. |

The L4 fixture source belongs to `L4TopologyVerification`; the L5 test package
links that same source through a test-only target. It does not make production L4
depend on L5. The isolated L2 target excludes three existing same-module source
transport bridges not consumed by this verifier; production L2 is unchanged.
No whole CADGeometry build is used as a substitute for these actual paths.

## Review findings and correction evidence

One scoped review and finding-specific confirmations closed these concrete gaps:

1. The offset graph exhausted the existing storage cap when every XYZ expression
   unnecessarily requested sign invariance. Compilation now selects only original
   predicate atoms, both W exclusions and equality laws. Existing nonzero-W exact
   division and a proved conjunctive-guard remainder reduce equations while keeping
   the original equations and identities. Case 7 succeeds within the same
   700,000,000-byte cap; no work/storage limit was raised.
2. Normalizing a canceled zero law erased source depth from the compiled theorem.
   `inherited-depth-red.log` records `input=20 normalized=0 rejected=false`.
   Sources/results now retain aggregate original/proof depth and admit it before
   resolution/reuse. `inherited-depth-green.log` and every final proof-failures run
   record rejection under limit 19.
3. Concurrent Native/WASM validation caused a Native case to exceed its one-minute
   test limit. Heavy lanes and test groups were isolated without changing that
   limit or the mathematical budget. The failed snapshot execution is retained in
   `superseded/concurrent-final-native`; earlier provisional evidence is also under
   `superseded` and is not counted as final success.

## State, ownership and target correspondence

| Logical state | Native / WASM / Embedded storage | Mutation / isolation | Lifetime |
|---|---|---|---|
| Original graph source, coefficient and parameter evidence | Same immutable `let` payloads and Sendable receipt on all targets | No shared mutation or target-specific conformance | Retained by graph receipt |
| Lifted selection, projected selection and component proof | Same immutable owners and indexed/range views | Query-local construction only | Retained by projection/result and lift views |
| Original equations, simplification identities and depths | Same immutable graph source/result | No shared cache or lazy mutable owner | Retained by L5 result |
| Admission and topology counters | Same noncopyable caller admission and local counters | Exclusive `inout`; no cross-task ledger | One query, cumulative across stages |

The changed production paths add no unsafe pointers, unchecked Sendable, raw
Embedded state, actor/Mutex substitution or platform-specific synchronization.
The final source audit classifies every `var` as a computed read-only view or
query-local construction variable; stored proof payloads remain immutable. Existing
source/solver owners retain their existing contracts. This is not a claim of
parallel runtime validation for unrelated owners.

## Final lane results

The generated table below and `audit.json` are the authoritative final execution
summary. Build timings describe reuse of the dedicated caches, not cold-build
performance. Runtime timings are verification costs, not a broad speedup claim.

| Lane | Result | Production inputs | Runtime | Evidence |
|---|---|---:|---:|---|
| [source-native](source-native/result.json) | PASS | 242 | Retained log | B1 evidence reused |
| [source-asan](source-asan/result.json) | PASS | 242 | Retained log | B1 evidence reused |
| [source-wasm](source-wasm/result.json) | PASS | 242 | Retained log | B1 evidence reused |
| [source-embedded](source-embedded/result.json) | PASS | 242 | 1.561s | Final direct run |
| [relation-native](relation-native/result.json) | PASS | 268 | 39.734s | Final direct run |
| [relation-asan](relation-asan/result.json) | PASS | 268 | 136.040s | Final direct run |
| [relation-wasm](relation-wasm/result.json) | PASS | 268 | 170.832s | Final direct run |
| [relation-embedded](relation-embedded/result.json) | PASS | 268 | 50.345s | Final direct run |

B0 `b1518779`, B1 `4e29afdd`, B2 `84497e56`. All final input and artifact
hashes match the committed implementation snapshot. Working branch:
`codex/original-graph-projection`. Main integration is outside B0-B2.
