import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Periodic B-spline tensor surfaces")
struct PeriodicBSplineSurfaceTests {
    private let tolerance = ModelingTolerance.standard

    private func surface(uPeriodic: Bool = true, vPeriodic: Bool = true,
                         rational: Bool = true) throws -> BSplineSurface3D {
        let uCount = uPeriodic ? 4 : 3
        let vCount = vPeriodic ? 4 : 3
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for j in 0..<vCount {
            let phi = Double(j) * Double.pi / 2
            points.append((0..<uCount).map { i in
                let theta = Double(i) * Double.pi / 2
                return Point3D(x: (3 + cos(phi)) * cos(theta),
                    y: (3 + cos(phi)) * sin(theta), z: sin(phi))
            })
            weights.append((0..<uCount).map { i in rational ? 1 + Double(i * j + i + j) * 0.1 : 1 })
        }
        return try .periodic(uDegree: uPeriodic ? 3 : 2, vDegree: vPeriodic ? 3 : 2,
            uKnots: uPeriodic ? [3, 3.5, 5, 6, 8] : [0, 0, 0, 1, 1, 1],
            vKnots: vPeriodic ? [-2, -1.75, -1, 0.5, 2] : [0, 0, 0, 1, 1, 1],
            controlPoints: points, weights: weights, isUPeriodic: uPeriodic,
            isVPeriodic: vPeriodic, tolerance: tolerance)
    }

    private func unwrapped(_ cyclic: BSplineSurface3D) -> BSplineSurface3D {
        BSplineSurface3D(uDegree: cyclic.uDegree, vDegree: cyclic.vDegree,
            uKnots: cyclic.uKnots, vKnots: cyclic.vKnots,
            controlPoints: cyclic.controlPoints, weights: cyclic.weights)
    }

    private func densePoint(_ surface: BSplineSurface3D, u: Double, v: Double) -> Point3D {
        let us = BSplineBasis.values(parameter: u, degree: surface.uDegree,
            knots: surface.uKnots, count: surface.uControlPointCount)
        let vs = BSplineBasis.values(parameter: v, degree: surface.vDegree,
            knots: surface.vKnots, count: surface.vControlPointCount)
        var numerator = Vector3D.zero
        var denominator = 0.0
        for j in vs.indices {
            for i in us.indices {
                let coefficient = us[i] * vs[j] * surface.weights[j][i]
                let point = surface.controlPoints[j][i]
                numerator = numerator + Vector3D(x: point.x, y: point.y, z: point.z) * coefficient
                denominator += coefficient
            }
        }
        return Point3D.origin + numerator / denominator
    }

    private func checkJets(_ lhs: BSplineSurface3D.RationalDerivatives,
                           _ rhs: BSplineSurface3D.RationalDerivatives, accuracy: Double = 2e-11) {
        #expect((lhs.position - rhs.position).length < accuracy)
        #expect((lhs.tangentU - rhs.tangentU).length < accuracy)
        #expect((lhs.tangentV - rhs.tangentV).length < accuracy)
        #expect((lhs.secondDerivativeUU - rhs.secondDerivativeUU).length < accuracy)
        #expect((lhs.secondDerivativeUV - rhs.secondDerivativeUV).length < accuracy)
        #expect((lhs.secondDerivativeVV - rhs.secondDerivativeVV).length < accuracy)
    }

    @Test(.timeLimit(.minutes(1)))
    func independentPeriodicAxesMatchTheDenseTensorBasis() throws {
        for (uPeriodic, vPeriodic) in [(true, false), (false, true), (true, true)] {
            for rational in [false, true] {
                let cyclic = try surface(uPeriodic: uPeriodic, vPeriodic: vPeriodic, rational: rational)
                #expect(cyclic.uDomain == (uPeriodic ? .periodic(period: 5) : .closed(0, 1)))
                #expect(cyclic.vDomain == (vPeriodic ? .periodic(period: 4) : .closed(0, 1)))
                for k in 0..<7 {
                    let u = uPeriodic ? 3 + (Double(k) + 0.25) * 5 / 7 : (Double(k) + 0.25) / 7
                    let v = vPeriodic ? -2 + (Double(k) + 0.4) * 4 / 7 : (Double(k) + 0.4) / 7
                    let expected = densePoint(cyclic, u: u, v: v)
                    for a in -2...2 {
                        for b in -2...2 {
                            let actual = try Surface3D.bSpline(cyclic).point(
                                u: u + (uPeriodic ? Double(a) * 5 : 0),
                                v: v + (vPeriodic ? Double(b) * 4 : 0), tolerance: tolerance)
                            #expect((actual - expected).length < 2e-12)
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func seamFirstSecondAndMixedDerivativesAgreeWithoutWrappingTheReference() throws {
        for rational in [false, true] {
            let cyclic = try surface(rational: rational)
            let raw = unwrapped(cyclic)
            #expect(cyclic.periodicSeamContinuityOrder(direction: .u) == 2)
            #expect(cyclic.periodicSeamContinuityOrder(direction: .v) == 2)
            for v in [-2.0, -1.5, -0.25, 1, 2] {
                checkJets(try raw.surfaceDerivatives(u: 3, v: v, tolerance: tolerance),
                          try raw.surfaceDerivatives(u: 8, v: v, tolerance: tolerance))
            }
            for u in [3.0, 3.25, 4.5, 6.25, 8] {
                checkJets(try raw.surfaceDerivatives(u: u, v: -2, tolerance: tolerance),
                          try raw.surfaceDerivatives(u: u, v: 2, tolerance: tolerance))
                checkJets(try cyclic.surfaceDerivatives(u: u, v: -2, tolerance: tolerance),
                          try cyclic.surfaceDerivatives(u: u - 15, v: 10, tolerance: tolerance))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mixedDerivativeMatchesIndependentFiniteDifferences() throws {
        let cyclic = try surface()
        let u = 4.25, v = -0.25, h = 1e-4
        let center = densePoint(cyclic, u: u, v: v)
        let a = densePoint(cyclic, u: u + h, v: v)
        let b = densePoint(cyclic, u: u - h, v: v)
        let c = densePoint(cyclic, u: u, v: v + h)
        let d = densePoint(cyclic, u: u, v: v - h)
        let pp = densePoint(cyclic, u: u + h, v: v + h)
        let pm = densePoint(cyclic, u: u + h, v: v - h)
        let mp = densePoint(cyclic, u: u - h, v: v + h)
        let mm = densePoint(cyclic, u: u - h, v: v - h)
        let jet = try cyclic.surfaceDerivatives(u: u + 10, v: v - 8, tolerance: tolerance)
        #expect((jet.tangentU - (a - b) / (2 * h)).length < 2e-7)
        #expect((jet.tangentV - (c - d) / (2 * h)).length < 2e-7)
        #expect((jet.secondDerivativeUU - ((a - center) + (b - center)) / (h * h)).length < 2e-6)
        #expect((jet.secondDerivativeVV - ((c - center) + (d - center)) / (h * h)).length < 2e-6)
        #expect((jet.secondDerivativeUV - ((pp - pm) - (mp - mm)) / (4 * h * h)).length < 2e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func originsChangeRepresentativesWithoutChangingTheFunctionOrCurvature() throws {
        let original = try surface()
        let changed = try original.changingPeriodicOrigin(direction: .u, to: 7.25, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .v, to: 1.75, tolerance: tolerance)
        #expect(changed.uFundamentalDomain == .closed(7.25, 12.25))
        #expect(changed.vFundamentalDomain == .closed(1.75, 5.75))
        for (u, v) in [(-12.5, 8.5), (3.0, -2.0), (4.25, -0.25), (8.0, 2.0)] {
            let a = try changed.normalizedParameter(u, direction: .u, tolerance: tolerance)
            let b = try changed.normalizedParameter(v, direction: .v, tolerance: tolerance)
            #expect(a >= 7.25 && a < 12.25 && b >= 1.75 && b < 5.75)
            #expect((try changed.point(u: a, v: b, tolerance: tolerance)
                - original.point(u: u, v: v, tolerance: tolerance)).length < 2e-12)
            checkJets(try changed.surfaceDerivatives(u: u, v: v, tolerance: tolerance),
                      try original.surfaceDerivatives(u: u, v: v, tolerance: tolerance))
        }
        let expected = try original.differentialGeometry(u: 4.25, v: -0.25, tolerance: tolerance)
        let actual = try changed.differentialGeometry(u: 14.25, v: -8.25, tolerance: tolerance)
        #expect((actual.normal - expected.normal).length < 2e-12)
        #expect(abs(actual.gaussianCurvature - expected.gaussianCurvature) < 2e-12)
        #expect(abs(actual.meanCurvature - expected.meanCurvature) < 2e-12)
        let sourceThird = try original.parameterDerivativesThroughThirdOrder(u: 4.25, v: -0.25, tolerance: tolerance)
        let movedThird = try changed.parameterDerivativesThroughThirdOrder(u: 14.25, v: -8.25, tolerance: tolerance)
        #expect((sourceThird.thirdDerivativeUUV - movedThird.thirdDerivativeUUV).length < 2e-12)
        #expect((sourceThird.thirdDerivativeUVV - movedThird.thirdDerivativeUVV).length < 2e-12)
        let sourceTaylor = try Surface3D.bSpline(original).taylorJet(u: 4.25, v: -0.25,
            throughOrder: 3, tolerance: tolerance)
        let movedTaylor = try Surface3D.bSpline(changed).taylorJet(u: 14.25, v: -8.25,
            throughOrder: 3, tolerance: tolerance)
        #expect((sourceTaylor.derivative(uOrder: 2, vOrder: 1)
            - movedTaylor.derivative(uOrder: 2, vOrder: 1)).length < 2e-12)

    }

    @Test(.timeLimit(.minutes(1)))
    func isocurvesNormalizeTheirFixedAxisAndRetainTheVaryingCycle() throws {
        let cyclic = try surface().changingPeriodicOrigin(direction: .u, to: 7.25, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .v, to: 1.75, tolerance: tolerance)
        let uCurve = try cyclic.uIsoparametricCurve(atV: 7.75, tolerance: tolerance)
        let vCurve = try cyclic.vIsoparametricCurve(atU: -5.75, tolerance: tolerance)
        #expect(uCurve.isPeriodic && uCurve.periodicOrigin == 7.25)
        #expect(vCurve.isPeriodic && vCurve.periodicOrigin == 1.75)
        for t in [-12.25, 0.25, 4.25, 8.5, 13.5] {
            let uJet = try uCurve.parameterDerivatives(at: t, tolerance: tolerance)
            let surfaceU = try cyclic.surfaceDerivatives(u: t, v: 7.75, tolerance: tolerance)
            #expect((uJet.position - surfaceU.position).length < 2e-12)
            #expect((uJet.firstDerivative - surfaceU.tangentU).length < 2e-12)
            #expect((uJet.secondDerivative - surfaceU.secondDerivativeUU).length < 2e-12)
            let vJet = try vCurve.parameterDerivatives(at: t, tolerance: tolerance)
            let surfaceV = try cyclic.surfaceDerivatives(u: -5.75, v: t, tolerance: tolerance)
            #expect((vJet.position - surfaceV.position).length < 2e-12)
            #expect((vJet.firstDerivative - surfaceV.tangentV).length < 2e-12)
            #expect((vJet.secondDerivative - surfaceV.secondDerivativeVV).length < 2e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidTransformsAndOpenAxisEditsPreserveTheOtherCycle() throws {
        let cyclic = try surface(uPeriodic: true, vPeriodic: false)
            .changingPeriodicOrigin(direction: .u, to: 7.25, tolerance: tolerance)
        let transform = RigidTransform3D.translated(by: Vector3D(x: 2, y: -3, z: 4))
        let moved = try transform.applying(to: cyclic, tolerance: tolerance)
        let refined = try cyclic.insertingKnot(direction: .v, value: 0.4, tolerance: tolerance)
        let raised = try cyclic.elevatingDegree(direction: .v, tolerance: tolerance)
        for value in [moved, refined, raised] {
            #expect(value.isUPeriodic && !value.isVPeriodic && value.uPeriodicOrigin == 7.25)
        }
        for (u, v) in [(3.0, 0.0), (4.25, 0.6), (13.75, 1.0)] {
            let expected = try cyclic.point(u: u, v: v, tolerance: tolerance)
            #expect((try moved.point(u: u, v: v, tolerance: tolerance) - transform.applying(to: expected)).length < 2e-12)
            #expect((try refined.point(u: u, v: v, tolerance: tolerance) - expected).length < 2e-12)
            #expect((try raised.point(u: u, v: v, tolerance: tolerance) - expected).length < 2e-12)
        }
        #expect(throws: KernelError.self) { try cyclic.elevatingDegree(direction: .u, tolerance: tolerance) }
    }

    @Test(.timeLimit(.minutes(1)))
    func schemaRequiresBothAxisFlagsAndPreservesOrigins() throws {
        let cyclic = try surface().changingPeriodicOrigin(direction: .v, to: 1.75, tolerance: tolerance)
        let data = try JSONEncoder().encode(cyclic)
        #expect(try JSONDecoder().decode(BSplineSurface3D.self, from: data) == cyclic)
        #expect(try JSONDecoder().decode(Surface3D.self, from: JSONEncoder().encode(Surface3D.bSpline(cyclic))) == .bSpline(cyclic))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["isUPeriodic", "isVPeriodic"] {
            var missing = object
            missing.removeValue(forKey: key)
            let damaged = try JSONSerialization.data(withJSONObject: missing)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(BSplineSurface3D.self, from: damaged) }
            missing[key] = "true"
            let mistyped = try JSONSerialization.data(withJSONObject: missing)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(BSplineSurface3D.self, from: mistyped) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedCyclesOriginsAndFiniteBudgetsAreRejected() throws {
        let original = try surface()
        var bad = original
        bad.controlPoints[6][6].z += 1
        #expect(throws: KernelError.self) { try bad.validate(tolerance: tolerance) }
        bad = original
        bad.weights[0][6] += 0.1
        #expect(throws: KernelError.self) { try bad.validate(tolerance: tolerance) }
        bad = original
        bad.vKnots[0] -= 0.01
        #expect(throws: KernelError.self) { try bad.validate(tolerance: tolerance) }
        bad = try surface(uPeriodic: true, vPeriodic: false)
        bad.vPeriodicOrigin = 0
        #expect(throws: KernelError.self) { try bad.validate(tolerance: tolerance) }
        #expect(throws: (any Error).self) {
            try original.changingPeriodicOrigin(direction: .u, to: .greatestFiniteMagnitude, tolerance: tolerance)
        }
        #expect(throws: GeometryError.self) { try original.point(u: .nan, v: 0, tolerance: tolerance) }
        #expect(throws: (any Error).self) {
            let overflow = BSplineSurface3D(uDegree: Int.max, vDegree: Int.max,
                uKnots: [], vKnots: [], controlPoints: [[.origin]])
            try overflow.validate(tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try BSplineSurface3D.periodic(uDegree: 3, vDegree: 3,
                uKnots: [0, 1, 2, 3, 4], vKnots: [0, 1, 2, 3, 4],
                controlPoints: Array(repeating: Array(repeating: .origin, count: 4), count: 4),
                isUPeriodic: true, isVPeriodic: true,
                expansionOptions: .init(maximumControlPointCount: 48), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func degreeGreaterThanTheCycleCountRetainsTranslatedEvaluation() throws {
        let cyclic = try BSplineSurface3D.periodic(uDegree: 5, vDegree: 1,
            uKnots: [0, 2, 4], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 1)]],
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        #expect(cyclic.uControlPointCount == 7)
        for u in [0.0, 0.25, 1, 3.5, 4] {
            checkJets(try cyclic.surfaceDerivatives(u: u, v: 0.4, tolerance: tolerance),
                      try cyclic.surfaceDerivatives(u: u + 12, v: 0.4, tolerance: tolerance))
        }
    }
}
