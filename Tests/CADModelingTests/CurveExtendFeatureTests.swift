import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact curve extend")
struct CurveExtendFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func extendsBothEndsOfFiniteLineExactly() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: .line,
            points: [.origin, Point3D(x: 0.100, y: 0.0, z: 0.0)],
            plane: .xy,
            exactCurve: .line(Line3D(origin: .origin, direction: .unitX)),
            exactParameterDomain: .closed(0.0, 0.100)
        )
        let output = try evaluate(
            featureID: featureID,
            sourceID: sourceID,
            source: source,
            end: .both,
            distance: 0.010
        )

        guard case .line = output.exactCurve else {
            Issue.record("Line extension must preserve exact line geometry.")
            return
        }
        #expect(output.exactParameterDomain == .closed(-0.010, 0.110))
        #expect(try #require(output.points.first).isApproximatelyEqual(
            to: Point3D(x: -0.010, y: 0.0, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect(try #require(output.points.last).isApproximatelyEqual(
            to: Point3D(x: 0.110, y: 0.0, z: 0.0),
            tolerance: 1.0e-12
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func extendsAnalyticArcByPhysicalLength() throws {
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
        let output = try evaluate(
            featureID: featureID,
            sourceID: sourceID,
            source: source,
            end: .end,
            distance: 0.010
        )

        guard case let .analytic(.arc(_, _, radius, startAngle, endAngle)) = output.exactCurve else {
            Issue.record("Analytic arc extension must remain an analytic arc.")
            return
        }
        #expect(abs(radius - 0.020) <= 1.0e-12)
        #expect(startAngle == 0.0)
        #expect(abs(endAngle - (.pi / 2.0 + 0.5)) <= 1.0e-12)
        #expect(output.exactParameterDomain == .closed(0.0, .pi / 2.0 + 0.5))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsCircularExtensionBeyondFullTurn() throws {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let exactCurve = Curve3D.circle(Circle3D(center: .origin, normal: .unitZ, radius: 0.020))
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
            exactCurve: exactCurve,
            exactParameterDomain: .closed(0.0, 2.0 * .pi)
        )

        do {
            _ = try evaluate(
                featureID: featureID,
                sourceID: sourceID,
                source: source,
                end: .end,
                distance: 0.010
            )
            Issue.record("A full circle must not extend beyond one revolution.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == featureID)
        }
    }

    private func evaluate(
        featureID: FeatureID,
        sourceID: FeatureID,
        source: EvaluatedCurve,
        end: CurveExtensionEnd,
        distance: Double
    ) throws -> EvaluatedCurve {
        let feature = FeatureNode(
            id: featureID,
            operation: .curveExtend(CurveExtendFeature(
                source: CurveOutputReference(featureID: sourceID),
                end: end,
                distance: .constant(.length(distance, unit: .meter))
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveExtendFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [sourceID: [source]],
                tolerance: .standard
            )
        )
        return try #require(result.generatedCurves.first)
    }
}
