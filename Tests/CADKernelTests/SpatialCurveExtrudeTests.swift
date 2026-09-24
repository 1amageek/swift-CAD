import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADModeling
import CADKernel

@Suite("Exact spatial curve extrusion", .timeLimit(.minutes(1)))
struct SpatialCurveExtrudeTests {
    @Test(arguments: [false, true])
    func explicitVectorRetainsRationalSpatialBoundary(rational: Bool) throws {
        let curve = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 0.2, y: 0.1, z: 0.1),
                Point3D(x: 0.8, y: 0.2, z: -0.1), Point3D(x: 1, y: 0, z: 0)],
            weights: rational ? [1, 0.8, 1.2, 1] : nil)
        let input = try section(curve)
        let result = try evaluate(input, direction: .vector(Vector3D(x: 0, y: 0, z: 3)))
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 4)
        #expect(result.brep.vertices.count == 4)
        let surface = try #require(result.brep.geometry.surfaces.values.first)
        for u in [0.0, 0.17, 0.5, 0.83, 1.0] {
            for v in [0.0, 0.5, 1.0] {
                let expected = try curve.point(at: u, tolerance: .standard) + Vector3D(x: 0, y: 0, z: 2 * v)
                #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected).length < 1e-8)
            }
        }
    }

    @Test func inPlaneTranslationNeedsNoInventedNormal() throws {
        var input = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0)]))
        input.plane = .xy
        let result = try evaluate(input, direction: .vector(.unitY))
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.vertices.values.allSatisfy { abs($0.point.z) < 1e-8 })
        #expect(throws: (any Error).self) { try evaluate(input, direction: .vector(.unitX)) }
    }

    @Test func absentNormalAndInvalidVectorFailExplicitly() throws {
        let input = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 1, y: 0, z: 0)]))
        for direction in [ExtrudeDirection.normal, .symmetric, .vector(.zero)] {
            #expect(throws: (any Error).self) { try evaluate(input, direction: direction) }
        }
    }

    private func section(_ curve: BSplineCurve3D) throws -> EvaluatedCurve {
        EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: [try curve.point(at: 0, tolerance: .standard), try curve.point(at: 1, tolerance: .standard)],
            exactCurve: .bSpline(curve), exactParameterDomain: .closed(0, 1), exactPointParameters: [0, 1])
    }

    private func evaluate(_ section: EvaluatedCurve, direction: ExtrudeDirection) throws -> EvaluationResult {
        let feature = FeatureNode(operation: .extrude(ExtrudeFeature(
            section: .curve(CurveSectionReference(featureID: section.sourceFeatureID)),
            distance: .constant(.length(2, unit: .meter)), direction: direction, resultKind: .sheet)),
            inputs: [FeatureInput(featureID: section.sourceFeatureID, role: .curve)],
            outputs: [FeatureOutput(role: .sheet)])
        return try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(feature: feature,
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                profiles: [:], curves: [section.sourceFeatureID: [section]], tolerance: .standard))
    }
}
