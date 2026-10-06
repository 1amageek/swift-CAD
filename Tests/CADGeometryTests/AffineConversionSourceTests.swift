import CADCore
import CADGeometry
import Testing

@Suite("Affine conversion sources", .timeLimit(.minutes(1)))
struct AffineConversionSourceTests {
    private let tolerance = ModelingTolerance.standard

    @Test func reversedCurvePublishesCertifiedGeometry() throws {
        let original = Curve3D.analytic(.circle(center: .origin, normal: .unitZ, radius: 2))
        let source = try AffineCurveConversionSource(source: NativeCurveConversionSource(original, tolerance: tolerance),
            scale: -2, offset: 0.5)
        let range = try ScalarInterval(lower: 0, upper: 0.125)
        let enclosure = try source.enclosure(over: range, tolerance: tolerance)
        for s in [0.0, 0.025, 0.0625, 0.125] {
            let native = try original.differentialGeometry(at: 0.5 - 2 * s, tolerance: tolerance)
            let value = try source.pointAndDerivative(at: s, tolerance: tolerance)
            #expect(enclosure.position.contains(native.position))
            #expect(enclosure.firstDerivative.contains(native.firstDerivative * -2))
            #expect(enclosure.secondDerivative.contains(native.secondDerivative * 4))
            #expect((value.derivative - native.firstDerivative * -2).length < 1e-12)
        }
        let requirements = GeometryConversionRequirements(maximumPositionError: 0.001,
            maximumTangentAngle: 0.05, maximumCurvatureError: 0.05,
            maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let result = try converter.approximateCurve(source: source, over: range,
            requirements: requirements, tolerance: tolerance)
        #expect(result.guarantee.positionErrorUpperBound <= requirements.maximumPositionError)
        #expect(result.guarantee.tangentAngleUpperBound <= requirements.maximumTangentAngle)
        #expect(result.guarantee.curvatureErrorUpperBound <= requirements.maximumCurvatureError)
        for s in [0.0, 0.02, 0.09, 0.125] {
            #expect(try (result.curve.point(at: s, tolerance: tolerance)
                - original.point(at: 0.5 - 2 * s, tolerance: tolerance)).length <= requirements.maximumPositionError)
        }
    }

    @Test func surfaceMixedDerivativeAndReversedNormalAreRetained() throws {
        let curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
        let upper = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 1)])
        let original = Surface3D.procedural(.ruled(.init(startBoundary: .bSpline(curve), endBoundary: .bSpline(upper))))
        let native = try NativeSurfaceConversionSource(original, tolerance: tolerance)
        let source = try AffineSurfaceConversionSource(source: native, uScale: -0.5, uOffset: 0.75, vScale: 0.5, vOffset: 0.25)
        let box = try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1))
        let bounds = try source.enclosure(over: box, tolerance: tolerance)
        // The original ruled law is (u,v,u*v), so the signed mixed derivative is -1/4.
        #expect(bounds.secondDerivativeUV.contains(Vector3D(x: 0, y: 0, z: -0.25)))
        #expect(bounds.tangentU.contains(Vector3D(x: -0.5, y: 0, z: -0.25)))
        #expect(bounds.tangentV.contains(Vector3D(x: 0, y: 0.5, z: 0.25)))
        let result = try CertifiedGeometryConverter().approximateSurface(source: source, over: box,
            requirements: .init(maximumPositionError: 0.001, maximumTangentAngle: 0.1, maximumCurvatureError: 0.1,
                maximumScalarCount: 64_000_000, maximumWorkUnits: 1_000_000_000), tolerance: tolerance)
        for (u, v) in [(0.0, 0.0), (0.23, 0.81), (1.0, 1.0)] {
            #expect(try (result.surface.point(u: u, v: v, tolerance: tolerance)
                - original.point(u: 0.75 - u * 0.5, v: 0.25 + v * 0.5, tolerance: tolerance)).length < 0.001)
        }
    }

    @Test func invalidScaleOverflowAndSourceDomainAreRefused() throws {
        let curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
        let native = try NativeCurveConversionSource(.bSpline(curve), tolerance: tolerance)
        #expect(throws: GeometryConversionError.self) { try AffineCurveConversionSource(source: native, scale: 0, offset: 0) }
        #expect(throws: GeometryConversionError.self) { try AffineSurfaceConversionSource(
            source: NativeSurfaceConversionSource(.analytic(.plane(origin: .origin, normal: .unitZ)), tolerance: tolerance),
            uScale: 1, uOffset: 0, vScale: .infinity, vOffset: 0) }
        let outOfDomain = try AffineCurveConversionSource(source: native, scale: 2, offset: 1)
        #expect(throws: GeometryConversionError.self) { try outOfDomain.validate(
            over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) }
        let overflow = try AffineCurveConversionSource(source: native, scale: .greatestFiniteMagnitude, offset: 0)
        #expect(throws: GeometryConversionError.self) { try overflow.enclosure(
            over: ScalarInterval(lower: 1, upper: 2), tolerance: tolerance) }
    }

    @Test func exactMappedNativeEndpointsRemainAdmissible() throws {
        let curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
        let source = try AffineCurveConversionSource(source: NativeCurveConversionSource(.bSpline(curve), tolerance: tolerance),
            scale: -2, offset: 1)
        let parameters = try ScalarInterval(lower: 0, upper: 0.5)
        let bounds = try source.enclosure(over: parameters, tolerance: tolerance)
        #expect(bounds.position.contains(.origin))
        #expect(bounds.position.contains(Point3D(x: 1, y: 0, z: 0)))
        let converted = try CertifiedGeometryConverter().approximateCurve(source: source, over: parameters,
            requirements: .init(maximumPositionError: 1e-6, maximumTangentAngle: 1e-3, maximumCurvatureError: 1e-3),
            tolerance: tolerance)
        #expect(try converted.curve.point(at: 0, tolerance: tolerance) == Point3D(x: 1, y: 0, z: 0))
        #expect(try converted.curve.point(at: 0.5, tolerance: tolerance) == .origin)
    }

    @Test func curveAndSurfaceCancellationPropagate() async throws {
        let native = try NativeCurveConversionSource(.analytic(.circle(center: .origin, normal: .unitZ, radius: 1)), tolerance: tolerance)
        let source = try AffineCurveConversionSource(source: native, scale: 2, offset: 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try source.enclosure(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let surface = try AffineSurfaceConversionSource(
            source: NativeSurfaceConversionSource(.analytic(.plane(origin: .origin, normal: .unitZ)), tolerance: tolerance),
            uScale: 2, uOffset: 0, vScale: -1, vOffset: 0)
        let surfaceTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try surface.point(u: 0, v: 0, tolerance: tolerance)
        }
        await #expect(throws: CancellationError.self) { try await surfaceTask.value }
    }
}
