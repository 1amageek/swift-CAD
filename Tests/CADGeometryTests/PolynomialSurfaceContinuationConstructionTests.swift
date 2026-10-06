import CADCore
import CADGeometry
import Testing

@Suite("Native-knot polynomial continuation construction", .timeLimit(.minutes(2)))
struct PolynomialSurfaceContinuationConstructionTests {
    private let distance = 1e-7
    private let proof: any GeometryPolynomialSurfaceContinuationPositionCertifying = CertifiedPolynomialSurfaceContinuationPositionCertifier()
    private let constructor: any GeometryPolynomialSurfaceContinuationConstructing = NativeKnotPolynomialSurfaceContinuationConstructor()

    @Test(arguments: [1.0, 7.0])
    func originalQuadraticC1LawBecomesBicubicWithoutUniformRefinement(weight: Double) throws {
        let source = quadratic(weight: weight)
        let box = try rectangle(u: (-0.25, 1.25), v: (-0.5, 1.5))
        let request = try prepare(source, box)
        let result = try construct(request)
        let candidate = result.surface
        #expect(candidate.uDegree == 3 && candidate.vDegree == 3)
        #expect(candidate.uKnots == [-0.25, -0.25, -0.25, -0.25, 0.5, 0.5, 1.25, 1.25, 1.25, 1.25])
        #expect(candidate.vKnots == [-0.5, -0.5, -0.5, -0.5, 1.5, 1.5, 1.5, 1.5])
        #expect(candidate.uControlPointCount == 6 && candidate.vControlPointCount == 4)
        #expect(result.certificate.coveredParameters == box)
        #expect(result.certificate.positionErrorUpperBound <= distance)
        #expect(result.certificate.certifiedBoxCount == 2)
        if weight == 1 {
            print("Native-knot continuation usage: scalarCount=\(result.certificate.scalarCount), workUnits=\(result.certificate.workUnits), certifiedBoxes=\(result.certificate.certifiedBoxCount).")
        }
        for u in [-0.25, 0, 0.5, 1, 1.25] {
            for v in [-0.5, 0, 0.37, 1, 1.5] {
                // Independently expanded original left/right polynomials. The original
                // C1 knot remains, including both exterior end-span laws.
                let x = u <= 0.5 ? (4 * u - 2 * u * u) / 3 : (1 + 2 * u * u) / 3
                let expected = Point3D(x: 0.02 * x, y: 0.02 * v, z: 0.02 * (4 * u - 4 * u * u) / 3)
                let actual = try candidate.point(u: u, v: v, tolerance: .standard)
                #expect((actual - expected).length <= distance)
            }
        }
        // The independent proof of the same stored candidate without authoring has
        // strictly lower cumulative usage: construction is part of the returned proof.
        let bareProof = try proof.certifyContinuationPosition(preparedRequest: request, candidate: candidate)
        #expect(result.certificate.scalarCount > bareProof.scalarCount)
        #expect(result.certificate.workUnits > bareProof.workUnits)
    }

    @Test
    func twoAxisC0PartitionsAndEveryExteriorCornerRetainTheirLaws() throws {
        let source = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 0.5, 1, 1],
            controlPoints: [0.0, 0.5, 1].enumerated().map { row, v in
                [0.0, 0.5, 1].enumerated().map { column, u in
                    Point3D(x: u, y: v, z: [0.0, 0.03125, 0][column] + [0.0, -0.015625, 0.015625][row])
                }
            })
        let box = try rectangle(u: (-0.25, 1.25), v: (-0.25, 1.25))
        let result = try construct(prepare(source, box))
        #expect(result.surface.uControlPointCount == 7 && result.surface.vControlPointCount == 7)
        #expect(result.surface.uKnots.filter { $0 == 0.5 }.count == 3)
        #expect(result.surface.vKnots.filter { $0 == 0.5 }.count == 3)
        #expect(result.certificate.certifiedBoxCount == 4)
        #expect(result.certificate.positionErrorUpperBound <= distance)
        for u in [-0.25, 0, 0.5, 1, 1.25] {
            for v in [-0.25, 0, 0.5, 1, 1.25] {
                let f = u <= 0.5 ? 0.0625 * u : 0.0625 * (1 - u)
                let g = v <= 0.5 ? -0.03125 * v : 0.0625 * v - 0.046875
                let expected = Point3D(x: u, y: v, z: f + g)
                #expect((try result.surface.point(u: u, v: v, tolerance: .standard) - expected).length <= distance)
            }
        }
    }

    @Test
    func asymmetricNativeChartAndSingleBezierComposeWithoutChangingTheSource() throws {
        let original = quadratic()
        let source = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [-2, -2, -2, 1, 4, 4, 4], vKnots: [3, 3, 5, 5],
            controlPoints: original.controlPoints.map { row in row.map { p in
                Point3D(x: 1024 + p.x, y: -512 + p.y, z: 256 + p.z)
            } })
        let box = try rectangle(u: (-3.5, 5.5), v: (2, 6))
        let request = try prepare(source, box)
        let result = try construct(request)
        #expect(result.surface.uKnots.first == -3.5 && result.surface.uKnots.last == 5.5)
        #expect(result.surface.uKnots.filter { $0 == 1 }.count == 2)
        for u in [-3.5, -2, 1, 4, 5.5] {
            for v in [2.0, 3, 4.17, 5, 6] {
                let t = (u + 2) / 6, w = (v - 3) / 2
                let x = t <= 0.5 ? (4 * t - 2 * t * t) / 3 : (1 + 2 * t * t) / 3
                let expected = Point3D(x: 1024 + 0.02 * x, y: -512 + 0.02 * w, z: 256 + 0.02 * (4 * t - 4 * t * t) / 3)
                #expect((try result.surface.point(u: u, v: v, tolerance: .standard) - expected).length <= distance)
            }
        }
        let arch = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1].map { v in [Point3D(x: 0, y: v, z: 0),
                Point3D(x: 0.5, y: v, z: 0.015625), Point3D(x: 1, y: v, z: 0)] })
        let single = try construct(prepare(arch, rectangle(u: (-0.25, 1.25), v: (0, 1))))
        #expect(single.surface.uControlPointCount == 4 && single.surface.vControlPointCount == 4)
        #expect(single.certificate.certifiedBoxCount == 1 && single.certificate.positionErrorUpperBound <= distance)
        #expect(request.source == source)
    }

    @Test
    func completeAuthoringAndProofHaveExactCumulativeAllowanceBoundaries() throws {
        let source = quadratic(), box = try rectangle(u: (-0.25, 1.25), v: (0, 1))
        let full = try construct(prepare(source, box))
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: full.certificate.certifiedBoxCount,
            maximumScalarCount: full.certificate.scalarCount, maximumWorkUnits: full.certificate.workUnits)
        #expect(try construct(prepare(source, box, limits: exact)).certificate == full.certificate)
        for limits in [NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: exact.maximumCertificationBoxes,
            maximumScalarCount: exact.maximumScalarCount - 1, maximumWorkUnits: exact.maximumWorkUnits),
            NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: exact.maximumCertificationBoxes,
                maximumScalarCount: exact.maximumScalarCount, maximumWorkUnits: exact.maximumWorkUnits - 1)] {
            try expectResource { _ = try construct(prepare(source, box, limits: limits)) }
        }
        let request = try prepare(source, box)
        try expectResource { _ = try constructor.constructContinuationCandidate(preparedRequest: request,
            uDegree: 3, vDegree: 3, maximumSpanCount: 1, maximumControlPointCountPerAxis: 131) }
        try expectResource { _ = try constructor.constructContinuationCandidate(preparedRequest: request,
            uDegree: 3, vDegree: 3, maximumSpanCount: 128, maximumControlPointCountPerAxis: 5) }
    }

    @Test
    func wrongOuterLawAndInteriorCoefficientExcessRemainIndependentRefusals() throws {
        let source = quadratic(), box = try rectangle(u: (-0.25, 1.25), v: (0, 1))
        let request = try prepare(source, box)
        let result = try construct(request)
        var wrongEnd = result.surface
        for row in wrongEnd.controlPoints.indices { wrongEnd.controlPoints[row][0].z += 0.01 }
        var bump = result.surface
        for row in bump.controlPoints.indices { bump.controlPoints[row][3].z += 0.01 }
        for candidate in [wrongEnd, bump] {
            do {
                _ = try proof.certifyContinuationPosition(preparedRequest: request, candidate: candidate)
                Issue.record("An independently displaced candidate received whole-law evidence.")
            } catch let error as GeometryConversionError {
                #expect(error == .toleranceRejected)
            }
        }
    }

    @Test
    func malformedDegreeReductionAndHigherDegreeDoNotPublishCandidates() throws {
        let box = try rectangle(u: (-0.25, 1.25), v: (0, 1))
        let request = try prepare(quadratic(), box)
        do {
            _ = try constructor.constructContinuationCandidate(preparedRequest: request,
                uDegree: 0, vDegree: 3, maximumSpanCount: 128, maximumControlPointCountPerAxis: 131)
            Issue.record("Malformed layout options published a candidate.")
        } catch let error as GeometryConversionError {
            guard case .invalidInput = error else { Issue.record("Malformed options changed their typed error."); return }
        }
        do {
            _ = try constructor.constructContinuationCandidate(preparedRequest: request,
                uDegree: 1, vDegree: 3, maximumSpanCount: 128, maximumControlPointCountPerAxis: 131)
            Issue.record("Degree reduction was accepted as an exact basis conversion.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        let high = BSplineSurface3D(uDegree: 4, vDegree: 1,
            uKnots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1].map { v in (0...4).map { i in Point3D(x: Double(i) / 4, y: v, z: 0) } })
        do {
            _ = try construct(prepare(high, box))
            Issue.record("A source above bicubic degree entered the bounded construction family.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    }

    @Test
    func immutableReceiptReuseAndCancellationRetainTheOriginalPrefix() async throws {
        var source = quadratic()
        let original = source, box = try rectangle(u: (-0.25, 1.25), v: (0, 1))
        let request = try prepare(source, box)
        source.controlPoints[0][0].z += 10
        source.uKnots[3] = 0.25
        let a = try construct(request), b = try construct(request)
        #expect(a.surface == b.surface && a.certificate == b.certificate)
        #expect(request.source == original && request.source != source)
        let task = Task { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try construct(request); return false }
            catch is CancellationError { return true }
        }
        #expect(try await task.value)
        #expect(request.source == original)
    }

    private func construct(_ request: PreparedPolynomialSurfaceContinuationPositionRequest) throws -> CertifiedPolynomialSurfaceContinuationCandidate {
        try constructor.constructContinuationCandidate(preparedRequest: request,
            uDegree: 3, vDegree: 3, maximumSpanCount: 128, maximumControlPointCountPerAxis: 131)
    }

    private func prepare(_ source: BSplineSurface3D, _ box: SurfaceParameterBox,
        limits: NativeSurfacePositionCertificationLimits = .standard) throws -> PreparedPolynomialSurfaceContinuationPositionRequest {
        try proof.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: distance, limits: limits, tolerance: .standard)
    }

    private func quadratic(weight: Double = 1) -> BSplineSurface3D {
        let xs: [Double] = [0, 1.0 / 3, 2.0 / 3, 1]
        let zs: [Double] = [0, 1.0 / 3, 1.0 / 3, 0]
        let points: [[Point3D]] = [0.0, 1].map { v in
            zip(xs, zs).map { x, z in
                Point3D(x: 0.02 * x, y: 0.02 * v, z: 0.02 * z)
            }
        }
        return BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 0.5, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: points, weights: points.map { row in row.map { _ in weight } })
    }

    private func rectangle(u: (Double, Double), v: (Double, Double)) throws -> SurfaceParameterBox {
        try SurfaceParameterBox(u: ScalarInterval(lower: u.0, upper: u.1), v: ScalarInterval(lower: v.0, upper: v.1))
    }

    private func expectResource(_ operation: () throws -> Void) throws {
        do { try operation(); Issue.record("An exhausted cumulative or layout allowance published a candidate.") }
        catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else { Issue.record("Resource exhaustion changed its typed error: \(error)."); return }
        }
    }
}
