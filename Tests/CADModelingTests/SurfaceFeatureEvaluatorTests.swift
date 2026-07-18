import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact surface modeling")
struct SurfaceFeatureEvaluatorTests {
    @Test(.timeLimit(.minutes(1)))
    func bSplineSurfaceProducesValidatedTrimmedSheetAndGeneratedLineage() throws {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .bSplineSurface(BSplineSurfaceFeature(
                surface: BSplineSurface3D.cubicBezierPatch(
                    bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
                    bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
                    topRight: Point3D(x: 2.0, y: 1.0, z: 0.5),
                    topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
                ),
                outerTrimDomain: BSplineSurfaceTrimDomain(
                    uLowerBound: 0.2,
                    uUpperBound: 0.8,
                    vLowerBound: 0.1,
                    vUpperBound: 0.9
                )
            )),
            outputs: [FeatureOutput(role: .sheet)]
        )

        let result = try BSplineSurfaceFeatureEvaluator().evaluate(
            feature: feature,
            context: context()
        )

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.values.first?.kind == .sheet)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        #expect(result.lineage.isEmpty == false)
        #expect(result.lineage.values.allSatisfy { lineage in
            lineage.output.featureID == featureID && lineage.parents.isEmpty
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func bridgeSurfaceProducesExactRationalRuledSheet() throws {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .bridgeSurface(BridgeSurfaceFeature(
                startBoundary: rationalBoundary(y: 0.0),
                endBoundary: rationalBoundary(y: 2.0)
            )),
            outputs: [FeatureOutput(role: .sheet)]
        )

        let result = try BridgeSurfaceFeatureEvaluator().evaluate(
            feature: feature,
            context: context()
        )
        let face = try #require(result.brep.faces.values.first)
        guard case let .bSpline(surface) = try #require(
            result.brep.geometry.surfaces[face.surfaceID]
        ) else {
            Issue.record("Bridge surface must retain exact B-spline geometry.")
            return
        }

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(surface.uDegree == 2)
        #expect(surface.vDegree == 1)
        #expect(surface.isRational)
        #expect(result.lineage.values.allSatisfy { $0.output.featureID == featureID })
    }

    @Test(.timeLimit(.minutes(1)))
    func patchSurfaceProducesExactCoonsSheet() throws {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .patchSurface(PatchSurfaceFeature(
                vMinimumBoundary: line(from: Point3D(x: 0.0, y: 0.0, z: 0.0), to: Point3D(x: 2.0, y: 0.0, z: 0.0)),
                vMaximumBoundary: line(from: Point3D(x: 0.0, y: 2.0, z: 0.0), to: Point3D(x: 2.0, y: 2.0, z: 0.5)),
                uMinimumBoundary: line(from: Point3D(x: 0.0, y: 0.0, z: 0.0), to: Point3D(x: 0.0, y: 2.0, z: 0.0)),
                uMaximumBoundary: line(from: Point3D(x: 2.0, y: 0.0, z: 0.0), to: Point3D(x: 2.0, y: 2.0, z: 0.5))
            )),
            outputs: [FeatureOutput(role: .sheet)]
        )

        let result = try PatchSurfaceFeatureEvaluator().evaluate(
            feature: feature,
            context: context()
        )
        let face = try #require(result.brep.faces.values.first)
        guard case let .bSpline(surface) = try #require(
            result.brep.geometry.surfaces[face.surfaceID]
        ) else {
            Issue.record("Patch surface must retain exact B-spline geometry.")
            return
        }

        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(surface.uDegree == 1)
        #expect(surface.vDegree == 1)
        #expect(surface.isRational == false)
        #expect(result.lineage.values.allSatisfy { $0.output.featureID == featureID })
    }

    private func context() -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            tolerance: .standard
        )
    }

    private func rationalBoundary(y: Double) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: y, z: 0.0),
                Point3D(x: 1.0, y: y, z: 0.5),
                Point3D(x: 2.0, y: y, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        )
    }

    private func line(from start: Point3D, to end: Point3D) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [start, end]
        )
    }
}
