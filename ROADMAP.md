# Development Roadmap

This roadmap describes work that is not registered as a current kernel
capability. An item moves to the Capability Ledger only after its request,
evaluator, exact output, typed diagnostics, and focused fixture are present.

## Modeling sequence

1. Extend exact Sweep beyond the registered straight-path linear-scale and circular-revolve path-normal subsets to general exact moving frames, twist and curved-path scale transforms, guide-constrained surfaces, and exact round corner transitions
2. General curve/surface intersections and general Boolean operations
3. Expand setback corners, G1/G2 blends, and chamfer beyond their registered orthogonal constant-radius envelopes
4. Expand shell, thicken, draft, face move, edge move, and vertex move beyond their registered exact envelopes
5. Radial, grid, and curve-driven patterns; expand linear pattern beyond separated line-only planar solids
6. General curve/surface offset, trim, extend, and match

## Kernel completion

- Mandatory p-curves and curve-on-surface residual validation
- Curved-shell orientation, watertightness, and exact volume validation
- Provenance-first stable selection with geometry-signature fallback
- DOF/residual/Jacobian constraint solving with forward differentiation and
  Levenberg-Marquardt iteration
- Exact STEP and IGES topology reconstruction and round-trip validation

## Later milestone

Technical drawing remains outside the current critical path and is tracked as
M7 after modeling, stable selection, constraints, and exact exchange gates.
