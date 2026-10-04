import CADCore
import CADGeometry
import Testing

@Suite("Finite original polynomial continuation", .timeLimit(.minutes(2)))
struct MultiSpanPolynomialSurfaceContinuationPositionCertificationTests {
    private let certifier: any GeometryPolynomialSurfaceContinuationPositionCertifying = CertifiedPolynomialSurfaceContinuationPositionCertifier()
    private let distance = 1e-7

    @Test(arguments: [false, true])
    func independentPiecewiseLawCoversEveryEndAndCorner(asymmetric: Bool) throws {
        let fixture = try tensors(asymmetric: asymmetric)
        // Original analytic laws are authored directly, without natural extension,
        // refinement, fitting or production degree elevation as the oracle producer.
        #expect(fixture.source.controlPoints[0][1].z == 0.03125)
        let proof = try certify(fixture.source, fixture.candidate, fixture.box)
        #expect(proof.coveredParameters == fixture.box)
        #expect(proof.positionErrorUpperBound <= distance)
        #expect(proof.certifiedBoxCount == 8)
        #expect(proof.scalarCount < NativeSurfacePositionCertificationLimits.standard.maximumScalarCount)
        #expect(fixture.source == fixture.sourceSnapshot && fixture.candidate == fixture.candidateSnapshot)
    }

    @Test
    func differentOriginalDegreesAndSingleSourceMultipleCandidateCompose() throws {
        let scale = 0.03125
        // For u-u², quadratic B-spline coefficients are Greville(u)
        // minus the product of the two inner original knots: [0,.25,.25,0].
        let source = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 0.5, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1].map { v in
                zip([0.0, 0.25, 0.75, 1], [0.0, 0.25, 0.25, 0]).map { u, z in
                    Point3D(x: u, y: v, z: scale * z)
                }
            })
        // Independently expanded cubic Bernstein coefficients of u-u²
        // on [-.25,1.25] are [-.3125,.4375,.4375,-.3125].
        let candidate = BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: [-0.25, -0.25, -0.25, -0.25, 1.25, 1.25, 1.25, 1.25],
            vKnots: [0, 0, 1, 1], controlPoints: [0.0, 1].map { v in
                zip([-0.25, 0.25, 0.75, 1.25], [-0.3125, 0.4375, 0.4375, -0.3125]).map { u, z in
                    Point3D(x: u, y: v, z: scale * z)
                }
            })
        let request = try box(u: (-0.25, 1.25), v: (0, 1))
        let proof = try certify(source, candidate, request)
        #expect(proof.certifiedBoxCount == 2 && proof.positionErrorUpperBound <= distance)

        let plane = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let multiple = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [-0.25, -0.25, 0.5, 1.25, 1.25], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1].map { v in [-0.25, 0.5, 1.25].map { u in
                Point3D(x: u, y: v, z: 0)
            } })
        let prepared = try prepare(plane, request)
        let composed = try certifier.certifyContinuationPosition(preparedRequest: prepared, candidate: multiple)
        #expect(composed == (try certify(plane, multiple, request)))
        #expect(composed.certifiedBoxCount == 2 && composed.positionErrorUpperBound <= distance)
    }

    @Test
    func wrongOuterPolynomialAndInteriorExcessAreDefiniteRefusals() throws {
        let fixture = try tensors()
        var wrong = fixture.candidate
        for row in wrong.controlPoints.indices {
            for column in wrong.controlPoints[row].indices {
                let u = wrong.controlPoints[row][column].x
                let v = wrong.controlPoints[row][column].y
                wrong.controlPoints[row][column].z = 0.0625 * u + g(v)
            }
        }
        try expectExcess(fixture.source, wrong, fixture.box)
        var bump = fixture.candidate
        bump.controlPoints[1][2].z += 0.001
        // The literal knot control is an actual piecewise-linear value at (.5,.5).
        #expect(bump.controlPoints[1][2].z - fixture.candidate.controlPoints[1][2].z > 0.0009)
        try expectExcess(fixture.source, bump, fixture.box)
    }

    @Test
    func receiptKeepsTheOriginalAndPaidPrefixAcrossReuse() throws {
        let fixture = try tensors()
        var source = fixture.source
        let request = try prepare(source, fixture.box)
        source.controlPoints[0][0].z += 1
        source.uKnots[2] = 0.25
        #expect(request.source == fixture.sourceSnapshot && request.source != source)
        let a = try certifier.certifyContinuationPosition(preparedRequest: request, candidate: fixture.candidate)
        let b = try certify(fixture.source, fixture.candidate, fixture.box)
        #expect(a == b)
        #expect(try certifier.certifyContinuationPosition(preparedRequest: request, candidate: fixture.candidate) == a)
        let noPrefix = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: a.certifiedBoxCount,
            maximumScalarCount: a.scalarCount, maximumWorkUnits: a.workUnits - request.admittedWorkUnits)
        let bounded = try prepare(fixture.source, fixture.box, limits: noPrefix)
        do {
            _ = try certifier.certifyContinuationPosition(preparedRequest: bounded, candidate: fixture.candidate)
            Issue.record("A reset source admission prefix published evidence.")
        } catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else {
                Issue.record("A missing paid prefix changed the typed failure: \(error).")
                return
            }
        }
    }

    @Test
    func actualEachAllowanceBoundaryIsRetained() throws {
        let fixture = try tensors()
        let proof = try certify(fixture.source, fixture.candidate, fixture.box)
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits)
        #expect(try certify(fixture.source, fixture.candidate, fixture.box, limits: exact) == proof)
        for limits in [
            NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount - 1,
                maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits),
            NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
                maximumScalarCount: proof.scalarCount - 1, maximumWorkUnits: proof.workUnits),
            NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
                maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits - 1)
        ] {
            do {
                _ = try certify(fixture.source, fixture.candidate, fixture.box, limits: limits)
                Issue.record("An operation below its actual cumulative usage published evidence.")
            } catch let error as GeometryConversionError {
                guard case .resourceLimitExceeded = error else {
                    Issue.record("Wrong resource failure: \(error).")
                    return
                }
            }
        }
    }

    @Test
    func unsupportedWeightsAndStrictCandidateSupportStayDistinct() throws {
        let fixture = try tensors()
        var rational = fixture.source
        rational.weights[0][1] = 2
        do {
            _ = try prepare(rational, fixture.box)
            Issue.record("Varying original weights produced a fitting receipt.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        var periodic = fixture.source
        periodic.isUPeriodic = true
        do {
            _ = try prepare(periodic, fixture.box)
            Issue.record("Periodic source produced a continuation receipt.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        let outside = try box(u: (-0.25, Double(1.25).nextUp), v: (-0.25, 1.25))
        do {
            _ = try certify(fixture.source, fixture.candidate, outside)
            Issue.record("Candidate support was clipped or accepted outside its exact domain.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
    }

    @Test
    func cancellationAfterPaidPreparationCannotPublish() async throws {
        let fixture = try tensors()
        let request = try prepare(fixture.source, fixture.box)
        let task = Task { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try certifier.certifyContinuationPosition(preparedRequest: request, candidate: fixture.candidate)
                return false
            } catch is CancellationError { return true }
        }
        #expect(try await task.value)
        #expect(request.source == fixture.sourceSnapshot)
    }

    private func prepare(_ source: BSplineSurface3D, _ box: SurfaceParameterBox,
        limits: NativeSurfacePositionCertificationLimits = .standard) throws -> PreparedPolynomialSurfaceContinuationPositionRequest {
        try certifier.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: distance, limits: limits, tolerance: .standard)
    }

    private func certify(_ source: BSplineSurface3D, _ candidate: BSplineSurface3D, _ box: SurfaceParameterBox,
        limits: NativeSurfacePositionCertificationLimits = .standard) throws -> NativeSurfacePositionCertificate {
        try certifier.certifyContinuationPosition(source: source, candidate: candidate,
            over: box, maximumPositionError: distance, limits: limits, tolerance: .standard)
    }

    private func expectExcess(_ source: BSplineSurface3D, _ candidate: BSplineSurface3D,
        _ box: SurfaceParameterBox) throws {
        do {
            _ = try certify(source, candidate, box)
            Issue.record("A wrong continuation polynomial published a whole-law certificate.")
        } catch let error as GeometryConversionError { #expect(error == .toleranceRejected) }
    }

    private func f(_ u: Double) -> Double { u <= 0.5 ? 0.0625 * u : 0.0625 * (1 - u) }
    private func g(_ v: Double) -> Double { v <= 0.5 ? -0.03125 * v : 0.03125 * (v - 1) }

    private func tensors(asymmetric: Bool = false) throws -> (source: BSplineSurface3D,
        candidate: BSplineSurface3D, box: SurfaceParameterBox,
        sourceSnapshot: BSplineSurface3D, candidateSnapshot: BSplineSurface3D) {
        let us = [0.0, 0.5, 1], vs = [0.0, 0.5, 1]
        let targetUs = [-0.25, 0.25, 0.5, 0.75, 1.25], targetVs = [-0.25, 0.5, 1.25]
        func nativeU(_ u: Double) -> Double { asymmetric ? 2 + 4 * u : u }
        func nativeV(_ v: Double) -> Double { asymmetric ? -3 + 4 * v : v }
        func tensor(_ u: [Double], _ v: [Double], weight: Double) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [nativeU(u[0])] + u.map(nativeU) + [nativeU(u[u.count - 1])],
                vKnots: [nativeV(v[0])] + v.map(nativeV) + [nativeV(v[v.count - 1])],
                controlPoints: v.map { b in u.map { a in
                    Point3D(x: nativeU(a), y: nativeV(b), z: f(a) + g(b))
                } }, weights: v.map { _ in u.map { _ in weight } })
        }
        let source = tensor(us, vs, weight: asymmetric ? 7 : 1)
        let target = tensor(targetUs, targetVs, weight: asymmetric ? 3 : 1)
        let request = try box(u: (nativeU(-0.25), nativeU(1.25)), v: (nativeV(-0.25), nativeV(1.25)))
        return (source, target, request, source, target)
    }

    private func box(u: (Double, Double), v: (Double, Double)) throws -> SurfaceParameterBox {
        try SurfaceParameterBox(u: ScalarInterval(lower: u.0, upper: u.1),
            v: ScalarInterval(lower: v.0, upper: v.1))
    }
}
