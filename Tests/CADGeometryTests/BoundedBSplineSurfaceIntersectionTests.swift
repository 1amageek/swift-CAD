import CADCore
@testable import CADGeometry
import Testing

@Suite("Bounded B-Spline Surface Intersection")
struct BoundedBSplineSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func transverseBilinearSurfacesProduceVerifiedCurveAndDualPcurves() throws {
        let horizontal = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
        let vertical = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.5, z: -1.0), Point3D(x: 1.0, y: 0.5, z: -1.0)],
                [Point3D(x: 0.0, y: 0.5, z: 1.0), Point3D(x: 1.0, y: 0.5, z: 1.0)],
            ],
            weights: [
                [1.0, 1.25],
                [0.75, 1.0],
            ]
        )
        let first = Surface3D.bSpline(horizontal)
        let second = Surface3D.bSpline(vertical)

        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        guard case let .curve(result) = try #require(intersections.first),
              case let .implicit(implicitCurve) = result.curve,
              case let .bSpline(derivedSpline) = result.derivedRepresentation.curve,
              case .certifiedImplicit = result.firstSurfaceParameterCurve,
              case .certifiedImplicit = result.secondSurfaceParameterCurve else {
            Issue.record("Two transverse bounded B-spline surfaces must produce certified implicit truth and derived caches.")
            return
        }
        #expect(intersections.count == 1)
        #expect(implicitCurve.cells.isEmpty == false)
        #expect(derivedSpline.degree == 3)
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let firstUV = try result.firstSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let secondUV = try result.secondSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let firstPoint = try first.point(u: firstUV.u, v: firstUV.v, tolerance: tolerance)
            let secondPoint = try second.point(u: secondUV.u, v: secondUV.v, tolerance: tolerance)
            #expect(firstPoint.isApproximatelyEqual(to: secondPoint, tolerance: tolerance.distance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func identicalSurfacesProduceCoincidence() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(surface),
            second: .bSpline(surface),
            tolerance: tolerance
        )
        #expect(intersections.count == 1)
        #expect(intersections.contains { if case .coincident = $0 { return true }; return false })
    }

    @Test(.timeLimit(.minutes(1)))
    func exactQuadraticTangencyCertificateBypassesSubdivisionBudget() throws {
        let plane = Self.planarPatch()
        let paraboloid = Self.quadraticHeightPatch { xCoefficient, yCoefficient in
            xCoefficient + yCoefficient
        }

        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(plane),
            second: .bSpline(paraboloid),
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 8,
                maximumSubdivisionCells: 1
            ),
            tolerance: tolerance
        )
        guard intersections.count == 1,
              case let .point(point) = intersections[0] else {
            Issue.record("An exact quadratic tangency certificate must bypass generic subdivision.")
            return
        }
        #expect(point.residual <= tolerance.distance)
        #expect(point.point.isApproximatelyEqual(
            to: .origin,
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func completeRegularGraphStopsBeforeSubdivisionAndPreservesOperandOrder() throws {
        let horizontal = Self.unitPlanarPatch()
        let vertical = Self.verticalPlanarPatch()
        let options = SurfaceSurfaceIntersectionOptions(
            maximumSubdivisionDepth: 8,
            maximumSubdivisionCells: 1,
            maximumRootAttempts: 3
        )

        let forward = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(horizontal),
            second: .bSpline(vertical),
            options: options,
            tolerance: tolerance
        )
        let reverse = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(vertical),
            second: .bSpline(horizontal),
            options: options,
            tolerance: tolerance
        )

        let forwardCurve = try Self.onlyCurve(forward)
        let reverseCurve = try Self.onlyCurve(reverse)
        #expect(forwardCurve.kind == .transverse)
        #expect(reverseCurve.kind == .transverse)
        #expect(forwardCurve.maximumResidual <= tolerance.distance)
        #expect(reverseCurve.maximumResidual <= tolerance.distance)
        for fraction in [0.0, 0.5, 1.0] {
            let forwardPoint = try Self.point(
                on: forwardCurve.curve,
                fraction: fraction,
                tolerance: tolerance
            )
            let reversePoint = try Self.point(
                on: reverseCurve.curve,
                fraction: fraction,
                tolerance: tolerance
            )
            #expect(abs(forwardPoint.x - 0.5) <= tolerance.distance)
            #expect(abs(forwardPoint.z) <= tolerance.distance)
            #expect(forwardPoint.isApproximatelyEqual(
                to: reversePoint,
                tolerance: tolerance.distance
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func completeRegularGraphChargesEveryCertifiedProbeToTheRootAttemptBudget() throws {
        do {
            _ = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .bSpline(Self.unitPlanarPatch()),
                second: .bSpline(Self.verticalPlanarPatch()),
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 8,
                    maximumSubdivisionCells: 1,
                    maximumRootAttempts: 2
                ),
                tolerance: tolerance
            )
            Issue.record("A complete regular graph requires three budgeted root probes.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
            #expect(error.message.contains("numerical root-attempt"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundaryKrawczykPromotesAClippedRegularArcToAFullGraph() throws {
        let horizontal = Self.unitPlanarPatch()
        let vertical = Self.verticalPlanarPatch(yLower: 0.4, yUpper: 1.6)
        let options = SurfaceSurfaceIntersectionOptions(
            maximumSubdivisionDepth: 0,
            maximumSubdivisionCells: 1,
            maximumSeedCount: 2,
            maximumRootAttempts: 3
        )

        let forward = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(horizontal),
            second: .bSpline(vertical),
            options: options,
            tolerance: tolerance
        )
        let reverse = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(vertical),
            second: .bSpline(horizontal),
            options: options,
            tolerance: tolerance
        )

        let forwardCurve = try Self.onlyCurve(forward)
        let reverseCurve = try Self.onlyCurve(reverse)
        for fraction in [0.0, 0.5, 1.0] {
            let forwardPoint = try Self.point(
                on: forwardCurve.curve,
                fraction: fraction,
                tolerance: tolerance
            )
            let reversePoint = try Self.point(
                on: reverseCurve.curve,
                fraction: fraction,
                tolerance: tolerance
            )
            #expect(forwardPoint.isApproximatelyEqual(
                to: reversePoint,
                tolerance: tolerance.distance
            ))
            #expect(abs(forwardPoint.x - 0.5) <= tolerance.distance)
            #expect(abs(forwardPoint.z) <= tolerance.distance)
        }
        let lower = try Self.point(
            on: forwardCurve.curve,
            fraction: 0.0,
            tolerance: tolerance
        )
        let upper = try Self.point(
            on: forwardCurve.curve,
            fraction: 1.0,
            tolerance: tolerance
        )
        #expect(abs(lower.y - 0.4) <= tolerance.distance)
        #expect(abs(upper.y - 1.0) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedQuadraticTangencyProducesOneVerifiedPoint() throws {
        let plane = Self.planarPatch()
        let paraboloid = Self.quadraticHeightPatch { xCoefficient, yCoefficient in
            xCoefficient + yCoefficient
        }

        let forward = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(plane),
            second: .bSpline(paraboloid),
            tolerance: tolerance
        )
        let reverse = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(paraboloid),
            second: .bSpline(plane),
            tolerance: tolerance
        )

        guard case let .point(forwardPoint) = try #require(forward.first),
              case let .point(reversePoint) = try #require(reverse.first) else {
            Issue.record("An isolated B-spline surface tangency must produce one point.")
            return
        }
        #expect(forward.count == 1)
        #expect(reverse.count == 1)
        #expect(forwardPoint.residual <= tolerance.distance)
        #expect(reversePoint.residual <= tolerance.distance)
        #expect(forwardPoint.point.isApproximatelyEqual(
            to: .origin,
            tolerance: tolerance.distance
        ))
        #expect(forwardPoint.point.isApproximatelyEqual(
            to: reversePoint.point,
            tolerance: tolerance.distance
        ))
        #expect(abs(forwardPoint.firstSurfaceParameter.u - 0.5) <= tolerance.distance)
        #expect(abs(forwardPoint.firstSurfaceParameter.v - 0.5) <= tolerance.distance)
        #expect(abs(forwardPoint.secondSurfaceParameter.u - 0.5) <= tolerance.distance)
        #expect(abs(forwardPoint.secondSurfaceParameter.v - 0.5) <= tolerance.distance)

        let firstNormal = try plane.normal(
            u: forwardPoint.firstSurfaceParameter.u,
            v: forwardPoint.firstSurfaceParameter.v,
            tolerance: tolerance
        )
        let secondNormal = try paraboloid.normal(
            u: forwardPoint.secondSurfaceParameter.u,
            v: forwardPoint.secondSurfaceParameter.v,
            tolerance: tolerance
        )
        #expect(firstNormal.cross(secondNormal).length <= tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentContactCurveProducesVerifiedCurveAndDualPcurves() throws {
        let plane = Self.planarPatch()
        let parabolicCylinder = Self.quadraticHeightPatch { xCoefficient, _ in
            xCoefficient
        }

        let forward = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(plane),
            second: .bSpline(parabolicCylinder),
            tolerance: tolerance
        )
        let reverse = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(parabolicCylinder),
            second: .bSpline(plane),
            tolerance: tolerance
        )

        guard case let .curve(forwardCurve) = try #require(forward.first),
              case let .curve(reverseCurve) = try #require(reverse.first),
              case let .bSpline(forwardSpline) = forwardCurve.curve,
              case let .bSpline(reverseSpline) = reverseCurve.curve,
              case .quadraticTangency = forwardCurve.truth,
              case .quadraticTangency = reverseCurve.truth else {
            Issue.record("A rank-one B-spline tangency must produce a bounded contact curve.")
            return
        }
        #expect(forward.count == 1)
        #expect(reverse.count == 1)
        #expect(forwardSpline.degree == 1)
        #expect(reverseSpline.degree == 1)
        #expect(forwardCurve.kind == .tangent)
        #expect(reverseCurve.kind == .tangent)
        #expect(forwardCurve.maximumResidual <= tolerance.distance)
        #expect(reverseCurve.maximumResidual <= tolerance.distance)
        try forwardCurve.firstSurfaceParameterCurve.validate(
            on: .bSpline(plane),
            tolerance: tolerance
        )
        try forwardCurve.secondSurfaceParameterCurve.validate(
            on: .bSpline(parabolicCylinder),
            tolerance: tolerance
        )

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let planeUV = try forwardCurve.firstSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let cylinderUV = try forwardCurve.secondSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let reverseCylinderUV = try reverseCurve.firstSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let reversePlaneUV = try reverseCurve.secondSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let planePoint = try plane.point(
                u: planeUV.u,
                v: planeUV.v,
                tolerance: tolerance
            )
            let cylinderPoint = try parabolicCylinder.point(
                u: cylinderUV.u,
                v: cylinderUV.v,
                tolerance: tolerance
            )
            let reverseCylinderPoint = try parabolicCylinder.point(
                u: reverseCylinderUV.u,
                v: reverseCylinderUV.v,
                tolerance: tolerance
            )
            let reversePlanePoint = try plane.point(
                u: reversePlaneUV.u,
                v: reversePlaneUV.v,
                tolerance: tolerance
            )
            #expect(planePoint.isApproximatelyEqual(
                to: cylinderPoint,
                tolerance: tolerance.distance
            ))
            #expect(planePoint.isApproximatelyEqual(
                to: reverseCylinderPoint,
                tolerance: tolerance.distance
            ))
            #expect(planePoint.isApproximatelyEqual(
                to: reversePlanePoint,
                tolerance: tolerance.distance
            ))
            #expect(abs(planePoint.x) <= tolerance.distance)
            #expect(abs(planePoint.z) <= tolerance.distance)

            let planeNormal = try plane.normal(
                u: planeUV.u,
                v: planeUV.v,
                tolerance: tolerance
            )
            let cylinderNormal = try parabolicCylinder.normal(
                u: cylinderUV.u,
                v: cylinderUV.v,
                tolerance: tolerance
            )
            #expect(planeNormal.cross(cylinderNormal).length <= tolerance.angle)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundarySubdivisionIsolatesMultipleRootsWithoutFourDimensionalSubdivision() throws {
        let horizontal = Self.narrowHorizontalPatch()
        let oscillating = Self.oscillatingRuledPatch()
        let options = SurfaceSurfaceIntersectionOptions(
            maximumSubdivisionDepth: 0,
            maximumSubdivisionCells: 1,
            maximumSeedCount: 6,
            maximumRootAttempts: 64,
            maximumBoundarySubdivisionDepth: 10,
            maximumBoundarySubdivisionCells: 4_096
        )

        let forward = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(horizontal),
            second: .bSpline(oscillating),
            options: options,
            tolerance: tolerance
        )
        let reverse = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(oscillating),
            second: .bSpline(horizontal),
            options: options,
            tolerance: tolerance
        )
        let forwardCurves = try Self.curvesOrderedByMidpointX(
            forward,
            tolerance: tolerance
        )
        let reverseCurves = try Self.curvesOrderedByMidpointX(
            reverse,
            tolerance: tolerance
        )

        #expect(forwardCurves.count == 3)
        #expect(reverseCurves.count == 3)
        for index in forwardCurves.indices {
            for fraction in [0.0, 0.5, 1.0] {
                let forwardPoint = try Self.point(
                    on: forwardCurves[index].curve,
                    fraction: fraction,
                    tolerance: tolerance
                )
                let reversePoint = try Self.point(
                    on: reverseCurves[index].curve,
                    fraction: fraction,
                    tolerance: tolerance
                )
                #expect(forwardPoint.isApproximatelyEqual(
                    to: reversePoint,
                    tolerance: tolerance.distance
                ))
                #expect(abs(forwardPoint.z) <= tolerance.distance)
            }
            let lowerEndpoint = try Self.point(
                on: forwardCurves[index].curve,
                fraction: 0.0,
                tolerance: tolerance
            )
            let upperEndpoint = try Self.point(
                on: forwardCurves[index].curve,
                fraction: 1.0,
                tolerance: tolerance
            )
            #expect(abs(abs(lowerEndpoint.y) - 0.001) <= tolerance.distance)
            #expect(abs(abs(upperEndpoint.y) - 0.001) <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func incompleteBoundaryProofRejectsInsteadOfReturningOneOfMultipleComponents() throws {
        do {
            _ = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .bSpline(Self.narrowHorizontalPatch()),
                second: .bSpline(Self.oscillatingRuledPatch()),
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 0,
                    maximumSubdivisionCells: 1,
                    maximumBoundarySubdivisionDepth: 10,
                    maximumBoundarySubdivisionCells: 1
                ),
                tolerance: tolerance
            )
            Issue.record("An uncertified regular cell must not return a partial component set.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
            #expect(error.message.contains("complete boundary-root proof"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func branchingTangencyProducesTwoVerifiedMixedCurves() throws {
        let plane = Self.planarPatch()
        let saddle = Self.quadraticHeightPatch { xCoefficient, yCoefficient in
            xCoefficient - yCoefficient
        }
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(plane),
            second: .bSpline(saddle),
            tolerance: tolerance
        )

        try verifyBranchingIntersections(
            intersections,
            plane: plane,
            saddle: saddle,
            planeParameterIsFirst: true
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func reversedBranchingTangencyProducesTwoVerifiedMixedCurves() throws {
        let plane = Self.planarPatch()
        let saddle = Self.quadraticHeightPatch { xCoefficient, yCoefficient in
            xCoefficient - yCoefficient
        }
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(saddle),
            second: .bSpline(plane),
            tolerance: tolerance
        )

        try verifyBranchingIntersections(
            intersections,
            plane: plane,
            saddle: saddle,
            planeParameterIsFirst: false
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func uncertifiedHigherOrderTangencyRejectsInsteadOfReturningAPartialLocus() throws {
        do {
            _ = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .bSpline(Self.planarPatch()),
                second: .bSpline(Self.quarticHeightPatch()),
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 0,
                    maximumSubdivisionCells: 1
                ),
                tolerance: tolerance
            )
            Issue.record("An uncertified higher-order tangency must not return a partial locus.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
            #expect(error.message.contains("complete tangency-locus certificate"))
        }
    }

    @Test
    func quadraticTangencyCompletenessRequiresExactEligibility() throws {
        let plane = Self.planarPatch()
        let exactHeight = Self.quadraticHeightPatch { xCoefficient, yCoefficient in
            xCoefficient + yCoefficient
        }
        var nonConstantWeights = exactHeight.weights
        nonConstantWeights[1][1] = nonConstantWeights[1][1].nextUp
        let rationalPerturbation = BSplineSurface3D(
            uDegree: exactHeight.uDegree,
            vDegree: exactHeight.vDegree,
            uKnots: exactHeight.uKnots,
            vKnots: exactHeight.vKnots,
            controlPoints: exactHeight.controlPoints,
            weights: nonConstantWeights
        )
        var nonAffineControls = exactHeight.controlPoints
        let center = nonAffineControls[1][1]
        nonAffineControls[1][1] = Point3D(
            x: center.x.nextUp,
            y: center.y,
            z: center.z
        )
        let affinePerturbation = BSplineSurface3D(
            uDegree: exactHeight.uDegree,
            vDegree: exactHeight.vDegree,
            uKnots: exactHeight.uKnots,
            vKnots: exactHeight.vKnots,
            controlPoints: nonAffineControls,
            weights: exactHeight.weights
        )

        for surface in [rationalPerturbation, affinePerturbation] {
            let certificate = try QuadraticHeightFieldTangencyCertificate.certified(
                first: plane,
                second: surface,
                tolerance: tolerance
            )
            switch certificate {
            case nil:
                break
            case .some:
                Issue.record("Arithmetic-near eligibility must not become an exact tangency certificate.")
            }
        }
    }

    private func verifyBranchingIntersections(
        _ intersections: [SurfaceSurfaceIntersection],
        plane: BSplineSurface3D,
        saddle: BSplineSurface3D,
        planeParameterIsFirst: Bool
    ) throws {
        let curves = intersections.compactMap { intersection in
            if case let .curve(curve) = intersection { return curve }
            return nil
        }
        #expect(intersections.count == 2)
        #expect(curves.count == 2)

        var points: [Point3D] = []
        for curve in curves {
            guard case let .bSpline(spline) = curve.curve else {
                Issue.record("A branching bounded intersection must use a B-spline curve.")
                continue
            }
            guard case .quadraticTangency = curve.truth else {
                Issue.record("A branching quadratic locus must retain its completeness certificate.")
                continue
            }
            #expect(spline.degree == 1)
            #expect(curve.kind == .mixed)
            #expect(curve.maximumResidual <= tolerance.distance)
            let planePcurve = planeParameterIsFirst
                ? curve.firstSurfaceParameterCurve
                : curve.secondSurfaceParameterCurve
            let saddlePcurve = planeParameterIsFirst
                ? curve.secondSurfaceParameterCurve
                : curve.firstSurfaceParameterCurve
            try planePcurve.validate(on: .bSpline(plane), tolerance: tolerance)
            try saddlePcurve.validate(on: .bSpline(saddle), tolerance: tolerance)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let planeUV = try planePcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let saddleUV = try saddlePcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let planePoint = try plane.point(
                    u: planeUV.u,
                    v: planeUV.v,
                    tolerance: tolerance
                )
                let saddlePoint = try saddle.point(
                    u: saddleUV.u,
                    v: saddleUV.v,
                    tolerance: tolerance
                )
                #expect(planePoint.isApproximatelyEqual(
                    to: saddlePoint,
                    tolerance: tolerance.distance
                ))
                #expect(abs(abs(planePoint.x) - abs(planePoint.y)) <= tolerance.distance)
                #expect(abs(planePoint.z) <= tolerance.distance)
                points.append(planePoint)
            }
        }
        let expectedBoundaryPoints = [
            Point3D(x: -1.0, y: -1.0, z: 0.0),
            Point3D(x: -1.0, y: 1.0, z: 0.0),
            Point3D(x: 1.0, y: -1.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
        ]
        for expected in expectedBoundaryPoints {
            #expect(points.contains {
                expected.isApproximatelyEqual(to: $0, tolerance: tolerance.distance)
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func adaptiveCubicResidualCertificateAcceptsExactPlanarCurve() throws {
        let plane = Self.unitPlanarPatch()
        let result = try CubicSurfaceResidualCertifier().certify(
            pointControls: [
                Point3D(x: 0.0, y: 0.5, z: 0.0),
                Point3D(x: 1.0 / 3.0, y: 0.5, z: 0.0),
                Point3D(x: 2.0 / 3.0, y: 0.5, z: 0.0),
                Point3D(x: 1.0, y: 0.5, z: 0.0),
            ],
            firstControls: Self.planarParameterControls,
            secondControls: Self.planarParameterControls,
            first: plane,
            second: plane,
            options: SurfaceSurfaceIntersectionOptions(
                maximumResidualCertificationDepth: 12,
                maximumResidualCertificationCells: 4_096
            ),
            tolerance: tolerance
        )

        #expect(result.maximumResidualUpperBound <= tolerance.distance)
        #expect(result.certifiedCellCount > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func adaptiveCubicResidualCertificateRejectsBetweenLegacySamples() throws {
        let certificationTolerance = ModelingTolerance(
            distance: 1.0e-3,
            angle: 1.0e-8
        )
        let plane = Self.unitPlanarPatch()
        let scale = 0.004149721015416819
        let zControls = [
            0.061336593293372266,
            0.7884847648009938,
            -0.9487422730978872,
            0.190661237778591,
        ].map { $0 * scale }
        let pointControls = zip(Self.planarParameterControls, zControls).map { parameter, z in
            Point3D(x: parameter.x, y: parameter.y, z: z)
        }
        let legacyFractions = (0...8).map { Double($0) / 8.0 }
        let legacyMaximum = legacyFractions.map { fraction in
            abs(Self.cubicValue(zControls, fraction: fraction))
        }.max() ?? .infinity
        #expect(legacyMaximum < certificationTolerance.distance)

        do {
            _ = try CubicSurfaceResidualCertifier().certify(
                pointControls: pointControls,
                firstControls: Self.planarParameterControls,
                secondControls: Self.planarParameterControls,
                first: plane,
                second: plane,
                options: SurfaceSurfaceIntersectionOptions(
                    maximumResidualCertificationDepth: 20,
                    maximumResidualCertificationCells: 65_536
                ),
                tolerance: certificationTolerance
            )
            Issue.record("Adaptive residual certification must reject a between-sample excursion.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect((error.residual ?? 0.0) > certificationTolerance.distance)
            #expect(error.tolerance == certificationTolerance)
        }
    }

    private static func planarPatch() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: -1.0, y: -1.0, z: 0.0), Point3D(x: 1.0, y: -1.0, z: 0.0)],
                [Point3D(x: -1.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
    }

    private static func unitPlanarPatch() -> BSplineSurface3D {
        BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )
    }

    private static func verticalPlanarPatch(
        yLower: Double = -1.0,
        yUpper: Double = 2.0
    ) -> BSplineSurface3D {
        BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: 0.5, y: yLower, z: -1.0),
            bottomRight: Point3D(x: 0.5, y: yUpper, z: -1.0),
            topRight: Point3D(x: 0.5, y: yUpper, z: 1.0),
            topLeft: Point3D(x: 0.5, y: yLower, z: 1.0)
        )
    }

    private static func narrowHorizontalPatch() -> BSplineSurface3D {
        BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: 0.0, y: -0.001, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: -0.001, z: 0.0),
            topRight: Point3D(x: 1.0, y: 0.001, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 0.001, z: 0.0)
        )
    }

    private static func oscillatingRuledPatch() -> BSplineSurface3D {
        let roots = [0.18, 0.47, 0.82]
        let scale = 0.25
        let constant = -roots[0] * roots[1] * roots[2] * scale
        let linear = (
            roots[0] * roots[1]
                + roots[0] * roots[2]
                + roots[1] * roots[2]
        ) * scale
        let quadratic = -(roots[0] + roots[1] + roots[2]) * scale
        let cubic = scale
        let yControls = [
            constant,
            constant + linear / 3.0,
            constant + 2.0 * linear / 3.0 + quadratic / 3.0,
            constant + linear + quadratic + cubic,
        ]
        let xControls = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        return BSplineSurface3D(
            uDegree: 3,
            vDegree: 1,
            uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [-1.0, 1.0].map { z in
                xControls.indices.map { index in
                    Point3D(x: xControls[index], y: yControls[index], z: z)
                }
            }
        )
    }

    private static func curvesOrderedByMidpointX(
        _ intersections: [SurfaceSurfaceIntersection],
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersectionCurve] {
        let curves = try intersections.map { intersection in
            guard case let .curve(curve) = intersection else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected only bounded surface intersection curves."
                )
            }
            return curve
        }
        let keyed = try curves.map { curve in
            (
                curve: curve,
                midpointX: try point(
                    on: curve.curve,
                    fraction: 0.5,
                    tolerance: tolerance
                ).x
            )
        }
        return keyed.sorted { $0.midpointX < $1.midpointX }.map(\.curve)
    }

    private static func onlyCurve(
        _ intersections: [SurfaceSurfaceIntersection]
    ) throws -> SurfaceSurfaceIntersectionCurve {
        guard intersections.count == 1,
              case let .curve(curve) = intersections[0] else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: .standard,
                message: "Expected one bounded surface intersection curve."
            )
        }
        return curve
    }

    private static func point(
        on curve: Curve3D,
        fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        guard case let .closed(lower, upper) = curve.parameterDomain else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Expected a bounded surface intersection curve domain."
            )
        }
        return try curve.point(
            at: lower + (upper - lower) * fraction,
            tolerance: tolerance
        )
    }

    private static let planarParameterControls = [
        Point2D(x: 0.0, y: 0.5),
        Point2D(x: 1.0 / 3.0, y: 0.5),
        Point2D(x: 2.0 / 3.0, y: 0.5),
        Point2D(x: 1.0, y: 0.5),
    ]

    private static func cubicValue(_ controls: [Double], fraction: Double) -> Double {
        let complement = 1.0 - fraction
        return controls[0] * complement * complement * complement
            + 3.0 * controls[1] * complement * complement * fraction
            + 3.0 * controls[2] * complement * fraction * fraction
            + controls[3] * fraction * fraction * fraction
    }

    private static func quadraticHeightPatch(
        height: (_ xSquaredCoefficient: Double, _ ySquaredCoefficient: Double) -> Double
    ) -> BSplineSurface3D {
        let coordinates = [-1.0, 0.0, 1.0]
        let squaredCoefficients = [1.0, -1.0, 1.0]
        let controlPoints = coordinates.indices.map { vIndex in
            coordinates.indices.map { uIndex in
                Point3D(
                    x: coordinates[uIndex],
                    y: coordinates[vIndex],
                    z: height(
                        squaredCoefficients[uIndex],
                        squaredCoefficients[vIndex]
                    )
                )
            }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: controlPoints,
            weights: Array(
                repeating: Array(repeating: 2.0, count: 3),
                count: 3
            )
        )
    }

    private static func quarticHeightPatch() -> BSplineSurface3D {
        let degree = 4
        let powerCoefficients = [1.0, -8.0, 24.0, -32.0, 16.0]
        let heightControls = (0...degree).map { controlIndex in
            (0...controlIndex).reduce(0.0) { result, powerIndex in
                result + powerCoefficients[powerIndex]
                    * binomial(controlIndex, powerIndex)
                    / binomial(degree, powerIndex)
            }
        }
        let coordinateControls = (0...degree).map {
            -1.0 + 2.0 * Double($0) / Double(degree)
        }
        return BSplineSurface3D(
            uDegree: degree,
            vDegree: degree,
            uKnots: Array(repeating: 0.0, count: degree + 1)
                + Array(repeating: 1.0, count: degree + 1),
            vKnots: Array(repeating: 0.0, count: degree + 1)
                + Array(repeating: 1.0, count: degree + 1),
            controlPoints: coordinateControls.indices.map { vIndex in
                coordinateControls.indices.map { uIndex in
                    Point3D(
                        x: coordinateControls[uIndex],
                        y: coordinateControls[vIndex],
                        z: heightControls[uIndex] + heightControls[vIndex]
                    )
                }
            }
        )
    }

    private static func binomial(_ degree: Int, _ index: Int) -> Double {
        let reducedIndex = min(index, degree - index)
        guard reducedIndex > 0 else { return 1.0 }
        return (1...reducedIndex).reduce(1.0) { result, step in
            result * Double(degree - reducedIndex + step) / Double(step)
        }
    }
}
