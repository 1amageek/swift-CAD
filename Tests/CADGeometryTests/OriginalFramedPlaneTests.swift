import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Original framed infinite plane", .timeLimit(.minutes(1)))
struct OriginalFramedPlaneTests {
    private let tolerance = ModelingTolerance.standard
    private let origin = Point3D(x: 2, y: 3, z: 4)
    private let authoredU = Vector3D(x: 0.6, y: 0.8, z: 0)
    private let authoredV = Vector3D(x: -0.8, y: 0.6, z: 0)

    private var source: Surface3D {
        .plane(Plane3D(origin: origin, normal: .unitZ, uDirection: authoredU))
    }

    @Test
    func literalNativeLawAndProjectionRetainTheAuthoredAxes() throws {
        let surface = source
        #expect(surface.uDomain == .unbounded)
        #expect(surface.vDomain == .unbounded)
        let point = try surface.point(u: 5, v: -2, tolerance: tolerance)
        expectPoint(point, equals: Point3D(x: 6.6, y: 5.8, z: 4))
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
        #expect(abs(projection.u - 5) < 1e-13)
        #expect(abs(projection.v + 2) < 1e-13)
        let differential = try surface.differentialGeometry(u: 5, v: -2, tolerance: tolerance)
        #expect(differential.tangentU == authoredU)
        #expect(differential.tangentV == authoredV)
        #expect(differential.normal == .unitZ)
        #expect(differential.minimumPrincipalCurvature == 0)
        #expect(differential.maximumPrincipalCurvature == 0)
    }

    @Test
    func everyDifferentialVisitorEnclosesTheLiteralInfiniteLaw() throws {
        let surface = source
        let third = try surface.parameterDerivativesThroughThirdOrder(u: 5, v: -2, tolerance: tolerance)
        expectPoint(third.position, equals: Point3D(x: 6.6, y: 5.8, z: 4))
        #expect(third.tangentU == authoredU)
        #expect(third.tangentV == authoredV)
        #expect(third.secondDerivativeUU == .zero)
        #expect(third.secondDerivativeUV == .zero)
        #expect(third.secondDerivativeVV == .zero)
        #expect(third.thirdDerivativeUUU == .zero)
        #expect(third.thirdDerivativeUUV == .zero)
        #expect(third.thirdDerivativeUVV == .zero)
        #expect(third.thirdDerivativeVVV == .zero)
        let taylor = try surface.taylorJet(u: 5, v: -2, throughOrder: 3, tolerance: tolerance)
        #expect(taylor.derivative(uOrder: 1, vOrder: 0) == authoredU)
        #expect(taylor.derivative(uOrder: 0, vOrder: 1) == authoredV)
        for uOrder in 0...3 {
            for vOrder in 0...(3 - uOrder) where uOrder + vOrder >= 2 {
                #expect(taylor.derivative(uOrder: uOrder, vOrder: vOrder) == .zero)
            }
        }
        let box = try SurfaceParameterBox(u: ScalarInterval(lower: 4, upper: 6),
            v: ScalarInterval(lower: -3, upper: -1))
        let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(of: surface, over: box, tolerance: tolerance)
        for (u, v) in [(4.0, -3.0), (6.0, -1.0), (5.0, -2.0)] {
            #expect(jet.x.value.contains(2 + 0.6 * u - 0.8 * v))
            #expect(jet.y.value.contains(3 + 0.8 * u + 0.6 * v))
            #expect(jet.z.value.contains(4))
        }
        #expect(jet.x.derivativeU.contains(0.6))
        #expect(jet.y.derivativeU.contains(0.8))
        #expect(jet.x.derivativeV.contains(-0.8))
        #expect(jet.y.derivativeV.contains(0.6))
        #expect(jet.z.derivativeU.contains(0))
        #expect(jet.z.derivativeV.contains(0))
    }

    @Test
    func rigidReflectionAndOffsetRetainNativeParameters() throws {
        let reflection = try RigidTransform3D(basisX: -Vector3D.unitX, basisY: .unitY,
            basisZ: .unitZ, translation: Vector3D(x: 10, y: -1, z: 2), tolerance: tolerance)
        let reflected = try reflection.applying(to: source, tolerance: tolerance)
        expectPoint(try reflected.point(u: 5, v: -2, tolerance: tolerance),
            equals: Point3D(x: 3.4, y: 4.8, z: 6))
        let reflectedJet = try reflected.parameterDerivativesThroughThirdOrder(u: 5, v: -2, tolerance: tolerance)
        #expect(reflectedJet.tangentU == Vector3D(x: -0.6, y: 0.8, z: 0))
        #expect(reflectedJet.tangentV == Vector3D(x: 0.8, y: 0.6, z: 0))
        let rotation = try RigidTransform3D(basisX: .unitY, basisY: -Vector3D.unitX,
            basisZ: .unitZ, translation: .zero, tolerance: tolerance)
        expectPoint(try rotation.applying(to: source, tolerance: tolerance)
            .point(u: 5, v: -2, tolerance: tolerance), equals: Point3D(x: -5.8, y: 6.6, z: 4))
        let offset = OffsetSurface3D(source: source, distance: 0.5)
        let equivalent = try #require(try offset.exactChartPreservingSurface(tolerance: tolerance))
        expectPoint(try equivalent.point(u: 5, v: -2, tolerance: tolerance),
            equals: Point3D(x: 6.6, y: 5.8, z: 4.5))
        #expect(try equivalent.parameterDerivatives(u: 5, v: -2, tolerance: tolerance).tangentU == authoredU)
    }

    @Test
    func rationalChartAndHarmonicLiftUseTheStoredAxes() throws {
        let map = try AnalyticSurfaceRationalParameterMap(surface: source,
            periodicSeamOffset: 0, tolerance: tolerance)
        // The canonical rational plane has U=+Y and V=-X for this normal.
        let native = try map.parameter(fromRational: SurfaceParameter(u: 2, v: 3), tolerance: tolerance)
        #expect(abs(native.u + 0.2) < 1e-13)
        #expect(abs(native.v - 3.6) < 1e-13)
        expectPoint(try source.point(u: native.u, v: native.v, tolerance: tolerance),
            equals: Point3D(x: -1, y: 5, z: 4))
        let circle = Curve3D.circle(Circle3D(center: origin, normal: .unitZ, radius: 1))
        let pcurve = SurfaceParameterCurve.harmonic(center: Point2D(x: 0, y: 0),
            cosine: Point2D(x: 0.6, y: -0.8), sine: Point2D(x: 0.8, y: 0.6),
            startParameter: 0, endParameter: 0.7)
        try DefaultCurveSurfaceCorrespondenceValidator().validate(curve: circle, from: 0, to: 0.7,
            surface: source, parameterCurve: pcurve,
            options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 65_536), tolerance: tolerance)
    }

    @Test
    func legacyTwoFieldsAndExplicitAxesSurviveCodable() throws {
        let oldJSON = Data(#"{"origin":{"x":2,"y":3,"z":4},"normal":{"x":0,"y":0,"z":1}}"#.utf8)
        let legacy = try JSONDecoder().decode(Plane3D.self, from: oldJSON)
        #expect(legacy.uDirection == nil)
        let encodedLegacy = try JSONEncoder().encode(legacy)
        let oldObject = try #require(JSONSerialization.jsonObject(with: encodedLegacy) as? [String: Any])
        #expect(Set(oldObject.keys) == ["origin", "normal"])
        expectPoint(try Surface3D.plane(legacy).point(u: 5, v: -2, tolerance: tolerance),
            equals: Point3D(x: 7, y: 1, z: 4))
        let restored = try JSONDecoder().decode(Surface3D.self, from: JSONEncoder().encode(source))
        #expect(restored == source)
        expectPoint(try restored.point(u: 5, v: -2, tolerance: tolerance),
            equals: Point3D(x: 6.6, y: 5.8, z: 4))
    }

    @Test
    func invalidAxesRefuseBeforeEvaluation() throws {
        #expect(throws: KernelError.self) {
            try Plane3D(origin: origin, normal: .unitZ, uDirection: .unitZ).validate(tolerance: tolerance)
        }
        for axis in [Vector3D.zero, Vector3D(x: 2, y: 0, z: 0), Vector3D(x: .nan, y: 0, z: 0)] {
            #expect(throws: GeometryError.self) {
                try Surface3D.plane(Plane3D(origin: origin, normal: .unitZ, uDirection: axis))
                    .point(u: 5, v: -2, tolerance: tolerance)
            }
        }
    }

    @Test
    func publicConversionRetainsOriginalChartAndThreeGuarantees() throws {
        let adapter = try NativeSurfaceConversionSource(source, tolerance: tolerance)
        let box = try SurfaceParameterBox(u: ScalarInterval(lower: 1, upper: 6),
            v: ScalarInterval(lower: -3, upper: 1))
        let limits = GeometryConversionRequirements(maximumPositionError: 1e-8,
            maximumTangentAngle: 1e-6, maximumCurvatureError: 1e-6,
            maximumDegree: 1, maximumControlPointCount: 4)
        let converter: any GeometryConverting = CertifiedGeometryConverter()
        let result = try converter.approximateSurface(source: adapter, over: box,
            requirements: limits, tolerance: tolerance)
        #expect(result.parameters.u == box.u)
        #expect(result.parameters.v == box.v)
        #expect(result.surface.uDegree == 1 && result.surface.vDegree == 1)
        #expect(result.surface.uControlPointCount * result.surface.vControlPointCount == 4)
        #expect(result.guarantee.positionErrorUpperBound <= limits.maximumPositionError)
        #expect(result.guarantee.tangentAngleUpperBound <= limits.maximumTangentAngle)
        #expect(result.guarantee.curvatureErrorUpperBound <= limits.maximumCurvatureError)
        expectPoint(try result.surface.point(u: 5, v: -2, tolerance: tolerance),
            equals: Point3D(x: 6.6, y: 5.8, z: 4))
        #expect(adapter.surface == source)
    }

    private func expectPoint(_ actual: Point3D, equals expected: Point3D) {
        #expect(abs(actual.x - expected.x) < 1e-12)
        #expect(abs(actual.y - expected.y) < 1e-12)
        #expect(abs(actual.z - expected.z) < 1e-12)
    }
}
