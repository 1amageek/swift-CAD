import Testing
import CADCore
import CADGeometry
@testable import CADModeling

@Suite("Turning cap loop side approximation")
struct TurningCapLoopSideApproximationTests {
    private func quartic(_ coefficient: Double) -> BSplineCurve3D {
        BSplineCurve3D(degree: 4, knots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.25, y: 0, z: 0),
                            Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 0.75, y: 0, z: 0),
                            Point3D(x: 1, y: coefficient, z: 0)])
    }

    @Test(.timeLimit(.minutes(1)))
    func quarticCentersRefuteSixthSamplesAndRequireWholeSideRefinement() throws {
        let tolerance = ModelingTolerance.standard
        let allowance = tolerance.distance / 8
        let coefficient = allowance * 65_536 * 16 * 1.03
        let curve = quartic(coefficient)
        let builder = TurningCapLoopCornerPatchBuilder(tolerance: tolerance)
        let coarse = try builder.hermite(curve, spans: 16)
        // For t^4, exact Hermite error on [a,b] is k(t-a)^2(t-b)^2.
        let center = 1.0 / 32
        let exact = Point3D(x: center, y: coefficient * center * center * center * center, z: 0)
        let centerError = (try coarse.point(at: center, tolerance: tolerance) - exact).length
        #expect(abs(centerError / allowance - 1.03) < 1e-8)
        var sampledError = 0.0
        for k in 0..<96 {
            let t = (Double(k) + 0.5) / 96
            let p = Point3D(x: t, y: coefficient * t * t * t * t, z: 0)
            sampledError = max(sampledError, (try coarse.point(at: t, tolerance: tolerance) - p).length)
        }
        #expect(sampledError <= allowance)
        #expect(try builder.certifiesSide(curve, spline: coarse, spans: 16) == false)
        let count = try builder.spans(curve)
        #expect(count >= 32 && count <= 64)
        let refined = try builder.hermite(curve, spans: count)
        #expect(try builder.certifiesSide(curve, spline: refined, spans: count))
        let t = 0.5 / Double(count)
        let p = Point3D(x: t, y: coefficient * t * t * t * t, z: 0)
        #expect((try refined.point(at: t, tolerance: tolerance) - p).length <= allowance)
    }

    @Test(.timeLimit(.minutes(1)))
    func literalLineAndRationalRoundSidesKeepWholeCertificatesAtFinalCommonSpans() throws {
        let tolerance = ModelingTolerance.standard
        let builder = TurningCapLoopCornerPatchBuilder(tolerance: tolerance)
        let line = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0.006, y: 0.008, z: 0.016), Point3D(x: 0.006, y: 0.008, z: 0.014)])
        let round = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0.002, y: 0, z: 0), .origin, Point3D(x: 0, y: 0, z: 0.002)],
            weights: [1, 0.5.squareRoot(), 1])
        let descent = try builder.descent(from: Point3D(x: 0.008, y: 0, z: 0.018),
            foot: Point3D(x: 0.008, y: 0, z: 0.016), vertex: Point3D(x: 0.006, y: 0, z: 0.016),
            to: Point3D(x: 0.006, y: 0, z: 0.014), arc: nil)
        for curve in [line, round, descent] {
            let count = try builder.spans(curve)
            let common = max(16, count)
            #expect(try builder.certifiesSide(curve, spline: builder.hermite(curve, spans: common), spans: common))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func quarticExhaustionAndUnsupportedOriginalSpansRemainExplicitFailures() throws {
        let tolerance = ModelingTolerance.standard
        let builder = TurningCapLoopCornerPatchBuilder(tolerance: tolerance)
        let coefficient = (tolerance.distance / 8) * 16_777_216 * 16 * 2
        let tooFar = quartic(coefficient)
        let coarse = try builder.hermite(tooFar, spans: 64)
        let t = 1.0 / 128
        let exact = Point3D(x: t, y: coefficient * t * t * t * t, z: 0)
        #expect((try coarse.point(at: t, tolerance: tolerance) - exact).length > tolerance.distance / 8)
        do {
            _ = try builder.spans(tooFar)
            Issue.record("An uncertified side must not succeed after the 64-span limit.")
        } catch let error as KernelError {
            #expect(error.code == .classificationFailure)
        }
        let multiSpan = BSplineCurve3D(degree: 1, knots: [0, 0, 0.5, 1, 1],
            controlPoints: [.origin, Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)])
        do {
            _ = try builder.spans(multiSpan)
            Issue.record("Unowned original spans require an explicit capability refusal.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }
}
