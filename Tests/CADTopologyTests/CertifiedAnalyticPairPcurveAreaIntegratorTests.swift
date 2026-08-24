import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing

@Suite("Certified analytic-pair pcurve area integration")
struct CertifiedAnalyticPairPcurveAreaIntegratorTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func boundedPlaneTorusComponentBoundsPlaneRole() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let planeCurve = try certifiedCurve(truth.firstSurfaceParameterCurve)
        let integrator = SurfaceParameterCurveAreaIntegrator()

        let planeBounds = try integrator.bounds(
            for: .certifiedAnalyticPair(planeCurve),
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let planeReference = try midpointReference(planeCurve, intervalCount: 8_192)

        #expect(planeBounds.lower <= planeReference)
        #expect(planeBounds.upper >= planeReference)
        #expect(planeBounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedPlaneTorusComponentBoundsTorusRoleAcrossSeam() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let torusCurve = try certifiedCurve(truth.secondSurfaceParameterCurve)
        let torusBounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: .certifiedAnalyticPair(torusCurve),
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let torusReference = try midpointReference(torusCurve, intervalCount: 8_192)

        #expect(torusBounds.lower <= torusReference)
        #expect(torusBounds.upper >= torusReference)
        #expect(torusBounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func negativeInnerSupportNodalPlaneRoleHasCertifiedAreaBounds() throws {
        try verifyInnerSupportNodalAreaBounds(
            componentIndex: 0,
            role: .first
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func negativeInnerSupportNodalTorusRoleHasCertifiedAreaBounds() throws {
        try verifyInnerSupportNodalAreaBounds(
            componentIndex: 0,
            role: .second
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func positiveInnerSupportNodalPlaneRoleHasCertifiedAreaBounds() throws {
        try verifyInnerSupportNodalAreaBounds(
            componentIndex: 1,
            role: .first
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func positiveInnerSupportNodalTorusRoleHasCertifiedAreaBounds() throws {
        try verifyInnerSupportNodalAreaBounds(
            componentIndex: 1,
            role: .second
        )
    }

    private func verifyInnerSupportNodalAreaBounds(
        componentIndex: Int,
        role: SurfaceIntersectionSurfaceRole
    ) throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let truth = try analyticTruth(plane: plane, torus: torus)
        #expect(truth.count == 2)
        let result = truth[componentIndex]
        let curve = try certifiedCurve(
            role == .first
                ? result.firstSurfaceParameterCurve
                : result.secondSurfaceParameterCurve
        )
        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: .certifiedAnalyticPair(curve),
            uShift: 0.0,
            requestedWidth: 1.0e-5,
            tolerance: tolerance
        )
        let reference = try midpointReference(
            curve,
            intervalCount: 4_096
        )
        #expect(bounds.lower <= reference)
        #expect(bounds.upper >= reference)
        #expect(bounds.width <= 1.0e-5)
    }

    @Test(.timeLimit(.minutes(1)))
    func innerSupportNodalTorusEnclosuresRetainGeometryUniversalCoverSheet() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let result = try #require(analyticTruth(plane: plane, torus: torus).last)
        let curve = try certifiedCurve(result.secondSurfaceParameterCurve)
        let declaredStart = try curve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        #expect(declaredStart.u < 0.0)

        let enclosures = try CertifiedAnalyticPairPcurveAreaIntegrator()
            .parameterEnclosures(
                for: curve,
                maximumWidth: 0.05,
                tolerance: tolerance
            )
        #expect(enclosures.isEmpty == false)
        #expect(abs(enclosures[0].lowerFraction) <= tolerance.relative)
        #expect(abs(enclosures[enclosures.count - 1].upperFraction - 1.0)
            <= tolerance.relative)
        #expect(enclosures[0].u.lower <= declaredStart.u)
        #expect(enclosures[0].u.upper >= declaredStart.u)
        for enclosure in enclosures {
            let midpoint = enclosure.lowerFraction
                + (enclosure.upperFraction - enclosure.lowerFraction) * 0.5
            let parameter = try curve.parameter(
                atNormalizedFraction: midpoint,
                tolerance: tolerance
            )
            #expect(enclosure.u.lower <= parameter.u)
            #expect(enclosure.u.upper >= parameter.u)
            #expect(enclosure.v.lower <= parameter.v)
            #expect(enclosure.v.upper >= parameter.v)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func sphereCylinderBothRolesHaveCertifiedAreaAndFluxBounds() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )
        let exact = try #require(intersections.compactMap {
            intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .sphereCylinder = exact.definition else {
                return nil
            }
            return exact
        }.first)

        for role in [SurfaceIntersectionSurfaceRole.first, .second] {
            let curve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: role,
                startFraction: 0.17,
                endFraction: 0.37,
                tolerance: tolerance
            )
            let requestedWidth = 1.0e-4
            let area = try SurfaceParameterCurveAreaIntegrator().bounds(
                for: .certifiedAnalyticPair(curve),
                uShift: 0.0,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
            let areaReference = try midpointReference(
                curve,
                intervalCount: 16_384
            )
            #expect(area.lower <= areaReference)
            #expect(area.upper >= areaReference)
            #expect(area.width <= requestedWidth)

            let integrand = try #require(
                try TrimmedAnalyticSurfaceVolumeEvaluator.Integrand(
                    surface: exact.surface(for: role),
                    reference: .origin,
                    tolerance: tolerance
                )
            )
            let flux = try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
                for: curve,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
            let fluxReference = try midpointFluxReference(
                curve,
                integrand: integrand,
                intervalCount: 16_384
            )
            #expect(flux.lower <= fluxReference)
            #expect(flux.upper >= fluxReference)
            #expect(flux.width <= requestedWidth)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func sphereCylinderGenericLongitudeSeamHasCertifiedAreaAndFluxBounds() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )
        let exact = try #require(intersections.compactMap {
            intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .sphereCylinder = exact.definition else {
                return nil
            }
            return exact
        }.first)
        let curve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            startFraction: 0.07,
            endFraction: 0.83,
            tolerance: tolerance
        )
        let seam = try #require(try longitudeSeamFraction(in: curve))
        let requestedWidth = 1.0e-4

        let area = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: .certifiedAnalyticPair(curve),
            uShift: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let areaReference = try midpointReference(
            curve,
            from: 0.0,
            to: seam,
            intervalCount: 16_384
        ) + midpointReference(
            curve,
            from: seam,
            to: 1.0,
            intervalCount: 16_384
        )
        #expect(area.lower <= areaReference)
        #expect(area.upper >= areaReference)
        #expect(area.width <= requestedWidth)

        let integrand = try #require(
            try TrimmedAnalyticSurfaceVolumeEvaluator.Integrand(
                surface: sphere,
                reference: .origin,
                tolerance: tolerance
            )
        )
        let flux = try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
            for: curve,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let fluxReference = try midpointFluxReference(
            curve,
            integrand: integrand,
            from: 0.0,
            to: seam,
            intervalCount: 16_384
        ) + midpointFluxReference(
            curve,
            integrand: integrand,
            from: seam,
            to: 1.0,
            intervalCount: 16_384
        )
        #expect(flux.lower <= fluxReference)
        #expect(flux.upper >= fluxReference)
        #expect(flux.width <= requestedWidth)
    }

    @Test(.timeLimit(.minutes(1)))
    func orthogonalCylinderCylinderBothRolesHaveCertifiedFluxBounds() throws {
        let first = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let second = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitX,
            radius: 3.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let exact = try #require(intersections.compactMap {
            intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .cylinderCylinder = exact.definition else {
                return nil
            }
            return exact
        }.first)

        for role in [SurfaceIntersectionSurfaceRole.first, .second] {
            let curve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: role,
                tolerance: tolerance
            )
            let integrand = try #require(
                try TrimmedAnalyticSurfaceVolumeEvaluator.Integrand(
                    surface: exact.surface(for: role),
                    reference: .origin,
                    tolerance: tolerance
                )
            )
            let requestedWidth = 1.0e-5
            let flux = try CertifiedAnalyticPairPcurveAreaIntegrator(
                maximumSubdivisionDepth: 32,
                maximumCellCount: 16_384
            ).fluxBounds(
                for: curve,
                integrand: integrand,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
            let reference = try continuousCylinderFluxReference(
                curve,
                integrand: integrand,
                intervalCount: 16_384
            )
            #expect(flux.lower <= reference)
            #expect(flux.upper >= reference)
            #expect(flux.width <= requestedWidth)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cylinderCylinderSeamEndingTrimRetainsDeclaredPeriodicSheet() throws {
        let first = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let second = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitX,
            radius: 3.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let exact = try #require(intersections.compactMap {
            intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .cylinderCylinder = exact.definition else {
                return nil
            }
            return exact
        }.first)
        let curve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            startFraction: 0.75,
            endFraction: 1.0,
            tolerance: tolerance
        )
        let integrand = try #require(
            try TrimmedAnalyticSurfaceVolumeEvaluator.Integrand(
                surface: first,
                reference: Point3D(x: 0.25, y: -0.5, z: 0.75),
                tolerance: tolerance
            )
        )
        let requestedWidth = 1.0e-5
        let flux = try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
            for: curve,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let fluxReference = try continuousCylinderFluxReference(
            curve,
            integrand: integrand,
            intervalCount: 32_768
        )
        let area = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: .certifiedAnalyticPair(curve),
            uShift: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let areaReference = try continuousCylinderAreaReference(
            curve,
            intervalCount: 32_768
        )

        #expect(flux.lower <= fluxReference)
        #expect(flux.upper >= fluxReference)
        #expect(flux.width <= requestedWidth)
        #expect(area.lower <= areaReference)
        #expect(area.upper >= areaReference)
        #expect(area.width <= requestedWidth)
    }

    @Test(.timeLimit(.minutes(1)))
    func trimmedFullBranchBoundsAndReversalContainIndependentIntegral() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let source = try certifiedCurve(truth.secondSurfaceParameterCurve)
        let trimmed = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: source.intersection,
            role: source.role,
            startFraction: 0.13,
            endFraction: 0.72,
            tolerance: tolerance
        )
        let reversed = try trimmed.reversed(tolerance: tolerance)
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forwardBounds = try integrator.bounds(
            for: .certifiedAnalyticPair(trimmed),
            uShift: 2.0 * Double.pi,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let reversedBounds = try integrator.bounds(
            for: .certifiedAnalyticPair(reversed),
            uShift: 2.0 * Double.pi,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let reference = try midpointReference(
            trimmed,
            uShift: 2.0 * Double.pi,
            intervalCount: 8_192
        )

        #expect(forwardBounds.lower <= reference)
        #expect(forwardBounds.upper >= reference)
        #expect(forwardBounds.width <= 1.0e-6)
        #expect(reversedBounds.lower <= -reference)
        #expect(reversedBounds.upper >= -reference)
        #expect(reversedBounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func partialAndReversedCurveParametersMapToTheirStoredIntersectionInterval() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let source = try certifiedCurve(truth.secondSurfaceParameterCurve)
        let trimmed = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: source.intersection,
            role: source.role,
            startFraction: 0.13,
            endFraction: 0.72,
            tolerance: tolerance
        )
        let reversed = try trimmed.reversed(tolerance: tolerance)
        let domain = ParameterDomain.periodic(period: 2.0 * Double.pi)

        let forwardStart = try SurfaceParameterCurve.certifiedAnalyticPair(trimmed).parameter(
            atCurveParameter: 0.13 * 2.0 * Double.pi,
            curveDomain: domain,
            tolerance: tolerance
        )
        let forwardEnd = try SurfaceParameterCurve.certifiedAnalyticPair(trimmed).parameter(
            atCurveParameter: 0.72 * 2.0 * Double.pi,
            curveDomain: domain,
            tolerance: tolerance
        )
        let reversedStart = try SurfaceParameterCurve.certifiedAnalyticPair(reversed).parameter(
            atCurveParameter: 0.72 * 2.0 * Double.pi,
            curveDomain: domain,
            tolerance: tolerance
        )
        let reversedEnd = try SurfaceParameterCurve.certifiedAnalyticPair(reversed).parameter(
            atCurveParameter: 0.13 * 2.0 * Double.pi,
            curveDomain: domain,
            tolerance: tolerance
        )
        let expectedStart = try trimmed.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let expectedEnd = try trimmed.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        )

        #expect(forwardStart.isApproximatelyEqual(to: expectedStart, tolerance: tolerance.distance))
        #expect(forwardEnd.isApproximatelyEqual(to: expectedEnd, tolerance: tolerance.distance))
        #expect(reversedStart.isApproximatelyEqual(to: expectedEnd, tolerance: tolerance.distance))
        #expect(reversedEnd.isApproximatelyEqual(to: expectedStart, tolerance: tolerance.distance))
    }

    @Test(.timeLimit(.minutes(1)))
    func operandSwappedTrimPreservesBothRoleEnclosures() throws {
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
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: torus,
            second: plane,
            tolerance: tolerance
        )
        let result = try #require(intersections.compactMap { intersection -> SurfaceSurfaceIntersectionCurve? in
            guard case let .curve(curve) = intersection,
                  case .analyticAnalytic = curve.truth else {
                return nil
            }
            return curve
        }.first)
        let torusSource = try certifiedCurve(result.firstSurfaceParameterCurve)
        let planeSource = try certifiedCurve(result.secondSurfaceParameterCurve)
        let torusTrim = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: torusSource.intersection,
            role: torusSource.role,
            startFraction: 0.18,
            endFraction: 0.81,
            tolerance: tolerance
        )
        let planeTrim = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: planeSource.intersection,
            role: planeSource.role,
            startFraction: 0.18,
            endFraction: 0.81,
            tolerance: tolerance
        )
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let torusBounds = try integrator.bounds(
            for: .certifiedAnalyticPair(torusTrim),
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let planeBounds = try integrator.bounds(
            for: .certifiedAnalyticPair(planeTrim),
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let torusReference = try midpointReference(torusTrim, intervalCount: 8_192)
        let planeReference = try midpointReference(planeTrim, intervalCount: 8_192)

        #expect(torusBounds.lower <= torusReference)
        #expect(torusBounds.upper >= torusReference)
        #expect(torusBounds.width <= 1.0e-6)
        #expect(planeBounds.lower <= planeReference)
        #expect(planeBounds.upper >= planeReference)
        #expect(planeBounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedProofBudgetReturnsTypedResourceDiagnostic() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let source = try certifiedCurve(truth.secondSurfaceParameterCurve)
        let trimmed = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: source.intersection,
            role: source.role,
            startFraction: 0.13,
            endFraction: 0.72,
            tolerance: tolerance
        )

        do {
            _ = try CertifiedAnalyticPairPcurveAreaIntegrator(
                maximumSubdivisionDepth: 0,
                maximumCellCount: 1
            ).bounds(
                for: trimmed,
                uShift: 0.0,
                requestedWidth: 1.0e-12,
                tolerance: tolerance
            )
            Issue.record("An exhausted proof budget must not return a successful enclosure.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func torusRoleFluxBoundsContainIndependentBoundaryIntegral() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let source = try certifiedCurve(truth.secondSurfaceParameterCurve)
        let trimmed = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: source.intersection,
            role: source.role,
            startFraction: 0.13,
            endFraction: 0.72,
            tolerance: tolerance
        )
        let integrand = try #require(try TrimmedAnalyticSurfaceVolumeEvaluator.Integrand(
            surface: torus,
            reference: .origin,
            tolerance: tolerance
        ))
        let bounds = try CertifiedAnalyticPairPcurveAreaIntegrator().fluxBounds(
            for: trimmed,
            integrand: integrand,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        var reference = 0.0
        let intervalCount = 8_192
        for index in 0..<intervalCount {
            let fraction = (Double(index) + 0.5) / Double(intervalCount)
            let differential = try trimmed.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let primitiveBounds = integrand.greenPrimitive(
                u: .floating(differential.parameter.u),
                v: .floating(differential.parameter.v)
            )
            let primitive = primitiveBounds.lower
                + (primitiveBounds.upper - primitiveBounds.lower) * 0.5
            reference += primitive * differential.firstDerivative.y
        }
        reference /= Double(intervalCount)

        #expect(bounds.lower <= reference)
        #expect(bounds.upper >= reference)
        #expect(bounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicTranslationFluxUsesContinuousTorusMeridianEndpoints() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let planes = [Vector3D.unitX, -.unitX].map { normal in
            Surface3D.plane(Plane3D(
                origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
                normal: normal
            ))
        }
        let candidates = try planes.flatMap { plane in
            try DefaultSurfaceSurfaceIntersector().intersections(
                first: torus,
                second: plane,
                tolerance: tolerance
            ).compactMap { intersection -> SurfaceSurfaceIntersectionCurve? in
                guard case let .curve(curve) = intersection,
                      case .analyticAnalytic = curve.truth else {
                    return nil
                }
                return curve
            }
        }.map { truth in
            let source = try certifiedCurve(truth.firstSurfaceParameterCurve)
            return try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: source.intersection,
                role: source.role,
                startFraction: 0.25000000000000006,
                endFraction: 0.0,
                tolerance: tolerance
            )
        }
        let seamCrossing = try #require(try candidates.first { candidate in
            let start = try candidate.parameter(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let end = try candidate.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            return end.v - start.v > Double.pi
        })
        let rawStart = try seamCrossing.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let rawEnd = try seamCrossing.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        )
        #expect(rawEnd.v - rawStart.v > Double.pi)

        let uShift = 2.0 * Double.pi
        let translated = SurfaceParameterCurve.periodicTranslation(
            base: .certifiedAnalyticPair(seamCrossing),
            uShift: uShift,
            vShift: 0.0
        )
        let integrand = try #require(try TrimmedAnalyticSurfaceVolumeEvaluator.Integrand(
            surface: torus,
            reference: .origin,
            tolerance: tolerance
        ))
        let requestedWidth = 1.0e-6
        let bounds = try #require(try CertifiedAnalyticPcurveFluxIntegrator().bounds(
            for: translated,
            integrand: integrand,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        ))

        var reference = 0.0
        let intervalCount = 16_384
        for index in 0..<intervalCount {
            let fraction = (Double(index) + 0.5) / Double(intervalCount)
            let differential = try seamCrossing.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let primitiveBounds = integrand.greenPrimitive(
                u: .floating(differential.parameter.u + uShift),
                v: .floating(differential.parameter.v)
            )
            let primitive = primitiveBounds.lower
                + (primitiveBounds.upper - primitiveBounds.lower) * 0.5
            reference += primitive * differential.firstDerivative.y
        }
        reference /= Double(intervalCount)

        #expect(bounds.lower <= reference)
        #expect(bounds.upper >= reference)
        #expect(bounds.width <= requestedWidth)
    }

    @Test(.timeLimit(.minutes(1)))
    func bothAnalyticPairRolesProduceCompleteParameterEnclosures() throws {
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
        let truth = try #require(analyticTruth(plane: plane, torus: torus).first)
        let curves = [
            try certifiedCurve(truth.firstSurfaceParameterCurve),
            try certifiedCurve(truth.secondSurfaceParameterCurve),
        ]

        for curve in curves {
            let enclosures = try CertifiedSurfaceParameterCurveEncloser()
                .enclosures(
                    for: .certifiedAnalyticPair(curve),
                    maximumWidth: 0.05,
                    tolerance: tolerance
                )
            #expect(enclosures.isEmpty == false)
            #expect(enclosures.allSatisfy { $0.maximumWidth <= 0.05 })
            #expect(abs(enclosures[0].lowerFraction) <= 1.0e-12)
            #expect(abs(enclosures[enclosures.count - 1].upperFraction - 1.0)
                <= 1.0e-12)
            #expect(zip(enclosures, enclosures.dropFirst()).allSatisfy { pair in
                abs(pair.0.upperFraction - pair.1.lowerFraction) <= 1.0e-12
            })

            let partial = try CertifiedSurfaceParameterCurveEncloser()
                .enclosures(
                    for: .certifiedAnalyticPair(curve),
                    fromNormalizedFraction: 0.2,
                    toNormalizedFraction: 0.8,
                    maximumWidth: 0.05,
                    tolerance: tolerance
                )
            #expect(partial.isEmpty == false)
            #expect(partial.allSatisfy { $0.maximumWidth <= 0.05 })
            #expect(abs(partial[0].lowerFraction - 0.2) <= 1.0e-12)
            #expect(abs(partial[partial.count - 1].upperFraction - 0.8)
                <= 1.0e-12)
            #expect(zip(partial, partial.dropFirst()).allSatisfy { pair in
                abs(pair.0.upperFraction - pair.1.lowerFraction) <= 1.0e-12
            })
        }
    }

    private func analyticTruth(
        plane: Surface3D,
        torus: Surface3D
    ) throws -> [SurfaceSurfaceIntersectionCurve] {
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: plane,
            second: torus,
            tolerance: tolerance
        )
        let curves = intersections.compactMap { intersection -> SurfaceSurfaceIntersectionCurve? in
            guard case let .curve(curve) = intersection,
                  case .analyticAnalytic = curve.truth else {
                return nil
            }
            return curve
        }
        #expect(curves.isEmpty == false)
        return curves
    }

    private func certifiedCurve(
        _ curve: SurfaceParameterCurve
    ) throws -> CertifiedAnalyticPairSurfaceParameterCurve {
        guard case let .certifiedAnalyticPair(certified) = curve else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "The test fixture did not produce an analytic-pair pcurve."
            )
        }
        return certified
    }

    private func midpointReference(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        uShift: Double = 0.0,
        intervalCount: Int
    ) throws -> Double {
        try midpointReference(
            curve,
            uShift: uShift,
            from: 0.0,
            to: 1.0,
            intervalCount: intervalCount
        )
    }

    private func midpointReference(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        uShift: Double = 0.0,
        from lower: Double,
        to upper: Double,
        intervalCount: Int
    ) throws -> Double {
        var sum = 0.0
        let width = upper - lower
        for index in 0..<intervalCount {
            let fraction = lower + width
                * (Double(index) + 0.5) / Double(intervalCount)
            let differential = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            sum += (differential.parameter.u + uShift)
                * differential.firstDerivative.y
        }
        return sum * width / Double(intervalCount)
    }

    private func midpointFluxReference(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        intervalCount: Int
    ) throws -> Double {
        try midpointFluxReference(
            curve,
            integrand: integrand,
            from: 0.0,
            to: 1.0,
            intervalCount: intervalCount
        )
    }

    private func midpointFluxReference(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        from lower: Double,
        to upper: Double,
        intervalCount: Int
    ) throws -> Double {
        var sum = 0.0
        let width = upper - lower
        for index in 0..<intervalCount {
            let fraction = lower + width
                * (Double(index) + 0.5) / Double(intervalCount)
            let differential = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let primitiveBounds = integrand.greenPrimitive(
                u: .floating(differential.parameter.u),
                v: .floating(differential.parameter.v)
            )
            let primitive = primitiveBounds.lower
                + (primitiveBounds.upper - primitiveBounds.lower) * 0.5
            sum += primitive * differential.firstDerivative.y
        }
        return sum * width / Double(intervalCount)
    }

    private func continuousCylinderFluxReference(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
        intervalCount: Int
    ) throws -> Double {
        let period = 2.0 * Double.pi
        var previousU = try curve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        ).u
        var sum = 0.0
        for index in 0..<intervalCount {
            let fraction = (Double(index) + 0.5) / Double(intervalCount)
            let differential = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let canonicalU = differential.parameter.u
            let liftedU = canonicalU
                + round((previousU - canonicalU) / period) * period
            previousU = liftedU
            let primitiveBounds = integrand.greenPrimitive(
                u: .floating(liftedU),
                v: .floating(differential.parameter.v)
            )
            let primitive = primitiveBounds.lower
                + (primitiveBounds.upper - primitiveBounds.lower) * 0.5
            sum += primitive * differential.firstDerivative.y
        }
        return sum / Double(intervalCount)
    }

    private func continuousCylinderAreaReference(
        _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
        intervalCount: Int
    ) throws -> Double {
        let period = 2.0 * Double.pi
        var previousU = try curve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        ).u
        var sum = 0.0
        for index in 0..<intervalCount {
            let fraction = (Double(index) + 0.5) / Double(intervalCount)
            let differential = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let canonicalU = differential.parameter.u
            let liftedU = canonicalU
                + round((previousU - canonicalU) / period) * period
            previousU = liftedU
            sum += liftedU * differential.firstDerivative.y
        }
        return sum / Double(intervalCount)
    }

    private func longitudeSeamFraction(
        in curve: CertifiedAnalyticPairSurfaceParameterCurve
    ) throws -> Double? {
        let sampleCount = 4_096
        var lowerFraction = 0.0
        var lowerU = try curve.parameter(
            atNormalizedFraction: lowerFraction,
            tolerance: tolerance
        ).u
        var bracket: (lower: Double, upper: Double, lowerU: Double)?
        for index in 1...sampleCount {
            let upperFraction = Double(index) / Double(sampleCount)
            let upperU = try curve.parameter(
                atNormalizedFraction: upperFraction,
                tolerance: tolerance
            ).u
            if abs(upperU - lowerU) > Double.pi {
                bracket = (lowerFraction, upperFraction, lowerU)
                break
            }
            lowerFraction = upperFraction
            lowerU = upperU
        }
        guard var bracket else { return nil }
        for _ in 0..<80 {
            let middle = bracket.lower
                + (bracket.upper - bracket.lower) * 0.5
            let middleU = try curve.parameter(
                atNormalizedFraction: middle,
                tolerance: tolerance
            ).u
            if abs(middleU - bracket.lowerU) < Double.pi {
                bracket.lower = middle
                bracket.lowerU = middleU
            } else {
                bracket.upper = middle
            }
        }
        return bracket.lower + (bracket.upper - bracket.lower) * 0.5
    }
}
