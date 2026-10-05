import Foundation
import CADCore
import Testing
import CADGeometry

@Suite("Conversion publication cancellation", .timeLimit(.minutes(1)))
struct GeometryConversionPublicationCancellationTests {
    @Test(arguments: [0, 1, 2])
    func finalSurfaceEnclosureCannotPublishCancelledSuccess(operation: Int) async throws {
        let task = Task {
            let tolerance = ModelingTolerance.standard
            let source = CancellingAnchorSurface()
            let converter: any GeometryConverting = CertifiedGeometryConverter()
            let requirements = GeometryConversionRequirements(maximumPositionError: 1e-8,
                maximumTangentAngle: 1e-5, maximumCurvatureError: 1e-5)
            let interval = try ScalarInterval(lower: 0, upper: 1)
            let box = SurfaceParameterBox(u: interval, v: interval)
            let candidate = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)], [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
            switch operation {
            case 0:
                _ = try converter.approximateSurface(source: source, over: box,
                    requirements: requirements, tolerance: tolerance)
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
        }
        do {
            try await task.value
            Issue.record("Final source cancellation published a surface conversion guarantee.")
        } catch is CancellationError { }
    }

    @Test(arguments: [0, 1, 2])
    func finalCurveEnclosureCannotPublishCancelledSuccess(operation: Int) async throws {
        let task = Task {
            let tolerance = ModelingTolerance.standard
            let source = CancellingAnchorCurve()
            let converter: any GeometryConverting = CertifiedGeometryConverter()
            let requirements = GeometryConversionRequirements(maximumPositionError: 1e-8,
                maximumTangentAngle: 1e-5, maximumCurvatureError: 1e-5)
            let interval = try ScalarInterval(lower: 0, upper: 1)
            switch operation {
            case 0:
                _ = try converter.approximateCurve(source: source, over: interval,
                    requirements: requirements, tolerance: tolerance)
            case 1:
                _ = try converter.interpolateCurve(source: source, at: [0, 1],
                    requirements: requirements, tolerance: tolerance)
            default:
                let candidate = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                    controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
                _ = try converter.certifyCurve(source: source, candidate: candidate, over: interval,
                    requirements: requirements, tolerance: tolerance)
            }
        }
        do {
            try await task.value
            Issue.record("Final source cancellation published a conversion guarantee.")
        } catch is CancellationError { }
    }
}

private struct CancellingAnchorSurface: GeometrySurfaceConversionSource {
    func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws { }
    func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D { .init(x: u, y: v, z: 0) }
    func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        if parameters.u.width < 1e-12 && parameters.v.width < 1e-12 {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let zero = try ScalarInterval(lower: 0, upper: 0), one = try ScalarInterval(lower: 1, upper: 1)
        let empty = CoordinateEnclosure3D(x: zero, y: zero, z: zero)
        return .init(position: .init(x: parameters.u, y: parameters.v, z: zero),
            tangentU: .init(x: one, y: zero, z: zero), tangentV: .init(x: zero, y: one, z: zero),
            secondDerivativeUU: empty, secondDerivativeUV: empty, secondDerivativeVV: empty)
    }
}

private struct CancellingAnchorCurve: GeometryCurveConversionSource {
    func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws { }
    func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        (.init(x: parameter, y: 0, z: 0), .unitX)
    }
    func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        if parameters.width < 1e-12 {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let zero = try ScalarInterval(lower: 0, upper: 0)
        let one = try ScalarInterval(lower: 1, upper: 1)
        return CurveDifferentialEnclosure(position: .init(x: parameters, y: zero, z: zero),
            firstDerivative: .init(x: one, y: zero, z: zero), secondDerivative: .init(x: zero, y: zero, z: zero))
    }
}
