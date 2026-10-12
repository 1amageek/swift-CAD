# S-NATIVE-IDENTITY-COMPOSITION-01 Review

Verdict: **F1 OPEN — current-source completion evidence is incomplete.** The admitted binaries satisfy the fixed behavioral oracle and controls. No geometric or identity-semantic counterexample was found. The missing source-at-compile binding below prevents approving the requested current-source conformance outcome. One comprehensive review was performed; no new build, solver execution or lower proof was requested or run.

## F1: missing source-at-compile binding for the actual composition issuer

**Violated completion condition:** the current original restriction/symmetry/composition implementation must be bound to the actual reused compiler product that executes the fixed public input. Current file equality and a compiler input pathname alone do not establish which bytes the compiler consumed.

**Concrete input and affected decision:** the fixed original fold and same-owner `E/R/S/I/C` sequence below execute through reused DI. The Native assembly actually links `.build/m6-refinement-repair/native/65f7d95a6ab64322a1c41b8e1cdd8816/build/arm64-apple-macosx/debug/DI.build/DefaultOriginalParameterIdentityIssuer.swift.o`. This object supplies the restricted/symmetric/compose methods consumed by the public query. The failure is the current-source completion claim for this input, not a reproduced wrong geometric answer.

| Evidence | Observed binding |
|---|---|
| Actual Native issuer object | SHA-256 `d59b4e19d0f41c974a77b832c1dc8bb63aa4677ad732a4ad89c327e1326ada6a`; existing bytes match |
| Existing generation receipt | `Tests/OriginalNativeConsumerIntakeVerification/Evidence/native-query-field-accepted/generation.json`, SHA-256 `15a683225083abf1b743dca11ab553443f3fd33f953231eb526f27dadb6b1a82`; successful Swift 6.4.0 build of the actual package and object recorded |
| Build mapping | `build/debug.yaml`, SHA-256 `32bc97549615e1ed01518938b9ce0f95088688251927b2c960066e6c77905e27`, plus source/output mappings identify the package input and object paths |
| Generation canonical source input | `DefaultOriginalParameterIdentityIssuer.swift` recorded as SHA-256 `18c263e4ea9eb4481f9a3c882d8d5e8d2a2fe983af3641dd29e7d6d102fc7b1b` |
| Current production and present package input | Both byte-identical SHA-256 `71589c394b50fd0d564e0639e65c96e22bed5345fcd36146be4137713ec70efa`; current methods at lines 117–175 |
| Missing premise | No existing compile-time hash for the package's `71589c39…` bytes, or exact recorded `18c263e4… -> 71589c39…` adaptation binding, was located in the bounded check. The evidence owner independently confirmed this absence. |

The actual package input path is `.build/m6-refinement-repair/native/65f7d95a6ab64322a1c41b8e1cdd8816/package/Sources/DI/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift`. Its current bytes and the YAML path do not supply the missing compile-time byte binding. A separate combined-source copy containing these bytes also does not bind them to this DI object. The composition manifest has no original-path/source-hash tuple for this issuer body. Catalog integration source hashes must not replace compiler evidence.

**Minimum resolution:** retain and link an existing exact compile-time package-source/adaptation receipt if available. If unavailable, distinguish the successful retained-binary observation from current-source acceptance and leave the current-source completion condition open. No broad/lower rebuild or repeated runtime is prescribed by this finding. A correction needs only one focused recheck of this binding; all other reviewed obligations are closed.

## Fixed contract and actual source path

The source is the original one-chart `G(u,v)=(u²,v,0)` on closed `D=[-1,1]²`, bound and prepared once. Both ordered covers retain the same source/frame/scalar owner.

```text
E: A -> B, A={-1}x[-1,1], B={1}x[-1,1]
  -> R: restrict E by left V[-1,1/2], right V[-1/2,1]
       = A_J -> B_J, closed J=[-1/2,1/2]
S: symmetric E = B -> A
  -> I=compose(S,R): B_J -> B_J
  -> C=compose(I,S): B_J -> A_J
  -> public contacts(raw, excluding:[C]) + authored diagonal
  -> original-ring residual predicate -> retained L4 pullback -> result
```

Read the applicable AGENTS and PROGRESS contract, owning identity/self-contact designs, finite coverage definition, actual issuer/selection operations, fixture, runner and preserved receipts. Current source restriction intersects both cuts and pulls back the right cut; symmetry inverts the affine word without changing kind/depth/count; composition intersects the identical middle frame, pulls that support back and retains both parents. Exact intersection rejects an independently prepared equal-field/equal-source middle frame. The expected current C word is identity permutation/gains and offset `(-2,0)`, kind `declaredSharedBoundary`, depth 3 and proofCount 5. This source reading is kept separate from F1's unresolved compiler-byte correspondence.

The unchanged self4 consumer/result path was already source-reviewed and is hash-identical to the admitted whole-edge self4 assembly. It adds only the authored diagonal, consumes both scoped identity selections and the affine word, uses the caller's exclusive noncopyable admission, retains typed failures and checks cancellation before publication. The immutable result retains the original relation, covers, inverse maps, identity parents and refinements. This cell adds no production state or implementation.

## Behavioral assessment of admitted products

The independent complete residual is

`{ (u,v,-u,v) : u in [-1,1], u != 0, v in [-1,1], NOT(u=1 AND -1/2<=v<=1/2) }`.

| Obligation | Result and precise scope |
|---|---|
| Complete raw/residual relation | Every terminal is tested with exact sign-invariant iff for raw `u²-s²=0, v-w=0`, then non-diagonal and complement of the closed reverse-J exclusion. Counts 45/2409/31 are measurements, not proof. |
| Closed J and direction | Actual E/R/S/I/C relation views verify both exact closed scopes/words/depth/count. Forward edge remains at every tested V; reverse edge is removed at both J endpoints and interior, retained at V corners. |
| Original correspondence | Raw source cells/order, coordinate map, all terminal alignment, ordinal ranges and excluded `-1` are checked. Existing checked L4 correspondence is reused unchanged; no independent unique-raw-cell reclassification is claimed. |
| Proof kind and owner | Kind remains positional declaredSharedBoundary. Equal-field/same-source independently prepared middle frame throws foreignOwner. Position equality does not authorize derivative or normal equality; no germ API execution is claimed. |
| Readmission | C accepts exact transport depth 3/proofCount 5 and separately refuses depth 2/count 4 with matching typed causes. |
| Lifetime | After construction E/R/S/I/C and query-local owners leave scope, retained result supports relation view, identity decision and tuple membership. No arbitrary-schedule/concurrent-reader claim is added. |
| Cancellation | Entry cancellation and cancellation at calibrated last retainStorage call both throw cancelled; final checkpoint prevents partial success. |
| Resources | Independently prepared query succeeds at target-specific exact N and separately rejects work N-1 and storage N-1. Preparation and independent oracle ledgers are excluded. |

| Target | Query work N | Query storage N |
|---|---:|---:|
| Native / ASAN | 15,457,625 | 480,861,813 bytes |
| Ordinary / Embedded WASM | 15,357,024 | 243,513,853 bytes |

Image `(0,1] x [-1,1] x {0}`, parameter/image dimension two and fiber dimension zero are mathematical oracle meanings. The public self result does not expose image/fiber DTO fields. This is not an embedding certificate, whole-query workflow N claim, or general paired/nonlinear composition completion.

## Ownership and platform matrix

| Logical state | Native / WASM / Embedded storage and access | Release/isolation |
|---|---|---|
| Source/frame/proof parents and published result | Same immutable retained owners and unconditional Sendable contracts | Result owns all required lifetimes; read-only queries |
| Compiler temporaries and query/oracle ledgers | Invocation-local state, exclusive `inout` admission on every target | No shared mutable state or target-specific raw-state substitution |
| Fixture publication accounting | Local noncopyable PublicationAdmission/ledger; same mutation methods | Synchronous exclusive access; cancellation via owned ledger |
| Fixture entry | Nonisolated synchronous proof helper; Embedded direct if-let getenv decode | No Optional.map actor callback; accepted logs have no actor warning |

Accepted paths retain the same synchronization/ownership contracts. No real parallel-thread, actor scheduling or shutdown-race guarantee is inferred. Fixed Swift 6.4.0 commands select matching ordinary/Embedded SDK profiles; Embedded WMO and actual runtime are preserved. No target-only Sendable weakening or lock removal was introduced.

## Packet binding and acceptance limits

| Artifact | SHA-256 |
|---|---|
| Summary | `c5a7ec090e8ab92dce965418b6998d1bc2412195cb2c99da2e48ebcc7102627e` |
| Manifest | `8771ca0838f56aea0ba37f966ea0c6ac3accaa4515ac6f295bee14fcccb79224` |
| VERIFICATION | `d6de0197522a1802acf8a376d1f01574467d6e0fca820cc1d411e43c82100401` |
| Final fixture | `a97ee6c0cb20c8e5c54f8b2945bcaee32eb005757d22036fccf9e02c1880a7fe` |
| Runner | `6f4174b7e28ee780e1aae5406cdf4cc9c8414dad94993e18e722b21872aeeca1` |

All 980 unique retained references and 1,317 original-path/hash tuples match their saved size/hash bindings; own CAS is 807 files/8,580,839 bytes. Current fixture/runner match their archived copies. The initial Native complete fixture's prepare/identity/invariants/oracle bodies are byte-identical to the final versions and its direct public query has the same arguments. Final durable publication is a path move of the accepted prototype, with no replay.

Five accepted parts comprise initial Native complete plus Native five control/resource groups, and all six groups on each of ASAN, ordinary WASM and Embedded. All selected runs have exit zero, no bounded stop and no remaining owned descendant; raw logs contain expected behavioral markers with no actor warning, ASAN error or observed stop. Receipt pre/post admission agrees. The nonisolated-main compile diagnostic remains false and supplies no runtime acceptance.

The four current self4 source hashes, their exact previously compiled receipts/module products and the actual fixture proof binaries match across targets. Fresh production/source/upper compilation is zero and reused self4 is four; retained Native32/source5/SourceGeometry/DI/lower products remain premises rather than fresh proof. The previous cell's geometry result is not substituted for this cell's independent oracle. These successful checks do not close F1 for the additional DI issuer source-at-compile premise.

Review, coherent commit, protected-main integration and delivery remain root-owned. No general M5/M6, embedding, ordinary ruled dispatch, M7 XYZ, whole-seven or full87 completion is asserted.
