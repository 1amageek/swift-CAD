import Foundation
import CADCore
import Testing
@testable import CADGeometry

@Suite("Default-budget curved conversion", .timeLimit(.minutes(1)))
struct GeometryConversionDefaultAdmissionTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func originalCubicPowerJetEnclosesIndependentLawOnItsNativeChart() throws {
        // The stored integer controls define (3t, 3t^2, t^3), t = (u + 2) / 5.
        let curve = BSplineCurve3D(degree: 3, knots: [-2, -2, -2, -2, 3, 3, 3, 3],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .init(x: 2, y: 1, z: 0), .init(x: 3, y: 3, z: 1)],
            weights: [2, 2, 2, 2])
        let target = try PolynomialCurveConversionTarget(curve, tolerance: tolerance)
        for box in [try ScalarInterval(lower: -2, upper: 3), try ScalarInterval(lower: -1, upper: 2)] {
            let enclosure = try target.enclosure(over: box, tolerance: tolerance)
            for i in 0...16 {
                let u = box.lower + box.width * Double(i) / 16, t = (u + 2) / 5
                #expect(enclosure.position.contains(Point3D(x: 3 * t, y: 3 * t * t, z: t * t * t)))
                #expect(enclosure.firstDerivative.contains(Vector3D(x: 3.0 / 5, y: 6 * t / 5, z: 3 * t * t / 5)))
                #expect(enclosure.secondDerivative.contains(Vector3D(x: 0, y: 6.0 / 25, z: 6 * t / 25)))
            }
        }
        #expect(!PolynomialCurveConversionTarget.accepts(BSplineCurve3D(degree: 3, knots: curve.knots,
            controlPoints: curve.controlPoints, weights: [2, 2, 3, 2])))
    }

    @Test
    func originalTensorPowerJetEnclosesIndependentMixedDerivativeLaw() throws {
        // The stored integer controls define (2s, 2t, 2s^2 + 2t^2 + 4st).
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [-2, -2, -2, 3, 3, 3], vKnots: [4, 4, 4, 8, 8, 8],
            controlPoints: [
                [.origin, .init(x: 1, y: 0, z: 0), .init(x: 2, y: 0, z: 2)],
                [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 1), .init(x: 2, y: 1, z: 4)],
                [.init(x: 0, y: 2, z: 2), .init(x: 1, y: 2, z: 4), .init(x: 2, y: 2, z: 8)]
            ], weights: Array(repeating: Array(repeating: 3, count: 3), count: 3))
        let target = try PolynomialSurfaceConversionTarget(surface, tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: -1, upper: 2), v: try ScalarInterval(lower: 5, upper: 7))
        let enclosure = try target.enclosure(over: box, tolerance: tolerance)
        for i in 0...8 {
            for j in 0...8 {
                let u = box.u.lower + box.u.width * Double(i) / 8, s = (u + 2) / 5
                let v = box.v.lower + box.v.width * Double(j) / 8, t = (v - 4) / 4
                #expect(enclosure.position.contains(Point3D(x: 2 * s, y: 2 * t, z: 2 * s * s + 2 * t * t + 4 * s * t)))
                #expect(enclosure.tangentU.contains(Vector3D(x: 2.0 / 5, y: 0, z: (4 * s + 4 * t) / 5)))
                #expect(enclosure.tangentV.contains(Vector3D(x: 0, y: 2.0 / 4, z: (4 * s + 4 * t) / 4)))
                #expect(enclosure.secondDerivativeUU.contains(Vector3D(x: 0, y: 0, z: 4.0 / 25)))
                #expect(enclosure.secondDerivativeUV.contains(Vector3D(x: 0, y: 0, z: 4.0 / 20)))
                #expect(enclosure.secondDerivativeVV.contains(Vector3D(x: 0, y: 0, z: 4.0 / 16)))
            }
        }
    }

    @Test
    func curvedAnalyticCurveRefinesWithinUnchangedDefaults() throws {
        let source = Curve3D.analytic(.circle(center: .origin, normal: .unitZ, radius: 2))
        let interval = try ScalarInterval(lower: 0, upper: 0.5)
        let requirements = GeometryConversionRequirements(maximumPositionError: 5e-4,
            maximumTangentAngle: 0.05, maximumCurvatureError: 0.03)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let result = try converter.approximateCurve(source: NativeCurveConversionSource(source, tolerance: tolerance),
            over: interval, requirements: requirements, tolerance: tolerance)
        try verify(result, source: source, requirements: requirements)
    }

    @Test
    func varyingWeightNURBSCurveRefinesWithinUnchangedDefaults() throws {
        let original = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 2, y: 0, z: 0), .init(x: 2, y: 2, z: 0), .init(x: 0, y: 2, z: 0)],
            weights: [1, 0.5.squareRoot(), 1])
        let source = Curve3D.bSpline(original)
        let requirements = GeometryConversionRequirements(maximumPositionError: 0.002,
            maximumTangentAngle: 0.1, maximumCurvatureError: 0.1)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let result = try converter.approximateCurve(source: NativeCurveConversionSource(source, tolerance: tolerance),
            over: ScalarInterval(lower: 0, upper: 1), requirements: requirements, tolerance: tolerance)
        try verify(result, source: source, requirements: requirements)
        #expect(original.weights == [1, 0.5.squareRoot(), 1])
    }

    @Test
    func curvedAnalyticSurfaceRetainsItsChartWithinUnchangedDefaults() throws {
        let source = Surface3D.analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2))
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 0.15),
            v: try ScalarInterval(lower: -0.5, upper: 0.5))
        let requirements = GeometryConversionRequirements(maximumPositionError: 0.001,
            maximumTangentAngle: 0.1, maximumCurvatureError: 0.2)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let result = try converter.approximateSurface(source: NativeSurfaceConversionSource(source, tolerance: tolerance),
            over: box, requirements: requirements, tolerance: tolerance)
        try verify(result, source: source, requirements: requirements)
        #expect(result.parameters == box)
    }

    @Test
    func curvedProceduralSurfaceRetainsItsLawWithinUnchangedDefaults() throws {
        let lower = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0.1)])
        var upper = lower
        upper.controlPoints = lower.controlPoints.map { $0 + Vector3D.unitY }
        let source = Surface3D.procedural(.ruled(RuledSurface3D(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper))))
        let interval = try ScalarInterval(lower: 0, upper: 1)
        let requirements = GeometryConversionRequirements(maximumPositionError: 0.001,
            maximumTangentAngle: 0.2, maximumCurvatureError: 0.5)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let result = try converter.approximateSurface(source: NativeSurfaceConversionSource(source, tolerance: tolerance),
            over: SurfaceParameterBox(u: interval, v: interval), requirements: requirements, tolerance: tolerance)
        try verify(result, source: source, requirements: requirements)
    }

    private func verify(_ result: GeometryCurveConversionResult, source: Curve3D,
        requirements: GeometryConversionRequirements) throws {
        #expect(result.curve.degree <= requirements.maximumDegree)
        #expect(result.curve.controlPointCount <= requirements.maximumControlPointCount)
        try verify(result.guarantee, requirements: requirements)
        for index in 0...24 {
            let parameter = result.parameters.lower + result.parameters.width * Double(index) / 24
            let a = try source.differentialGeometry(at: parameter, tolerance: tolerance)
            let b = try Curve3D.bSpline(result.curve).differentialGeometry(at: parameter, tolerance: tolerance)
            #expect((a.position - b.position).length <= result.guarantee.positionErrorUpperBound + 1e-12)
            let cosine = a.firstDerivative.dot(b.firstDerivative) / (a.firstDerivative.length * b.firstDerivative.length)
            #expect(acos(max(-1, min(1, cosine))) <= result.guarantee.tangentAngleUpperBound + 1e-7)
            #expect(abs(a.curvature - b.curvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12)
        }
    }

    private func verify(_ result: GeometrySurfaceConversionResult, source: Surface3D,
        requirements: GeometryConversionRequirements) throws {
        #expect(max(result.surface.uDegree, result.surface.vDegree) <= requirements.maximumDegree)
        #expect(result.surface.uControlPointCount * result.surface.vControlPointCount <= requirements.maximumControlPointCount)
        try verify(result.guarantee, requirements: requirements)
        for i in 0...8 {
            for j in 0...8 {
                let u = result.parameters.u.lower + result.parameters.u.width * Double(i) / 8
                let v = result.parameters.v.lower + result.parameters.v.width * Double(j) / 8
                let a = try source.differentialGeometry(u: u, v: v, tolerance: tolerance)
                let b = try Surface3D.bSpline(result.surface).differentialGeometry(u: u, v: v, tolerance: tolerance)
                #expect((a.position - b.position).length <= result.guarantee.positionErrorUpperBound + 1e-12)
                #expect(acos(max(-1, min(1, a.normal.dot(b.normal)))) <= result.guarantee.tangentAngleUpperBound + 1e-7)
                #expect(abs(a.minimumPrincipalCurvature - b.minimumPrincipalCurvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12)
                #expect(abs(a.maximumPrincipalCurvature - b.maximumPrincipalCurvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12)
            }
        }
    }

    private func verify(_ guarantee: GeometryConversionGuarantee, requirements: GeometryConversionRequirements) throws {
        #expect(guarantee.certifiedBoxCount > 0)
        #expect(guarantee.positionErrorUpperBound <= requirements.maximumPositionError)
        #expect(guarantee.tangentAngleUpperBound <= requirements.maximumTangentAngle)
        #expect(guarantee.curvatureErrorUpperBound <= requirements.maximumCurvatureError)
    }
}
