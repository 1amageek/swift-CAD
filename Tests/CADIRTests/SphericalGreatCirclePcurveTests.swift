import Foundation
import Testing
import CADCore
import CADGeometry
@testable import CADIR

@Suite("Spherical great-circle pcurve")
struct SphericalGreatCirclePcurveTests {
    @Test
    func mapsAnArbitraryGreatCircleExactlyIntoSphereParameters() throws {
        let cosine = try Vector3D(x: 1.0, y: 1.0, z: 0.0).normalized(tolerance: 1.0e-12)
        let normal = try Vector3D(x: -1.0, y: 1.0, z: 1.0).normalized(tolerance: 1.0e-12)
        let sine = try normal.cross(cosine).normalized(tolerance: 1.0e-12)
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: cosine,
            sine: sine,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 3.0))

        try curve.validate(on: surface, tolerance: .standard)
        for index in 0...8 {
            let fraction = Double(index) / 8.0
            let parameter = try curve.parameter(
                atNormalizedFraction: fraction,
                tolerance: .standard
            )
            let actual = try surface.point(
                u: parameter.u,
                v: parameter.v,
                tolerance: .standard
            )
            let angle = fraction * Double.pi / 2.0
            let expected = Point3D(
                x: 3.0 * (cosine.x * cos(angle) + sine.x * sin(angle)),
                y: 3.0 * (cosine.y * cos(angle) + sine.y * sin(angle)),
                z: 3.0 * (cosine.z * cos(angle) + sine.z * sin(angle))
            )
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-12))
        }

        let decoded = try JSONDecoder().decode(
            SurfaceParameterCurve.self,
            from: JSONEncoder().encode(curve)
        )
        #expect(decoded == curve)
    }

    @Test
    func acceptsGeneratedOrthogonalityAtStrictSignatureTolerance() throws {
        let cosine = try Vector3D(x: 1.0, y: 1.0, z: 0.0).normalized(tolerance: 1.0e-12)
        let normal = try Vector3D(x: -1.0, y: 1.0, z: 1.0).normalized(tolerance: 1.0e-12)
        let sine = try normal.cross(cosine).normalized(tolerance: 1.0e-12)
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: cosine,
            sine: sine,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )
        let strictTolerance = ModelingTolerance(
            distance: Double.leastNonzeroMagnitude,
            angle: Double.leastNonzeroMagnitude,
            relative: Double.leastNonzeroMagnitude
        )

        try curve.validate(
            on: .analytic(.sphere(center: .origin, radius: 1.0)),
            tolerance: strictTolerance
        )
    }

    @Test
    func rejectsMateriallyNonOrthogonalGreatCircleBasis() throws {
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitX,
            sine: try Vector3D(x: 1.0e-12, y: 1.0, z: 0.0).normalized(tolerance: 1.0e-15),
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )

        #expect(throws: GeometryError.self) {
            try curve.validate(
                on: .analytic(.sphere(center: .origin, radius: 1.0)),
                tolerance: ModelingTolerance(
                    distance: Double.leastNonzeroMagnitude,
                    angle: Double.leastNonzeroMagnitude,
                    relative: Double.leastNonzeroMagnitude
                )
            )
        }
    }

    @Test
    func rejectsNonFiniteGreatCircleBasis() throws {
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: Vector3D(x: .nan, y: 0.0, z: 0.0),
            sine: .unitY,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )

        #expect(throws: GeometryError.self) {
            try curve.validate(
                on: .analytic(.sphere(center: .origin, radius: 1.0)),
                tolerance: .standard
            )
        }
    }

    @Test
    func rejectsDegenerateGreatCircleBasis() throws {
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .zero,
            sine: .unitY,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )

        #expect(throws: GeometryError.self) {
            try curve.validate(
                on: .analytic(.sphere(center: .origin, radius: 1.0)),
                tolerance: .standard
            )
        }
    }

    @Test
    func rejectsGreatCircleOnWrongSurface() throws {
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitX,
            sine: .unitY,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )

        #expect(throws: GeometryError.self) {
            try curve.validate(
                on: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                tolerance: .standard
            )
        }
    }

    @Test
    func rejectsOutOfDomainSurfaceParameters() throws {
        let curve = SurfaceParameterCurve.constantV(
            v: Double.pi,
            uStart: 0.0,
            uEnd: Double.pi / 2.0
        )

        #expect(throws: GeometryError.self) {
            try curve.validate(
                on: .analytic(.sphere(center: .origin, radius: 1.0)),
                tolerance: .standard
            )
        }
    }

    @Test
    func preservesTheInteriorLongitudeAtAPoleEndpoint() throws {
        let curve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitX,
            sine: .unitZ,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0
        )
        let nearPole = try curve.parameter(
            atNormalizedFraction: 1.0 - 1.0e-6,
            tolerance: .standard
        )
        let pole = try curve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: .standard
        )
        let reversedCurve = try curve.reversed(tolerance: .standard)
        let reversedPole = try reversedCurve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: .standard
        )

        #expect(abs(pole.u - nearPole.u) <= 1.0e-12)
        #expect(abs(reversedPole.u - nearPole.u) <= 1.0e-12)
        #expect(abs(pole.v - Double.pi / 2.0) <= 1.0e-12)
    }
}
