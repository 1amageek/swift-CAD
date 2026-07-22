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
        var sum = 0.0
        for index in 0..<intervalCount {
            let fraction = (Double(index) + 0.5) / Double(intervalCount)
            let differential = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            sum += (differential.parameter.u + uShift)
                * differential.firstDerivative.y
        }
        return sum / Double(intervalCount)
    }
}
