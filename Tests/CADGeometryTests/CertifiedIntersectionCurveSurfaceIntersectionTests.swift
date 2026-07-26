import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("Certified intersection curve-surface intersection")
struct CertifiedIntersectionCurveSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func reducedSectionIntersectionBoundIncludesTargetDegree() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.0, y: 0.0, z: 2.0),
            radius: sqrt(3.0)
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))
        let curve = CertifiedIntersectionCurve3D.sphereCone(
            try CertifiedSphereConeIntersectionCurve(
                sphereSurface: sphere,
                coneSurface: cone,
                componentKind: .positiveFullBranch,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
        )
        let resolver =
            DefaultCertifiedReducedSectionIntersectionBoundResolver()

        let planeBound = try resolver.isolatedIntersectionUpperBound(
            curve: curve,
            targetSurface: .analytic(.plane(
                origin: .origin,
                normal: .unitZ
            )),
            tolerance: tolerance
        )
        let cylinderBound = try resolver.isolatedIntersectionUpperBound(
            curve: curve,
            targetSurface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 1.0
            )),
            tolerance: tolerance
        )
        let torusBound = try resolver.isolatedIntersectionUpperBound(
            curve: curve,
            targetSurface: .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 2.0,
                minorRadius: 0.5
            )),
            tolerance: tolerance
        )

        #expect(planeBound == 4)
        #expect(cylinderBound == 8)
        #expect(torusBound == 16)
    }

    @Test(.timeLimit(.minutes(1)))
    func reducedSectionIntersectionBoundRejectsUncertifiedTargetDegree() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.0, y: 0.0, z: 2.0),
            radius: sqrt(3.0)
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))
        let curve = CertifiedIntersectionCurve3D.sphereCone(
            try CertifiedSphereConeIntersectionCurve(
                sphereSurface: sphere,
                coneSurface: cone,
                componentKind: .positiveFullBranch,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
        )
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ]
        )
        try surface.validate(tolerance: tolerance)

        do {
            _ = try DefaultCertifiedReducedSectionIntersectionBoundResolver()
                .isolatedIntersectionUpperBound(
                    curve: curve,
                    targetSurface: .bSpline(surface),
                    tolerance: tolerance
                )
            Issue.record(
                "A target without a certified algebraic degree must not produce an identity witness bound."
            )
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func reducedApexComponentsPreserveSharedNodeCandidate() throws {
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
        let intersections = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: cone,
                second: cylinder,
                tolerance: tolerance
            )
        let components: [(
            section: SurfaceSurfaceIntersectionCurve,
            curve: CertifiedIntersectionCurve3D
        )] = try intersections.map { intersection in
            guard case let .curve(section) = intersection,
                  case let .analyticAnalytic(truth) = section.truth,
                  case let .coneCylinder(curve) = truth.definition else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "The apex-node fixture requires certified cone-cylinder components."
                )
            }
            return (section, .coneCylinder(curve))
        }
        #expect(components.count == 2)
        let classifier = DefaultCertifiedReducedSectionComponentClassifier()
        let nodeResolver =
            DefaultCertifiedIntersectionNodeCandidateResolver()

        for index in components.indices {
            let query = components[index]
            let other = components[(index + 1) % components.count]
            switch try classifier.classification(
                of: query.section,
                relativeTo: query.curve,
                targetSurface: cylinder,
                tolerance: tolerance
            ) {
            case .identical:
                break
            case .distinct:
                Issue.record(
                    "A component must be identical to its own reduced section."
                )
            }
            switch try classifier.classification(
                of: other.section,
                relativeTo: query.curve,
                targetSurface: cylinder,
                tolerance: tolerance
            ) {
            case .identical:
                Issue.record(
                    "Two apex-node loops must remain distinct components."
                )
            case .distinct:
                break
            }

            let candidates = try nodeResolver.candidates(
                curve: query.curve,
                targetSurface: cylinder,
                tolerance: tolerance
            )
            #expect(candidates.count == 1)
            let candidate = try #require(candidates.first)
            #expect(candidate.point.isApproximatelyEqual(
                to: .origin,
                tolerance: tolerance.distance
            ))
            #expect(candidate.residual <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sphereConeReducedPlaneDistinguishesCoincidentComponents() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.0, y: 0.0, z: 2.0),
            radius: sqrt(3.0)
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))
        let curves = try [
            CertifiedSphereConeIntersectionCurve.ComponentKind
                .negativeFullBranch,
            .positiveFullBranch,
        ].map { componentKind in
            Curve3D.certifiedIntersection(.sphereCone(
                try CertifiedSphereConeIntersectionCurve(
                    sphereSurface: sphere,
                    coneSurface: cone,
                    componentKind: componentKind,
                    lowerAngle: 0.0,
                    upperAngle: 2.0 * Double.pi,
                    tolerance: tolerance
                )
            ))
        }

        for selectedCurve in curves {
            let selectedPoint = try selectedCurve.point(
                at: 0.375,
                tolerance: tolerance
            )
            let plane = Surface3D.analytic(.plane(
                origin: selectedPoint,
                normal: .unitZ
            ))
            do {
                _ = try DefaultCurveSurfaceIntersector().intersections(
                    curve: selectedCurve,
                    surface: plane,
                    options: .init(),
                    tolerance: tolerance
                )
                Issue.record(
                    "A plane containing one complete sphere-cone component must report a non-discrete intersection."
                )
            } catch let error as KernelError {
                #expect(error.code == .nonDiscreteIntersection)
            }

            for otherCurve in curves where otherCurve != selectedCurve {
                let intersections = try DefaultCurveSurfaceIntersector()
                    .intersections(
                        curve: otherCurve,
                        surface: plane,
                        options: .init(),
                        tolerance: tolerance
                    )
                #expect(intersections.isEmpty)
            }
        }
    }

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
        try verifyConeHostedTargetCone(curve: curve)
        try verifySeparatedBoundedSurfaceReturnsEmpty(
            curve: curve,
            thirdSurface: .analytic(.torus(
                center: Point3D(x: 100.0, y: 100.0, z: 100.0),
                axis: .unitZ,
                majorRadius: 2.0,
                minorRadius: 0.5
            ))
        )
        try verifyStructurallyBoundedTorusIntersections(curve: curve)
        try verifyStructurallyBoundedRationalSurfaceIntersection(curve: curve)
        try verifyNonPlanarRationalSurfaceIntersection(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func sphereConeSupportsArbitraryCylinderReductions() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: .unitY,
            radius: 1.0
        ))
        let coneCylinderSections = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: cone,
                second: cylinder,
                tolerance: tolerance
            )
        var sectionCurve: Curve3D?
        for section in coneCylinderSections {
            guard case let .curve(result) = section else {
                continue
            }
            sectionCurve = result.curve
            break
        }
        let expectedSection = try #require(sectionCurve)
        let expectedPoint = try expectedSection.point(
            at: 0.3125,
            tolerance: tolerance
        )
        let sphereCenter = Point3D(
            x: expectedPoint.x * 0.5,
            y: expectedPoint.y * 0.5,
            z: expectedPoint.z * 0.5
        )
        let sphere = Surface3D.analytic(.sphere(
            center: sphereCenter,
            radius: (expectedPoint - sphereCenter).length
        ))
        let sphereConeResults = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: sphere,
                second: cone,
                tolerance: tolerance
            )
        var certifiedCurves: [Curve3D] = []
        for result in sphereConeResults {
            guard case let .curve(section) = result,
                  case .certifiedIntersection(.sphereCone) = section.curve else {
                continue
            }
            certifiedCurves.append(section.curve)
        }
        #expect(certifiedCurves.isEmpty == false)

        var matchedCurve: Curve3D?
        var matchedIntersection: CurveSurfaceIntersection?
        for curve in certifiedCurves {
            let intersections = try DefaultCurveSurfaceIntersector()
                .intersections(
                    curve: curve,
                    surface: cylinder,
                    options: .init(),
                    tolerance: tolerance
                )
            for intersection in intersections {
                try verifyCylinderIntersection(
                    intersection,
                    expectedKind: .transverse,
                    curve: curve,
                    cylinder: cylinder
                )
                if (intersection.point - expectedPoint).length
                    <= tolerance.distance {
                    matchedCurve = curve
                    matchedIntersection = intersection
                }
            }
        }
        let curve = try #require(matchedCurve)
        let intersection = try #require(matchedIntersection)

        let curveRange = try ScalarInterval(
            lower: max(0.0, intersection.curveParameter - 0.01),
            upper: min(1.0, intersection.curveParameter + 0.01)
        )
        let restricted = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: cylinder,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(restricted.count == 1)
        #expect(restricted.allSatisfy {
            curveRange.contains($0.curveParameter)
        })

        let excludedVRange = try ScalarInterval(
            lower: intersection.surfaceV + 10.0,
            upper: intersection.surfaceV + 11.0
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: cylinder,
                options: .init(
                    curveRange: curveRange,
                    surfaceVRange: excludedVRange
                ),
                tolerance: tolerance
            )
        #expect(rangeExcluded.isEmpty)

        let reversedCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.0, y: 2.0, z: 4.0),
            axis: -Vector3D.unitY,
            radius: 1.0
        ))
        let reversedSections = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: cone,
                second: reversedCylinder,
                tolerance: tolerance
            )
        #expect(reversedSections.count == coneCylinderSections.count)
        var reversedSectionCandidates: [CurveSurfaceIntersection] = []
        for section in reversedSections {
            guard case let .curve(result) = section,
                  case let .analyticAnalytic(truth) = result.truth,
                  case let .coneCylinder(sectionCurve) = truth.definition else {
                continue
            }
            reversedSectionCandidates.append(
                contentsOf: try DefaultCurveSurfaceIntersector()
                    .intersections(
                        curve: .certifiedIntersection(
                            .coneCylinder(sectionCurve)
                        ),
                        surface: sphere,
                        options: .init(),
                        tolerance: tolerance
                    )
            )
        }
        #expect(reversedSectionCandidates.contains {
            ($0.point - expectedPoint).length <= tolerance.distance
        })
        let reversed = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: reversedCylinder,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        #expect(reversed.count == restricted.count)
        #expect(reversed.allSatisfy { candidate in
            restricted.contains {
                ($0.point - candidate.point).length <= tolerance.distance
            }
        })

        let emptyCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 10.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptyCylinder,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneConeSupportsReducedPlaneAndCylinderIntersections() throws {
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
        try verifyConeConeReducedCylinderIntersections(curve: curve)
        try verifyConeHostedTargetCone(curve: curve)
        try verifyConeHostedTargetSphere(curve: curve)
        try verifySeparatedBoundedSurfaceReturnsEmpty(curve: curve)
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
        try verifyConeCylinderConeIntersections(curve: curve)
        try verifySeparatedBoundedSurfaceReturnsEmpty(
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
    func certifiedTargetParameterRefinementExhaustionFailsExplicitly() throws {
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
        let modelCurve = try certifiedCurve(
            first: cone,
            second: cylinder
        )
        let certified = try #require({
            if case let .certifiedIntersection(curve) = modelCurve {
                return curve
            }
            return nil
        }())
        let expectedParameter = 0.3125
        let geometry = try modelCurve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let tangentPlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try geometry.curvatureVector.normalized(
                tolerance: tolerance.distance
            )
        ))
        do {
            _ = try DefaultCertifiedIntersectionTargetParameterRefiner()
                .refinedParameter(
                    initialParameter: expectedParameter + 1.0e-4,
                    curve: certified,
                    target: try CertifiedAnalyticIntersectionTarget(
                        surface: tangentPlane,
                        tolerance: tolerance
                    ),
                    restrictedTo: try ScalarInterval(
                        lower: expectedParameter - 0.01,
                        upper: expectedParameter + 0.01
                    ),
                    maximumIterations: 1,
                    tolerance: tolerance
                )
            Issue.record(
                "Expected certified target parameter refinement to exhaust its iteration budget."
            )
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func coneCylinderConePolynomialMatchesQuadraticResultant() throws {
        let sourceCone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))
        let targetCone = Surface3D.analytic(.cone(
            apex: Point3D(x: -0.5, y: 0.75, z: -1.0),
            axis: try Vector3D(
                x: 0.3,
                y: -0.4,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            halfAngle: atan(0.375)
        ))
        let context = try ConeCylinderConeIntersectionContext(
            sourceConeSurface: sourceCone,
            cylinderSurface: cylinder,
            targetConeSurface: targetCone,
            tolerance: tolerance
        )
        let polynomial = DefaultHeightQuadraticResultantPolynomialBuilder()
            .polynomial(
                first: context.sourceEquation,
                second: context.targetEquation
            )

        for angle in [0.1, 0.7, 1.8, 4.2, 5.7] {
            let tangentHalfAngle = tan(angle * 0.5)
            let polynomialValue = polynomial.coefficients.reversed()
                .reduce(0.0) {
                    $0 * tangentHalfAngle + $1
                }
            let first = context.sourceEquation.coefficients(at: angle)
            let second = context.targetEquation.coefficients(at: angle)
            let leadingConstant =
                first.leading * second.constant
                - first.constant * second.leading
            let leadingLinear =
                first.leading * second.linear
                - first.linear * second.leading
            let linearConstant =
                first.linear * second.constant
                - first.constant * second.linear
            let resultant = leadingConstant * leadingConstant
                - leadingLinear * linearConstant
            let denominatorScale = pow(
                1.0 + tangentHalfAngle * tangentHalfAngle,
                8.0
            )
            let expectedValue = resultant * denominatorScale
            #expect(
                abs(polynomialValue - expectedValue)
                    <= max(abs(expectedValue), 1.0) * 1.0e-9
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func coneCylinderConeDegenerateResultantDeclinesCertifiedPath() throws {
        let sourceCone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))
        let curve = try certifiedCurve(
            first: sourceCone,
            second: cylinder
        )
        guard case let .certifiedIntersection(.coneCylinder(component)) =
                curve else {
            Issue.record("Expected a certified cone-cylinder component.")
            return
        }
        let intersector = DefaultConeCylinderConeIntersector()

        #expect(try intersector.supports(
            curve: component,
            coneSurface: sourceCone,
            tolerance: tolerance
        ) == false)
        do {
            _ = try intersector.intersections(
                curve: component,
                coneSurface: sourceCone,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A degenerate resultant must not report intersections.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func coneHostedQuadricPolynomialMatchesQuadraticResultant() throws {
        let hostCone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let sourceSphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.75, y: -0.25, z: 1.5),
            radius: 2.0
        ))
        let targetCone = Surface3D.analytic(.cone(
            apex: Point3D(x: -0.5, y: 0.75, z: -1.0),
            axis: try Vector3D(
                x: 0.3,
                y: -0.4,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            halfAngle: atan(0.375)
        ))
        let context = try ConeHostedQuadricIntersectionContext(
            hostConeSurface: hostCone,
            sourceSurface: sourceSphere,
            targetSurface: targetCone,
            tolerance: tolerance
        )
        let polynomial = DefaultHeightQuadraticResultantPolynomialBuilder()
            .polynomial(
                first: context.sourceEquation,
                second: context.targetEquation
            )

        for angle in [0.1, 0.7, 1.8, 4.2, 5.7] {
            let tangentHalfAngle = tan(angle * 0.5)
            let polynomialValue = polynomial.coefficients.reversed()
                .reduce(0.0) {
                    $0 * tangentHalfAngle + $1
                }
            let first = context.sourceEquation.coefficients(at: angle)
            let second = context.targetEquation.coefficients(at: angle)
            let leadingConstant =
                first.leading * second.constant
                - first.constant * second.leading
            let leadingLinear =
                first.leading * second.linear
                - first.linear * second.leading
            let linearConstant =
                first.linear * second.constant
                - first.constant * second.linear
            let resultant = leadingConstant * leadingConstant
                - leadingLinear * linearConstant
            let denominatorScale = pow(
                1.0 + tangentHalfAngle * tangentHalfAngle,
                8.0
            )
            let expectedValue = resultant * denominatorScale
            #expect(
                abs(polynomialValue - expectedValue)
                    <= max(abs(expectedValue), 1.0) * 1.0e-9
            )
        }

        let degenerateContext = try ConeHostedQuadricIntersectionContext(
            hostConeSurface: hostCone,
            sourceSurface: sourceSphere,
            targetSurface: sourceSphere,
            tolerance: tolerance
        )
        let solver = DefaultHeightQuadraticTripleSolver()
        #expect(solver.supports(
            context: degenerateContext,
            tolerance: tolerance
        ) == false)
        do {
            _ = try solver.candidates(
                context: degenerateContext,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A degenerate cone-hosted resultant must fail.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect(error.tolerance == tolerance)
        }
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
        try verifySeparatedBoundedSurfaceReturnsEmpty(curve: curve)
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
            try verifySeparatedBoundedSurfaceReturnsEmpty(curve: curve)
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
                <= tolerance.relative * 64.0,
            "Expected \(expectedParameter), received \(expectedTangent.curveParameter)."
        )
        #expect(
            expectedTangent.kind == .tangent,
            "Expected tangent, received \(expectedTangent.kind)."
        )

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

    private func verifyConeHostedTargetCone(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.4125
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let targetAxis = try Vector3D(
            x: 0.3,
            y: -0.4,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let radialDirection = try analyticOrthonormalBasis(
            targetAxis,
            tolerance: tolerance
        ).u
        let targetCone = Surface3D.analytic(.cone(
            apex: expectedGeometry.position
                + targetAxis * -2.0
                + radialDirection * 0.75,
            axis: targetAxis,
            halfAngle: atan(0.375)
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.04,
            upper: expectedParameter + 0.04
        )
        try verifyConeHostedIntersection(
            curve: curve,
            targetSurface: targetCone,
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .transverse,
            curveRange: curveRange
        )
        try verifyConeHostedSurfaceRangeExclusion(
            curve: curve,
            targetSurface: targetCone,
            expectedGeometry: expectedGeometry,
            curveRange: curveRange
        )

        let curveTangent = try expectedGeometry.tangent.normalized(
            tolerance: tolerance.distance
        )
        let tangentConeAxis = try analyticOrthonormalBasis(
            curveTangent,
            tolerance: tolerance
        ).u
        let tangentRadialDirection = try curveTangent
            .cross(tangentConeAxis)
            .normalized(tolerance: tolerance.distance)
        let tangentCone = Surface3D.analytic(.cone(
            apex: expectedGeometry.position
                + tangentConeAxis * -2.0
                + tangentRadialDirection * -0.75,
            axis: tangentConeAxis,
            halfAngle: atan(0.375)
        ))
        try verifyConeHostedIntersection(
            curve: curve,
            targetSurface: tangentCone,
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .tangent,
            curveRange: curveRange
        )

        let excludedRange = try ScalarInterval(
            lower: expectedParameter + 0.08,
            upper: expectedParameter + 0.12
        )
        let excluded = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: targetCone,
            options: .init(curveRange: excludedRange),
            tolerance: tolerance
        )
        #expect(excluded.isEmpty)

        let emptyCone = Surface3D.analytic(.cone(
            apex: Point3D(x: 100.0, y: 100.0, z: 100.0),
            axis: .unitZ,
            halfAngle: atan(0.1)
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptyCone,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: targetCone,
                options: .init(maximumPolynomialDegree: 1),
                tolerance: tolerance
            )
            Issue.record("A degree-limited cone-hosted elimination must fail.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyConeHostedTargetSphere(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.5875
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let tangent = try expectedGeometry.tangent.normalized(
            tolerance: tolerance.distance
        )
        let transverseSphere = Surface3D.analytic(.sphere(
            center: expectedGeometry.position + tangent * -0.5,
            radius: 0.5
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.04,
            upper: expectedParameter + 0.04
        )
        try verifyConeHostedIntersection(
            curve: curve,
            targetSurface: transverseSphere,
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .transverse,
            curveRange: curveRange
        )
        try verifyConeHostedSurfaceRangeExclusion(
            curve: curve,
            targetSurface: transverseSphere,
            expectedGeometry: expectedGeometry,
            curveRange: curveRange
        )

        let tangentNormal = try analyticOrthonormalBasis(
            tangent,
            tolerance: tolerance
        ).u
        let tangentSphere = Surface3D.analytic(.sphere(
            center: expectedGeometry.position + tangentNormal * -0.5,
            radius: 0.5
        ))
        try verifyConeHostedIntersection(
            curve: curve,
            targetSurface: tangentSphere,
            expectedGeometry: expectedGeometry,
            expectedParameter: expectedParameter,
            expectedKind: .tangent,
            curveRange: curveRange
        )
    }

    private func verifyConeHostedIntersection(
        curve: Curve3D,
        targetSurface: Surface3D,
        expectedGeometry: Curve3D.DifferentialGeometry,
        expectedParameter: Double,
        expectedKind: CurveSurfaceIntersectionKind,
        curveRange: ScalarInterval
    ) throws {
        let intersections = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: targetSurface,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expected = try #require(intersections.min {
            ($0.point - expectedGeometry.position).length
                < ($1.point - expectedGeometry.position).length
        })
        #expect(
            (expected.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expected.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(expected.kind == expectedKind)
        let projection = try targetSurface.parameterProjection(
            of: expected.point,
            tolerance: tolerance
        )
        #expect(projection.residual <= tolerance.distance)
    }

    private func verifyConeHostedSurfaceRangeExclusion(
        curve: Curve3D,
        targetSurface: Surface3D,
        expectedGeometry: Curve3D.DifferentialGeometry,
        curveRange: ScalarInterval
    ) throws {
        let projection = try targetSurface.parameterProjection(
            of: expectedGeometry.position,
            tolerance: tolerance
        )
        let excludedSurfaceRange = try ScalarInterval(
            lower: projection.u + 0.25,
            upper: projection.u + 0.35
        )
        let excluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: targetSurface,
                options: .init(
                    curveRange: curveRange,
                    surfaceURange: excludedSurfaceRange
                ),
                tolerance: tolerance
            )
        #expect(excluded.isEmpty)
    }

    private func verifyConeCylinderConeIntersections(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.4375
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let targetAxis = try Vector3D(
            x: 0.3,
            y: -0.4,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let radialDirection = try analyticOrthonormalBasis(
            targetAxis,
            tolerance: tolerance
        ).u
        let targetApex = expectedGeometry.position
            + targetAxis * -2.0
            + radialDirection * 0.75
        let targetCone = Surface3D.analytic(.cone(
            apex: targetApex,
            axis: targetAxis,
            halfAngle: atan(0.375)
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.04,
            upper: expectedParameter + 0.04
        )
        let intersections = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: targetCone,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expected = try #require(intersections.min {
            ($0.point - expectedGeometry.position).length
                < ($1.point - expectedGeometry.position).length
        })
        #expect(
            (expected.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expected.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        let projection = try targetCone.parameterProjection(
            of: expected.point,
            tolerance: tolerance
        )
        #expect(projection.residual <= tolerance.distance)

        let curveTangent = try expectedGeometry.tangent.normalized(
            tolerance: tolerance.distance
        )
        let tangentConeAxis = try analyticOrthonormalBasis(
            curveTangent,
            tolerance: tolerance
        ).u
        let tangentRadialDirection = try curveTangent
            .cross(tangentConeAxis)
            .normalized(tolerance: tolerance.distance)
        let tangentApex = expectedGeometry.position
            + tangentConeAxis * -2.0
            + tangentRadialDirection * -0.75
        let tangentCone = Surface3D.analytic(.cone(
            apex: tangentApex,
            axis: tangentConeAxis,
            halfAngle: atan(0.375)
        ))
        let tangentIntersections = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: tangentCone,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expectedTangent = try #require(tangentIntersections.min {
            ($0.point - expectedGeometry.position).length
                < ($1.point - expectedGeometry.position).length
        })
        #expect(
            (expectedTangent.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(expectedTangent.kind == .tangent)

        let excludedRange = try ScalarInterval(
            lower: expectedParameter + 0.08,
            upper: expectedParameter + 0.12
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: targetCone,
                options: .init(curveRange: excludedRange),
                tolerance: tolerance
            )
        #expect(rangeExcluded.isEmpty)

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: targetCone,
                options: .init(maximumPolynomialDegree: 1),
                tolerance: tolerance
            )
            Issue.record("A degree-limited cone elimination must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyConeConeReducedCylinderIntersections(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.375
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let targetAxis = try Vector3D(
            x: -0.2,
            y: 1.0,
            z: 0.3
        ).normalized(tolerance: tolerance.distance)
        let radialDirection = try analyticOrthonormalBasis(
            targetAxis,
            tolerance: tolerance
        ).u
        let targetOrigin = expectedGeometry.position
            + radialDirection * -0.5
        let targetCylinder = Surface3D.analytic(.cylinder(
            origin: targetOrigin,
            axis: targetAxis,
            radius: 0.5
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.04,
            upper: expectedParameter + 0.04
        )
        let intersections = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: targetCylinder,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expected = try #require(intersections.min {
            ($0.point - expectedGeometry.position).length
                < ($1.point - expectedGeometry.position).length
        })
        #expect(
            (expected.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expected.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        let projection = try targetCylinder.parameterProjection(
            of: expected.point,
            tolerance: tolerance
        )
        #expect(projection.residual <= tolerance.distance)

        let excludedRange = try ScalarInterval(
            lower: expectedParameter + 0.08,
            upper: expectedParameter + 0.12
        )
        let rangeExcluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: targetCylinder,
                options: .init(curveRange: excludedRange),
                tolerance: tolerance
            )
        #expect(rangeExcluded.isEmpty)
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
        let skewRadial = try (
            source.axis - skewAxis * source.axis.dot(skewAxis)
        ).normalized(tolerance: tolerance.distance)
        let boundedSkewCylinder = Surface3D.analytic(.cylinder(
            origin: expectedGeometry.position
                + skewRadial * -transverseRadius,
            axis: skewAxis,
            radius: transverseRadius
        ))
        let boundedSkew = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: boundedSkewCylinder,
            options: .init(
                curveRange: curveRange,
                maximumSubdivisionDepth: 20
            ),
            tolerance: tolerance
        )
        #expect(boundedSkew.count == 1)
        let boundedSkewIntersection = try #require(boundedSkew.first)
        #expect(
            abs(boundedSkewIntersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        try verifyCylinderIntersection(
            boundedSkewIntersection,
            expectedKind: .transverse,
            curve: curve,
            cylinder: boundedSkewCylinder
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

    private func verifySeparatedBoundedSurfaceReturnsEmpty(
        curve: Curve3D,
        thirdSurface: Surface3D = .analytic(.sphere(
            center: Point3D(x: 100.0, y: 100.0, z: 100.0),
            radius: 1.0
        ))
    ) throws {
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: thirdSurface,
            options: .init(),
            tolerance: tolerance
        )
        #expect(intersections.isEmpty)
    }

    private func verifyStructurallyBoundedTorusIntersections(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.3125
        let geometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let range = try ScalarInterval(
            lower: expectedParameter - 0.001,
            upper: expectedParameter + 0.001
        )
        for configuration in [
            (
                normal: try geometry.firstDerivative.normalized(
                    tolerance: tolerance.distance
                ),
                kind: CurveSurfaceIntersectionKind.transverse
            ),
            (
                normal: try geometry.curvatureVector.normalized(
                    tolerance: tolerance.distance
                ),
                kind: CurveSurfaceIntersectionKind.tangent
            ),
        ] {
            let basis = try analyticOrthonormalBasis(
                configuration.normal,
                tolerance: tolerance
            )
            let majorRadius = 3.0
            let minorRadius = 0.75
            let target = Surface3D.analytic(.torus(
                center: geometry.position
                    + configuration.normal
                        * -(majorRadius + minorRadius),
                axis: basis.u,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
            let intersections: [CurveSurfaceIntersection]
            do {
                intersections = try DefaultCurveSurfaceIntersector()
                    .intersections(
                        curve: curve,
                        surface: target,
                        options: .init(
                            curveRange: range,
                            maximumSubdivisionDepth: 24
                        ),
                        tolerance: tolerance
                    )
            } catch {
                Issue.record(
                    "Structural torus \(configuration.kind) intersection failed: \(error)"
                )
                throw error
            }
            let intersection = try #require(intersections.min {
                ($0.point - geometry.position).length
                    < ($1.point - geometry.position).length
            })
            #expect(
                (intersection.point - geometry.position).length
                    <= tolerance.distance
            )
            #expect(
                abs(intersection.curveParameter - expectedParameter)
                    <= tolerance.relative * 64.0
            )
            #expect(intersection.kind == configuration.kind)
        }
    }

    private func verifyStructurallyBoundedRationalSurfaceIntersection(
        curve: Curve3D
    ) throws {
        let expectedParameter = 0.3125
        let geometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let normal = try geometry.firstDerivative.normalized(
            tolerance: tolerance.distance
        )
        let basis = try analyticOrthonormalBasis(
            normal,
            tolerance: tolerance
        )
        let extent = 1.0
        let bottomLeft = geometry.position + basis.u * -extent
            + basis.v * -extent
        let bottomRight = geometry.position + basis.u * extent
            + basis.v * -extent
        let topRight = geometry.position + basis.u * extent
            + basis.v * extent
        let topLeft = geometry.position + basis.u * -extent
            + basis.v * extent
        let target = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [bottomLeft, bottomRight],
                [topLeft, topRight],
            ],
            weights: [
                [1.0, 1.5],
                [2.0, 1.25],
            ]
        ))
        let range = try ScalarInterval(
            lower: expectedParameter - 0.001,
            upper: expectedParameter + 0.001
        )

        let intersections = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: target,
                options: .init(
                    curveRange: range,
                    maximumSubdivisionDepth: 24
                ),
                tolerance: tolerance
            )

        let intersection = try #require(intersections.min {
            ($0.point - geometry.position).length
                < ($1.point - geometry.position).length
        })
        #expect(
            (intersection.point - geometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(intersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(
            intersection.kind == CurveSurfaceIntersectionKind.transverse
        )
        #expect(intersection.residual <= tolerance.distance)
    }

    private func verifyNonPlanarRationalSurfaceIntersection(
        curve: Curve3D
    ) throws {
        let expectedCurveParameter = 0.3125
        let expectedSurfaceU = 0.37
        let expectedSurfaceV = 0.41
        let curveGeometry = try curve.differentialGeometry(
            at: expectedCurveParameter,
            tolerance: tolerance
        )
        let normal = try curveGeometry.firstDerivative.normalized(
            tolerance: tolerance.distance
        )
        let basis = try analyticOrthonormalBasis(
            normal,
            tolerance: tolerance
        )
        let localControlPoints = [
            [
                Point3D.origin + basis.u * -1.0 + basis.v * -1.0,
                Point3D.origin + basis.u * 1.0 + basis.v * -1.0
                    + normal * 0.20,
            ],
            [
                Point3D.origin + basis.u * -1.0 + basis.v * 1.0
                    + normal * -0.10,
                Point3D.origin + basis.u * 1.0 + basis.v * 1.0
                    + normal * 0.30,
            ],
        ]
        let weights = [
            [1.0, 1.5],
            [2.0, 1.25],
        ]
        let localSurface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: localControlPoints,
            weights: weights
        )
        let localPoint = try localSurface.point(
            u: expectedSurfaceU,
            v: expectedSurfaceV,
            tolerance: tolerance
        )
        let translation = curveGeometry.position - localPoint
        let target = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: localControlPoints.map { row in
                row.map { $0 + translation }
            },
            weights: weights
        ))
        let curveRange = try ScalarInterval(
            lower: expectedCurveParameter - 0.001,
            upper: expectedCurveParameter + 0.001
        )
        let uRange = try ScalarInterval(
            lower: expectedSurfaceU - 0.02,
            upper: expectedSurfaceU + 0.02
        )
        let vRange = try ScalarInterval(
            lower: expectedSurfaceV - 0.02,
            upper: expectedSurfaceV + 0.02
        )

        let intersections = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: target,
                options: .init(
                    curveRange: curveRange,
                    surfaceURange: uRange,
                    surfaceVRange: vRange,
                    maximumSubdivisionDepth: 24
                ),
                tolerance: tolerance
            )

        let intersection = try #require(intersections.min {
            ($0.point - curveGeometry.position).length
                < ($1.point - curveGeometry.position).length
        })
        #expect(
            (intersection.point - curveGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(intersection.curveParameter - expectedCurveParameter)
                <= tolerance.relative * 64.0
        )
        #expect(
            abs(intersection.surfaceU - expectedSurfaceU)
                <= tolerance.relative * 64.0
        )
        #expect(
            abs(intersection.surfaceV - expectedSurfaceV)
                <= tolerance.relative * 64.0
        )
        #expect(intersection.kind == .transverse)
        #expect(intersection.residual <= tolerance.distance)
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
