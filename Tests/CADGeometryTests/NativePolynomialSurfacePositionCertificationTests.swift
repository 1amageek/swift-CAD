import CADCore
import CADGeometry
import Testing

@Suite("Original multi-span polynomial position preparation", .timeLimit(.minutes(2)))
struct NativePolynomialSurfacePositionCertificationTests {
    private let certifier: any GeometrySurfacePositionCertifying = CertifiedNativeSurfacePositionCertifier()

    @Test(arguments: [false, true])
    func independentlyAuthoredTwoSpanAnd256PanelPolynomialCertifyUnderOriginalDefaults(shifted: Bool) throws {
        let u: (Double, Double) = shifted ? (2, 6) : (0, 1)
        let v: (Double, Double) = shifted ? (-3, 1) : (0, 1)
        let source = polynomial(degree: 2, uSpans: 2, vDegree: 1, vSpans: 1, u: u, v: v, weight: 3)
        let candidate = polynomial(degree: 3, uSpans: 128, vDegree: 3, vSpans: 2, u: u, v: v, height: 2e-9, weight: 2)
        let box = try rectangle(u: u, v: v)
        // Independent known law: S=(.02*s,.02*t,.02*s*(1-s)), with a 2e-9 offset.
        let literal = Point3D(x: 0.0075, y: 0.005, z: 0.02 * 0.375 * 0.625)
        let actualU = u.0 + (u.1 - u.0) * 0.375, actualV = v.0 + (v.1 - v.0) * 0.25
        #expect(try (source.point(u: actualU, v: actualV, tolerance: .standard) - literal).length < 1e-13)
        #expect(try abs(candidate.point(u: actualU, v: actualV, tolerance: .standard).z - literal.z - 2e-9) < 1e-13)
        #expect(source.uDegree == 2 && source.vDegree == 1 && source.uControlPointCount == 4)
        #expect(candidate.uDegree == 3 && candidate.uControlPointCount == 131 && candidate.vControlPointCount == 5)
        let proof = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        #expect(proof.coveredParameters == box && proof.certifiedBoxCount == 256)
        #expect(proof.positionErrorUpperBound >= 2e-9 - 1e-13 && proof.positionErrorUpperBound <= 1e-7)
        #expect(proof.scalarCount < NativeSurfacePositionCertificationLimits.standard.maximumScalarCount)
        #expect(proof.workUnits < NativeSurfacePositionCertificationLimits.standard.maximumWorkUnits)
        print("NATIVE_POLYNOMIAL_POSITION boxes=\(proof.certifiedBoxCount) scalars=\(proof.scalarCount) work=\(proof.workUnits) bound=\(proof.positionErrorUpperBound)")
    }

    @Test
    func selectedClosedPartialNativeChartAndCommonWorldOriginRemainOriginalAuthority() throws {
        let origin = Point3D(x: 10_000, y: -20_000, z: 30_000)
        let source = polynomial(degree: 2, uSpans: 2, vDegree: 1, vSpans: 1, origin: origin)
        let candidate = polynomial(degree: 3, uSpans: 128, vDegree: 3, vSpans: 2, height: 2e-9, origin: origin)
        let box = try rectangle(u: (0.25, 0.75), v: (0.25, 0.75))
        let proof = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        #expect(proof.coveredParameters == box && proof.certifiedBoxCount == 128)
        #expect(proof.positionErrorUpperBound <= 1e-7)
        #expect(source.controlPoints[0][0] == origin && candidate.controlPoints[0][0].z != origin.z)
    }

    @Test
    func independentlyKnownInteriorCubicPeakCannotPassWholePositionAdmission() throws {
        let source = polynomial(degree: 2, uSpans: 2, vDegree: 1, vSpans: 1)
        var candidate = polynomial(degree: 3, uSpans: 128, vDegree: 3, vSpans: 2, height: 2e-9)
        let index = 73
        for row in candidate.controlPoints.indices { candidate.controlPoints[row][index].z += 1e-3 }
        // Interior uniform cubic basis at its Greville center is exactly 2/3;
        // identical offsets on every V coefficient retain that peak by partition of unity.
        let u = Double(index - 1) / 128
        let literal = 0.02 * u * (1 - u) + 2e-9 + 2e-3 / 3
        #expect(try abs(candidate.point(u: u, v: 0.375, tolerance: .standard).z - literal) < 1e-13)
        #expect(literal - 0.02 * u * (1 - u) > 600e-6)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try certifier.certifyPosition(source: source, candidate: candidate, over: rectangle(),
                maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        }
    }

    @Test
    func paidNativePrefixAndExactReportedScalarWorkAndCellCeilingsAreRetained() throws {
        let source = polynomial(degree: 2, uSpans: 2, vDegree: 1, vSpans: 1)
        let candidate = polynomial(degree: 3, uSpans: 128, vDegree: 3, vSpans: 2, height: 2e-9)
        let box = try rectangle()
        let proof = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
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
                Issue.record("A native position operation spent beyond its exact cumulative ceiling.")
            } catch let error as GeometryConversionError {
                guard case .resourceLimitExceeded = error else { throw error }
            }
        }
    }

    @Test
    func cancellationPrecedesPositionOnlyPreparationAndPublication() async throws {
        let source = polynomial(degree: 2, uSpans: 2, vDegree: 1, vSpans: 1)
        let candidate = polynomial(degree: 3, uSpans: 128, vDegree: 3, vSpans: 2, height: 2e-9)
        let box = try rectangle()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        }
        do { _ = try await task.value; Issue.record("Cancelled native polynomial evidence was published.") }
        catch is CancellationError {}
    }

    private func rectangle(u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1), v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func polynomial(degree: Int, uSpans: Int, vDegree: Int, vSpans: Int,
        u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1), height: Double = 0,
        weight: Double = 1, origin: Point3D = .origin) -> BSplineSurface3D {
        func knots(_ degree: Int, _ spans: Int, _ domain: (Double, Double)) -> [Double] {
            Array(repeating: domain.0, count: degree + 1)
                + (1..<spans).map { domain.0 + (domain.1 - domain.0) * Double($0) / Double(spans) }
                + Array(repeating: domain.1, count: degree + 1)
        }
        let us = knots(degree, uSpans, u), vs = knots(vDegree, vSpans, v)
        let columns = us.count - degree - 1, rows = vs.count - vDegree - 1
        func normalizedKnot(_ index: Int) -> Double { (us[index] - u.0) / (u.1 - u.0) }
        var controls: [[Point3D]] = []
        for j in 0..<rows {
            let t = (1...vDegree).reduce(0.0) { $0 + (vs[j + $1] - v.0) / (v.1 - v.0) } / Double(vDegree)
            var row: [Point3D] = []
            for i in 0..<columns {
                let s = (1...degree).reduce(0.0) { $0 + normalizedKnot(i + $1) } / Double(degree)
                var pairs = 0.0
                for a in 1..<degree { for b in (a + 1)...degree { pairs += normalizedKnot(i + a) * normalizedKnot(i + b) } }
                let squared = pairs / Double(degree * (degree - 1) / 2)
                // Polynomial reproduction coefficients: t=Greville, t^2=mean of knot pairs.
                // This is independently authored; no insertion/elevation/refinement API supplies the oracle.
                row.append(Point3D(x: origin.x + 0.02 * s, y: origin.y + 0.02 * t,
                    z: origin.z + 0.02 * (s - squared) + height))
            }
            controls.append(row)
        }
        return BSplineSurface3D(uDegree: degree, vDegree: vDegree, uKnots: us, vKnots: vs,
            controlPoints: controls, weights: Array(repeating: Array(repeating: weight, count: columns), count: rows))
    }
}
