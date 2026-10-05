import Foundation
import CADCore
import Testing
import Synchronization
@testable import CADGeometry

@Suite("Certified geometry conversion", .timeLimit(.minutes(1)))
struct GeometryConversionTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func analyticCurveApproximationAndNonuniformInterpolationMeetGeometricLimits() throws {
        let curve = Curve3D.analytic(.circle(center: .origin, normal: .unitZ, radius: 2))
        let source = try NativeCurveConversionSource(curve, tolerance: tolerance)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let range = try ScalarInterval(lower: 0, upper: 0.5)
        let limits = GeometryConversionRequirements(maximumPositionError: 5e-4, maximumTangentAngle: 0.05, maximumCurvatureError: 0.03, maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000)
        let approximation = try converter.approximateCurve(source: source, over: range, requirements: limits, tolerance: tolerance)
        try verifyCurve(approximation, source: curve, limits: limits)
        let parameters = [0.0, 0.17, 0.43, 0.5]
        let interpolation = try converter.interpolateCurve(source: source, at: parameters, requirements: limits, tolerance: tolerance)
        try verifyCurve(interpolation, source: curve, limits: limits)
        for parameter in parameters {
            #expect(try (interpolation.curve.point(at: parameter, tolerance: tolerance)
                - curve.point(at: parameter, tolerance: tolerance)).length < 1e-13)
        }
        #expect(source.curve == curve)
    }

    @Test
    func rationalNURBSCurveAndProceduralSurfaceExecuteConstructionAndAdmission() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 2, y: 0, z: 0), .init(x: 2, y: 2, z: 0), .init(x: 0, y: 2, z: 0)],
            weights: [1, sqrt(0.5), 1])
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let limits = GeometryConversionRequirements(maximumPositionError: 0.002, maximumTangentAngle: 0.1, maximumCurvatureError: 0.1, maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000)
        let result = try converter.approximateCurve(source: NativeCurveConversionSource(.bSpline(curve), tolerance: tolerance),
            over: ScalarInterval(lower: 0, upper: 1), requirements: limits, tolerance: tolerance)
        try verifyCurve(result, source: .bSpline(curve), limits: limits)
        #expect(result.curve.degree == 3)
        let lower = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0.1)])
        var upper = lower
        upper.controlPoints = lower.controlPoints.map { $0 + Vector3D.unitY }
        let surface = Surface3D.procedural(.ruled(RuledSurface3D(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper))))
        let surfaceLimits = GeometryConversionRequirements(maximumPositionError: 0.001, maximumTangentAngle: 0.2, maximumCurvatureError: 0.5, maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000)
        let converted = try converter.approximateSurface(source: NativeSurfaceConversionSource(surface, tolerance: tolerance),
            over: rectangle(), requirements: surfaceLimits, tolerance: tolerance)
        try verifySurface(converted, source: surface, limits: surfaceLimits)
        #expect(converted.surface.uDegree == 3 && converted.surface.vDegree == 3)
        #expect(converted.surface.uControlPointCount * converted.surface.vControlPointCount == 16)
        #expect(upper.controlPoints == lower.controlPoints.map { $0 + Vector3D.unitY })
    }

    @Test
    func analyticAndNURBSSurfacesRetainChartAndPrincipalCurvatureBounds() throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let cylinder = Surface3D.analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2))
        let box = try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 0.15), v: ScalarInterval(lower: -0.5, upper: 0.5))
        let limits = GeometryConversionRequirements(maximumPositionError: 0.001, maximumTangentAngle: 0.1, maximumCurvatureError: 0.2, maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000)
        let result = try converter.approximateSurface(source: NativeSurfaceConversionSource(cylinder, tolerance: tolerance),
            over: box, requirements: limits, tolerance: tolerance)
        try verifySurface(result, source: cylinder, limits: limits)
        #expect(result.surface.uKnots.first == box.u.lower && result.surface.uKnots.last == box.u.upper)
        #expect(result.surface.vKnots.first == box.v.lower && result.surface.vKnots.last == box.v.upper)
        let repeated = try converter.approximateSurface(source: NativeSurfaceConversionSource(.bSpline(result.surface), tolerance: tolerance),
            over: box, requirements: limits, tolerance: tolerance)
        try verifySurface(repeated, source: .bSpline(result.surface), limits: limits)
    }

    @Test
    func explicitSurfaceInterpolationPreservesBasisAndCertifiesWholeRectangle() throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let source = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
        let box = try rectangle()
        let adapter = try NativeSurfaceConversionSource(source, tolerance: tolerance)
        let points = try [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map { u, v in
            GeometrySurfaceInterpolationPoint(u: u, v: v, point: try adapter.point(u: u, v: v, tolerance: tolerance))
        }
        let template = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[points[0].point + Vector3D.unitZ * 0.01, points[1].point + Vector3D.unitZ * 0.01],
                [points[2].point + Vector3D.unitZ * 0.01, points[3].point + Vector3D.unitZ * 0.01]])
        let limits = GeometryConversionRequirements(maximumPositionError: 1e-8, maximumTangentAngle: 1e-5,
            maximumCurvatureError: 1e-5, maximumDegree: 1, maximumControlPointCount: 4)
        let result = try converter.interpolateSurface(source: adapter, template: template, points: points,
            over: box, requirements: limits, tolerance: tolerance)
        #expect(result.surface.uKnots == template.uKnots && result.surface.vKnots == template.vKnots)
        #expect(result.surface.weights == template.weights)
        try verifySurface(result, source: source, limits: limits)
        for constraint in points {
            #expect(try (result.surface.point(u: constraint.u, v: constraint.v, tolerance: tolerance) - constraint.point).length < 1e-8)
        }
        #expect(template.controlPoints[0][0] == points[0].point + Vector3D.unitZ * 0.01)
    }

    @Test
    func sampledAliasCannotAuthorizeContinuousConversion() throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let source = SampledAliasSurface()
        let box = try rectangle()
        let sampled = try MappedBSplineSurfaceFitter.fit(layout: .init(uDegree: 3, vDegree: 3, uSpans: 1, vSpans: 1),
            u: box.u, v: box.v, tolerance: tolerance) { u, v in try source.point(u: u, v: v, tolerance: tolerance) }
        #expect(sampled.maximumDeviation < 1e-12)
        #expect(try (source.point(u: 1.0 / 24, v: 0.5, tolerance: tolerance)
            - sampled.surface.point(u: 1.0 / 24, v: 0.5, tolerance: tolerance)).length > 0.99)
        let limits = GeometryConversionRequirements(maximumPositionError: 0.01, maximumTangentAngle: 0.1,
            maximumCurvatureError: 0.1, maximumCandidateCount: 1, maximumCertificationBoxes: 8)
        #expect(throws: GeometryConversionError.self) {
            _ = try converter.certifySurface(source: source, candidate: sampled.surface, over: box, requirements: limits, tolerance: tolerance)
        }
        #expect(throws: GeometryConversionError.self) {
            _ = try converter.approximateSurface(source: source, over: box, requirements: limits, tolerance: tolerance)
        }
    }

    @Test
    func domainDegreeControlScalarWorkAndEnclosureLimitsRefuseAtomically() throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)]))
        let source = try NativeCurveConversionSource(curve, tolerance: tolerance)
        let interval = try ScalarInterval(lower: 0, upper: 1)
        let valid = GeometryConversionRequirements(maximumPositionError: 1e-8, maximumTangentAngle: 1e-5, maximumCurvatureError: 1e-5)
        for changed in 0..<4 {
            var limits = valid
            switch changed {
            case 0: limits.maximumControlPointCount = 3
            case 1: limits.maximumScalarCount = 1
            case 2: limits.maximumWorkUnits = 1
            default: limits.maximumDegree = 0
            }
            #expect(throws: GeometryConversionError.self) { _ = try converter.approximateCurve(source: source, over: interval, requirements: limits, tolerance: tolerance) }
        }
        #expect(throws: GeometryConversionError.self) {
            _ = try converter.approximateCurve(source: source, over: ScalarInterval(lower: -0.1, upper: 1), requirements: valid, tolerance: tolerance)
        }
        #expect(throws: GeometryConversionError.self) {
            _ = try converter.interpolateCurve(source: source, at: [0, 0.5, 0.5, 1], requirements: valid, tolerance: tolerance)
        }
        let candidate = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [.origin, .init(x: 1.0 / 3, y: 0, z: 0), .init(x: 2.0 / 3, y: 0, z: 0), .init(x: 1, y: 0, z: 0)])
        var lowerDegree = valid; lowerDegree.maximumDegree = 2
        #expect(throws: GeometryConversionError.self) {
            _ = try converter.certifyCurve(source: source, candidate: candidate, over: interval, requirements: lowerDegree, tolerance: tolerance)
        }
        let certified = try converter.certifyCurve(source: source, candidate: candidate, over: interval, requirements: valid, tolerance: tolerance)
        #expect(certified.positionErrorUpperBound <= valid.maximumPositionError)
        #expect(certified.certifiedBoxCount == 1)
        #expect(source.curve == curve)
    }

    @Test
    func sourceFailuresAndCancellationPropagateThroughPublicProtocol() async throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let limits = GeometryConversionRequirements(maximumPositionError: 0.01, maximumTangentAngle: 0.1, maximumCurvatureError: 0.1)
        let box = try rectangle()
        #expect(throws: ConversionSourceFailure.expected) {
            _ = try converter.approximateSurface(source: FailingSurface(), over: box, requirements: limits, tolerance: tolerance)
        }
        let source = try NativeSurfaceConversionSource(.analytic(.plane(origin: .origin, normal: .unitZ)), tolerance: tolerance)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try converter.approximateSurface(source: source, over: box, requirements: limits, tolerance: tolerance)
        }
        do { _ = try await task.value; Issue.record("Cancelled conversion published a surface.") }
        catch is CancellationError { }
        catch { Issue.record("Cancellation became \(error).") }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The main B-spline representation has
    // no periodic construction capability. The complete negative-cycle and nested
    // image fixture remains in commit 1017954's parity test owner and must execute
    // after periodic representation integration before full G6 can be completed.


    @Test
    func highDegreeNativeProbeIsChargedBeforeTriangularSplitAllocation() throws {
        let candidate = BSplineCurve3D(degree: 16, knots: Array(repeating: 0.0, count: 17) + Array(repeating: 1.0, count: 17),
            controlPoints: (0...16).map { Point3D(x: Double($0) / 16, y: 0, z: 0) })
        let source = try NativeCurveConversionSource(.analytic(.line(origin: .origin, direction: .unitX)), tolerance: tolerance)
        let interval = try ScalarInterval(lower: 0, upper: 1)
        let limits = GeometryConversionRequirements(maximumPositionError: 1e-6, maximumTangentAngle: 1e-5,
            maximumCurvatureError: 1e-5, maximumDegree: 16, maximumControlPointCount: 17,
            maximumCertificationBoxes: 1, maximumScalarCount: 784)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        do {
            _ = try converter.certifyCurve(source: source, candidate: candidate, over: interval, requirements: limits, tolerance: tolerance)
            Issue.record("High-degree triangular split exceeded its admitted scalar budget.")
        } catch GeometryConversionError.resourceLimitExceeded { }
        // One 17+...+1 homogeneous split alone generates 153*8 = 1,224 slots.
        var budget = GeometryConversionBudget(limits)
        do {
            try GeometryConversionTargetCost.curve(candidate).chargeProbe(over: interval, tolerance: tolerance, budget: &budget)
            Issue.record("Native probe cost did not account for degree-dependent levels.")
        } catch GeometryConversionError.resourceLimitExceeded { }
        #expect(try (candidate.point(at: 0.37, tolerance: tolerance) - source.pointAndDerivative(at: 0.37, tolerance: tolerance).point).length < 1e-12)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test
    func sourcePublicToleranceRejectionPropagatesOnceThroughBothApproximationLoops() throws {
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let curve = AdmissionFailingCurve()
        let surface = AdmissionFailingSurface()
        let curveLimits = GeometryConversionRequirements(maximumPositionError: 0.01, maximumTangentAngle: 0.1,
            maximumCurvatureError: 0.1, maximumControlPointCount: 4, maximumCandidateCount: 2)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try converter.approximateCurve(source: curve, over: ScalarInterval(lower: 0, upper: 1),
                requirements: curveLimits, tolerance: tolerance)
        }
        #expect(curve.calls.withLock { $0 } == 1)
        let surfaceLimits = GeometryConversionRequirements(maximumPositionError: 0.01, maximumTangentAngle: 0.1,
            maximumCurvatureError: 0.1, maximumControlPointCount: 16, maximumCandidateCount: 2)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try converter.approximateSurface(source: surface, over: rectangle(), requirements: surfaceLimits, tolerance: tolerance)
        }
        #expect(surface.calls.withLock { $0 } == 1)
    }

    private func rectangle() throws -> SurfaceParameterBox {
        try .init(u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1))
    }
    private func verifyCurve(_ result: GeometryCurveConversionResult, source: Curve3D, limits: GeometryConversionRequirements) throws {
        #expect(result.curve.degree <= limits.maximumDegree && result.curve.controlPointCount <= limits.maximumControlPointCount)
        #expect(result.guarantee.certifiedBoxCount > 0)
        #expect(result.guarantee.positionErrorUpperBound <= limits.maximumPositionError)
        #expect(result.guarantee.tangentAngleUpperBound <= limits.maximumTangentAngle)
        #expect(result.guarantee.curvatureErrorUpperBound <= limits.maximumCurvatureError)
        for i in 0...137 {
            let parameter = result.parameters.lower + result.parameters.width * Double(i) / 137
            let a = try source.differentialGeometry(at: parameter, tolerance: tolerance)
            let b = try Curve3D.bSpline(result.curve).differentialGeometry(at: parameter, tolerance: tolerance)
            #expect((a.position - b.position).length <= result.guarantee.positionErrorUpperBound + 1e-12)
            #expect(acos(max(-1, min(1, a.tangent.dot(b.tangent)))) <= result.guarantee.tangentAngleUpperBound + 1e-7)
            #expect(abs(a.curvature - b.curvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12)
        }
    }
    private func verifySurface(_ result: GeometrySurfaceConversionResult, source: Surface3D, limits: GeometryConversionRequirements) throws {
        #expect(max(result.surface.uDegree, result.surface.vDegree) <= limits.maximumDegree)
        #expect(result.surface.uControlPointCount * result.surface.vControlPointCount <= limits.maximumControlPointCount)
        #expect(result.guarantee.certifiedBoxCount > 0)
        #expect(result.guarantee.positionErrorUpperBound <= limits.maximumPositionError)
        #expect(result.guarantee.tangentAngleUpperBound <= limits.maximumTangentAngle)
        #expect(result.guarantee.curvatureErrorUpperBound <= limits.maximumCurvatureError)
        for i in 0...11 {
            for j in 0...13 {
                let u = result.parameters.u.lower + result.parameters.u.width * Double(i) / 11
                let v = result.parameters.v.lower + result.parameters.v.width * Double(j) / 13
                let a = try source.differentialGeometry(u: u, v: v, tolerance: tolerance)
                let b = try Surface3D.bSpline(result.surface).differentialGeometry(u: u, v: v, tolerance: tolerance)
                #expect((a.position - b.position).length <= result.guarantee.positionErrorUpperBound + 1e-12)
                #expect(acos(max(-1, min(1, a.normal.dot(b.normal)))) <= result.guarantee.tangentAngleUpperBound + 1e-7)
                #expect(abs(a.minimumPrincipalCurvature - b.minimumPrincipalCurvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12)
                #expect(abs(a.maximumPrincipalCurvature - b.maximumPrincipalCurvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12)
            }
        }
    }
}

private struct SampledAliasSurface: GeometrySurfaceConversionSource {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws { }
    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        .init(x: u, y: v, z: sin(12 * Double.pi * u))
    }
    func enclosure(over p: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        func vector(_ x: ScalarInterval, _ y: ScalarInterval, _ z: ScalarInterval) -> CoordinateEnclosure3D { .init(x: x, y: y, z: z) }
        let zero = try ScalarInterval(lower: 0, upper: 0), one = try ScalarInterval(lower: 1, upper: 1)
        // Broad, valid continuous bounds deliberately reveal the sampled alias.
        let frequency = (12 * Double.pi).nextUp
        return try .init(position: vector(p.u, p.v, ScalarInterval(lower: -1, upper: 1)),
            tangentU: vector(one, zero, ScalarInterval(lower: -frequency, upper: frequency)), tangentV: vector(zero, one, zero),
            secondDerivativeUU: vector(zero, zero, ScalarInterval(lower: -(frequency * frequency).nextUp, upper: (frequency * frequency).nextUp)),
            secondDerivativeUV: vector(zero, zero, zero), secondDerivativeVV: vector(zero, zero, zero))
    }
}
private enum ConversionSourceFailure: Error, Equatable { case expected }
private struct FailingSurface: GeometrySurfaceConversionSource {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws { }
    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D { throw ConversionSourceFailure.expected }
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure { throw ConversionSourceFailure.expected }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
private final class AdmissionFailingCurve: GeometryCurveConversionSource {
    let calls = Mutex(0)
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws { }
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        (.init(x: parameter, y: 0, z: 0), .unitX)
    }
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        calls.withLock { $0 += 1 }
        throw GeometryConversionError.toleranceRejected
    }
}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
private final class AdmissionFailingSurface: GeometrySurfaceConversionSource {
    let calls = Mutex(0)
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws { }
    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D { .init(x: u, y: v, z: 0) }
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        calls.withLock { $0 += 1 }
        throw GeometryConversionError.toleranceRejected
    }
}
