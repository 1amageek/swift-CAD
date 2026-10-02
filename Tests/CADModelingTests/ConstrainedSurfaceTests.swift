import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation
import Testing
@testable import CADModeling

@Suite("Constrained Surface")
struct ConstrainedSurfaceTests {
    @Test(.timeLimit(.minutes(1)), arguments: ConstrainedSurfaceFeature.Optimization.allCases)
    func angularToleranceControlsPointOnlyRelaxation(mode: ConstrainedSurfaceFeature.Optimization) throws {
        let fitter = ConstrainedSurfaceHeightFitter(maximumMatrixElements: 1_000_000)
        var source = fixture(mode: mode)
        source.angularTolerance = 1e-8
        let reference = try fitter.fit(source, tolerance: .standard)
        source.angularTolerance = 0.01
        let tight = try fitter.fit(source, tolerance: .standard)
        source.angularTolerance = 0.2
        let relaxed = try fitter.fit(source, tolerance: .standard)
        #expect(tight.controlPoints != relaxed.controlPoints)
        var tightChange = 0.0, relaxedChange = 0.0
        for v in 0...20 { for u in 0...20 {
            let uv = (Double(u) / 20, Double(v) / 20)
            let n = try reference.differentialGeometry(u: uv.0, v: uv.1, tolerance: .standard).normal
            let t = try tight.differentialGeometry(u: uv.0, v: uv.1, tolerance: .standard).normal
            let r = try relaxed.differentialGeometry(u: uv.0, v: uv.1, tolerance: .standard).normal
            tightChange = max(tightChange, acos(min(1, n.dot(t))))
            relaxedChange = max(relaxedChange, acos(min(1, n.dot(r))))
        } }
        #expect(tightChange <= 0.01 + 1e-8)
        #expect(relaxedChange <= 0.2 + 1e-8)
        #expect(relaxedChange > tightChange)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ConstrainedSurfaceFeature.Optimization.allCases)
    func nonplanarPointsProduceValidatedSheet(mode: ConstrainedSurfaceFeature.Optimization) throws {
        let source = fixture(mode: mode)
        let restored = try JSONDecoder().decode(ConstrainedSurfaceFeature.self,
            from: JSONEncoder().encode(source))
        #expect(restored == source)
        let feature = FeatureNode(operation: .constrainedSurface(restored),
            outputs: [FeatureOutput(role: .sheet)])
        let result = try ConstrainedSurfaceFeatureEvaluator().evaluate(feature: feature,
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                profiles: [:], tolerance: .standard))
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.values.first?.kind == .sheet)
        let face = try #require(result.brep.faces.values.first)
        let surface = try #require(result.brep.geometry.surfaces[face.surfaceID])
        for point in source.points {
            let projected = try surface.parameterProjection(of: point.position, tolerance: .standard)
            #expect(projected.residual <= source.positionTolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func degenerateAndOverBudgetInputsFail() throws {
        let fitter = ConstrainedSurfaceHeightFitter(maximumMatrixElements: 1_000_000)
        var source = fixture(mode: .smoothness)
        source.points = (0..<3).map { .init(position: Point3D(x: Double($0), y: 0, z: 0)) }
        #expect(throws: KernelError.self) { try fitter.fit(source, tolerance: .standard) }
        #expect(throws: KernelError.self) {
            try ConstrainedSurfaceHeightFitter(maximumMatrixElements: 16)
                .fit(fixture(mode: .smoothness), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func theSheetFramesThePointsWhateverOrderTheyComeIn() throws {
        // Four points of a square, clicked corner then diagonal: the sheet is the square with the
        // points at its corners, not a diamond twice its size.
        let fitter = ConstrainedSurfaceHeightFitter(maximumMatrixElements: 1_000_000)
        let corners = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 1, z: 0), Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let source = ConstrainedSurfaceFeature(points: corners.map { .init(position: $0) },
                                               positionTolerance: 1e-7, angularTolerance: 1e-4, optimization: .performance)
        let sheet = try fitter.fit(source, tolerance: .standard)
        let domainCorners = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { try sheet.point(u: $0.0, v: $0.1, tolerance: .standard) }
        for corner in corners {
            #expect(domainCorners.contains { ($0 - corner).length < 1e-6 }, "\(corner)")
        }
        // Three points of a triangle: two at adjacent corners, the third on the opposite side.
        let triangle = ConstrainedSurfaceFeature(
            points: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0.8, z: 0), Point3D(x: 1, y: 0, z: 0)].map { .init(position: $0) },
            positionTolerance: 1e-7, angularTolerance: 1e-4, optimization: .performance)
        let tri = try fitter.fit(triangle, tolerance: .standard)
        let triCorners = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { try tri.point(u: $0.0, v: $0.1, tolerance: .standard) }
        let triPoints = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0.8, z: 0), Point3D(x: 1, y: 0, z: 0)]
        #expect(triPoints.filter { point in triCorners.contains { ($0 - point).length < 1e-6 } }.count == 2)
    }

    private func fixture(mode: ConstrainedSurfaceFeature.Optimization) -> ConstrainedSurfaceFeature {
        ConstrainedSurfaceFeature(points: [
            .init(position: Point3D(x: 0, y: 0, z: 0)),
            .init(position: Point3D(x: 1, y: 0, z: 0)),
            .init(position: Point3D(x: 1, y: 1, z: 0)),
            .init(position: Point3D(x: 0, y: 1, z: 0)),
            .init(position: Point3D(x: 0.5, y: 0.5, z: 0.1)),
        ], positionTolerance: 1e-7, angularTolerance: 1e-4, optimization: mode)
    }
}
