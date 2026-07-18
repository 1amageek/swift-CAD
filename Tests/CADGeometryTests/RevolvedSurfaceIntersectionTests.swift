import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Revolved Surface Intersection")
struct RevolvedSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func parallelCylindersProduceVerifiedLinesTangencyAndCoincidence() throws {
        let first = cylinder(origin: .origin, radius: 2.0)
        let transverse = try intersector.intersections(
            first: first,
            second: cylinder(origin: Point3D(x: 2.0, y: 0.0, z: 3.0), radius: 2.0),
            tolerance: tolerance
        )
        #expect(transverse.count == 2)
        #expect(transverse.allSatisfy { intersection in
            guard case let .curve(result) = intersection,
                  case .line = result.curve else { return false }
            return result.kind == .transverse && result.maximumResidual <= tolerance.distance
        })

        let tangent = try intersector.intersections(
            first: first,
            second: cylinder(origin: Point3D(x: 4.0, y: 0.0, z: -2.0), radius: 2.0),
            tolerance: tolerance
        )
        guard case let .curve(tangentResult) = try #require(tangent.first) else {
            Issue.record("Externally tangent parallel cylinders must produce one exact line.")
            return
        }
        #expect(tangent.count == 1)
        #expect(tangentResult.kind == .tangent)

        let coincident = try intersector.intersections(
            first: first,
            second: .analytic(.cylinder(
                origin: Point3D(x: 0.0, y: 0.0, z: 5.0),
                axis: -.unitZ,
                radius: 2.0
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
    func coaxialSphereCylinderProducesTwoCirclesAndTangency() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let transverse = try intersector.intersections(
            first: sphere,
            second: cylinder(origin: Point3D(x: 0.0, y: 0.0, z: 4.0), radius: 1.0),
            tolerance: tolerance
        )
        let centers = transverse.compactMap(circleCenter).sorted { $0.z < $1.z }
        #expect(centers.count == 2)
        #expect(abs(centers[0].z + sqrt(3.0)) <= tolerance.distance)
        #expect(abs(centers[1].z - sqrt(3.0)) <= tolerance.distance)

        let tangent = try intersector.intersections(
            first: sphere,
            second: cylinder(origin: .origin, radius: 2.0),
            tolerance: tolerance
        )
        guard case let .curve(result) = try #require(tangent.first) else {
            Issue.record("A sphere and its equatorial cylinder must be tangent along one circle.")
            return
        }
        #expect(tangent.count == 1)
        #expect(result.kind == .tangent)
        #expect(result.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialConePairsProduceExactCircles() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 4.0
        ))
        let coneCylinder = try intersector.intersections(
            first: cone,
            second: cylinder(origin: Point3D(x: 0.0, y: 0.0, z: 2.0), radius: 1.0),
            tolerance: tolerance
        )
        let cylinderCenters = coneCylinder.compactMap(circleCenter).sorted { $0.z < $1.z }
        #expect(cylinderCenters.count == 2)
        #expect(abs(cylinderCenters[0].z + 1.0) <= tolerance.distance)
        #expect(abs(cylinderCenters[1].z - 1.0) <= tolerance.distance)

        let sphereCone = try intersector.intersections(
            first: .analytic(.sphere(center: .origin, radius: 2.0)),
            second: cone,
            tolerance: tolerance
        )
        let sphereCenters = sphereCone.compactMap(circleCenter).sorted { $0.z < $1.z }
        #expect(sphereCenters.count == 2)
        #expect(abs(sphereCenters[0].z + sqrt(2.0)) <= tolerance.distance)
        #expect(abs(sphereCenters[1].z - sqrt(2.0)) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialConesProduceExactCirclesPointAndCoincidence() throws {
        let first = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 4.0
        ))
        let equalAngle = try intersector.intersections(
            first: first,
            second: .analytic(.cone(
                apex: Point3D(x: 0.0, y: 0.0, z: 2.0),
                axis: .unitZ,
                halfAngle: Double.pi / 4.0
            )),
            tolerance: tolerance
        )
        guard let equalAngleCircle = equalAngle.compactMap(circle).first else {
            Issue.record("Axially shifted equal-angle cones must intersect in one exact circle.")
            return
        }
        #expect(equalAngle.count == 1)
        #expect(abs(equalAngleCircle.radius - 1.0) <= tolerance.distance)
        #expect(abs(equalAngleCircle.center.z - 1.0) <= tolerance.distance)

        let unequalAngle = try intersector.intersections(
            first: first,
            second: .analytic(.cone(
                apex: Point3D(x: 0.0, y: 0.0, z: 3.0),
                axis: .unitZ,
                halfAngle: atan(0.5)
            )),
            tolerance: tolerance
        )
        let unequalAngleCircles = unequalAngle.compactMap(circle).sorted {
            $0.radius < $1.radius
        }
        #expect(unequalAngleCircles.count == 2)
        #expect(abs(unequalAngleCircles[0].radius - 1.0) <= tolerance.distance)
        #expect(abs(unequalAngleCircles[0].center.z - 1.0) <= tolerance.distance)
        #expect(abs(unequalAngleCircles[1].radius - 3.0) <= tolerance.distance)
        #expect(abs(unequalAngleCircles[1].center.z + 3.0) <= tolerance.distance)

        let commonApex = try intersector.intersections(
            first: first,
            second: .analytic(.cone(
                apex: .origin,
                axis: .unitZ,
                halfAngle: Double.pi / 6.0
            )),
            tolerance: tolerance
        )
        guard case let .point(apexIntersection) = try #require(commonApex.first) else {
            Issue.record("Unequal-angle cones with a common apex must intersect at that apex.")
            return
        }
        #expect(commonApex.count == 1)
        #expect(apexIntersection.point == .origin)
        #expect(apexIntersection.residual <= tolerance.distance)

        let coincident = try intersector.intersections(
            first: first,
            second: .analytic(.cone(
                apex: .origin,
                axis: -.unitZ,
                halfAngle: Double.pi / 4.0
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
    func nonCoaxialConeConeReturnsTypedDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: .analytic(.cone(
                    apex: .origin,
                    axis: .unitZ,
                    halfAngle: Double.pi / 4.0
                )),
                second: .analytic(.cone(
                    apex: Point3D(x: 0.1, y: 0.0, z: 2.0),
                    axis: .unitZ,
                    halfAngle: Double.pi / 4.0
                )),
                tolerance: tolerance
            )
            Issue.record("Non-coaxial cones must reject without approximation.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.residual == 0.1)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialTorusCylinderProducesTransverseAndTangentCircles() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let transverse = try intersector.intersections(
            first: torus,
            second: cylinder(origin: .origin, radius: 3.0),
            tolerance: tolerance
        )
        let centers = transverse.compactMap(circleCenter).sorted { $0.z < $1.z }
        #expect(centers.count == 2)
        #expect(abs(centers[0].z + 1.0) <= tolerance.distance)
        #expect(abs(centers[1].z - 1.0) <= tolerance.distance)

        let tangent = try intersector.intersections(
            first: torus,
            second: cylinder(origin: .origin, radius: 4.0),
            tolerance: tolerance
        )
        guard case let .curve(result) = try #require(tangent.first) else {
            Issue.record("A torus and its support cylinder must produce one tangent circle.")
            return
        }
        #expect(tangent.count == 1)
        #expect(result.kind == .tangent)
        #expect(result.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialSphereTorusProducesTransverseAndTangentCircles() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let transverse = try intersector.intersections(
            first: .analytic(.sphere(center: .origin, radius: sqrt(10.0))),
            second: torus,
            tolerance: tolerance
        )
        let transverseCircles = transverse.compactMap(circle).sorted {
            $0.center.z < $1.center.z
        }
        #expect(transverseCircles.count == 2)
        #expect(abs(transverseCircles[0].center.z + 1.0) <= tolerance.distance)
        #expect(abs(transverseCircles[1].center.z - 1.0) <= tolerance.distance)
        #expect(transverseCircles.allSatisfy {
            abs($0.radius - 3.0) <= tolerance.distance
        })

        let tangent = try intersector.intersections(
            first: torus,
            second: .analytic(.sphere(center: .origin, radius: 4.0)),
            tolerance: tolerance
        )
        guard case let .curve(result) = try #require(tangent.first),
              case let .circle(tangentCircle) = result.curve else {
            Issue.record("A coaxial sphere and torus must produce one tangent circle.")
            return
        }
        #expect(tangent.count == 1)
        #expect(result.kind == .tangent)
        #expect(abs(tangentCircle.radius - 4.0) <= tolerance.distance)
        #expect(result.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedAndOffAxisSphereTorusCasesAreTyped() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let separated = try intersector.intersections(
            first: .analytic(.sphere(center: .origin, radius: 1.0)),
            second: torus,
            tolerance: tolerance
        )
        #expect(separated.isEmpty)

        do {
            _ = try intersector.intersections(
                first: .analytic(.sphere(
                    center: Point3D(x: 0.1, y: 0.0, z: 0.0),
                    radius: 3.0
                )),
                second: torus,
                tolerance: tolerance
            )
            Issue.record("Off-axis sphere-torus intersection must reject without approximation.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.residual == 0.1)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialToriProduceTwoCirclesTangencyAndCoincidence() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let transverse = try intersector.intersections(
            first: first,
            second: .analytic(.torus(
                center: Point3D(x: 0.0, y: 0.0, z: 1.0),
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 1.0
            )),
            tolerance: tolerance
        )
        let transverseCircles = transverse.compactMap(circle).sorted {
            $0.radius < $1.radius
        }
        #expect(transverseCircles.count == 2)
        #expect(transverseCircles.allSatisfy {
            abs($0.center.z - 0.5) <= tolerance.distance
        })
        #expect(abs(
            transverseCircles[0].radius - (3.0 - sqrt(3.0) * 0.5)
        ) <= tolerance.distance)
        #expect(abs(
            transverseCircles[1].radius - (3.0 + sqrt(3.0) * 0.5)
        ) <= tolerance.distance)

        let tangent = try intersector.intersections(
            first: first,
            second: .analytic(.torus(
                center: Point3D(x: 0.0, y: 0.0, z: 2.0),
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 1.0
            )),
            tolerance: tolerance
        )
        guard case let .curve(tangentResult) = try #require(tangent.first),
              case let .circle(tangentCircle) = tangentResult.curve else {
            Issue.record("Externally tangent coaxial tori must produce one circle.")
            return
        }
        #expect(tangent.count == 1)
        #expect(tangentResult.kind == .tangent)
        #expect(abs(tangentCircle.radius - 3.0) <= tolerance.distance)
        #expect(abs(tangentCircle.center.z - 1.0) <= tolerance.distance)

        let coincident = try intersector.intersections(
            first: first,
            second: .analytic(.torus(
                center: .origin,
                axis: -.unitZ,
                majorRadius: 3.0,
                minorRadius: 1.0
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
    func separatedAndNonCoaxialToriAreTyped() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let separated = try intersector.intersections(
            first: first,
            second: .analytic(.torus(
                center: Point3D(x: 0.0, y: 0.0, z: 3.0),
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 1.0
            )),
            tolerance: tolerance
        )
        #expect(separated.isEmpty)

        do {
            _ = try intersector.intersections(
                first: first,
                second: .analytic(.torus(
                    center: Point3D(x: 0.1, y: 0.0, z: 0.0),
                    axis: .unitZ,
                    majorRadius: 3.0,
                    minorRadius: 1.0
                )),
                tolerance: tolerance
            )
            Issue.record("Non-coaxial tori must reject without approximation.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.residual == 0.1)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialConeTorusProducesExactTransverseAndTangentCircles() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let transverse = try intersector.intersections(
            first: .analytic(.cone(
                apex: Point3D(x: 0.0, y: 0.0, z: -3.0),
                axis: .unitZ,
                halfAngle: Double.pi / 4.0
            )),
            second: torus,
            tolerance: tolerance
        )
        let transverseCircles = transverse.compactMap(circle).sorted {
            $0.radius < $1.radius
        }
        let meridianOffset = 1.0 / sqrt(2.0)
        #expect(transverseCircles.count == 2)
        #expect(abs(transverseCircles[0].radius - (3.0 - meridianOffset)) <= tolerance.distance)
        #expect(abs(transverseCircles[0].center.z + meridianOffset) <= tolerance.distance)
        #expect(abs(transverseCircles[1].radius - (3.0 + meridianOffset)) <= tolerance.distance)
        #expect(abs(transverseCircles[1].center.z - meridianOffset) <= tolerance.distance)

        let tangent = try intersector.intersections(
            first: torus,
            second: .analytic(.cone(
                apex: Point3D(x: 0.0, y: 0.0, z: -3.0 + sqrt(2.0)),
                axis: .unitZ,
                halfAngle: Double.pi / 4.0
            )),
            tolerance: tolerance
        )
        guard case let .curve(tangentResult) = try #require(tangent.first),
              case let .circle(tangentCircle) = tangentResult.curve else {
            Issue.record("A meridian-tangent coaxial cone and torus must produce one circle.")
            return
        }
        #expect(tangent.count == 1)
        #expect(tangentResult.kind == .tangent)
        #expect(abs(tangentCircle.radius - (3.0 - meridianOffset)) <= tolerance.distance)
        #expect(abs(tangentCircle.center.z - meridianOffset) <= tolerance.distance)
        #expect(tangentResult.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedAndOffAxisConeTorusCasesAreTyped() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let separated = try intersector.intersections(
            first: .analytic(.cone(
                apex: .origin,
                axis: .unitZ,
                halfAngle: Double.pi / 4.0
            )),
            second: torus,
            tolerance: tolerance
        )
        #expect(separated.isEmpty)

        do {
            _ = try intersector.intersections(
                first: .analytic(.cone(
                    apex: Point3D(x: 0.1, y: 0.0, z: -3.0),
                    axis: .unitZ,
                    halfAngle: Double.pi / 4.0
                )),
                second: torus,
                tolerance: tolerance
            )
            Issue.record("Off-axis cone-torus intersection must reject without approximation.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.residual == 0.1)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func undeclaredAxisRelationsReturnTypedDiagnostics() throws {
        do {
            _ = try intersector.intersections(
                first: cylinder(origin: .origin, radius: 2.0),
                second: .analytic(.cylinder(
                    origin: Point3D(x: 0.0, y: 0.5, z: 0.0),
                    axis: .unitX,
                    radius: 2.0
                )),
                tolerance: tolerance
            )
            Issue.record("Skew cylinders must not use an approximate curve fallback.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }

        do {
            _ = try intersector.intersections(
                first: .analytic(.sphere(
                    center: Point3D(x: 0.5, y: 0.0, z: 0.0),
                    radius: 2.0
                )),
                second: cylinder(origin: .origin, radius: 1.0),
                tolerance: tolerance
            )
            Issue.record("Non-coaxial sphere-cylinder intersections must reject without approximation.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }
    }

    private func cylinder(origin: Point3D, radius: Double) -> Surface3D {
        .analytic(.cylinder(origin: origin, axis: .unitZ, radius: radius))
    }

    private func circleCenter(_ intersection: SurfaceSurfaceIntersection) -> Point3D? {
        guard case let .curve(result) = intersection,
              case let .circle(circle) = result.curve,
              result.maximumResidual <= tolerance.distance else {
            return nil
        }
        return circle.center
    }

    private func circle(_ intersection: SurfaceSurfaceIntersection) -> Circle3D? {
        guard case let .curve(result) = intersection,
              case let .circle(circle) = result.curve,
              result.kind == .transverse,
              result.maximumResidual <= tolerance.distance else {
            return nil
        }
        return circle
    }
}
