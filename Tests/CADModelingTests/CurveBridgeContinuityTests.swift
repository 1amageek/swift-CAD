import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADModeling

@Suite("Curve bridge continuity through G3")
struct CurveBridgeContinuityTests {
    private let tolerances = CurveContinuityTolerances.standard(modelingTolerance: .standard)

    private func circle(center: Point3D, radius: Double) -> Curve3D {
        .circle(Circle3D(center: center, normal: .unitZ, radius: radius))
    }

    @Test func aCircleCurvatureVectorTurnsAtMinusOneOverRSquaredAlongItsTangent() throws {
        let radius = 2.0
        let target = CurveContinuityTarget(curve: circle(center: .origin, radius: radius), parameter: 0.3)
        let frame = try target.frame(tolerance: .standard)
        let derivative = try #require(frame.curvatureDerivativeVector)
        let expected = frame.tangent * (-1 / (radius * radius))
        #expect((derivative - expected).length <= 1e-12)
        let reversed = try CurveContinuityTarget(curve: circle(center: .origin, radius: radius), parameter: 0.3, orientation: .reversed)
            .frame(tolerance: .standard)
        #expect((try #require(reversed.curvatureDerivativeVector) + derivative).length <= 1e-12)
    }

    @Test func aBSplineThirdDerivativeMatchesTheChangeOfItsSecond() throws {
        let curve = BSplineCurve3D(
            degree: 4,
            knots: [0, 0, 0, 0, 0, 0.5, 1, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 2, z: 0), Point3D(x: 2, y: -1, z: 0),
                            Point3D(x: 3, y: 3, z: 0), Point3D(x: 4, y: 0, z: 0), Point3D(x: 5, y: 1, z: 0)]
        )
        let u = 0.3, h = 1e-5
        let third = try Curve3D.bSpline(curve).thirdParameterDerivative(at: u, tolerance: .standard)
        let before = try curve.parameterDerivatives(at: u - h, tolerance: .standard).secondDerivative
        let after = try curve.parameterDerivatives(at: u + h, tolerance: .standard).secondDerivative
        let central = (after - before) / (2 * h)
        #expect((third - central).length <= 1e-4 * max(1, third.length))
    }

    @Test func aG3BridgeBetweenTwoArcsIsSepticAndG3AtBothEnds() throws {
        let result = try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: circle(center: .origin, radius: 1), parameter: Double.pi / 2),
                requiredLevel: .curvatureVariation
            ),
            end: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: circle(center: Point3D(x: 4, y: 0, z: 0), radius: 1.5), parameter: Double.pi / 2),
                requiredLevel: .curvatureVariation
            ),
            continuityTolerances: tolerances
        ))
        #expect(result.curve.degree == 7)
        #expect(result.startContinuity.achievedLevel == .curvatureVariation)
        #expect(result.endContinuity.achievedLevel == .curvatureVariation)
    }

    @Test func mixedLevelsTakeTheSmallestDegreeThatHoldsBoth() throws {
        let result = try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: .line(Line3D(origin: .origin, direction: .unitX)), parameter: 0),
                requiredLevel: .tangent
            ),
            end: CurveBridgeEndpointConstraint(
                target: CurveContinuityTarget(curve: circle(center: Point3D(x: 3, y: 2, z: 0), radius: 1), parameter: 0),
                requiredLevel: .curvature
            ),
            continuityTolerances: tolerances
        ))
        #expect(result.curve.degree == 4)
        #expect(result.startContinuity.isSatisfied && result.endContinuity.isSatisfied)
    }

    @Test func theSecondAndThirdTensionsSlideTheirControlPointsAlongTheTangent() throws {
        func bridge(second: Double, third: Double) throws -> CurveBridgeResult {
            try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
                start: CurveBridgeEndpointConstraint(
                    target: CurveContinuityTarget(curve: circle(center: .origin, radius: 1), parameter: Double.pi / 2),
                    requiredLevel: .curvatureVariation,
                    secondTension: second,
                    thirdTension: third
                ),
                end: CurveBridgeEndpointConstraint(
                    target: CurveContinuityTarget(curve: circle(center: Point3D(x: 4, y: 0, z: 0), radius: 1.5), parameter: Double.pi / 2),
                    requiredLevel: .curvatureVariation
                ),
                continuityTolerances: tolerances
            ))
        }
        let natural = try bridge(second: 1, third: 1)
        let secondTensed = try bridge(second: 2, third: 1)
        let thirdTensed = try bridge(second: 1, third: 2)
        let tangent = try CurveContinuityTarget(curve: circle(center: .origin, radius: 1), parameter: Double.pi / 2)
            .frame(tolerance: .standard).tangent
        // Tension 2 leaves P0, P1 and moves P2 (and P3) along the tangent; tension 3 moves P3 alone.
        let n = natural.curve.controlPoints, s2 = secondTensed.curve.controlPoints, s3 = thirdTensed.curve.controlPoints
        #expect((s2[0] - n[0]).length <= 1e-12 && (s2[1] - n[1]).length <= 1e-12)
        #expect((s2[2] - n[2]).cross(tangent).length <= 1e-12 && (s2[2] - n[2]).length > 1e-3)
        #expect((s3[0] - n[0]).length <= 1e-12 && (s3[1] - n[1]).length <= 1e-12 && (s3[2] - n[2]).length <= 1e-12)
        #expect((s3[3] - n[3]).cross(tangent).length <= 1e-12 && (s3[3] - n[3]).length > 1e-3)
        #expect(secondTensed.startContinuity.achievedLevel == .curvatureVariation)
        #expect(thirdTensed.startContinuity.achievedLevel == .curvatureVariation)
    }
}
