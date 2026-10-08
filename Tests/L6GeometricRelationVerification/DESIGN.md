# L6 Independent Verification

## Purpose and Scope
Verify production L0-L6 without building CADGeometry or higher modules.

## Responsibilities and Boundaries
Own actual pullback, image/fiber, ownership and admission behavioral evidence.
Upper source extraction and legacy public publication are not proved by this package.

## Related Designs
Parent/test owner: [L6](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactGeometricRelation/DESIGN.md).
Depends on symlinked production sources L0-L6; never copy or mock solver algorithms.

## Architecture
```text
Production L0 -> L1 -> L2 -> L3 -> L4 -> L5 -> L6 -> tests/proof
```

## Contracts and Invariants
Retain original identity, full exclusion, all correspondences and atomic failures.
No tolerance/resource increases or claims from compile alone.

## Verification and Change Impact
Bounded native/ASAN/normal/Embedded runs with timeout and a fixed source snapshot.
