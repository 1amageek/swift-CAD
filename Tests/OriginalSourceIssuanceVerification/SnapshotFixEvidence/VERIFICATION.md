# Compiler Input Snapshot Fix

## Scope
Fix the P2 copy/hash race identified when reviewing implementation `5418013a`.
Production Swift sources remain byte-identical to that implementation. This
evidence covers the shared Python runner boundary, not additional issuer families,
public intersection queries or main integration.

## Invariant and Implementation
`VerificationInputs.copy_input` reads each source or proof once. Those captured
bytes generate both the compiler copy (with an import-only prefix if required)
and its receipt hash. `require_unchanged_inputs` checks originals against those
captured hashes before publication. The runner uses these functions for issuer
overlays, consumer overlays and proof input; it no longer hashes originals anew
after copying to establish compiler-input identity.

## Behavior
Four deterministic Python regressions pass: source-overlay and proof edits at
the copy write boundary are rejected; unchanged overlay and proof inputs pass,
and subsequent edits are rejected. Each test verifies exactly one source read
during capture, exact copied bytes and the captured hash. Mixed newline bytes
remain unchanged. Tests exercise the same helper and guard used by the runner.

The actual Native source-only runner passes all five Coons/traversal groups with
Swift 6.4.0 in 12.856 seconds. All 83 copied payloads, recorded hashes and current
originals match. Existing validated Geometry modules and verified archive payloads
are reused; no upper target is rebuilt. Python regressions use a 30-second guard;
the Native runner uses a 120-second guard.

## Evidence and Review
[receipt.json](receipt.json) binds the three changed/new Python scripts, all 83
compiled inputs, Native artifact, runner manifest and retained logs.
[python.log](python.log) and [native.log](native.log) record commands, success and
elapsed time. The finding confirmation checks that the old post-copy digest path
is removed and that later edits cannot replace the captured compiler-input hash.
No scoped finding remains.

The existing four-lane Swift evidence at
[TraversalEvidence](../TraversalEvidence/VERIFICATION.md) remains valid for
unchanged geometry. ASAN, ordinary WASM and Embedded were not rerun for this
Python-only fix; the shared runner helper regressions and actual Native execution
establish this fix's scope without claiming new target runtime evidence.
