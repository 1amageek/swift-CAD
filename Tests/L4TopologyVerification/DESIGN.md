# Independent L4 Verification

## Purpose and Scope
Independent test package for actual L0-L4 sources. Parent: [L4](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactRealTopology/DESIGN.md).
## Responsibilities and Boundaries
Owns public behavioral fixtures and portable proof entry, not a production target.
## Related Designs
Uses the public L4 contracts and unchanged lower contracts linked from its parent.
## Architecture
Fixtures -> L4 -> L3/L2/L1/L0; source symlinks compile the real implementation.
## Contracts and Invariants
No upper CAD source, quota reset, approximate identity or fake receipt. Dedicated paths and external timeouts.
## Verification and Change Impact
Native/ASAN and normal/Embedded WASI execute success and failure fixtures; exact source hashes bind [implementation evidence](VERIFICATION.md). The source snapshot and target-specific runtime claims are recorded there.

## Closure Capacity Preflight Regression

`incidenceClosureCapacityPreflight` uses a complete two-cell selection with closure
capacity one. Its separate work-4 admission permits source retention/validation
but refuses traversal or closure construction. The issuer must report the existing
`closureLimit` rather than spend that admission on an impossible result. Existing
zero-selection, exact-boundary, lifecycle, inherited-depth and cancellation tests
retain the same limits and source inputs.
