# Public CS review fixes

## Scope and source identity

The source baseline is main `75f3a99a20f988f61529db7a37d88f9474b1949a`.
`receipt.json` binds the actual compiled inventories, source SHA-256 values, eight raw
proof/smoke products, logs, SDK identities and the retained integration receipt.
Only the complete CS candidate ceiling, migrated smoke assertions and corresponding
contracts are changed. Lower L2/L3 proofs and unchanged inputs reuse their retained
evidence. Full seven-requirement completion remains 1/7.

## Counterexample and correction

On closed unit domains, C(t)=(t,0,0) and
S(u,v)=(u,(v-1/4)(v-3/4),0) have two continuous branches.
Before the fix, the regression linked against the pre-fix Geometry product exited
1 with `invalidEvidence`: maximumCandidateCount=1 incorrectly succeeded.
The shared publisher now checks selected cells and connected components before
numerical publication, in addition to the existing isolated point ceiling.

Both ordinary and caller-admitted public routes reject ceilings 1 and 5 with
resourceLimitExceeded. Ceiling 6 preserves six selected cells and two components;
exact TUV membership includes v=1/4 and v=3/4 and excludes v=1/2.
The discrete route reports nonDiscreteIntersection. No partial success, changed
query limit, new solver or repeated decomposition is introduced.

The existing portability smoke now checks retained L6 point owners, exact sample
parameters, selected-cell identity and foreign-handle rejection. CS TUV is
(1/2,1/2,1/2); SSI UVUV is (0,0,0,0). Empty results retain all three/four closed
unit parameter domains and complete exclusion. Native and normal WASM preserve
codec/source roundtrip checks. Existing ruled/affine ownership, independent limits,
final-storage failure and terminal cancellation checks remain intact.

## Runtime verification

| Lane | Candidate limits, both routes | Existing public CS and weighted contact | Existing portability smoke |
|---|---|---|---|
| Native arm64 | PASS | PASS | PASS |
| Native ASAN | PASS | PASS | PASS |
| Normal WASM | PASS | PASS | PASS |
| Embedded WASM | PASS | PASS | PASS |

Native's full 12-test suite passed before the fixture-only process-selector split.
Production code was unchanged afterward. The final fixture retains ceiling 1/5/6
assertions and removes only redundant ceiling 2; both selectors were rerun against
current compiled sources on all four lanes. ASAN, normal and Embedded also reran
the existing CS classification/mixed proof group. Every runtime/test process has
a 120-second deadline. The combined ASAN regression initially exceeded that
external deadline; separate ordinary/admitted proof processes then passed in
about 99/89 seconds without changing any per-query work, storage or depth limit.

Swift 6.4.0 release and matching normal/Embedded SDKs are used; WASM executes on
Node 24.19.0 WASI Preview 1. Embedded is raw Onone with required WMO. The first
Embedded smoke link omitted the Unicode archive already required by the parent
smoke design and failed. The existing recipe was then applied with the matching
SDK archive in receipt.json; compile/link/runtime passed. Package configuration,
SDK contents and String semantics were not changed. Both failed-attempt logs are
retained alongside successful replacements and are not counted as success.

## Ownership, review and integration

| State | Native / normal WASM / Embedded contract |
|---|---|
| Retained relation and cells | Existing immutable owner plus index/view |
| Query ledger | Existing exclusive inout admission, unchanged accounting |
| Publisher result ceiling | Common checked count guards before publication |
| Proof sample and coefficient owner | Retained exact source and field |
| Shared source configuration | Existing Mutex storage and isolation unchanged |

The correction adds no mutable shared state, allocation or unsafe boundary.
The scoped review found no remaining violation of the modified contract.
Actual parallel WASI execution and full-seven/full-87 completion are outside
this evidence. Latest-main composition is checked by committed source hashes;
unchanged code is not rebuilt solely because its Git branch label changes.
