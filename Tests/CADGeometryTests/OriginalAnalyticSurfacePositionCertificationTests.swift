import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Original analytic Rebuild position certification", .timeLimit(.minutes(2)))
struct OriginalAnalyticSurfacePositionCertificationTests {
    private let certifier: any GeometryAnalyticSurfacePositionCertifying = CertifiedAnalyticSurfacePositionCertifier()

    @Test(arguments: [false, true])
    func independentlyAuthoredPlaneRetainsOriginalAsymmetricNativeChart(analytic: Bool) throws {
        let source = planeSource(analytic: analytic)
        let candidate = planeCandidate(analytic: analytic, u: (-2, 3), v: (-0.25, 0.5), height: 2e-9)
        let box = try rectangle(u: (-2, 3), v: (-0.25, 0.5))
        let retainedSource = source, retainedCandidate = candidate
        let literal = analytic ? Point3D(x: -0.125, y: 0.75, z: 2e-9) : Point3D(x: 0.75, y: 0.125, z: 2e-9)
        #expect(try (candidate.point(u: 0.75, v: 0.125, tolerance: .standard) - literal).length < 1e-13)
        let proof = try certify(source, candidate, box, distance: 1e-7)
        #expect(proof.coveredParameters == box && proof.positionErrorUpperBound >= 2e-9)
        #expect(proof.positionErrorUpperBound <= 1e-7 && proof.certifiedBoxCount == 1)
        #expect(candidate.uDegree == 1 && candidate.vDegree == 1 && candidate.controlPoints.count == 2)
        #expect(source == retainedSource && candidate == retainedCandidate)
    }

    @Test(arguments: [false, true])
    func cylindricalTaylorCandidateUsesOriginalAngularChartIncludingNegativeCycles(analytic: Bool) throws {
        let center = -2 * Double.pi
        let box = try rectangle(u: (center - 0.05, center + 0.05), v: (-0.03, 0.05))
        let source = cylinderSource(analytic: analytic)
        let candidate = cylinderTaylor(analytic: analytic, center: center)
        let retained = candidate
        // Literal third-order Taylor remainder: radius * |u-center|^4 / 4!.
        let analyticalRemainder = 0.01 * pow(0.05, 4) / 24
        #expect(analyticalRemainder < 3e-9)
        for u in [box.u.lower, center - 0.0125, center + 0.025, box.u.upper] {
            let literal = analytic ? Point3D(x: -0.01 * sin(u), y: 0.01 * cos(u), z: 0.0125)
                : Point3D(x: 0.01 * cos(u), y: 0.01 * sin(u), z: 0.0125)
            #expect(try (candidate.point(u: u, v: 0.0125, tolerance: .standard) - literal).length <= analyticalRemainder + 1e-13)
        }
        let proof = try certify(source, candidate, box, distance: 1e-8)
        #expect(proof.coveredParameters == box && proof.positionErrorUpperBound <= 1e-8)
        #expect(proof.certifiedBoxCount > 0 && candidate == retained)
        #expect(candidate.uKnots.first == box.u.lower && candidate.uKnots.last == box.u.upper)
        #expect(proof.scalarCount <= NativeSurfacePositionCertificationLimits.standard.maximumScalarCount)
        #expect(proof.workUnits <= NativeSurfacePositionCertificationLimits.standard.maximumWorkUnits)
    }

    @Test(arguments: [false, true])
    func originalFourthULawCertifiesAnIndependentCubicInOneNativeCell(analytic: Bool) throws {
        let center = -2 * Double.pi
        let candidate = cylinderTaylor(analytic: analytic, center: center)
        let box = try rectangle(u: (center - 0.05, center + 0.05), v: (-0.03, 0.05))
        let literalFourthRemainder = 0.01 * pow(0.05, 4) / 24
        #expect(literalFourthRemainder < 3e-9)
        let proof = try certify(cylinderSource(analytic: analytic), candidate, box, distance: 3e-9)
        #expect(proof.coveredParameters == box && proof.certifiedBoxCount == 1)
        #expect(proof.positionErrorUpperBound >= literalFourthRemainder)
        #expect(proof.positionErrorUpperBound <= 3e-9)
        print("G6_ANALYTIC_CUBIC_USAGE analytic=\(analytic) scalars=\(proof.scalarCount) work=\(proof.workUnits) boxes=\(proof.certifiedBoxCount) bound=\(proof.positionErrorUpperBound)")
    }

    @Test
    func refinedCubicRetainsOriginalWholeBoundsUnderExactCumulativeCeilings() throws {
        let source = cylinderSource(analytic: false), box = try rectangle(u: (-0.05, 0.05), v: (-0.03, 0.05))
        var candidate = cylinderTaylor(analytic: false, center: 0)
        let shift = 0.01 * pow(0.05, 4) / 48
        for j in candidate.controlPoints.indices { for i in candidate.controlPoints[j].indices {
            candidate.controlPoints[j][i].x += shift
        } }
        let retained = candidate
        // Independent cos fourth/sin fifth remainders bound this shifted cubic.
        let literalError = hypot(shift, 0.01 * pow(0.05, 5) / 120)
        #expect(literalError < 1.31e-9)
        for u in [-0.05, -0.0375, -0.025, 0, 0.025, 0.0375, 0.05] {
            let literal = Point3D(x: 0.01 * cos(u), y: 0.01 * sin(u), z: 0.0125)
            #expect(try (candidate.point(u: u, v: 0.0125, tolerance: .standard) - literal).length <= literalError + 1e-14)
        }
        let proof = try certify(source, candidate, box, distance: 2e-9)
        #expect(proof.certifiedBoxCount > 1 && proof.coveredParameters == box)
        #expect(proof.positionErrorUpperBound <= 2e-9)
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits)
        #expect(try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 2e-9, limits: exact, tolerance: .standard) == proof)
        for limits in [NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount - 1,
                            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits),
                       NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
                            maximumScalarCount: proof.scalarCount - 1, maximumWorkUnits: proof.workUnits),
                       NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
                            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits - 1)] {
            do {
                _ = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                    maximumPositionError: 2e-9, limits: limits, tolerance: .standard)
                Issue.record("Retained whole bounds spent beyond the exact cumulative caller ceiling.")
            } catch let error as GeometryConversionError {
                guard case .resourceLimitExceeded = error else { throw error }
            }
        }
        #expect(candidate == retained && source == cylinderSource(analytic: false))
        print("G6_ANALYTIC_RETAINED_USAGE scalars=\(proof.scalarCount) work=\(proof.workUnits) boxes=\(proof.certifiedBoxCount) bound=\(proof.positionErrorUpperBound)")
    }

    @Test
    func varyingWeightCubicCannotBorrowTheZeroFourthDerivativeOfAPolynomial() throws {
        let weights = [0.1, 0.4, 0.7, 1.0]
        let xNumerators = [0.0, 0.1 / 3, 0.1 * 2 / 3 + 0.9 / 3, 1.0]
        let zNumerators = [-0.001 / 8, 0.001 / 8, -0.001 / 8, 0.001 / 8]
        let candidate = BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1.0].map { v in (0..<4).map { i in
                Point3D(x: xNumerators[i] / weights[i], y: v, z: zNumerators[i] / weights[i])
            } }, weights: [weights, weights])
        let retained = candidate
        // Independent law: z=.001*(u-.5)^3/(.1+.9*u), x=u, y=v.
        #expect(try abs(candidate.point(u: 0.5, v: 0.5, tolerance: .standard).z) < 1e-15)
        #expect(try abs(candidate.point(u: 0, v: 0.5, tolerance: .standard).z + 0.00125) < 1e-15)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try certify(planeSource(), candidate, rectangle(), distance: 0.0003)
        }
        #expect(candidate == retained)
    }

    @Test
    func identicalLocusOnADifferentChartCannotAuthorizeNativeParameterCorrespondence() throws {
        let source = cylinderSource(analytic: false)
        let center = -2 * Double.pi
        var candidate = cylinderTaylor(analytic: false, center: center)
        // Same cylindrical locus approximation but a quarter turn of the original U law.
        for j in candidate.controlPoints.indices {
            for i in candidate.controlPoints[j].indices {
                let p = candidate.controlPoints[j][i]
                candidate.controlPoints[j][i] = Point3D(x: -p.y, y: p.x, z: p.z)
            }
        }
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try certify(source, candidate, rectangle(u: (center - 0.05, center + 0.05), v: (-0.03, 0.05)), distance: 1e-8)
        }
    }

    @Test
    func cornerAliasCannotHideTheIndependentlyKnownInteriorBump() throws {
        var candidate = planeCandidate(degree: 3)
        candidate.controlPoints[1][1].z = 0.001
        for u in [0.0, 1.0] { for v in [0.0, 1.0] {
            #expect(try candidate.point(u: u, v: v, tolerance: .standard).z == 0)
        } }
        // B_1^3(1/2)^2 * .001 = (3/8)^2 * .001.
        let literalPeak = 0.001 * 9 / 64
        #expect(try abs(candidate.point(u: 0.5, v: 0.5, tolerance: .standard).z - literalPeak) < 1e-15)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try certify(planeSource(), candidate, rectangle(), distance: 1e-7)
        }
    }

    @Test
    func c0CandidatePiecesRetainEachOriginalNativeSide() throws {
        let candidate = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 0.5, y: 0, z: 2e-9), .init(x: 1, y: 0, z: 0)],
                            [.init(x: 0, y: 1, z: 0), .init(x: 0.5, y: 1, z: 2e-9), .init(x: 1, y: 1, z: 0)]])
        let proof = try certify(planeSource(), candidate, rectangle(), distance: 1e-7)
        #expect(proof.certifiedBoxCount == 2 && proof.positionErrorUpperBound >= 2e-9)
        #expect(proof.positionErrorUpperBound <= 1e-7)
    }

    @Test
    func exactChargedScalarWorkAndCellLimitsAreEnforced() throws {
        let source = planeSource(), box = try rectangle()
        let candidate = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.init(x: 0, y: 0, z: 1e-9), .init(x: 0.5, y: 0, z: 1e-9), .init(x: 1, y: 0, z: 1e-9)],
                            [.init(x: 0, y: 1, z: 1e-9), .init(x: 0.5, y: 1, z: 1e-9), .init(x: 1, y: 1, z: 1e-9)]])
        let retained = candidate
        let proof = try certify(source, candidate, box, distance: 1e-7)
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits)
        #expect(try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-7, limits: exact, tolerance: .standard) == proof)
        for limits in [NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount - 1,
                            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits),
                       NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
                            maximumScalarCount: proof.scalarCount - 1, maximumWorkUnits: proof.workUnits),
                       NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
                            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits - 1)] {
            do {
                _ = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                    maximumPositionError: 1e-7, limits: limits, tolerance: .standard)
                Issue.record("Analytic proof spent beyond its exact cumulative ceiling.")
            } catch let error as GeometryConversionError {
                guard case .resourceLimitExceeded = error else { throw error }
            }
        }
        #expect(source == planeSource() && candidate == retained)
    }

    @Test
    func unsupportedMalformedAndStrictChartOvershootFailuresRemainTyped() throws {
        let candidate = planeCandidate()
        do {
            _ = try certify(.analytic(.sphere(center: .origin, radius: 0.01)), candidate, rectangle(), distance: 1e-7)
            Issue.record("An unsupported analytic source was published.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        var invalid = candidate
        invalid.weights[0][0] = 0
        #expect(throws: GeometryError.invalidDistance(0)) {
            _ = try certify(planeSource(), invalid, rectangle(), distance: 1e-7)
        }
        for box in [try rectangle(u: (-Double.leastNonzeroMagnitude, 1)), try rectangle(v: (0, 1.0.nextUp))] {
            do {
                _ = try certify(planeSource(), candidate, box, distance: 1e-7)
                Issue.record("The candidate's exact original native chart was exceeded.")
            } catch let error as KernelError {
                #expect(error.code == .invalidInput)
            }
        }
    }

    @Test
    func cancelledTaskCannotPrepareOrPublishAnalyticPositionEvidence() async throws {
        let source = planeSource(), candidate = planeCandidate(), box = try rectangle()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        }
        do { _ = try await task.value; Issue.record("Cancelled original analytic position evidence was published.") }
        catch is CancellationError {}
    }

    private func certify(_ source: Surface3D, _ candidate: BSplineSurface3D,
        _ box: SurfaceParameterBox, distance: Double) throws -> NativeSurfacePositionCertificate {
        try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: distance, limits: .standard, tolerance: .standard)
    }

    private func rectangle(u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1), v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func planeSource(analytic: Bool = false) -> Surface3D {
        analytic ? .analytic(.plane(origin: .origin, normal: .unitZ)) : .plane(Plane3D(origin: .origin, normal: .unitZ))
    }

    private func planeCandidate(analytic: Bool = false, degree: Int = 1,
        u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1), height: Double = 0) -> BSplineSurface3D {
        let xs = (0...degree).map { u.0 + (u.1 - u.0) * Double($0) / Double(degree) }
        let ys = (0...degree).map { v.0 + (v.1 - v.0) * Double($0) / Double(degree) }
        return BSplineSurface3D(uDegree: degree, vDegree: degree,
            uKnots: Array(repeating: u.0, count: degree + 1) + Array(repeating: u.1, count: degree + 1),
            vKnots: Array(repeating: v.0, count: degree + 1) + Array(repeating: v.1, count: degree + 1),
            controlPoints: ys.map { y in xs.map { x in analytic ? Point3D(x: -y, y: x, z: height) : Point3D(x: x, y: y, z: height) } })
    }

    private func cylinderSource(analytic: Bool) -> Surface3D {
        analytic ? .analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 0.01))
            : .cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 0.01))
    }

    private func cylinderTaylor(analytic: Bool, center: Double) -> BSplineSurface3D {
        let lower = center - 0.05, upper = center + 0.05, width = upper - lower
        let c = cos(center), s = sin(center)
        func radial(_ u: Double) -> Vector3D {
            let d = u - center
            let x = 0.01 * (c - s * d - c * d * d / 2 + s * d * d * d / 6)
            let y = 0.01 * (s + c * d - s * d * d / 2 - c * d * d * d / 6)
            return analytic ? Vector3D(x: -y, y: x, z: 0) : Vector3D(x: x, y: y, z: 0)
        }
        func derivative(_ u: Double) -> Vector3D {
            let d = u - center
            let x = 0.01 * (-s - c * d + s * d * d / 2)
            let y = 0.01 * (c - s * d - c * d * d / 2)
            return analytic ? Vector3D(x: -y, y: x, z: 0) : Vector3D(x: x, y: y, z: 0)
        }
        let controls = [radial(lower), radial(lower) + derivative(lower) * (width / 3),
                        radial(upper) - derivative(upper) * (width / 3), radial(upper)]
        return BSplineSurface3D(uDegree: 3, vDegree: 1, uKnots: [lower, lower, lower, lower, upper, upper, upper, upper],
            vKnots: [-0.03, -0.03, 0.05, 0.05], controlPoints: [-0.03, 0.05].map { v in
                controls.map { Point3D(x: $0.x, y: $0.y, z: v) }
            })
    }
}
