# Capability Ledger

This ledger is the development source of truth for the currently supported
kernel capabilities. A capability is complete only when its input contract,
exact output contract, typed failures, public operation path, and focused
fixture are all present.

| ID | Capability | Exact output | Current state | Tolerance contract | Public API | Fixture / evidence |
|---|---|---|---|---|---|---|
| `GEO-CURVE-001` | Analytic line, circle, arc, and ellipse evaluation | `Curve3D` with domain, derivatives, and curvature | Implemented in `CADGeometry` | Explicit `ModelingTolerance` | `AnalyticCurve3D` | `GeometryKernelTests` domain and derivative invariants |
| `GEO-CURVE-002` | Rational NURBS curve evaluation | Rational curve with validated knots and positive weights | Implemented in `CADGeometry` | Explicit `ModelingTolerance` | `RationalBSplineCurve3D` | `GeometryKernelTests` knot, span, weight fixtures |
| `GEO-SURFACE-001` | Analytic plane, cylinder, cone, sphere, and torus evaluation | Surface position, derivatives, normal, and UVN frame | Implemented in `CADGeometry` | Explicit `ModelingTolerance` | `AnalyticSurface3D` | `GeometryKernelTests` differential geometry fixtures |
| `GEO-SURFACE-002` | Rational NURBS surface evaluation | Rational surface with validated parameter domain | Implemented partial in `CADGeometry` | Explicit `ModelingTolerance` | `RationalBSplineSurface3D` | `GeometryKernelTests` derivative and normal fixtures |
| `TOPO-BREP-001` | Validated coedge B-rep | Manifold, oriented, watertight B-rep | Existing partial implementation | Explicit validation tolerance | `BRepModel`, `ValidatedBRepModel` | B-rep loop, shell, pcurve, volume diagnostics |
| `TOPO-LINEAGE-001` | Stable subshape lineage across recomputation | Deterministic `SubshapeID` mapping | Implemented partial; split/merge parents are deterministic | Explicit evaluation tolerance | `SubshapeID`, `TopologyLineage` | Incremental, split, and merge lineage fixtures |
| `MODEL-EXTRUDE-001` | Profile extrusion | Exact analytic or NURBS-backed B-rep | Existing limited implementation | Explicit feature tolerance | `CADCommand`, `FeatureRequest`, `DocumentEvaluator` | Extrude solid, sheet, orientation, and failure fixtures |
| `MODEL-FEATURE-001` | Shared feature evaluator contract | Validated B-rep, sheet, or curve output | Partial; unsupported cases fail closed | Explicit feature tolerance | `FeatureRequest`, `KernelError` | Feature request and diagnostic fixtures |
| `MODEL-BOOLEAN-001` | General union, difference, intersection, and slice | Validated exact B-rep | Fixed phase pipeline with orthogonal-box backend; general intersections remain gated | Explicit Boolean tolerance | `BooleanPipeline`, `KernelError` | Operand, classification, and topology fixtures |
| `MODEL-FILLET-001` | Edge fillet and blend | Trimmed exact surfaces with lineage | Planned | Declared but not implemented | `FeatureRequest` (capability-gated) | Radius, continuity, setback, and failure fixtures |
| `MODEL-SHELL-001` | Shell and thicken | Validated offset surfaces and topology | Planned | Declared but not implemented | `FeatureRequest` (capability-gated) | Open-face, singularity, and thickness fixtures |
| `API-PARITY-001` | Shared UI, Builder, and Agent operation path | Identical command and evaluation result | Partial | Command carries explicit tolerance at apply/evaluate boundary | `CADCommand`, `CADCommandApplier`, `CADPipeline` | Codable command parity fixtures |
| `EXCHANGE-STEP-001` | Exact STEP geometry/topology exchange | Curves, surfaces, pcurves, topology, units | Exact writer gate is explicit; mesh fallback removed | Exchange resource limits plus modeling tolerance | `STEPExchange.write(brep:)`, `STEPExchange.import` | Resource-limit and mesh-rejection fixtures |
| `EXCHANGE-IGES-001` | Exact IGES geometry/topology exchange | Curves, surfaces, trims, topology | Exact writer gate is explicit; mesh fallback removed | Exchange resource limits plus modeling tolerance | `IGESExchange.write(brep:)`, `IGESExchange.import` | Resource-limit and mesh-rejection fixtures |

Unsupported cases must be represented by stable typed error codes and must not
silently downgrade to a mesh approximation.
