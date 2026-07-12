# Development Roadmap

This roadmap describes the replacement sequence for the pre-v1 kernel. It is
ordered by dependency and correctness, not by the number of public feature
cases.

## M0 — Development contract

- Remote package resolution from a fresh checkout.
- Token-aware Swift policy checks and bounded Xcode test commands.
- Capability ledger as the current support source of truth.
- Pre-v1 source format with no migration or compatibility layer.
- Shared `CADCommand`, typed `KernelError`, capability catalog, and topology IDs.

## M1 — Geometry foundation

- Analytic line, circle, arc, ellipse, plane, cylinder, cone, sphere, and torus.
- Rational NURBS curves and surfaces with domains, knots, weights, derivatives,
  curvature, and UVN frames.
- Explicit tolerance propagation and robust predicates.
- Analytic and NURBS intersection contracts with residual validation.

## M2 — Topology foundation

- Vertex, edge, coedge, loop, face, shell, and body tables.
- Exact 3D curves and face-local pcurves on coedges.
- Loop, manifold, watertight, orientation, and volume validation.
- Explicit sewing, classification, healing requests, and topology lineage.

## M3 — Stable editing semantics

- `SubshapeID` and provenance-based `TopologyLineage`.
- Deterministic split/merge matching and ambiguity diagnostics.
- General sketch constraint solving with DOF, Jacobian, residual, and status.
- Shared selection, measurement, projection, and diagnostic queries.

## M4 — Modeling slices

1. Primitive, extrude, revolve, and general Boolean.
2. Sweep, loft, bridge surface, patch, and PolySpline.
3. Fillet, chamfer, blend, shell, thicken, draft, and direct topology edits.
4. Linear, radial, grid, and curve-driven patterns.
5. Curve/surface offset, trim, extend, and match.

Every slice must complete source IR, evaluator, topology validation, lineage,
Builder, Agent, persistence, and focused fixtures before the next slice starts.

## M5 — Operation parity

- UI, Builder, and Agent use the same Codable `CADCommand`.
- Capability discovery precedes command application.
- Results include revision, generated subshapes, lineage, and diagnostics.

## M6 — Exact CAD exchange

- STEP and IGES map exact curves, surfaces, pcurves, trims, topology, units,
  and placements.
- USD, STL, OBJ, GLB, and 3MF remain explicit mesh exchange paths.
- External fixtures, round-trip checks, resource limits, and third-party
  validation are required.

Technical drawing output is intentionally outside this roadmap and belongs to
a later M7 design.
