# Lazy Original Coordinate Generator Verification

The exact coordinate fraction path requests its retained context generator only
when a canonical term has a positive exponent. Constant terms recurse through
original parent coefficients, and zero polynomials need no root. Numerator and
denominator share one local optional generator. Both original causal depth axes
are retained even when the destination omits the unused extension; source towers
remain owned by the transfer receipt. Limits, denominator division, selector
semantics and entry/final cancellation are unchanged.

## Behavioral evidence

| Scope | Result |
|---|---|
| Native, Address Sanitizer, normal WASM, Embedded WASM coordinate compile/link/runtime | PASS |
| Independent work256/storage8192 constant regression | PASS; work53, Native admitted536 bytes |
| Refined value/coefficient roots, zero, negative rational, reduced square, released input | PASS; exact values and retained tower/depth |
| Strict destination policy, shallow later query, work/storage exhaustion and cancel | PASS; explicit failure and usable retained operands |
| Parent-dependent coefficient, necessary nested roots, foreign nonrational base, repeated owner, N/N-1 work/storage | PASS |
| Native original issued-map/TUV composition | PASS; algebraic T, seams, distinct same-XYZ UV, complete exclusion, ordering and atomic failures |

The regression fails with the old producer at commit4226a1f7 by exhausting work,
then succeeds with the unchanged independent cap. The final proof asserts the
output field has no unused parent; it also retrieves the original L2 extension
from receipt.sources after the temporary producer leaves scope. The existing
pre-allocation storage regression remains in all four lanes.

Swift6.4.0 RELEASE and matching normal/Embedded WASM SDKs are fixed in the receipts.
Only the five-file coordinate bridge and the Native issued-map overlay compile.
Unchanged L0-L5, SourceIssuer and current Native domain artifacts are reused with
source/object checks. No full CADCore/CADGeometry/Kernel or L2-L6 target is rebuilt.
The final logging-only proof edit was relinked against unchanged compiled bridges
in Native/ASAN/normal WASM; finalProofCommands records those bounded commands.
Embedded uses the complete narrow verification command. The map composition
preceded that proof-only logging edit; its actual production premises are unchanged.

## Same-input Native Debug performance

| Fixture | Before median ms | After median ms | Work before / after | Admitted bytes before / after |
|---|---:|---:|---:|---:|
| Root-wrapped exact constant7 | 2.807125 | 0.012709 | 5652 / 53 | 129608 / 536 |
| Mixed exact values, count3 | 3.003500 | 2.737083 | 5983 / 5873 | 130224 / 130192 |
| Mixed exact values, count12 | 3.267709 | 2.812500 | 7625 / 7119 | 133040 / 132896 |
| Mixed exact values, count48 | 4.487625 | 3.823917 | 13970 / 11934 | 144200 / 143624 |
| Algebraic CS TUV assembly | 30.137000 | 26.759042 | 47305 / 47165 | 1199744 / 1199704 |
| Folded CS TUV assembly | 70.654125 | 67.481625 | 129609 / 129130 | 2863624 / 2863504 |

The same root-wrapped input is compared before/after, separately from baseConstant.
Five transfer repetitions use fresh ledgers in each process; the first sample is
retained in the reported median. Preparation precedes timing and exact comparison
follows it. These scalar timings are prepared-input transfer measurements, not
cold geometry-query timings. Three fresh-process stage runs preserve the full
DomainProof behavioral checks. stage-timing.patch adds timings to that existing
fixture rather than maintaining another copy. Stages are timed with ContinuousClock;
logging occurs after each timed call. Compile and run commands have30/60-second
limits and no optimization flag; unchanged lower products are Debug artifacts.

The constant path is about221x faster in this microcase. Work and admitted bytes
reduce deterministically. The unchanged L5 relation stages also vary in wall time
(e.g. algebraic585.815 ->551.117 ms), so the smaller TUV timing changes alone do not
establish an end-to-end CAD speedup. Necessary-root costs remain, and the folded
fixture is CS, not the unresolved general SSI closure fixture. No throughput or
performance guarantee for Release, normal WASM or Embedded is inferred here.
Admitted storage measures cumulative charged generation, not allocation counts,
copy counts or peak resident memory. The actual semantic suites cover portable
correctness, not portable speed. No measured case has increased work/storage;
small wall-time variation in unchanged paths is retained in the raw logs.

performance-receipt.json binds benchmark inputs, baseline commit/bridge hash,
current linked libraries, compile/runtime commands and measured medians. The
benchmark can be repeated with those checked cached products: copy
ScalarPerformance.swift into .build/performance-check, apply stage-timing.patch
to the recorded DomainProof input to produce StageProof.swift, then use the
recorded compile and runtime commands. Preserve the same query checks and flags.
Baseline source is recoverable from commit4226a1f7; final artifacts are tracked
by the adjacent verification receipts. Native/ASAN/normal-WASM/Embedded source
hashes and object/artifact hashes were checked after final execution.

## Scoped review and ownership

One aggregate review traces fraction storage through recursive polynomial
coefficients, generator retention, original division and L0 final publication.
No open finding remains: exact term powers decide dependency; parent fields are
imported after any necessary extension; the source/context/calculation/produced
depths are retained independently; no partially evaluated value escapes on error.
The public transporter and result protocol are unchanged. Existing source payload
admission remains before array construction. No unsafe code, lock, target branch,
callback or new allocation owner is introduced.

| Logical state | Native / ASAN | Normal WASM | Embedded | Lifetime / access |
|---|---|---|---|---|
| field, entries, bases | Invocation-local value | Same | Same | Exclusive synchronous transfer, no escaping mutation |
| optional generator | Local Optional value | Same | Same | Shared only by this numerator/denominator evaluation |
| source/output receipt | Immutable retained owners | Same | Same | Original inputs survive caller release |
| caller admission | Exclusive inout | Same | Same | One cumulative query budget; final checkpoint retained |

Review of changed files and the roots helper finds no hasFeature(Embedded),
canImport(Synchronization), unchecked Sendable or nonisolated(unsafe) state
substitution. All target-specific work is confined to existing verification flags
and SDK selection. The full public CS/SSI migration and seven requirements remain
separate unfinished work; this evidence closes only coordinate transport optimization.

Optimization commit60c47896 was independently fast-forwarded into the existing
integration worktree, then main from4226a1f7. All73 unique recorded source/proof
inputs match the integrated main exactly; all four final coordinate artifacts and
the Native domain/map artifacts retain their recorded hashes. No integration code
change or new proof premise was introduced, so existing runtime evidence is reused.
The unrelated retained publisher draft remains outside this commit and main.
