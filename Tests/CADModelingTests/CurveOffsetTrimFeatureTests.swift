import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact curve offset and trim")
struct CurveOffsetTrimFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func offsetPreservesAnalyticArcIdentityAndDomain() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let exactCurve = Curve3D.analytic(.arc(
            center: .origin,
            normal: .unitZ,
            radius: 0.020,
            startAngle: 0.0,
            endAngle: .pi / 2.0
        ))
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .arc,
            points: [
                try exactCurve.point(at: 0.0, tolerance: .standard),
                try exactCurve.point(at: .pi / 2.0, tolerance: .standard),
            ],
            plane: .xy,
            exactCurve: exactCurve,
            exactParameterDomain: .closed(0.0, .pi / 2.0)
        )
        let feature = FeatureNode(
            id: featureID,
            operation: .curveOffset(CurveOffsetFeature(
                source: CurveOutputReference(featureID: sourceID),
                distance: .constant(.length(0.005, unit: .meter)),
                planeNormal: .unitZ,
                side: .right
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveOffsetFeatureEvaluator().evaluate(
            feature: feature,
            context: context(curves: [sourceID: [source]])
        )
        let output = try #require(result.generatedCurves.first)

        guard case let .analytic(.arc(center, normal, radius, startAngle, endAngle)) = output.exactCurve else {
            Issue.record("Exact arc offset must remain an analytic arc.")
            return
        }
        #expect(center == .origin)
        #expect(normal == .unitZ)
        #expect(abs(radius - 0.025) <= 1.0e-12)
        #expect(startAngle == 0.0)
        #expect(endAngle == .pi / 2.0)
        #expect(output.exactParameterDomain == .closed(0.0, .pi / 2.0))
        #expect(output.kind == .arc)
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetRejectsEllipseWithoutApproximation() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let exactCurve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 0.030,
            minorRadius: 0.020
        ))
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .spline,
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
            operation: .curveOffset(CurveOffsetFeature(
                source: CurveOutputReference(featureID: sourceID),
                distance: .constant(.length(0.005, unit: .meter)),
                planeNormal: .unitZ
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )

        do {
            _ = try CurveOffsetFeatureEvaluator().evaluate(
                feature: feature,
                context: context(curves: [sourceID: [source]])
            )
            Issue.record("Ellipse offset must not return an approximate exact curve.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == featureID)
        }
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
