# Coordinate Source Buffer Storage Repair

The owned base-context source array is admitted before materialization. The L0
transfer receipt shares its backing; reusing a base owner does not allocate or
readmit that source buffer. Arithmetic, exact identity, retained root selectors,
value/coefficient depth, immutable ownership and failure contracts are unchanged.

The regression invokes the public coordinate transfer with one rational value.
Its cap is twice the target OriginalExactScalar stride minus one byte, independent
of execution-measured resource totals. An exclusive admission observer requires
failure at the second storage request, after exactly one work unit, with only the
output array payload retained. This rejects before lower scalar transfer begins.
The source at 591de4c3 fails this test at Proof.swift:45; the repaired source passes.

| Verification | Result | Wall time |
|---|---|---|
| Native coordinate compile/link/runtime | PASS | 3.719 s |
| ASAN coordinate compile/link/runtime | PASS | 6.542 s |
| Normal WASM coordinate compile/link/runtime | PASS | 5.974 s |
| Embedded WASM coordinate compile/link/runtime | PASS | 19.018 s |
| Current Native issued-domain compile/link/runtime | PASS | 17.085 s |
| Current Native issued-map/TUV compile/link/runtime | PASS | 27.300 s |

All lanes use Swift 6.4.0 RELEASE; WASM uses its matching normal/Embedded SDK.
Each coordinate run also executes retained roots, fractions, nested extensions,
nonrational base transport, repeated owners, exact work/storage boundaries and
cancellation. Native composition additionally executes algebraic T, closed seam
incidences, distinct UV at one XYZ, exact ordering, retained domain depths,
complete exclusion, atomic mixed/positive rejection and resource limits.

Existing immutable L0-L5 artifacts are reused with checked source/object manifests.
Only the coordinate bridge and independent domain/map overlays are compiled.
No CADCore, full CADGeometry, Kernel, or L2-L6 target is rebuilt. The current domain
and map overlays include the main family-query changes through 96ab5619.
Runtime commands are bounded by the existing 120-second per-command timeout and
outer 60/90/150-second process guards. No whole public CS/SSI migration is claimed.

The adjacent receipts retain copied-input hashes, actual compile/link/runtime
commands, target/SDK selection, lower artifact provenance and artifact hashes.
Logs retain the red failure and each successful lane. A single scoped review of
the source addition, independent regression and unchanged consumers has no open
finding: all mutable state remains invocation-local, with no target-specific
synchronization or Sendable change. The updated ExactRealRoot design owns the
allocation admission contract; the existing coordinate proof owns its test.

Repair commit 5a1eedb7 was fast-forwarded into main from 591de4c3. All 73
unique retained source/proof input hashes match the resulting main exactly. The
integration introduces no additional source change; unchanged verification
premises are reused instead of rerunning the same runtime proof.
