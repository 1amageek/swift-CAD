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

    @Test(.timeLimit(.minutes(1)))
    func offsetSupportsEveryDeclaredRepresentationOrientationAndSide() throws {
        let lineCases: [Curve3D] = [
            .line(Line3D(origin: .origin, direction: .unitX)),
            .analytic(.line(origin: .origin, direction: .unitX)),
        ]
        for curve in lineCases {
            for side in CurveOffsetSide.allCases {
                let output = try evaluateOffset(
                    curve: curve,
                    kind: .line,
                    domain: .closed(0.0, 1.0),
                    isClosed: false,
                    planeNormal: .unitZ,
                    side: side,
                    distance: 0.2
                )
                let expectedY = side == .left ? 0.2 : -0.2
                #expect(abs(try #require(output.points.first).y - expectedY) <= 1.0e-12)
                #expect(output.exactParameterDomain == .closed(0.0, 1.0))
                switch (curve, output.exactCurve) {
                case (.line, .line), (.analytic(.line), .analytic(.line)):
                    break
                default:
                    Issue.record("Line offset must preserve its exact representation.")
                }
            }
        }

        let circularCases: [Curve3D] = [
            .circle(Circle3D(center: .origin, normal: .unitZ, radius: 2.0)),
            .analytic(.circle(center: .origin, normal: .unitZ, radius: 2.0)),
            .analytic(.arc(
                center: .origin,
                normal: .unitZ,
                radius: 2.0,
                startAngle: 0.0,
                endAngle: .pi
            )),
        ]
        for curve in circularCases {
            for planeNormal in [Vector3D.unitZ, -Vector3D.unitZ] {
                for side in CurveOffsetSide.allCases {
                    let output = try evaluateOffset(
                        curve: curve,
                        kind: .arc,
                        domain: .closed(0.0, .pi),
                        isClosed: false,
                        planeNormal: planeNormal,
                        side: side,
                        distance: 0.25
                    )
                    let orientation = planeNormal == .unitZ ? 1.0 : -1.0
                    let sideSign = side == .left ? 1.0 : -1.0
                    let expectedRadius = 2.0 - sideSign * orientation * 0.25
                    #expect(abs(try radius(of: #require(output.exactCurve)) - expectedRadius) <= 1.0e-12)
                    #expect(output.exactParameterDomain == .closed(0.0, .pi))
                    #expect(output.kind == .arc)
                    #expect(output.isClosed == false)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func fullCircleOffsetDerivesClosedMetadataFromExactDomain() throws {
        let curve = Curve3D.analytic(.circle(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        ))
        let output = try evaluateOffset(
            curve: curve,
            kind: .circle,
            domain: nil,
            isClosed: false,
            planeNormal: .unitZ,
            side: .right,
            distance: 0.25
        )

        #expect(output.isClosed)
        #expect(output.kind == .circle)
        #expect(abs(try radius(of: #require(output.exactCurve)) - 2.25) <= 1.0e-12)
        #expect(try #require(output.points.first).isApproximatelyEqual(
            to: try #require(output.points.last),
            tolerance: 1.0e-12
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetRejectsNonCoplanarLineNormalAndCollapsedRadius() throws {
        let tiltedNormal = try Vector3D(x: 1.0, y: 0.0, z: 1.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        do {
            _ = try evaluateOffset(
                curve: .line(Line3D(origin: .origin, direction: .unitX)),
                kind: .line,
                domain: .closed(0.0, 1.0),
                isClosed: false,
                planeNormal: tiltedNormal,
                side: .left,
                distance: 0.1
            )
            Issue.record("Line offset must reject a plane normal not perpendicular to the line.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(try #require(error.residual) > 0.0)
        }

        do {
            _ = try evaluateOffset(
                curve: .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0)),
                kind: .circle,
                domain: nil,
                isClosed: true,
                planeNormal: .unitZ,
                side: .left,
                distance: 1.0
            )
            Issue.record("Circular offset must reject radius collapse.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func requestUsesStrictCurrentSchema() throws {
        let feature = CurveOffsetFeature(
            source: CurveOutputReference(featureID: FeatureID()),
            distance: .constant(.length(1.0, unit: .meter)),
            planeNormal: .unitZ,
            side: .left
        )
        let data = try JSONEncoder().encode(feature)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["legacyPolylineFallback"] = true
        let invalid = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CurveOffsetFeature.self, from: invalid)
        }
    }

    private func evaluateOffset(
        curve: Curve3D,
        kind: EvaluatedCurveKind,
        domain: ParameterDomain?,
        isClosed: Bool,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        distance: Double
    ) throws -> EvaluatedCurve {
        let sourceID = FeatureID()
        let featureID = FeatureID()
        let sampleDomain = domain ?? .closed(0.0, 2.0 * .pi)
        guard case let .closed(lower, upper) = sampleDomain else {
            Issue.record("Offset test requires a finite sampling domain.")
            throw GeometryError.invalidDistance(0.0)
        }
        let source = EvaluatedCurve(
            sourceFeatureID: sourceID,
            source: .generatedFeature,
            kind: kind,
            points: [
                try curve.point(at: lower, tolerance: .standard),
                try curve.point(at: (lower + upper) * 0.5, tolerance: .standard),
                try curve.point(at: upper, tolerance: .standard),
            ],
            isClosed: isClosed,
            plane: .xy,
            exactCurve: curve,
            exactParameterDomain: domain
        )
        let feature = FeatureNode(
            id: featureID,
            operation: .curveOffset(CurveOffsetFeature(
                source: CurveOutputReference(featureID: sourceID),
                distance: .constant(.length(distance, unit: .meter)),
                planeNormal: planeNormal,
                side: side
            )),
            inputs: [FeatureInput(featureID: sourceID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveOffsetFeatureEvaluator().evaluate(
            feature: feature,
            context: context(curves: [sourceID: [source]])
        )
        return try #require(result.generatedCurves.first)
    }

    private func radius(of curve: Curve3D) throws -> Double {
        switch curve {
        case let .circle(circle):
            return circle.radius
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            return radius
        case .line,
             .analytic(.line),
             .analytic(.ellipse),
             .analytic(.hyperbola),
             .analytic(.parabola),
             .analytic(.planeTorus),
             .bSpline,
             .implicit,
             .surfaceLift:
            throw GeometryError.invalidRadius(0.0)
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
