import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("Analytic and B-Spline Surface Intersection")
struct AnalyticBSplineSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func sphereAndRationalPlaneProduceVerifiedClosedIntersectionInBothOrders() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))
        let rationalPlane = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.5, y: -1.5, z: 0.0),
                    Point3D(x: 1.5, y: -1.5, z: 0.0),
                ],
                [
                    Point3D(x: -1.5, y: 1.5, z: 0.0),
                    Point3D(x: 1.5, y: 1.5, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 1.25],
                [0.8, 1.0],
            ]
        ))

        for operands in [(sphere, rationalPlane), (rationalPlane, sphere)] {
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: operands.0,
                second: operands.1,
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 4,
                    maximumIterations: 48,
                    maximumSeedCount: 1_024
                ),
                tolerance: tolerance
            )

            #expect(intersections.count == 1)
            guard case let .curve(result) = try #require(intersections.first) else {
                Issue.record("A transverse sphere and rational planar surface must produce a curve.")
                continue
            }
            guard case .analyticBSpline = result.truth else {
                Issue.record("Analytic–B-spline intersections must retain certified implicit truth.")
                continue
            }
            #expect(result.kind == .transverse)
            #expect(result.maximumResidual <= tolerance.distance)
            let encoded = try JSONEncoder().encode(SurfaceSurfaceIntersection.curve(result))
            let decoded = try JSONDecoder().decode(
                SurfaceSurfaceIntersection.self,
                from: encoded
            )
            #expect(decoded == .curve(result))
            try result.firstSurfaceParameterCurve.validate(
                on: operands.0,
                tolerance: tolerance
            )
            try result.secondSurfaceParameterCurve.validate(
                on: operands.1,
                tolerance: tolerance
            )
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let firstUV = try result.firstSurfaceParameterCurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let secondUV = try result.secondSurfaceParameterCurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                _ = try result.firstSurfaceParameterCurve.differentialGeometry(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                _ = try result.secondSurfaceParameterCurve.differentialGeometry(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let firstPoint = try operands.0.point(
                    u: firstUV.u,
                    v: firstUV.v,
                    tolerance: tolerance
                )
                let secondPoint = try operands.1.point(
                    u: secondUV.u,
                    v: secondUV.v,
                    tolerance: tolerance
                )
                #expect(firstPoint.isApproximatelyEqual(
                    to: secondPoint,
                    tolerance: tolerance.distance
                ))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactAnalyticNURBSRepresentationsRemainOnTheirSourceSurfaces() throws {
        let reference = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: -3.0, y: -3.0, z: 0.5), Point3D(x: 3.0, y: -3.0, z: 0.5)],
                [Point3D(x: -3.0, y: 3.0, z: 2.0), Point3D(x: 3.0, y: 3.0, z: 2.0)],
            ],
            weights: [[1.0, 1.2], [0.9, 1.0]]
        )
        let surfaces: [Surface3D] = [
            .analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 1.0)),
            .analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: Double.pi * 0.25)),
            .analytic(.sphere(center: .origin, radius: 1.0)),
            .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 2.0,
                minorRadius: 0.5
            )),
        ]

        for source in surfaces {
            let built = try AnalyticSurfaceBSplineBuilder().surface(
                for: CanonicalAnalyticSurface(source),
                boundedBy: reference,
                periodicSeamOffset: Double.pi * 0.125,
                tolerance: tolerance
            )
            guard case let .closed(uLower, uUpper) = built.uDomain,
                  case let .closed(vLower, vUpper) = built.vDomain else {
                Issue.record("An exact analytic NURBS conversion must be bounded.")
                continue
            }
            for uFraction in [0.125, 0.375, 0.625, 0.875] {
                for vFraction in [0.125, 0.375, 0.625, 0.875] {
                    let point = try built.point(
                        u: uLower + (uUpper - uLower) * uFraction,
                        v: vLower + (vUpper - vLower) * vFraction,
                        tolerance: tolerance
                    )
                    let projection = try source.parameterProjection(
                        of: point,
                        tolerance: tolerance
                    )
                    #expect(projection.residual <= tolerance.distance)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cylinderAndBoundedRationalPlaneProduceVerifiedGenerator() throws {
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let plane = rationalPatch(
            lowerLeft: Point3D(x: 0.0, y: 0.5, z: -0.5),
            lowerRight: Point3D(x: 0.0, y: 1.5, z: -0.5),
            upperLeft: Point3D(x: 0.0, y: 0.5, z: 0.5),
            upperRight: Point3D(x: 0.0, y: 1.5, z: 0.5)
        )
        try expectSingleVerifiedCurve(first: cylinder, second: plane)
    }

    @Test(.timeLimit(.minutes(1)))
    func seamAlignedCylinderGeneratorUsesDeterministicAlternateParameterization() throws {
        let fixture = try seamAlignedCylinderFixture()
        try expectSingleVerifiedCurve(first: fixture.cylinder, second: fixture.plane)
    }

    @Test(.timeLimit(.minutes(1)))
    func seamAlignedCylinderGeneratorIsOperandOrderStable() throws {
        let fixture = try seamAlignedCylinderFixture()
        try expectSingleVerifiedCurve(first: fixture.plane, second: fixture.cylinder)
    }

    private func seamAlignedCylinderFixture() throws -> (
        cylinder: Surface3D,
        plane: Surface3D
    ) {
        let seamAngle = Double.pi * 0.125
        let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
        let radial = basis.u * cos(seamAngle) + basis.v * sin(seamAngle)
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let lowerAxis = Vector3D.unitZ * -0.5
        let upperAxis = Vector3D.unitZ * 0.5
        let innerRadial = radial * 0.5
        let outerRadial = radial * 1.5
        let lowerLeft = Point3D.origin + innerRadial + lowerAxis
        let lowerRight = Point3D.origin + outerRadial + lowerAxis
        let upperLeft = Point3D.origin + innerRadial + upperAxis
        let upperRight = Point3D.origin + outerRadial + upperAxis
        let plane = rationalPatch(
            lowerLeft: lowerLeft,
            lowerRight: lowerRight,
            upperLeft: upperLeft,
            upperRight: upperRight
        )
        return (cylinder, plane)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneAndBoundedRationalPlaneProduceVerifiedGenerator() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))
        let plane = rationalPatch(
            lowerLeft: Point3D(x: 0.0, y: 0.25, z: 0.5),
            lowerRight: Point3D(x: 0.0, y: 2.5, z: 0.5),
            upperLeft: Point3D(x: 0.0, y: 0.25, z: 2.0),
            upperRight: Point3D(x: 0.0, y: 2.5, z: 2.0)
        )
        try expectSingleVerifiedCurve(first: cone, second: plane)
    }

    @Test(.timeLimit(.minutes(1)))
    func torusAndBoundedRationalPlaneProduceVerifiedArc() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 2.0,
            minorRadius: 0.5
        ))
        let plane = rationalPatch(
            lowerLeft: Point3D(x: 2.0, y: -0.5, z: 0.0),
            lowerRight: Point3D(x: 3.0, y: -0.5, z: 0.0),
            upperLeft: Point3D(x: 2.0, y: 0.5, z: 0.0),
            upperRight: Point3D(x: 3.0, y: 0.5, z: 0.0)
        )
        try expectSingleVerifiedCurve(first: torus, second: plane)
    }

    private func rationalPatch(
        lowerLeft: Point3D,
        lowerRight: Point3D,
        upperLeft: Point3D,
        upperRight: Point3D
    ) -> Surface3D {
        .bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [lowerLeft, lowerRight],
                [upperLeft, upperRight],
            ],
            weights: [[1.0, 1.2], [0.85, 1.0]]
        ))
    }

    private func expectSingleVerifiedCurve(
        first: Surface3D,
        second: Surface3D
    ) throws {
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 4,
                maximumIterations: 48,
                maximumSeedCount: 1_024
            ),
            tolerance: tolerance
        )
        #expect(
            intersections.count == 1,
            "Expected one analytic–B-spline component, received \(intersections.count): \(intersectionSummary(intersections))."
        )
        guard case let .curve(result) = try #require(intersections.first) else {
            Issue.record("A transverse analytic and rational surface pair must produce a curve.")
            return
        }
        guard case .analyticBSpline = result.truth else {
            Issue.record("Analytic–B-spline intersections must retain certified implicit truth.")
            return
        }
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(
            on: first,
            tolerance: tolerance
        )
        try result.secondSurfaceParameterCurve.validate(
            on: second,
            tolerance: tolerance
        )
    }

    private func intersectionSummary(
        _ intersections: [SurfaceSurfaceIntersection]
    ) -> String {
        intersections.enumerated().map { index, intersection in
            guard case let .curve(value) = intersection,
                  case let .bSpline(curve) = value.curve,
                  let first = curve.controlPoints.first,
                  let last = curve.controlPoints.last else {
                return "\(index): non-B-spline"
            }
            let xValues = curve.controlPoints.map(\.x)
            let yValues = curve.controlPoints.map(\.y)
            let zValues = curve.controlPoints.map(\.z)
            return "\(index): points=\(curve.controlPoints.count), first=\(first), last=\(last), x=\(xValues.min() ?? 0.0)...\(xValues.max() ?? 0.0), y=\(yValues.min() ?? 0.0)...\(yValues.max() ?? 0.0), z=\(zValues.min() ?? 0.0)...\(zValues.max() ?? 0.0)"
        }.joined(separator: "; ")
    }
}
