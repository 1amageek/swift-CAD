import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact curve trim modeling")
struct CurveTrimFeatureEvaluatorTests {
    @Test(.timeLimit(.minutes(1)))
    func trimKeepsExactCircleAndAddsFiniteDomain() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let exactCurve = Curve3D.circle(
            Circle3D(center: .origin, normal: .unitZ, radius: 0.020)
        )
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .circle,
            points: [
                try exactCurve.point(at: 0.0, tolerance: .standard),
                try exactCurve.point(at: .pi, tolerance: .standard),
                try exactCurve.point(at: 2.0 * .pi, tolerance: .standard),
            ],
            isClosed: true,
            plane: .xy,
            exactCurve: exactCurve
        )
        let feature = FeatureNode(
            id: featureID,
            operation: .curveTrim(CurveTrimFeature(
                source: CurveOutputReference(featureID: sourceID),
                domain: .closed(0.0, .pi / 2.0)
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveTrimFeatureEvaluator().evaluate(
            feature: feature,
            context: context(curves: [sourceID: [source]])
        )
        let output = try #require(result.generatedCurves.first)

        guard case .circle = output.exactCurve else {
            Issue.record("Curve trim must retain the exact circle geometry.")
            return
        }
        #expect(output.exactParameterDomain == .closed(0.0, .pi / 2.0))
        #expect(output.kind == .arc)
        #expect(output.isClosed == false)
        #expect(try #require(output.points.first).isApproximatelyEqual(
            to: try exactCurve.point(at: 0.0, tolerance: .standard),
            tolerance: 1.0e-12
        ))
        #expect(try #require(output.points.last).isApproximatelyEqual(
            to: try exactCurve.point(at: .pi / 2.0, tolerance: .standard),
            tolerance: 1.0e-12
        ))
    }

    private func context(curves: [FeatureID: [EvaluatedCurve]]) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [:],
            curves: curves,
            tolerance: .standard
        )
    }
}
