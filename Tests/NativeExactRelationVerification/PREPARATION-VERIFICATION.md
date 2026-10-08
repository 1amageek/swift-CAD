# Native Preparation and Ordered Import

## Scope and Execution
The parameter-only Native CS/SSI path constructs authored X/Y/Z/W directly,
without interval jets, differential, normal or silhouette preparation. The legacy
OriginalRationalSurfacePolynomial consumes the same homogeneous issuer and keeps
its original native-token translations and all differential/publication work.
Native coefficient import populates one final L1 term array, sorts it in descending
slot order, and validates/retains it through ExactPolynomialOrderedConstructing.
The arbitrary-term constructor and all L0-L5 decomposition/topology remain intact.

The verified scope is the existing source-valid, finite, nonperiodic,
positive-weight, single-positive-span Native contract. Source degree zero remains
invalid. This is not a migration of legacy intersectionResult, a new shape family,
or whole-seven acceptance.

PreparationEvidence/run.json binds all 1,359 actual production compiler inputs
(64 CADCore, 1,295 CADGeometry), shared fixture hashes, runtime logs and portable
artifact hashes. Historical connection Evidence/ is preserved separately.
Compiler/SDK are Swift 6.4.0 release with its matching normal/Embedded WASM SDKs;
WASI Preview 1 runs under Node 24.19.0. Runtime guards remain 120 seconds.

| Execution lane | Evidence |
|---|---|
| Native | Five tests pass in 12.354s; unchanged legacy public smoke passes |
| ASAN | Preparation plus separately guarded original CS, SSI, failure and provenance groups pass |
| Normal WASM | Preparation and unchanged legacy smoke pass; each measured original public proof passes |
| Embedded WASM | Preparation and unchanged legacy smoke pass; each measured original public proof passes |

## Owned Behavioral Proof
- Weighted and nonclamped original laws match independent exact closed forms.
- Existing differential issuer gives the identical homogeneous coefficients.
- Invalid span and degree-zero source refuse explicitly; validation is not weakened.
- Ordered L1 input rejects wrong exponent dimension, negative exponent, zero term,
  unordered/duplicate exponent, foreign coefficient owner and insufficient work.
- Domain depth on both value/coefficient axes is inherited even for empty input.
- Terminal cancellation refuses publication after the final work callback.
- Nested scoped buffer-pointer comparison confirms identical input/result term
  backing; mutation/release of the caller array leaves the retained result valid.
  This is a backing-sharing proof, not an allocation census of the entire query.
- Zero storage budget accepts already allocated rational terms without recharging
  that same retained payload. Newly generated Native arrays and sort workspace
  are still admitted before generation/mutation.
- Original public CS/SSI proof checks exact membership, distinct UVs, empty coverage,
  complete folded topology, independent bounds, source lifetime and provenance.

## Resource and Performance Results
Admission counts measure cumulative generated payloads, not peak resident memory
or actual allocation count. Native fixed-input examples are:

| Public query | Work before -> after | Admitted bytes before -> after |
|---|---|---|
| CS weighted transverse | 831,607 -> 831,313 | 30,514,171 -> 30,505,479 |
| CS excluded selection | 2,232 -> 1,956 | 62,440 -> 55,068 |
| Folded SSI | 9,520,618 -> 9,520,022 | 371,107,969 -> 371,096,473 |

The folded result retains 45 selected cells, 108 incidence attachments and one
component. Source equality, caps, degrees and tolerances are unchanged. Preparation
savings are small relative to total folded algebra/topology work.

MeasurePreparation.py retains three fresh-process runs per target using the
unchanged original public fixture body. Times include startup, membership checks,
failure/provenance assertions and Node startup where applicable; they are not
individual query latency measurements. No compiler runs during measurement.

| Lane | Initial before median | Initial after median |
|---|---:|---:|
| Native | 20.841s | 22.078s |
| Normal WASM | 33.944s | 30.793s |
| Embedded WASM | 17.739s | 17.863s |

Native and normal WASM show considerable run variation. The initial sequence
alone does not establish acceleration or isolate a regression. Alternating
old/new comparisons in paired.json check the apparent Native/Embedded difference
without changing source, fixture or the before artifacts.

| Paired lane | Before median | After median | Individual after/before differences |
|---|---:|---:|---|
| Native | 20.579s | 20.693s | +0.61%, -0.04%, +1.27% |
| Embedded WASM | 17.875s | 17.754s | -0.77%, -2.40%, +0.37% |

The initial Native slowdown does not reproduce. Native paired differences stay
within the observed old/new sample ranges; Embedded changes have mixed signs.
This bounded experiment finds no consistent deterioration beyond observed run
variation, but does not establish whole-query acceleration or per-case latency
nonregression. The accepted change removes verified unnecessary preparation and
retained-buffer normalization with smaller admitted work/storage on the fixed
public cases. Large SSI acceleration and a measured heap/PSC improvement remain
separate work. There is no allocation/RSS or release-build speedup claim.

## Ownership and Integrated Review
| Logical state | Native / normal WASM / Embedded | Lifetime |
|---|---|---|
| Homogeneous source | Same immutable Sendable value, original source retained | Law construction / downstream source owner |
| Imported term array | Same invocation-local Array; COW retention at L1 boundary | Published polynomial owner |
| Admission | Same exclusive inout caller and checkpoints | Invocation, no reset or escape |
| L5 receipts | Same immutable source/coverage/topology owners | Public result lifetime |
| Ordered fixture counter | Noncopyable invocation-local ledger | Fixture invocation only |

One integrated review checks direct source validation, original span/translation
math, exact order/coefficient validation, generated-vs-retained storage, inherited
depth and terminal cancellation. There is no open scoped correctness finding.
No new shared mutable state, target-specific synchronization, unsafe production
memory or cache is introduced. Existing lower proofs are reused for unchanged
contracts; the new ports execute under all four actual production lanes.

## Operational Evidence
Full Native, ASAN, normal WASM and Embedded builds completed. Copied Clang PCM
caches encoded their prior absolute paths; only private relocated caches were
regenerated. cache-relocation.json hashes the retained raw failure and its concise
excerpt; that failed build is not pass evidence. Full Embedded WMO compilation
uses the communicated build-only 300-second watchdog and completed in 176.98s.
An initial degree-zero fixture assumption was corrected to preserve the existing
Geometry source-validation contract; its rejected run is retained separately.

## Main Integration
Implementation commit ad490916 was fast-forwarded from main 498c4367, with no
concurrent main changes or merge edits. All 1,359 compiled production hashes,
five shared fixture hashes and retained runtime log hashes match integrated main.
The unchanged byte snapshot reuses the four-lane evidence above; no redundant
full compilation follows the fast-forward. Main and the isolated implementation
worktree retain clean committed checkpoints. Existing outside-task unpushed main
history is preserved; it is not included in an automatic push.
