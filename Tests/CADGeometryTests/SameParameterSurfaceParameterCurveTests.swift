import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Same-parameter surface pcurve images")
struct SameParameterSurfaceParameterCurveTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11,
        relative: 1.0e-12
    )

    @Test(.timeLimit(.minutes(1)))
    func preservesTheExactParameterChartOnTheTargetSurface() throws {
        let sourceSurface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let targetSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 2.0),
            normal: .unitZ
        ))
        let source = SurfaceParameterCurve.affine(
            origin: Point2D(x: 0.1, y: -0.2),
            direction: Point2D(x: 0.8, y: 0.5),
            startParameter: 0.0,
            endParameter: 1.0
        )
        let image = try SameParameterSurfaceParameterCurve(
            source: source,
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            tolerance: tolerance
        )
        let pcurve = SurfaceParameterCurve.sameParameterImage(image)

        try pcurve.validate(on: targetSurface, tolerance: tolerance)
        let parameter = try pcurve.parameter(
            atNormalizedFraction: 0.25,
            tolerance: tolerance
        )
        #expect(abs(parameter.u - 0.3) <= tolerance.relative)
        #expect(abs(parameter.v + 0.075) <= tolerance.relative)

        let differential = try pcurve.differentialGeometry(
            atNormalizedFraction: 0.25,
            tolerance: tolerance
        )
        #expect(abs(differential.firstDerivative.x - 0.8) <= tolerance.relative)
        #expect(abs(differential.firstDerivative.y - 0.5) <= tolerance.relative)
        #expect(abs(differential.secondDerivative.x) <= tolerance.relative)
        #expect(abs(differential.secondDerivative.y) <= tolerance.relative)

        let lifted = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: targetSurface,
            parameterCurve: pcurve
        ))
        let point = try lifted.point(at: 0.25, tolerance: tolerance)
        #expect(point.isApproximatelyEqual(
            to: Point3D(x: 0.3, y: -0.075, z: 2.0),
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func reversalAndSubdivisionRemainBoundToTheSameTarget() throws {
        let sourceSurface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let targetSurface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 2.5
        ))
        let image = SurfaceParameterCurve.sameParameterImage(
            try SameParameterSurfaceParameterCurve(
                source: .constantV(
                    v: 0.4,
                    uStart: 0.2,
                    uEnd: 1.2
                ),
                sourceSurface: sourceSurface,
                targetSurface: targetSurface,
                tolerance: tolerance
            )
        )

        let reversed = try image.reversed(tolerance: tolerance)
        let reversedStart = try reversed.startParameter(tolerance: tolerance)
        #expect(abs(reversedStart.u - 1.2) <= tolerance.relative)
        #expect(abs(reversedStart.v - 0.4) <= tolerance.relative)
        try reversed.validate(on: targetSurface, tolerance: tolerance)

        let middle = try image.subcurve(
            fromNormalizedFraction: 0.25,
            toNormalizedFraction: 0.75,
            tolerance: tolerance
        )
        let middleStart = try middle.startParameter(tolerance: tolerance)
        let middleEnd = try middle.endParameter(tolerance: tolerance)
        #expect(abs(middleStart.u - 0.45) <= tolerance.relative)
        #expect(abs(middleEnd.u - 0.95) <= tolerance.relative)
        try middle.validate(on: targetSurface, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func codableRoundTripRetainsBothSurfaceIdentities() throws {
        let sourceSurface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let targetSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: -0.25),
            normal: .unitZ
        ))
        let value = SurfaceParameterCurve.sameParameterImage(
            try SameParameterSurfaceParameterCurve(
                source: .constantU(u: 0.4, vStart: -1.0, vEnd: 1.0),
                sourceSurface: sourceSurface,
                targetSurface: targetSurface,
                tolerance: tolerance
            )
        )

        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(
            SurfaceParameterCurve.self,
            from: encoded
        )

        #expect(decoded == value)
        try decoded.validate(on: targetSurface, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsValidationAgainstAnotherSurface() throws {
        let sourceSurface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let targetSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitZ
        ))
        let otherSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 2.0),
            normal: .unitZ
        ))
        let image = try SameParameterSurfaceParameterCurve(
            source: .constantV(v: 0.2, uStart: 0.0, uEnd: 1.0),
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            tolerance: tolerance
        )

        #expect(throws: KernelError.self) {
            try image.validate(on: otherSurface, tolerance: tolerance)
        }
    }
}
