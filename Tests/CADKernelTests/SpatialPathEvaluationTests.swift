import Testing
import CADCore
import CADIR
import CADGeometry
import CADTopology
import CADModeling
import CADKernel

@Suite("Spatial path evaluation")
struct SpatialPathEvaluationTests {
    @Test(.timeLimit(.minutes(1)))
    func defaultEvaluatorProducesExactSpatialCurve() throws {
        let path = SpatialPathFeature(kind: .bezier, knots: [
            SpatialPathKnot(position: .origin, outgoing: Vector3D(x: 1, y: 0, z: 2)),
            SpatialPathKnot(position: Point3D(x: 3, y: 1, z: 4), incoming: Vector3D(x: -1, y: 0, z: -1)),
        ])
        let feature = FeatureNode(operation: .spatialPath(path), outputs: [FeatureOutput(role: .curve)])
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                                        profiles: [:], curves: [:], tolerance: .standard)
        let result = try DefaultFeatureEvaluator().evaluate(feature: feature, context: context)
        let curve = try #require(result.generatedCurves.first)
        #expect(result.generatedCurves.count == 1)
        #expect(curve.plane == nil)
        #expect(curve.sourceFeatureID == feature.id)
        #expect(curve.points.contains(where: { $0.z > 1 && $0.z < 4 }))
        #expect(curve.points.first == path.knots.first?.position)
        #expect(curve.points.last == path.knots.last?.position)
        #expect(curve.exactCurve == .bSpline(try path.exactCurve(tolerance: .standard)))
    }
}
