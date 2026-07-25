import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("Certified intersection curve-surface intersection")
struct CertifiedIntersectionCurveSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func sphereConeSupportsRegisteredReductions() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))

        let curve = try certifiedCurve(first: sphere, second: cone)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [sphere, cone]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyReducedSphereIntersections(
            curve: curve,
            sourceSphere: sphere
        )
        try verifyReducedCoaxialCylinderIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(
            curve: curve,
            thirdSurface: .analytic(.cylinder(
                origin: Point3D(x: 100.0, y: 100.0, z: 100.0),
                axis: .unitZ,
                radius: 1.0
            ))
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coneConeSupportsReducedPlaneIntersections() throws {
        let first = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 2.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))

        let curve = try certifiedCurve(first: first, second: second)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [first, second]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneCylinderSupportsPlaneSphereAndCylinderIntersections() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))

        let curve = try certifiedCurve(first: cone, second: cylinder)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [cone, cylinder]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyConeCylinderReducedSphereIntersections(
            curve: curve,
            sourceCylinder: cylinder
        )
        try verifyConeCylinderReducedCylinderIntersections(
            curve: curve,
            sourceCylinder: cylinder
        )
        try verifyUnsupportedNonPlaneSurface(
            curve: curve,
            thirdSurface: .analytic(.torus(
                center: Point3D(x: 100.0, y: 100.0, z: 100.0),
                axis: .unitZ,
                majorRadius: 2.0,
                minorRadius: 0.5
            ))
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coneTorusSupportsReducedPlaneIntersections() throws {
        let coneAxis = try Vector3D(
            x: 0.05,
            y: 0.0,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 4.0, y: 0.0, z: 0.0),
            axis: coneAxis,
            halfAngle: atan(6.0)
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        let curve = try certifiedCurve(first: cone, second: torus)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [cone, torus]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func nearNodalParallelTorusSupportsExactPlaneIntersections() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.5
        ))
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 1.99, y: 0.0, z: 0.0),
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.5
        ))

        try verifyParallelTorusPlaneIntersections(
            first: first,
            second: second,
            expectedKind: .nearNodalClosedLoop,
            expectedCount: 2
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nodalParallelTorusSupportsExactPlaneIntersections() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.5
        ))
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 2.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.5
        ))

        try verifyParallelTorusPlaneIntersections(
            first: first,
            second: second,
            expectedKind: .nodalSelfLoop,
            expectedCount: 4
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func regularParallelTorusSupportsExactPlaneIntersections() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.5
        ))
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 2.2, y: 0.0, z: 0.0),
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.5
        ))

        try verifyParallelTorusPlaneIntersections(
            first: first,
            second: second,
            expectedKind: .regularClosed,
            expectedCount: 4
        )
    }

    private func certifiedCurve(
        first: Surface3D,
        second: Surface3D
    ) throws -> Curve3D {
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case .certifiedIntersection = result.curve else {
                continue
            }
            return result.curve
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "The test fixture did not produce a certified intersection curve."
        )
    }

    private func verifySourceCoincidence(
        curve: Curve3D,
        sourceSurfaces: [Surface3D]
    ) throws {
        let intersector = DefaultCurveSurfaceIntersector()
        for surface in sourceSurfaces {
            for representation in [
                surface,
                equivalentRepresentation(of: surface),
            ] {
                do {
                    _ = try intersector.intersections(
                        curve: curve,
                        surface: representation,
                        options: .init(),
                        tolerance: tolerance
                    )
                    Issue.record(
                        "A source-surface intersection must be non-discrete."
                    )
                } catch let error as KernelError {
                    #expect(error.phase == .geometry)
                    #expect(error.code == .nonDiscreteIntersection)
                    #expect(error.tolerance == tolerance)
                }
            }
        }
    }

    private func equivalentRepresentation(
        of surface: Surface3D
    ) -> Surface3D {
        switch CanonicalAnalyticSurface(surface) {
        case let .plane(plane):
            return .analytic(.plane(
                origin: plane.origin,
                normal: -plane.normal
            ))
        case let .sphere(sphere):
            return .analytic(.sphere(
                center: sphere.center + Vector3D.unitX
                    * (tolerance.distance * 0.25),
                radius: sphere.radius
            ))
        case let .cylinder(cylinder):
            return .analytic(.cylinder(
                origin: cylinder.origin + cylinder.axis * 2.0,
                axis: -cylinder.axis,
                radius: cylinder.radius
            ))
        case let .cone(cone):
            return .analytic(.cone(
                apex: cone.apex,
                axis: -cone.axis,
                halfAngle: cone.halfAngle
            ))
        case let .torus(torus):
            return .analytic(.torus(
                center: torus.center,
                axis: -torus.axis,
                majorRadius: torus.majorRadius,
                minorRadius: torus.minorRadius
            ))
        case .unsupported:
            return surface
        }
    }

    private func verifyParallelTorusPlaneIntersections(
        first: Surface3D,
        second: Surface3D,
        expectedKind:
            CertifiedParallelTorusTorusIntersectionCurve.ComponentKind,
        expectedCount: Int
    ) throws {
        let certified = try CertifiedParallelTorusTorusIntersectionCurve
            .certifiedCurves(
                firstTorusSurface: first,
                secondTorusSurface: second,
                options: .init(),
                tolerance: tolerance
            )
        #expect(certified.count == expectedCount)
        for procedural in certified {
            #expect(procedural.componentKind == expectedKind)
            let curve = Curve3D.certifiedIntersection(
                .parallelTorusTorus(procedural)
            )
            try verifySourceCoincidence(
                curve: curve,
                sourceSurfaces: [first, second]
            )
            try verifyReducedPlaneIntersections(curve: curve)
            try verifyUnsupportedNonPlaneSurface(curve: curve)
            if procedural.branchIndex == 0 {
                try verifyParallelTorusResourceLimits(curve: curve)
                if expectedKind == .regularClosed {
                    try verifyParallelTorusHalfAnglePole(curve: curve)
                }
            }
        }
    }

    private func verifyReducedPlaneIntersections(
        curve: Curve3D
    ) throws {
        try verifyRecoveredParameters(curve: curve)

        let expectedParameter = 0.3125
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let plane = Surface3D.analytic(.plane(
            origin: expectedGeometry.position,
            normal: try expectedGeometry.tangent.normalized(
                tolerance: tolerance.distance
            )
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.05,
            upper: expectedParameter + 0.05
        )
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: plane,
            options: .init(curveRange: curveRange),
            tolerance: tolerance
        )
        let expectedIntersection = try #require(
            intersections.min {
                ($0.point - expectedGeometry.position).length
                    < ($1.point - expectedGeometry.position).length
            }
        )
        #expect(
            (expectedIntersection.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expectedIntersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(expectedIntersection.kind == .transverse)

        for intersection in intersections {
            #expect(curveRange.contains(intersection.curveParameter))
            #expect(intersection.residual <= tolerance.distance)
            let curvePoint = try curve.point(
                at: intersection.curveParameter,
                tolerance: tolerance
            )
            #expect(
                (curvePoint - intersection.point).length
                    <= tolerance.distance
            )
            let surfacePoint = try plane.point(
                u: intersection.surfaceU,
                v: intersection.surfaceV,
                tolerance: tolerance
            )
            #expect(
                (surfacePoint - intersection.point).length
                    <= tolerance.distance
            )
        }

        let excludedSurfaceRange = try ScalarInterval(
            lower: expectedIntersection.surfaceU + 10.0,
            upper: expectedIntersection.surfaceU + 11.0
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: plane,
            options: .init(
                curveRange: curveRange,
                surfaceURange: excludedSurfaceRange
            ),
            tolerance: tolerance
        )
        #expect(rangeExcluded.isEmpty)

        let tangentPlane = Surface3D.analytic(.plane(
            origin: expectedGeometry.position,
            normal: try expectedGeometry.curvatureVector.normalized(
                tolerance: tolerance.distance
            )
        ))
        let tangentIntersections =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: tangentPlane,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expectedTangent = try #require(
            tangentIntersections.min {
                ($0.point - expectedGeometry.position).length
                    < ($1.point - expectedGeometry.position).length
            }
        )
        #expect(
            (expectedTangent.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expectedTangent.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(expectedTangent.kind == .tangent)

        let bounds = try certifiedBoundingBox(curve: curve)
        let emptyPlane = Surface3D.analytic(.plane(
            origin: Point3D(
                x: bounds.maximum.x + max(bounds.size.length, 1.0) + 1.0,
                y: bounds.center.y,
                z: bounds.center.z
            ),
            normal: .unitX
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptyPlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)
    }

    private func verifyParallelTorusResourceLimits(
        curve: Curve3D
    ) throws {
        let geometry = try curve.differentialGeometry(
            at: 0.3125,
            tolerance: tolerance
        )
        let plane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try geometry.tangent.normalized(
                tolerance: tolerance.distance
            )
        ))
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: plane,
                options: .init(maximumPolynomialDegree: 1),
                tolerance: tolerance
            )
            Issue.record("A degree-limited elimination must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: plane,
                options: .init(maximumCandidateCount: 1),
                tolerance: tolerance
            )
            Issue.record("A candidate-limited elimination must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyReducedSphereIntersections(
        curve: Curve3D,
        sourceSphere: Surface3D
    ) throws {
        let expectedParameter = 0.3125
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let tangent = try expectedGeometry.tangent.normalized(
            tolerance: tolerance.distance
        )
        let sourceProjection = try sourceSphere.parameterProjection(
            of: expectedGeometry.position,
            tolerance: tolerance
        )
        let sourceNormal = try sourceSphere.normal(
            u: sourceProjection.u,
            v: sourceProjection.v,
            tolerance: tolerance
        )
        let targetRadius = 0.25
        let transverseSphere = Surface3D.analytic(.sphere(
            center: expectedGeometry.position + tangent * -targetRadius,
            radius: targetRadius
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.05,
            upper: expectedParameter + 0.05
        )
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseSphere,
            options: .init(curveRange: curveRange),
            tolerance: tolerance
        )
        let expectedTransverse = try #require(
            transverse.min {
                ($0.point - expectedGeometry.position).length
                    < ($1.point - expectedGeometry.position).length
            }
        )
        try verifySphereIntersection(
            expectedTransverse,
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .transverse,
            curve: curve,
            sphere: transverseSphere,
            curveRange: curveRange
        )

        let excludedSurfaceRange = try ScalarInterval(
            lower: expectedTransverse.surfaceU + 10.0,
            upper: expectedTransverse.surfaceU + 11.0
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseSphere,
            options: .init(
                curveRange: curveRange,
                surfaceURange: excludedSurfaceRange
            ),
            tolerance: tolerance
        )
        #expect(rangeExcluded.isEmpty)

        let tangentNormal = try tangent.cross(sourceNormal).normalized(
            tolerance: tolerance.distance
        )
        let tangentSphere = Surface3D.analytic(.sphere(
            center: expectedGeometry.position + tangentNormal * -targetRadius,
            radius: targetRadius
        ))
        let tangentIntersections =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: tangentSphere,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expectedTangent = try #require(
            tangentIntersections.min {
                ($0.point - expectedGeometry.position).length
                    < ($1.point - expectedGeometry.position).length
            }
        )
        try verifySphereIntersection(
            expectedTangent,
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .tangent,
            curve: curve,
            sphere: tangentSphere,
            curveRange: curveRange
        )

        let filteredPointSphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.0, y: 0.0, z: 1.25),
            radius: 0.25
        ))
        let filteredPoint = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: filteredPointSphere,
            options: .init(),
            tolerance: tolerance
        )
        #expect(filteredPoint.isEmpty)

        let emptySphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 100.0, y: 100.0, z: 100.0),
            radius: 1.0
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptySphere,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)
    }

    private func verifySphereIntersection(
        _ intersection: CurveSurfaceIntersection,
        expectedGeometry: Curve3D.DifferentialGeometry,
        expectedParameter: Double,
        expectedKind: CurveSurfaceIntersectionKind,
        curve: Curve3D,
        sphere: Surface3D,
        curveRange: ScalarInterval
    ) throws {
        #expect(
            (intersection.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(intersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(intersection.kind == expectedKind)
        #expect(curveRange.contains(intersection.curveParameter))
        #expect(intersection.residual <= tolerance.distance)
        let curvePoint = try curve.point(
            at: intersection.curveParameter,
            tolerance: tolerance
        )
        #expect(
            (curvePoint - intersection.point).length
                <= tolerance.distance
        )
        let spherePoint = try sphere.point(
            u: intersection.surfaceU,
            v: intersection.surfaceV,
            tolerance: tolerance
        )
        #expect(
            (spherePoint - intersection.point).length
                <= tolerance.distance
        )
    }

    private func verifyReducedCoaxialCylinderIntersections(
        curve: Curve3D
    ) throws {
        let transverseCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 0.25
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseCylinder,
            options: .init(),
            tolerance: tolerance
        )
        #expect(transverse.count == 2)
        for intersection in transverse {
            try verifyCylinderIntersection(
                intersection,
                expectedKind: .transverse,
                curve: curve,
                cylinder: transverseCylinder
            )
        }
        let equivalentCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 3.0),
            axis: Vector3D(x: 0.0, y: 0.0, z: -1.0),
            radius: 0.25
        ))
        let equivalent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: equivalentCylinder,
            options: .init(),
            tolerance: tolerance
        )
        #expect(equivalent.count == transverse.count)
        for expected in transverse {
            #expect(equivalent.contains {
                ($0.point - expected.point).length <= tolerance.distance
            })
        }

        let selectedParameter = try #require(
            transverse.min {
                abs($0.curveParameter - 0.5)
                    < abs($1.curveParameter - 0.5)
            }
        ).curveParameter
        let curveRange = try ScalarInterval(
            lower: max(0.0, selectedParameter - 0.01),
            upper: min(1.0, selectedParameter + 0.01)
        )
        let rangeRestricted = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseCylinder,
            options: .init(curveRange: curveRange),
            tolerance: tolerance
        )
        #expect(rangeRestricted.count == 1)
        #expect(rangeRestricted.allSatisfy {
            curveRange.contains($0.curveParameter)
        })

        let excludedSurfaceRange = try ScalarInterval(
            lower: 10.0,
            upper: 11.0
        )
        let surfaceRangeExcluded =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: transverseCylinder,
                options: .init(surfaceVRange: excludedSurfaceRange),
                tolerance: tolerance
            )
        #expect(surfaceRangeExcluded.isEmpty)

        let tangentCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 0.4
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentCylinder,
            options: .init(),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        for intersection in tangent {
            try verifyCylinderIntersection(
                intersection,
                expectedKind: .tangent,
                curve: curve,
                cylinder: tangentCylinder
            )
        }

        let emptyCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 0.5
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptyCylinder,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)
    }

    private func verifyConeCylinderReducedSphereIntersections(
        curve: Curve3D,
        sourceCylinder: Surface3D
    ) throws {
        let expectedParameter = 0.375
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        guard case let .cylinder(cylinder) =
            CanonicalAnalyticSurface(sourceCylinder) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The reduction fixture requires an exact cylinder."
            )
        }
        let relative = expectedGeometry.position - cylinder.origin
        let axisPoint = cylinder.origin
            + cylinder.axis * relative.dot(cylinder.axis)
        let axialDelta = 0.123
        let transverseRadius = hypot(cylinder.radius, axialDelta)
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.05,
            upper: expectedParameter + 0.05
        )
        let transverseSphere = Surface3D.analytic(.sphere(
            center: axisPoint + cylinder.axis * -axialDelta,
            radius: transverseRadius
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseSphere,
            options: .init(curveRange: curveRange),
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        try verifySphereIntersection(
            try #require(transverse.first),
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .transverse,
            curve: curve,
            sphere: transverseSphere,
            curveRange: curveRange
        )

        let excludedSurfaceRange = try ScalarInterval(
            lower: 10.0,
            upper: 11.0
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseSphere,
            options: .init(
                curveRange: curveRange,
                surfaceVRange: excludedSurfaceRange
            ),
            tolerance: tolerance
        )
        #expect(rangeExcluded.isEmpty)

        let tangentSphere = Surface3D.analytic(.sphere(
            center: axisPoint,
            radius: cylinder.radius
        ))
        let tangentIntersections =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: tangentSphere,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(tangentIntersections.count == 1)
        try verifySphereIntersection(
            try #require(tangentIntersections.first),
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .tangent,
            curve: curve,
            sphere: tangentSphere,
            curveRange: curveRange
        )

        let emptySphere = Surface3D.analytic(.sphere(
            center: axisPoint,
            radius: cylinder.radius * 0.5
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptySphere,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)

        let perpendicular = try analyticOrthonormalBasis(
            cylinder.axis,
            tolerance: tolerance
        ).u
        let distantNoncoaxialSphere = Surface3D.analytic(.sphere(
            center: axisPoint + perpendicular * 10.0,
            radius: cylinder.radius
        ))
        let distantNoncoaxial = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: distantNoncoaxialSphere,
                options: .init(),
                tolerance: tolerance
            )
        #expect(distantNoncoaxial.isEmpty)

        let tangent = try expectedGeometry.tangent.normalized(
            tolerance: tolerance.distance
        )
        let cylinderProjection = try sourceCylinder.parameterProjection(
            of: expectedGeometry.position,
            tolerance: tolerance
        )
        let cylinderNormal = try sourceCylinder.normal(
            u: cylinderProjection.u,
            v: cylinderProjection.v,
            tolerance: tolerance
        )
        let localRadius = 0.25
        let noncoaxialTransverseSphere = Surface3D.analytic(.sphere(
            center: expectedGeometry.position + tangent * -localRadius,
            radius: localRadius
        ))
        let noncoaxialTransverse = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: noncoaxialTransverseSphere,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(noncoaxialTransverse.count == 1)
        try verifySphereIntersection(
            try #require(noncoaxialTransverse.first),
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .transverse,
            curve: curve,
            sphere: noncoaxialTransverseSphere,
            curveRange: curveRange
        )

        let noncoaxialTangentSphere = Surface3D.analytic(.sphere(
            center: expectedGeometry.position
                + cylinderNormal * -localRadius,
            radius: localRadius
        ))
        let noncoaxialTangent = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: noncoaxialTangentSphere,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(noncoaxialTangent.count == 1)
        try verifySphereIntersection(
            try #require(noncoaxialTangent.first),
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .tangent,
            curve: curve,
            sphere: noncoaxialTangentSphere,
            curveRange: curveRange
        )

        try verifyConeCylinderSphereResourceLimits(
            curve: curve,
            sphere: noncoaxialTransverseSphere
        )
    }

    private func verifyConeCylinderSphereResourceLimits(
        curve: Curve3D,
        sphere: Surface3D
    ) throws {
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: sphere,
                options: .init(maximumPolynomialDegree: 1),
                tolerance: tolerance
            )
            Issue.record("A degree-limited sphere elimination must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: sphere,
                options: .init(maximumCandidateCount: 1),
                tolerance: tolerance
            )
            Issue.record("A candidate-limited sphere elimination must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyConeCylinderReducedCylinderIntersections(
        curve: Curve3D,
        sourceCylinder: Surface3D
    ) throws {
        let expectedParameter = 0.375
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        guard case let .cylinder(source) =
            CanonicalAnalyticSurface(sourceCylinder) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The cylinder-reduction fixture requires an exact source cylinder."
            )
        }
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.02,
            upper: expectedParameter + 0.02
        )
        let tangent = try expectedGeometry.tangent.normalized(
            tolerance: tolerance.distance
        )
        let transverseNormal = try (
            tangent - source.axis * tangent.dot(source.axis)
        ).normalized(
            tolerance: tolerance.distance
        )
        let transverseRadius = 0.3
        let transverseCylinder = Surface3D.analytic(.cylinder(
            origin: expectedGeometry.position
                + transverseNormal * -transverseRadius,
            axis: source.axis,
            radius: transverseRadius
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transverseCylinder,
            options: .init(curveRange: curveRange),
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        let transverseIntersection = try #require(transverse.first)
        #expect(
            abs(transverseIntersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        try verifyCylinderIntersection(
            transverseIntersection,
            expectedKind: .transverse,
            curve: curve,
            cylinder: transverseCylinder
        )
        let reversedTransverseCylinder = Surface3D.analytic(.cylinder(
            origin: expectedGeometry.position
                + transverseNormal * -transverseRadius
                + source.axis * 2.0,
            axis: -source.axis,
            radius: transverseRadius
        ))
        let reversedTransverse =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: reversedTransverseCylinder,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(reversedTransverse.count == transverse.count)
        #expect(reversedTransverse.allSatisfy { candidate in
            transverse.contains {
                ($0.point - candidate.point).length <= tolerance.distance
            }
        })

        let sourceProjection = try sourceCylinder.parameterProjection(
            of: expectedGeometry.position,
            tolerance: tolerance
        )
        let tangentNormal = try sourceCylinder.normal(
            u: sourceProjection.u,
            v: sourceProjection.v,
            tolerance: tolerance
        )
        let tangentRadius = 0.2
        let tangentCylinder = Surface3D.analytic(.cylinder(
            origin: expectedGeometry.position
                + tangentNormal * -tangentRadius,
            axis: source.axis,
            radius: tangentRadius
        ))
        let tangentIntersections =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: tangentCylinder,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(tangentIntersections.count == 1)
        let tangentIntersection = try #require(
            tangentIntersections.first
        )
        #expect(
            abs(tangentIntersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        try verifyCylinderIntersection(
            tangentIntersection,
            expectedKind: .tangent,
            curve: curve,
            cylinder: tangentCylinder
        )

        let excludedSurfaceRange = try ScalarInterval(
            lower: 10.0,
            upper: 11.0
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: transverseCylinder,
                options: .init(
                    curveRange: curveRange,
                    surfaceVRange: excludedSurfaceRange
                ),
                tolerance: tolerance
            )
        #expect(rangeExcluded.isEmpty)

        let emptyCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 20.0, y: -15.0, z: 10.0),
            axis: source.axis,
            radius: 0.1
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptyCylinder,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)

        let skewAxis = try (
            source.axis + transverseNormal
        ).normalized(tolerance: tolerance.distance)
        try verifyUnsupportedNonPlaneSurface(
            curve: curve,
            thirdSurface: .analytic(.cylinder(
                origin: expectedGeometry.position
                    + transverseNormal * -transverseRadius,
                axis: skewAxis,
                radius: transverseRadius
            ))
        )
    }

    private func verifyCylinderIntersection(
        _ intersection: CurveSurfaceIntersection,
        expectedKind: CurveSurfaceIntersectionKind,
        curve: Curve3D,
        cylinder: Surface3D
    ) throws {
        #expect(intersection.kind == expectedKind)
        #expect(intersection.residual <= tolerance.distance)
        let curvePoint = try curve.point(
            at: intersection.curveParameter,
            tolerance: tolerance
        )
        #expect(
            (curvePoint - intersection.point).length
                <= tolerance.distance
        )
        let cylinderPoint = try cylinder.point(
            u: intersection.surfaceU,
            v: intersection.surfaceV,
            tolerance: tolerance
        )
        #expect(
            (cylinderPoint - intersection.point).length
                <= tolerance.distance
        )
    }

    private func verifyParallelTorusHalfAnglePole(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.5
        let geometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let plane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try geometry.tangent.normalized(
                tolerance: tolerance.distance
            )
        ))
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: plane,
            options: .init(curveRange: try ScalarInterval(
                lower: 0.49,
                upper: 0.51
            )),
            tolerance: tolerance
        )
        let intersection = try #require(intersections.first)
        #expect(
            abs(intersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect((intersection.point - geometry.position).length
            <= tolerance.distance)
        #expect(intersection.kind == .transverse)
    }

    private func verifyRecoveredParameters(
        curve: Curve3D
    ) throws {
        guard case let .certifiedIntersection(certifiedCurve) = curve else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The test requires a certified intersection curve."
            )
        }
        let resolver = DefaultCertifiedIntersectionParameterResolver()
        for expectedParameter in [0.0, 0.125, 0.3125, 0.5, 0.8125, 1.0] {
            let expectedPoint = try certifiedCurve.point(
                atNormalizedFraction: expectedParameter,
                tolerance: tolerance
            )
            let recovered = try resolver.normalizedParameters(
                of: expectedPoint,
                on: certifiedCurve,
                restrictedTo: nil,
                tolerance: tolerance
            )
            #expect(recovered.contains {
                abs($0 - expectedParameter) <= tolerance.relative * 64.0
            })
            for parameter in recovered {
                let recoveredPoint = try certifiedCurve.point(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
                #expect(
                    (recoveredPoint - expectedPoint).length
                        <= tolerance.distance
                )
            }
        }
    }

    private func verifyUnsupportedNonPlaneSurface(
        curve: Curve3D,
        thirdSurface: Surface3D = .analytic(.sphere(
            center: Point3D(x: 100.0, y: 100.0, z: 100.0),
            radius: 1.0
        ))
    ) throws {
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: thirdSurface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A non-plane third-surface path must remain explicitly unsupported.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }
    }

    private func certifiedBoundingBox(
        curve: Curve3D
    ) throws -> BoundingBox3D {
        guard case let .certifiedIntersection(certifiedCurve) = curve else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The test requires a certified intersection curve."
            )
        }
        switch certifiedCurve {
        case let .sphereCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .parallelTorusTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        }
    }
}
