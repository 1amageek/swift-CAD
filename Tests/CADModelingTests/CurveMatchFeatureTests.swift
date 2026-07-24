import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Exact curve match")
struct CurveMatchFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func matchesCubicBezierEndToLineWithVerifiedG2Continuity() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let featureID = FeatureID()
        let sourceSpline = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -0.030, y: 0.0, z: 0.0),
                Point3D(x: -0.020, y: 0.0, z: 0.0),
                Point3D(x: -0.010, y: 0.0, z: 0.0),
                .origin,
            ]
        )
        let source = try evaluatedCurve(id: sourceID, exactCurve: .bSpline(sourceSpline), domain: .closed(0.0, 1.0))
        let targetLine = Curve3D.line(Line3D(
            origin: Point3D(x: 0.100, y: 0.100, z: 0.0),
            direction: .unitY
        ))
        let target = try evaluatedCurve(id: targetID, exactCurve: targetLine, domain: .closed(0.0, 0.100))
        let feature = FeatureNode(
            id: featureID,
            operation: .curveMatch(CurveMatchFeature(
                source: CurveOutputReference(featureID: sourceID),
                sourceEnd: .end,
                target: CurveOutputReference(featureID: targetID),
                targetEnd: .start,
                continuity: .curvature
            )),
            inputs: [
                FeatureInput(featureID: sourceID, role: .curve),
                FeatureInput(featureID: targetID, role: .target),
            ],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveMatchFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [sourceID: [source], targetID: [target]],
                tolerance: .standard
            )
        )
        let output = try #require(result.generatedCurves.first)
        guard case let .bSpline(matched) = output.exactCurve else {
            Issue.record("Curve match must return an exact cubic B-spline.")
            return
        }
        let frame = try matched.differentialGeometry(at: 1.0, tolerance: .standard)
        #expect(frame.position.isApproximatelyEqual(
            to: Point3D(x: 0.100, y: 0.100, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect((frame.tangent - .unitY).length <= 1.0e-12)
        #expect(frame.curvatureVector.length <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func matchesFiniteAnalyticLineSourceWithoutShapeEnvelopeRejection() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let featureID = FeatureID()
        let sourceCurve = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let targetCurve = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.2, y: 0.0, z: 0.0),
            normal: .unitZ,
            radius: 0.05
        ))
        let source = try evaluatedCurve(id: sourceID, exactCurve: sourceCurve, domain: .closed(0.0, 0.1))
        let target = try evaluatedCurve(id: targetID, exactCurve: targetCurve, domain: .closed(0.0, Double.pi * 0.5))
        let feature = FeatureNode(
            id: featureID,
            operation: .curveMatch(CurveMatchFeature(
                source: CurveOutputReference(featureID: sourceID),
                sourceEnd: .end,
                target: CurveOutputReference(featureID: targetID),
                targetEnd: .start,
                continuity: .curvature
            )),
            inputs: [
                FeatureInput(featureID: sourceID, role: .curve),
                FeatureInput(featureID: targetID, role: .target),
            ],
            outputs: [FeatureOutput(role: .curve)]
        )

        let result = try CurveMatchFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [sourceID: [source], targetID: [target]],
                tolerance: .standard
            )
        )
        let output = try #require(result.generatedCurves.first)
        guard case let .bSpline(matched) = output.exactCurve else {
            Issue.record("Curve match must return an exact B-spline.")
            return
        }
        let preserved = try matched.differentialGeometry(at: 0.0, tolerance: .standard)
        let joined = try matched.differentialGeometry(at: 1.0, tolerance: .standard)
        let targetFrame = try targetCurve.differentialGeometry(at: 0.0, tolerance: .standard)
        #expect(preserved.position.isApproximatelyEqual(to: .origin, tolerance: 1.0e-12))
        #expect((preserved.tangent - .unitX).length <= 1.0e-12)
        #expect(preserved.curvatureVector.length <= 1.0e-9)
        #expect(joined.position.isApproximatelyEqual(to: targetFrame.position, tolerance: 1.0e-12))
        #expect((joined.tangent - targetFrame.tangent).length <= 1.0e-12)
        #expect((joined.curvatureVector - targetFrame.curvatureVector).length <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func matchesMultiSpanRationalSourceAndPreservesOppositeG2Jet() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let sourceCurve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.00, y: 0.00, z: 0.00),
                Point3D(x: 0.02, y: 0.01, z: 0.00),
                Point3D(x: 0.04, y: 0.02, z: 0.01),
                Point3D(x: 0.06, y: 0.03, z: 0.01),
                Point3D(x: 0.08, y: 0.02, z: 0.02),
                Point3D(x: 0.10, y: 0.01, z: 0.02),
                Point3D(x: 0.12, y: 0.00, z: 0.02),
            ],
            weights: [1.0, 0.8, 1.2, 1.0, 1.1, 0.9, 1.0]
        )
        let targetCurve = Curve3D.line(Line3D(
            origin: Point3D(x: -0.02, y: 0.08, z: 0.04),
            direction: .unitY
        ))
        let source = try evaluatedCurve(
            id: sourceID,
            exactCurve: .bSpline(sourceCurve),
            domain: .closed(0.0, 1.0)
        )
        let target = try evaluatedCurve(
            id: targetID,
            exactCurve: targetCurve,
            domain: .closed(0.0, 0.1)
        )
        let feature = FeatureNode(
            operation: .curveMatch(CurveMatchFeature(
                source: CurveOutputReference(featureID: sourceID),
                sourceEnd: .start,
                target: CurveOutputReference(featureID: targetID),
                targetEnd: .start,
                targetOrientation: .reversed,
                continuity: .curvature
            )),
            inputs: [
                FeatureInput(featureID: sourceID, role: .curve),
                FeatureInput(featureID: targetID, role: .target),
            ],
            outputs: [FeatureOutput(role: .curve)]
        )
        let result = try CurveMatchFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                curves: [sourceID: [source], targetID: [target]],
                tolerance: .standard
            )
        )
        guard case let .bSpline(matched)? = result.generatedCurves.first?.exactCurve else {
            Issue.record("Curve match must return an exact quintic B-spline.")
            return
        }
        let expectedPreserved = try sourceCurve.differentialGeometry(at: 1.0, tolerance: .standard)
        let actualPreserved = try matched.differentialGeometry(at: 1.0, tolerance: .standard)
        let actualJoined = try matched.differentialGeometry(at: 0.0, tolerance: .standard)
        #expect(matched.degree == 5)
        #expect(actualPreserved.position.isApproximatelyEqual(
            to: expectedPreserved.position,
            tolerance: 1.0e-12
        ))
        #expect((actualPreserved.tangent - expectedPreserved.tangent).length <= 1.0e-12)
        #expect((actualPreserved.curvatureVector - expectedPreserved.curvatureVector).length <= 1.0e-6)
        #expect(actualJoined.position.isApproximatelyEqual(
            to: Point3D(x: -0.02, y: 0.08, z: 0.04),
            tolerance: 1.0e-12
        ))
        #expect((actualJoined.tangent + .unitY).length <= 1.0e-12)
        #expect(actualJoined.curvatureVector.length <= 1.0e-6)
    }

    private func evaluatedCurve(
        id: FeatureID,
        exactCurve: Curve3D,
        domain: ParameterDomain
    ) throws -> EvaluatedCurve {
        guard case let .closed(lower, upper) = domain else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: .standard,
                message: "Test curve domain must be finite."
            )
        }
        return EvaluatedCurve(
            sourceFeatureID: id,
            source: .generatedFeature,
            kind: exactCurveKind(exactCurve),
            points: [
                try exactCurve.point(at: lower, tolerance: .standard),
                try exactCurve.point(at: upper, tolerance: .standard),
            ],
            exactCurve: exactCurve,
            exactParameterDomain: domain
        )
    }

    private func exactCurveKind(_ curve: Curve3D) -> EvaluatedCurveKind {
        switch curve {
        case .line, .analytic(.line):
            return .line
        case .circle, .analytic(.circle):
            return .circle
        case .analytic(.arc):
            return .arc
        case .analytic(.ellipse),
             .analytic(.hyperbola),
             .analytic(.parabola),
             .analytic(.planeTorus),
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            return .spline
        }
    }
}
