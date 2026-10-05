import CADCore
import CADGeometry
import Foundation

enum ConversionAdmissionSmoke {
    static func runCurvedConversions() throws {
        let tolerance = ModelingTolerance.standard
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let circle = Curve3D.analytic(.circle(center: .origin, normal: .unitZ, radius: 2))
        let circleLimits = GeometryConversionRequirements(maximumPositionError: 5e-4,
            maximumTangentAngle: 0.05, maximumCurvatureError: 0.03)
        try verify(converter.approximateCurve(source: NativeCurveConversionSource(circle, tolerance: tolerance),
            over: ScalarInterval(lower: 0, upper: 0.5), requirements: circleLimits, tolerance: tolerance),
            original: circle, requirements: circleLimits, tolerance: tolerance)

        let rational = Curve3D.bSpline(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 2, y: 0, z: 0), .init(x: 2, y: 2, z: 0), .init(x: 0, y: 2, z: 0)],
            weights: [1, 0.5.squareRoot(), 1]))
        let rationalLimits = GeometryConversionRequirements(maximumPositionError: 0.002,
            maximumTangentAngle: 0.1, maximumCurvatureError: 0.1)
        try verify(converter.approximateCurve(source: NativeCurveConversionSource(rational, tolerance: tolerance),
            over: ScalarInterval(lower: 0, upper: 1), requirements: rationalLimits, tolerance: tolerance),
            original: rational, requirements: rationalLimits, tolerance: tolerance)

        let cylinder = Surface3D.analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2))
        let cylinderLimits = GeometryConversionRequirements(maximumPositionError: 0.001,
            maximumTangentAngle: 0.1, maximumCurvatureError: 0.2)
        let cylinderBox = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 0.15),
            v: try ScalarInterval(lower: -0.5, upper: 0.5))
        try verify(converter.approximateSurface(source: NativeSurfaceConversionSource(cylinder, tolerance: tolerance),
            over: cylinderBox, requirements: cylinderLimits, tolerance: tolerance),
            original: cylinder, requirements: cylinderLimits, tolerance: tolerance)

        let lower = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0.1)])
        var upper = lower
        upper.controlPoints = lower.controlPoints.map { $0 + Vector3D.unitY }
        let ruled = Surface3D.procedural(.ruled(RuledSurface3D(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper))))
        let ruledLimits = GeometryConversionRequirements(maximumPositionError: 0.001,
            maximumTangentAngle: 0.2, maximumCurvatureError: 0.5)
        let unit = try ScalarInterval(lower: 0, upper: 1)
        try verify(converter.approximateSurface(source: NativeSurfaceConversionSource(ruled, tolerance: tolerance),
            over: SurfaceParameterBox(u: unit, v: unit), requirements: ruledLimits, tolerance: tolerance),
            original: ruled, requirements: ruledLimits, tolerance: tolerance)
    }

    static func runPublicationCancellation() async throws {
        for surface in [false, true] {
            for operation in 0..<3 {
                let task = Task {
                    let tolerance = ModelingTolerance.standard
                    let converter: any GeometryConverting = CertifiedGeometryConverter()
                    let requirements = GeometryConversionRequirements(maximumPositionError: 1e-8,
                        maximumTangentAngle: 1e-5, maximumCurvatureError: 1e-5)
                    let unit = try ScalarInterval(lower: 0, upper: 1)
                    if surface {
                        let source = CancellingAnchorSurface()
                        let box = SurfaceParameterBox(u: unit, v: unit)
                        let candidate = BSplineSurface3D(uDegree: 1, vDegree: 1,
                            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                            controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)],
                                [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
                        switch operation {
                        case 0:
                            _ = try converter.approximateSurface(source: source, over: box, requirements: requirements, tolerance: tolerance)
                        case 1:
                            let points = [GeometrySurfaceInterpolationPoint(u: 0, v: 0, point: .origin),
                                .init(u: 1, v: 0, point: .init(x: 1, y: 0, z: 0)),
                                .init(u: 0, v: 1, point: .init(x: 0, y: 1, z: 0)),
                                .init(u: 1, v: 1, point: .init(x: 1, y: 1, z: 0))]
                            _ = try converter.interpolateSurface(source: source, template: candidate, points: points,
                                over: box, requirements: requirements, tolerance: tolerance)
                        default:
                            _ = try converter.certifySurface(source: source, candidate: candidate, over: box,
                                requirements: requirements, tolerance: tolerance)
                        }
                    } else {
                        let source = CancellingAnchorCurve()
                        switch operation {
                        case 0:
                            _ = try converter.approximateCurve(source: source, over: unit, requirements: requirements, tolerance: tolerance)
                        case 1:
                            _ = try converter.interpolateCurve(source: source, at: [0, 1], requirements: requirements, tolerance: tolerance)
                        default:
                            let candidate = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                                controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
                            _ = try converter.certifyCurve(source: source, candidate: candidate, over: unit,
                                requirements: requirements, tolerance: tolerance)
                        }
                    }
                }
                do {
                    try await task.value
                    throw failure("Final source callback cancellation published a conversion value.")
                } catch is CancellationError { }
            }
        }
    }

    private static func verify(_ result: GeometryCurveConversionResult, original: Curve3D,
                               requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws {
        try require(result.curve.degree <= requirements.maximumDegree
            && result.curve.controlPointCount <= requirements.maximumControlPointCount, "Converted curve exceeded requested structural limits.")
        try verify(result.guarantee, requirements: requirements)
        for i in 0...24 {
            let u = result.parameters.lower + result.parameters.width * Double(i) / 24
            let source = try original.differentialGeometry(at: u, tolerance: tolerance)
            let target = try Curve3D.bSpline(result.curve).differentialGeometry(at: u, tolerance: tolerance)
            let cosine = source.firstDerivative.dot(target.firstDerivative) / (source.firstDerivative.length * target.firstDerivative.length)
            try require((source.position - target.position).length <= result.guarantee.positionErrorUpperBound + 1e-12
                && acos(max(-1, min(1, cosine))) <= result.guarantee.tangentAngleUpperBound + 1e-7
                && abs(source.curvature - target.curvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12,
                "An original curved source witness exceeded its continuous guarantee.")
        }
    }

    private static func verify(_ result: GeometrySurfaceConversionResult, original: Surface3D,
                               requirements: GeometryConversionRequirements, tolerance: ModelingTolerance) throws {
        try require(max(result.surface.uDegree, result.surface.vDegree) <= requirements.maximumDegree
            && result.surface.uControlPointCount * result.surface.vControlPointCount <= requirements.maximumControlPointCount,
            "Converted surface exceeded requested structural limits.")
        try verify(result.guarantee, requirements: requirements)
        for i in 0...8 {
            for j in 0...8 {
                let u = result.parameters.u.lower + result.parameters.u.width * Double(i) / 8
                let v = result.parameters.v.lower + result.parameters.v.width * Double(j) / 8
                let source = try original.differentialGeometry(u: u, v: v, tolerance: tolerance)
                let target = try Surface3D.bSpline(result.surface).differentialGeometry(u: u, v: v, tolerance: tolerance)
                try require((source.position - target.position).length <= result.guarantee.positionErrorUpperBound + 1e-12
                    && acos(max(-1, min(1, source.normal.dot(target.normal)))) <= result.guarantee.tangentAngleUpperBound + 1e-7
                    && abs(source.minimumPrincipalCurvature - target.minimumPrincipalCurvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12
                    && abs(source.maximumPrincipalCurvature - target.maximumPrincipalCurvature) <= result.guarantee.curvatureErrorUpperBound + 1e-12,
                    "An original curved surface witness exceeded its continuous guarantee.")
            }
        }
    }

    private static func verify(_ guarantee: GeometryConversionGuarantee, requirements: GeometryConversionRequirements) throws {
        try require(guarantee.certifiedBoxCount > 0
            && guarantee.positionErrorUpperBound <= requirements.maximumPositionError
            && guarantee.tangentAngleUpperBound <= requirements.maximumTangentAngle
            && guarantee.curvatureErrorUpperBound <= requirements.maximumCurvatureError,
            "Conversion did not certify all requested continuous geometric fields.")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> KernelError {
        .init(phase: .validation, code: .classificationFailure, tolerance: .standard, message: message)
    }

    private struct CancellingAnchorCurve: GeometryCurveConversionSource {
        func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws { }
        func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
            (.init(x: parameter, y: 0, z: 0), .unitX)
        }
        func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
            if parameters.width < 1e-12 { withUnsafeCurrentTask { $0?.cancel() } }
            let zero = try ScalarInterval(lower: 0, upper: 0), one = try ScalarInterval(lower: 1, upper: 1)
            return .init(position: .init(x: parameters, y: zero, z: zero),
                firstDerivative: .init(x: one, y: zero, z: zero), secondDerivative: .init(x: zero, y: zero, z: zero))
        }
    }

    private struct CancellingAnchorSurface: GeometrySurfaceConversionSource {
        func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws { }
        func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D { .init(x: u, y: v, z: 0) }
        func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
            if parameters.u.width < 1e-12 && parameters.v.width < 1e-12 { withUnsafeCurrentTask { $0?.cancel() } }
            let zero = try ScalarInterval(lower: 0, upper: 0), one = try ScalarInterval(lower: 1, upper: 1)
            let empty = CoordinateEnclosure3D(x: zero, y: zero, z: zero)
            return .init(position: .init(x: parameters.u, y: parameters.v, z: zero),
                tangentU: .init(x: one, y: zero, z: zero), tangentV: .init(x: zero, y: one, z: zero),
                secondDerivativeUU: empty, secondDerivativeUV: empty, secondDerivativeVV: empty)
        }
    }
}
