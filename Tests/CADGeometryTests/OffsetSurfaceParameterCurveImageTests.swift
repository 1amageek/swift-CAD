import CADCore
import Foundation
import XCTest
@testable import CADGeometry

final class OffsetSurfaceParameterCurveImageTests: XCTestCase {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11,
        relative: 1.0e-12
    )

    func testPreservesTheSourceChartOnTheDerivedOffsetSurface() throws {
        let sourceSurface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let source = SurfaceParameterCurve.affine(
            origin: Point2D(x: 0.1, y: -0.2),
            direction: Point2D(x: 0.8, y: 0.5),
            startParameter: 0.0,
            endParameter: 1.0
        )
        let image = try OffsetSurface3D(
            source: sourceSurface,
            distance: 2.0
        ).parameterCurveImage(
            transporting: source,
            tolerance: tolerance
        )
        let targetSurface = try image.targetSurface(tolerance: tolerance)
        let pcurve = SurfaceParameterCurve.offsetSurfaceImage(image)

        try pcurve.validate(on: targetSurface, tolerance: tolerance)
        let parameter = try pcurve.parameter(
            atNormalizedFraction: 0.25,
            tolerance: tolerance
        )
        XCTAssertLessThanOrEqual(abs(parameter.u - 0.3), tolerance.relative)
        XCTAssertLessThanOrEqual(abs(parameter.v + 0.075), tolerance.relative)

        let differential = try pcurve.differentialGeometry(
            atNormalizedFraction: 0.25,
            tolerance: tolerance
        )
        XCTAssertLessThanOrEqual(
            abs(differential.firstDerivative.x - 0.8),
            tolerance.relative
        )
        XCTAssertLessThanOrEqual(
            abs(differential.firstDerivative.y - 0.5),
            tolerance.relative
        )
        XCTAssertLessThanOrEqual(
            abs(differential.secondDerivative.x),
            tolerance.relative
        )
        XCTAssertLessThanOrEqual(
            abs(differential.secondDerivative.y),
            tolerance.relative
        )

        let lifted = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: targetSurface,
            parameterCurve: pcurve
        ))
        let point = try lifted.point(at: 0.25, tolerance: tolerance)
        XCTAssertTrue(point.isApproximatelyEqual(
            to: Point3D(x: 0.3, y: -0.075, z: 2.0),
            tolerance: tolerance.distance
        ))
    }

    func testReversalAndSubdivisionRetainTheOffsetRelation() throws {
        let sourceSurface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let offset = OffsetSurface3D(source: sourceSurface, distance: 0.5)
        let transported = try offset.parameterCurveImage(
            transporting: .constantV(
                v: 0.4,
                uStart: 0.2,
                uEnd: 1.2
            ),
            tolerance: tolerance
        )
        let image = SurfaceParameterCurve.offsetSurfaceImage(transported)
        let targetSurface = try transported.targetSurface(tolerance: tolerance)

        let reversed = try image.reversed(tolerance: tolerance)
        let reversedStart = try reversed.startParameter(tolerance: tolerance)
        XCTAssertLessThanOrEqual(abs(reversedStart.u - 1.2), tolerance.relative)
        XCTAssertLessThanOrEqual(abs(reversedStart.v - 0.4), tolerance.relative)
        try reversed.validate(on: targetSurface, tolerance: tolerance)

        let middle = try image.subcurve(
            fromNormalizedFraction: 0.25,
            toNormalizedFraction: 0.75,
            tolerance: tolerance
        )
        let middleStart = try middle.startParameter(tolerance: tolerance)
        let middleEnd = try middle.endParameter(tolerance: tolerance)
        XCTAssertLessThanOrEqual(abs(middleStart.u - 0.45), tolerance.relative)
        XCTAssertLessThanOrEqual(abs(middleEnd.u - 0.95), tolerance.relative)
        try middle.validate(on: targetSurface, tolerance: tolerance)
    }

    func testCodableRoundTripRetainsTheOffsetRelationWithoutDuplicatingTheTarget() throws {
        let sourceSurface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let image = try OffsetSurface3D(
            source: sourceSurface,
            distance: -0.25
        ).parameterCurveImage(
            transporting: .constantU(u: 0.4, vStart: -1.0, vEnd: 1.0),
            tolerance: tolerance
        )
        let value = SurfaceParameterCurve.offsetSurfaceImage(image)
        let targetSurface = try image.targetSurface(tolerance: tolerance)

        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(
            SurfaceParameterCurve.self,
            from: encoded
        )

        XCTAssertEqual(decoded, value)
        try decoded.validate(on: targetSurface, tolerance: tolerance)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let encodedImage = try XCTUnwrap(
            object["offsetSurfaceImage"] as? [String: Any]
        )
        XCTAssertNotNil(encodedImage["offset"])
        XCTAssertNil(encodedImage["targetSurface"])
    }

    func testFactoryRejectsASourceCurveOutsideTheOffsetSourceChart() throws {
        let sourceSurface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                ],
                [
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 1.0],
                [1.0, 1.0],
            ]
        ))
        let offset = OffsetSurface3D(source: sourceSurface, distance: 0.1)

        XCTAssertThrowsError(
            try offset.parameterCurveImage(
                transporting: .constantV(
                    v: 1.5,
                    uStart: 0.0,
                    uEnd: 1.0
                ),
                tolerance: tolerance
            )
        )
    }

    func testRejectsAnUnrelatedSurfaceEvenWhenItsDomainsMatch() throws {
        let sourceSurface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let unrelatedSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitX
        ))
        let image = try OffsetSurface3D(
            source: sourceSurface,
            distance: 1.0
        ).parameterCurveImage(
            transporting: .constantV(v: 0.2, uStart: 0.0, uEnd: 1.0),
            tolerance: tolerance
        )

        XCTAssertEqual(sourceSurface.uDomain, unrelatedSurface.uDomain)
        XCTAssertEqual(sourceSurface.vDomain, unrelatedSurface.vDomain)
        XCTAssertThrowsError(
            try image.validate(on: unrelatedSurface, tolerance: tolerance)
        ) { error in
            XCTAssertTrue(error is KernelError)
        }
    }

    func testRejectsAStoredTargetSurfaceThatCouldForgeTheOffsetRelation() throws {
        let image = try OffsetSurface3D(
            source: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            distance: 1.0
        ).parameterCurveImage(
            transporting: .constantV(v: 0.2, uStart: 0.0, uEnd: 1.0),
            tolerance: tolerance
        )
        let value = SurfaceParameterCurve.offsetSurfaceImage(image)
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var encodedImage = try XCTUnwrap(
            object["offsetSurfaceImage"] as? [String: Any]
        )
        let unrelatedSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 3.0),
            normal: .unitZ
        ))
        encodedImage["targetSurface"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(unrelatedSurface)
        )
        object["offsetSurfaceImage"] = encodedImage
        let forged = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try JSONDecoder().decode(SurfaceParameterCurve.self, from: forged)
        ) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }
}
