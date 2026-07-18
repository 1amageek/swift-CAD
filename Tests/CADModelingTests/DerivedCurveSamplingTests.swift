import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Derived curve sampling")
struct DerivedCurveSamplingTests {
    private static let testTolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func samplingPolicyDoesNotChangeExactBridgeGeometry() throws {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            operation: .bridgeCurve(BridgeCurveFeature(
                start: BridgeCurveEndpointTarget(
                    curve: .line(Line3D(origin: .origin, direction: .unitX)),
                    parameter: 0.0,
                    requiredLevel: .tangent
                ),
                end: BridgeCurveEndpointTarget(
                    curve: .line(Line3D(
                        origin: Point3D(x: 2.0, y: 1.0, z: 0.0),
                        direction: .unitX
                    )),
                    parameter: 0.0,
                    requiredLevel: .tangent
                ),
                continuityTolerances: .standard(modelingTolerance: Self.testTolerance)
            )),
            outputs: [FeatureOutput(role: .curve)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            tolerance: Self.testTolerance
        )

        let sparse = try BridgeCurveFeatureEvaluator(
            sampler: UniformDerivedCurveSampler(pointCount: 5)
        ).evaluate(feature: feature, context: context)
        let dense = try BridgeCurveFeatureEvaluator(
            sampler: UniformDerivedCurveSampler(pointCount: 41)
        ).evaluate(feature: feature, context: context)
        let sparseCurve = try #require(sparse.generatedCurves.first)
        let denseCurve = try #require(dense.generatedCurves.first)

        #expect(sparseCurve.points.count == 5)
        #expect(denseCurve.points.count == 41)
        #expect(sparseCurve.exactCurve == denseCurve.exactCurve)
    }
}
