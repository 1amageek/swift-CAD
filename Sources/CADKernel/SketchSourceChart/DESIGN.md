# Sketch Source Chart

## Purpose and Scope
This component owns source sketch curve and profile extraction under the authored native plane chart. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
CADIR owns sketch entities, expressions, constraints and the optional authored plane U direction. CADGeometry owns the exact Plane3D parameter basis. This component owns world-space curve/profile construction after parameter resolution and constraint solving; it never remaps constraint coordinates to imitate a chart change.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | SketchCurveExtracting / SketchProfileExtracting | Source extraction | Existing output validation remains required |
| [Imported Source Translation](../../CADIR/ImportedSourceTranslation/DESIGN.md) | coordinates with | translated explicit sketch plane | Local source coordinates stay authored | Native U direction must be consumed |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | Plane3D.parameterBasis | One exact chart authority | Nil direction preserves legacy basis |

## Architecture
```text
sketch source -> resolved local entities / solved constraints
    -> authored plane native U,V -> exact world curves / profiles
        -> existing output admission
```

## Contracts and Invariants
Default XY, YZ and ZX retain their existing native axes. Explicit planes consume their authored U direction when present, otherwise the existing deterministic legacy basis. Both curve and profile extraction use the same geometry-owned basis. Source entity IDs, expressions, local coordinates and constraints remain unchanged.

## Verification and Change Impact
Deferred evidence includes translated default planes in every direction, constrained and parametric sketches, authored rotated U directions, curved/spline entities, curve/profile agreement and invalid chart rejection. Recheck source translation and all section consumers when the chart contract changes. Source edits are not runtime evidence.
