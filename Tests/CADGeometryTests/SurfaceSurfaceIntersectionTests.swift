import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Surface-Surface Intersection")
struct SurfaceSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func planePlaneProducesVerifiedLineAndCoincidence() throws {
        let horizontal = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let vertical = Surface3D.analytic(.plane(origin: .origin, normal: .unitX))

        let intersections = try intersector.intersections(
            first: horizontal,
            second: vertical,
            tolerance: tolerance
        )
        let intersection = try #require(intersections.first)
        guard case let .curve(result) = intersection,
              case let .line(line) = result.curve else {
            Issue.record("Perpendicular planes must intersect in a line.")
            return
        }
        #expect(intersections.count == 1)
        #expect(abs(line.direction.dot(.unitY)) >= 1.0 - tolerance.angle)
        #expect(result.maximumResidual <= tolerance.distance)

        let coincident = try intersector.intersections(
            first: horizontal,
            second: .analytic(.plane(
                origin: Point3D(x: 0.5, y: -0.25, z: 0.0),
                normal: -.unitZ
            )),
            tolerance: tolerance
        )
        #expect(coincident.count == 1)
        #expect(coincident.contains {
            if case .coincident = $0 { return true }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func planeSphereProducesCircleAndTangentPoint() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let section = try intersector.intersections(
            first: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 1.0),
                normal: .unitZ
            )),
            second: sphere,
            tolerance: tolerance
        )
        guard case let .curve(result) = try #require(section.first),
              case let .circle(circle) = result.curve else {
            Issue.record("A secant plane must produce a circle on a sphere.")
            return
        }
        #expect(abs(circle.radius - sqrt(3.0)) <= tolerance.distance)
        #expect(circle.center.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 0.0, z: 1.0),
            tolerance: tolerance.distance
        ))

        let tangent = try intersector.intersections(
            first: .analytic(.plane(
                origin: Point3D(x: 0.0, y: 0.0, z: 2.0),
                normal: .unitZ
            )),
            second: sphere,
            tolerance: tolerance
        )
        guard case let .point(point) = try #require(tangent.first) else {
            Issue.record("A tangent plane must produce one verified point.")
            return
        }
        #expect(point.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 0.0, z: 2.0),
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func planeCylinderProducesParallelLinesAndObliqueEllipse() throws {
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let parallelSection = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitX)),
            second: cylinder,
            tolerance: tolerance
        )
        #expect(parallelSection.count == 2)
        #expect(parallelSection.allSatisfy {
            guard case let .curve(result) = $0,
                  case .line = result.curve else { return false }
            return result.maximumResidual <= tolerance.distance
        })

        let perpendicularSection = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            second: cylinder,
            tolerance: tolerance
        )
        guard case let .curve(perpendicularResult) = try #require(perpendicularSection.first),
              case let .circle(perpendicularCircle) = perpendicularResult.curve else {
            Issue.record("A perpendicular plane must produce a circle on a cylinder.")
            return
        }
        #expect(abs(perpendicularCircle.radius - 2.0) <= tolerance.distance)
        #expect(perpendicularResult.maximumResidual <= tolerance.distance)

        let obliqueNormal = try Vector3D(x: 0.0, y: 1.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let obliqueSection = try intersector.intersections(
            first: .analytic(.plane(origin: .origin, normal: obliqueNormal)),
            second: cylinder,
            tolerance: tolerance
        )
        guard case let .curve(result) = try #require(obliqueSection.first),
              case let .analytic(.ellipse(_, _, _, majorRadius, minorRadius)) = result.curve else {
            Issue.record("An oblique plane must produce an ellipse on a cylinder.")
            return
        }
        #expect(abs(majorRadius - 2.0 * sqrt(2.0)) <= tolerance.distance)
        #expect(abs(minorRadius - 2.0) <= tolerance.distance)
        #expect(result.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func sphereSphereProducesCircleTangentAndCoincidence() throws {
        let first = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let second = Surface3D.analytic(.sphere(
            center: Point3D(x: 2.0, y: 0.0, z: 0.0),
            radius: 2.0
        ))
        let section = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        guard case let .curve(result) = try #require(section.first),
              case let .circle(circle) = result.curve else {
            Issue.record("Two secant spheres must produce a circle.")
            return
        }
        #expect(circle.center.isApproximatelyEqual(
            to: Point3D(x: 1.0, y: 0.0, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(abs(circle.radius - sqrt(3.0)) <= tolerance.distance)

        let tangent = try intersector.intersections(
            first: first,
            second: .analytic(.sphere(
                center: Point3D(x: 4.0, y: 0.0, z: 0.0),
                radius: 2.0
            )),
            tolerance: tolerance
        )
        #expect(tangent.contains {
            if case .point = $0 { return true }
            return false
        })

        let coincident = try intersector.intersections(
            first: first,
            second: first,
            tolerance: tolerance
        )
        #expect(coincident.contains {
            if case .coincident = $0 { return true }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func planeConeProducesClosedEllipseAndApexGeneratorLines() throws {
        let halfAngle = Double.pi / 6.0
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))
        let obliqueNormal = try Vector3D(x: 0.0, y: 0.5, z: sqrt(0.75)).normalized(
            tolerance: tolerance.distance
        )
        let closedSection = try intersector.intersections(
            first: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 2.0),
                normal: obliqueNormal
            )),
            second: cone,
            tolerance: tolerance
        )
        guard case let .curve(closedResult) = try #require(closedSection.first),
              case .analytic(.ellipse) = closedResult.curve else {
            Issue.record("An elliptic plane-cone section must retain exact ellipse geometry.")
            return
        }
        #expect(closedResult.maximumResidual <= tolerance.distance)

        let generatorSection = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitY)),
            second: cone,
            tolerance: tolerance
        )
        #expect(generatorSection.count == 2)
        #expect(generatorSection.allSatisfy {
            guard case let .curve(result) = $0,
                  case .line = result.curve else { return false }
            return result.kind == .transverse && result.maximumResidual <= tolerance.distance
        })

        let tangentNormal = try Vector3D(
            x: cos(halfAngle),
            y: 0.0,
            z: -sin(halfAngle)
        ).normalized(tolerance: tolerance.distance)
        let tangentSection = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: tangentNormal)),
            second: cone,
            tolerance: tolerance
        )
        guard case let .curve(tangentResult) = try #require(tangentSection.first) else {
            Issue.record("A tangent plane through the cone apex must produce one generator.")
            return
        }
        #expect(tangentSection.count == 1)
        #expect(tangentResult.kind == .tangent)
        #expect(tangentResult.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func planeConeProducesExactUnboundedHyperbolaBranchesAndDualPcurves() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))

        let intersections = try intersector.intersections(
            first: plane,
            second: cone,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case .analytic(.hyperbola) = result.curve else {
                Issue.record("A hyperbolic plane-cone section must retain exact unbounded conic geometry.")
                continue
            }
            #expect(result.curve.parameterDomain == .unbounded)
            #expect(result.kind == .transverse)
            #expect(result.maximumResidual <= tolerance.distance)
            for parameter in [-1.0, 0.0, 1.0] {
                let point = try result.curve.point(at: parameter, tolerance: tolerance)
                let planeUV = try result.surfaceParameter(
                    on: .first,
                    atCurveParameter: parameter,
                    tolerance: tolerance
                )
                let coneUV = try result.surfaceParameter(
                    on: .second,
                    atCurveParameter: parameter,
                    tolerance: tolerance
                )
                let planePoint = try plane.point(u: planeUV.u, v: planeUV.v, tolerance: tolerance)
                let conePoint = try cone.point(u: coneUV.u, v: coneUV.v, tolerance: tolerance)
                #expect(point.isApproximatelyEqual(to: planePoint, tolerance: tolerance.distance))
                #expect(point.isApproximatelyEqual(to: conePoint, tolerance: tolerance.distance))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func planeConeProducesExactUnboundedParabolaAndDualPcurves() throws {
        let halfAngle = Double.pi / 6.0
        let normal = try Vector3D(
            x: cos(halfAngle),
            y: 0.0,
            z: -sin(halfAngle)
        ).normalized(tolerance: tolerance.distance)
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: -normal.x, y: -normal.y, z: -normal.z),
            normal: normal
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))

        let intersections = try intersector.intersections(
            first: plane,
            second: cone,
            tolerance: tolerance
        )

        guard case let .curve(result) = try #require(intersections.first),
              case .analytic(.parabola) = result.curve else {
            Issue.record("A parabolic plane-cone section must retain exact unbounded conic geometry.")
            return
        }
        #expect(intersections.count == 1)
        #expect(result.curve.parameterDomain == .unbounded)
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        for parameter in [-1.0, 0.0, 1.0] {
            let point = try result.curve.point(at: parameter, tolerance: tolerance)
            let planeUV = try result.surfaceParameter(
                on: .first,
                atCurveParameter: parameter,
                tolerance: tolerance
            )
            let coneUV = try result.surfaceParameter(
                on: .second,
                atCurveParameter: parameter,
                tolerance: tolerance
            )
            let planePoint = try plane.point(u: planeUV.u, v: planeUV.v, tolerance: tolerance)
            let conePoint = try cone.point(u: coneUV.u, v: coneUV.v, tolerance: tolerance)
            #expect(point.isApproximatelyEqual(to: planePoint, tolerance: tolerance.distance))
            #expect(point.isApproximatelyEqual(to: conePoint, tolerance: tolerance.distance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusProducesAxialMeridionalAndTangentSections() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let axialSection = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            second: torus,
            tolerance: tolerance
        )
        let axialRadii = axialSection.compactMap { intersection -> Double? in
            guard case let .curve(result) = intersection,
                  case let .circle(circle) = result.curve else { return nil }
            return circle.radius
        }.sorted()
        #expect(axialRadii.count == 2)
        #expect(abs(axialRadii[0] - 2.0) <= tolerance.distance)
        #expect(abs(axialRadii[1] - 4.0) <= tolerance.distance)

        let meridionalSection = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitY)),
            second: torus,
            tolerance: tolerance
        )
        #expect(meridionalSection.count == 2)
        #expect(meridionalSection.allSatisfy {
            guard case let .curve(result) = $0,
                  case let .circle(circle) = result.curve else { return false }
            return abs(circle.radius - 1.0) <= tolerance.distance
                && result.maximumResidual <= tolerance.distance
        })

        let tangentSection = try intersector.intersections(
            first: .plane(Plane3D(
                origin: Point3D(x: 4.0, y: 0.0, z: 0.0),
                normal: .unitX
            )),
            second: torus,
            tolerance: tolerance
        )
        guard case let .point(tangentPoint) = try #require(tangentSection.first) else {
            Issue.record("A torus support plane must produce one verified tangent point.")
            return
        }
        #expect(tangentSection.count == 1)
        #expect(tangentPoint.point.isApproximatelyEqual(
            to: Point3D(x: 4.0, y: 0.0, z: 0.0),
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusProducesVerifiedOffsetQuarticSection() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let intersections = try intersector.intersections(
            first: plane,
            second: torus,
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        guard case let .curve(result) = try #require(intersections.first),
              case .analyticAnalytic = result.truth,
              case .analytic(.planeTorus) = result.curve else {
            Issue.record("An offset plane-torus section must produce exact algebraic truth.")
            return
        }
        #expect(result.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusOffsetQuarticCertificateRoundTripsAndEvaluates() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let intersections = try intersector.intersections(
            first: plane,
            second: torus,
            tolerance: tolerance
        )
        try verifyGeneralPlaneTorusCurves(
            intersections,
            plane: plane,
            torus: torus
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusOffsetSectionIsOperandOrderInvariant() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let intersections = try intersector.intersections(
            first: plane,
            second: torus,
            tolerance: tolerance
        )

        let reverse = try intersector.intersections(
            first: torus,
            second: plane,
            tolerance: tolerance
        )
        #expect(intersectionCurves(intersections) == intersectionCurves(reverse))
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusProducesTwoVerifiedObliqueQuarticSections() throws {
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let plane = Surface3D.analytic(.plane(origin: .origin, normal: normal))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let intersections = try intersector.intersections(
            first: plane,
            second: torus,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        try verifyGeneralPlaneTorusCurves(
            intersections,
            plane: plane,
            torus: torus
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusInternalTangencyReturnsTypedSingularDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: .plane(Plane3D(
                    origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
                    normal: .unitX
                )),
                second: .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 3.0,
                    minorRadius: 1.0
                )),
                tolerance: tolerance
            )
            Issue.record("A singular inner-support plane-torus section must not be regularized.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unsupportedAnalyticPairReturnsTypedDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: .analytic(.cone(
                    apex: Point3D(x: 0.25, y: 0.0, z: 0.0),
                    axis: .unitZ,
                    halfAngle: Double.pi / 6.0
                )),
                second: .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 3.0,
                    minorRadius: 1.0
                )),
                tolerance: tolerance
            )
            Issue.record("Unsupported analytic pairs must not return approximate geometry.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyGeneralPlaneTorusCurves(
        _ intersections: [SurfaceSurfaceIntersection],
        plane: Surface3D,
        torus: Surface3D
    ) throws {
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case .analyticAnalytic = result.truth,
                  case .analytic(.planeTorus) = result.curve,
                  case let .periodic(period) = result.curve.parameterDomain else {
                Issue.record("A regular general plane-torus section must use certified algebraic truth.")
                continue
            }
            let lower = 0.0
            let upper = period
            #expect(result.kind == .transverse)
            #expect(result.maximumResidual <= tolerance.distance)
            try result.firstSurfaceParameterCurve.validate(
                on: plane,
                tolerance: tolerance
            )
            try result.secondSurfaceParameterCurve.validate(
                on: torus,
                tolerance: tolerance
            )
            let encoded = try JSONEncoder().encode(intersection)
            let decoded = try JSONDecoder().decode(
                SurfaceSurfaceIntersection.self,
                from: encoded
            )
            #expect(decoded == intersection)
            for index in 0...24 {
                let parameter = lower + (upper - lower) * Double(index) / 24.0
                let point = try result.curve.point(
                    at: parameter,
                    tolerance: tolerance
                )
                let planeProjection = try plane.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
                let torusProjection = try torus.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
                #expect(planeProjection.residual <= tolerance.distance)
                #expect(torusProjection.residual <= tolerance.distance)
            }
            for fraction in [0.125, 0.5, 0.875] {
                let firstDifferential = try result.firstSurfaceParameterCurve
                    .differentialGeometry(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                let secondDifferential = try result.secondSurfaceParameterCurve
                    .differentialGeometry(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                #expect(firstDifferential.firstDerivative.x.isFinite)
                #expect(firstDifferential.firstDerivative.y.isFinite)
                #expect(secondDifferential.firstDerivative.x.isFinite)
                #expect(secondDifferential.firstDerivative.y.isFinite)
            }
        }
    }

    private func intersectionCurves(
        _ intersections: [SurfaceSurfaceIntersection]
    ) -> [Curve3D] {
        intersections.compactMap {
            guard case let .curve(result) = $0 else { return nil }
            return result.curve
        }
    }
}
