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
        let startFeatureID = FeatureID()
        let endFeatureID = FeatureID()
        let featureID = FeatureID()
        let startReference = CurveOutputReference(featureID: startFeatureID)
        let endReference = CurveOutputReference(featureID: endFeatureID)
        let feature = FeatureNode(
            id: featureID,
            operation: .bridgeCurve(BridgeCurveFeature(
                start: BridgeCurveEndpointReference(
                    curve: startReference,
                    end: .end,
                    requiredLevel: .tangent
                ),
                end: BridgeCurveEndpointReference(
                    curve: endReference,
                    end: .start,
                    requiredLevel: .tangent
                ),
                continuityTolerances: .standard(modelingTolerance: Self.testTolerance)
            )),
            inputs: [
                FeatureInput(featureID: startFeatureID, role: .curve),
                FeatureInput(featureID: endFeatureID, role: .target),
            ],
            outputs: [FeatureOutput(role: .curve)]
        )
        let startCurve = EvaluatedCurve(
            sourceFeatureID: startFeatureID,
            source: .generatedFeature,
            kind: .line,
            points: [Point3D(x: -1.0, y: 0.0, z: 0.0), .origin],
            exactCurve: .line(Line3D(origin: .origin, direction: .unitX)),
            exactParameterDomain: .closed(-1.0, 0.0)
        )
        let endCurve = EvaluatedCurve(
            sourceFeatureID: endFeatureID,
            source: .generatedFeature,
            kind: .line,
            points: [
                Point3D(x: 2.0, y: 1.0, z: 0.0),
                Point3D(x: 3.0, y: 1.0, z: 0.0),
            ],
            exactCurve: .line(Line3D(
                origin: Point3D(x: 2.0, y: 1.0, z: 0.0),
                direction: .unitX
            )),
            exactParameterDomain: .closed(0.0, 1.0)
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            curves: [
                startFeatureID: [startCurve],
                endFeatureID: [endCurve],
            ],
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
