# Analysis Log

## 2026-07-23T05:28:40+09:00

- Created a new current-state analysis session; retained the 2026-07-12 session as immutable historical evidence.
- Verified clean revision `a268a4ee21a3b7c4f224a798bfbeb1ed5bad8d83` before new work.
- Ran `Scripts/check_goal_contract.py`: consistency passed; completion remained 0/8.
- Ran `Scripts/check_capability_ledger.py`: 55 capabilities, 52 envelopes, 422 bindings.
- Inspected the Geometry capability catalog: 5 supported and 2 partial entries.
- Used `skltn` to locate the general torus-torus intersector, certified procedural curve, public dispatcher, and regression tests; opened each implementation path in original source.
- Initial hypothesis: the meridian-root condition can be a coordinate singularity rather than a singular 3D intersection. Confidence 0.65 pending direct mathematical and runtime evidence.

## 2026-07-23T05:42:22+09:00

- Tested a whole-surface analytic-to-rational B-spline fallback for the orthogonal congruent torus fixture; the focused test reached its five-minute limit and failed.
- Rejected that fallback as a production solution and removed the exploratory test from the working tree.
- Derived the exact congruent-centered factorization: the difference of the torus implicit equations is the product of the two axis-bisector plane equations.
- Identified four genuine second-order branch-contact points in the orthogonal fixture, disproving the stronger interpretation that every observed failure is only a coordinate singularity.
- Selected a specialized certified bisector-plane representation as the next implementation slice; Geometry remains incomplete and no completion claim is made.

## 2026-07-23T06:00:00+09:00

- Implemented the exact congruent-centered torus factorization into both axis-bisector planes.
- Preserved four mixed closed branches, exact dual pcurves, second-order branch contacts, deterministic operand/axis-sign invariance, residual certification, and strict decode-time branch reconstruction.
- Verified the focused torus-torus suite (5/5), full CADGeometry suite, capability contract (10/10), and capability ledger (55 capabilities, 53 envelopes, 424 bindings).
- Committed and pushed checkpoint `5990bba95f4bc63109ae9f53f22175821d036ff8` (`Support congruent torus intersection graphs`).

## 2026-07-23T06:19:30+09:00

- Audited the former plane-torus inner-support singular diagnostic and derived the actual locus: two self-loop branches sharing one nodal contact with four distinct half-branch tangents.
- Implemented arithmetic-gated inner-support certification, bounded branch domains, exact one-sided first/second double-root differentials, exact 3D evaluation, mandatory dual pcurves, residual certification, and strict decode reconstruction.
- Added axial and oblique nodal graph tests plus nearby non-nodal rejection guards; the full focused `SurfaceSurfaceIntersectionTests` suite executed 16 tests and all 16 passed.
- Retained typed failures for unresolved higher-order cases and did not add mesh, sampled, or silent fallback behavior.
- Ran the full CADGeometry suite successfully in 301.912 seconds.
- The first capability-contract build exposed six non-exhaustive switches in the downstream analytic-pair Topology area integrator. Implemented the new branch mappings and added an explicit typed unsupported boundary because its existing regular-pcurve proof cannot certify the nodal double root.
- Verified the analytic-pair Topology suite (9/9) and capability contract (10/10) after the downstream correction.

## 2026-07-23T07:10:00+09:00

- Re-audited the next undeclared `GEO-INTERSECTION-002` envelope from original source after structural scan.
- Traced parallel-offset torus-torus data through the interval certificate, procedural differential, analytic-pair lift, dual pcurves, derived B-spline cache, and intersection kind.
- Derived the rejected generator-tangency locus as four bounded self-loop edges grouped at two nodes, rather than an empty or unrepresentable singular result.
- Selected an arithmetic-gated nodal certificate and exact one-sided double-root differential as the root implementation; nearby non-nodal inputs and all undeclared tangencies must not be falsely admitted.

## 2026-07-23T07:15:00+09:00

- Implemented ENV-055 as four bounded mixed nodal self-loop edges at two certified contacts, including exact one-sided first/second derivatives, dual pcurves, deterministic operand/rotation behavior, and strict Codable reconstruction with tamper rejection.
- Corrected the derived-spline construction to use bounded rather than periodic endpoint differencing for nodal self-loops; this preserves the distinct half-branch tangents and removes the measured residual violation at the contact.
- Verified the focused parallel torus-torus suite (8/8), capability contract (10/10), capability ledger (55 capabilities, 55 envelopes, 432 bindings), ontology validator (19 Factor nodes, 6 groups), and goal contract consistency (still not achieved, 0/8).
- In the full CADGeometry run, every new nodal test passed. The pre-existing `GeneralConeTorusSurfaceIntersectionTests/operandOrderPreservesDeterministicThreeDimensionalCurves()` alone reached its four-minute time limit under parallel suite load. A correctly matched isolated rerun passed in 141.963 seconds; the earlier zero-test filter attempt was discarded from evidence.
