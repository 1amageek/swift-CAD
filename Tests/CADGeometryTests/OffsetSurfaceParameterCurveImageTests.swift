import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite struct OffsetSurfaceParameterCurveImageTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11,
        relative: 1.0e-12
    )

    @Test(.timeLimit(.minutes(1)))
    func preservesTheSourceChartOnTheDerivedOffsetSurface() throws {
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
    func pullbackEvaluatesOriginalCurvedSurfaceAndRetainsDerivativesAndDirection() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 1)]
            ], weights: [[1, 1], [1, 1]]
        ))
        let offset = OffsetSurface3D(source: surface, distance: 0.3)
        let image = try offset.parameterCurvePullback(
            transporting: .affine(origin: Point2D(x: 0.1, y: 0.2),
                                 direction: Point2D(x: 0.6, y: 0.4),
                                 startParameter: 0, endParameter: 1),
            tolerance: tolerance
        )
        #expect(image.isPullback)
        #expect(try image.targetSurface(tolerance: tolerance) == surface)
        let pcurve = SurfaceParameterCurve.offsetSurfaceImage(image)
        let restored = try JSONDecoder().decode(SurfaceParameterCurve.self,
                                                from: JSONEncoder().encode(pcurve))
        #expect(restored == pcurve)
        try restored.validate(on: surface, tolerance: tolerance)
        #expect(throws: (any Error).self) {
            try restored.validate(on: .procedural(.offset(offset)), tolerance: tolerance)
        }
        let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: restored)
        for t in [0.0, 0.25, 0.7, 1.0] {
            let u = 0.1 + 0.6 * t
            let v = 0.2 + 0.4 * t
            let value = try lift.differentialGeometry(atNormalizedFraction: t, tolerance: tolerance)
            #expect((value.position - Point3D(x: u, y: v, z: u * v)).length <= tolerance.distance)
            #expect((value.firstDerivative - Vector3D(x: 0.6, y: 0.4, z: 0.6 * v + 0.4 * u)).length <= tolerance.distance)
            #expect((value.secondDerivative - Vector3D(x: 0, y: 0, z: 0.48)).length <= tolerance.distance)
        }
        let middle = try image.subcurve(fromNormalizedFraction: 0.25, toNormalizedFraction: 0.75,
                                        tolerance: tolerance).reversed(tolerance: tolerance)
        #expect(middle.isPullback)
        try middle.validate(on: surface, tolerance: tolerance)
        let start = try middle.parameter(atNormalizedFraction: 0, tolerance: tolerance)
        #expect(abs(start.u - 0.55) <= tolerance.distance)
        #expect(abs(start.v - 0.5) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func pullbackDirectionCannotDecodeInvalidValuesAsForward() throws {
        let offset = OffsetSurface3D(source: .plane(Plane3D(origin: .origin, normal: .unitZ)), distance: 1)
        let image = try offset.parameterCurvePullback(
            transporting: .constantV(v: 0, uStart: 0, uEnd: 1), tolerance: tolerance
        )
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(image)) as? [String: Any])
        for invalid in [NSNull(), "false"] as [Any] {
            object["isPullback"] = invalid
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(OffsetSurfaceParameterCurveImage.self, from: data)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func reversalAndSubdivisionRetainTheOffsetRelation() throws {
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
    func codableRoundTripRetainsTheOffsetRelationWithoutDuplicatingTheTarget() throws {
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

        #expect(decoded == value)
        try decoded.validate(on: targetSurface, tolerance: tolerance)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedImage = try #require(object["offsetSurfaceImage"] as? [String: Any])
        #expect(encodedImage["offset"] != nil)
        #expect(encodedImage["targetSurface"] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func factoryRejectsASourceCurveOutsideTheOffsetSourceChart() throws {
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

        #expect(throws: (any Error).self) {
            try offset.parameterCurveImage(
                transporting: .constantV(
                    v: 1.5,
                    uStart: 0.0,
                    uEnd: 1.0
                ),
                tolerance: tolerance
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAnUnrelatedSurfaceEvenWhenItsDomainsMatch() throws {
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

        #expect(sourceSurface.uDomain == unrelatedSurface.uDomain)
        #expect(sourceSurface.vDomain == unrelatedSurface.vDomain)
        #expect(throws: KernelError.self) {
            try image.validate(on: unrelatedSurface, tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAStoredTargetSurfaceThatCouldForgeTheOffsetRelation() throws {
        let image = try OffsetSurface3D(
            source: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            distance: 1.0
        ).parameterCurveImage(
            transporting: .constantV(v: 0.2, uStart: 0.0, uEnd: 1.0),
            tolerance: tolerance
        )
        let value = SurfaceParameterCurve.offsetSurfaceImage(image)
        let encoded = try JSONEncoder().encode(value)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var encodedImage = try #require(object["offsetSurfaceImage"] as? [String: Any])
        let unrelatedSurface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 0.0, y: 0.0, z: 3.0),
            normal: .unitZ
        ))
        encodedImage["targetSurface"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(unrelatedSurface)
        )
        object["offsetSurfaceImage"] = encodedImage
        let forged = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SurfaceParameterCurve.self, from: forged)
        }
    }
}
