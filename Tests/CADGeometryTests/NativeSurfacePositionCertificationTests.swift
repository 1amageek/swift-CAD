import CADCore
import CADGeometry
import Testing

@Suite("Original native surface position certification", .timeLimit(.minutes(2)))
struct NativeSurfacePositionCertificationTests {
    private let certifier: any GeometrySurfacePositionCertifying = CertifiedNativeSurfacePositionCertifier()

    @Test(arguments: [false, true])
    func independentAffineNativeChartsCertifyIncludingCollapsedMetric(collapsed: Bool) throws {
        let source = plane(degree: 3, u: (2, 5), v: (-3, 1), collapsed: collapsed)
        let candidate = plane(degree: 1, u: (1.5, 5.5), v: (-4, 2), collapsed: collapsed, height: 2e-9)
        let box = try rectangle(u: (2, 5), v: (-3, 1))
        let proof = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-8, limits: .standard, tolerance: .standard)
        #expect(proof.coveredParameters == box)
        #expect(proof.positionErrorUpperBound >= 2e-9 && proof.positionErrorUpperBound <= 1e-8)
        #expect(proof.certifiedBoxCount == 1)
        #expect(proof.scalarCount > 0 && proof.scalarCount <= NativeSurfacePositionCertificationLimits.standard.maximumScalarCount)
        #expect(proof.workUnits > 0 && proof.workUnits <= NativeSurfacePositionCertificationLimits.standard.maximumWorkUnits)
        // The independent candidate's literal affine XY chart holds over its larger domain.
        let literal = Point3D(x: 3.5, y: collapsed ? 0 : -1, z: 2e-9)
        #expect(try (candidate.point(u: 3.5, v: -1, tolerance: .standard) - literal).length <= 1e-13)
    }

    @Test
    func originalLiteralInteriorBumpCannotBeCertifiedAgainstAnAliasedPlane() throws {
        let source = bump()
        let candidate = plane(degree: 3)
        let literal = Point3D(x: 1.0 / 8, y: 1.0 / 8, z: 4e-3 / 9)
        #expect(try (source.point(u: 1.0 / 8, v: 1.0 / 8, tolerance: .standard) - literal).length <= 1e-12)
        #expect(try abs(candidate.point(u: 1.0 / 8, v: 1.0 / 8, tolerance: .standard).z) <= 1e-15)
        #expect(literal.z > 400e-6)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try certifier.certifyPosition(source: source, candidate: candidate, over: rectangle(),
                maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
        }
    }

    @Test(arguments: [false, true])
    func asymmetricOriginalKnotAnchorCoversAllOffsets(raised: Bool) throws {
        let source = bump(amplitude: raised ? 1e-3 : 0)
        let candidate = plane(degree: 3, height: 2e-9)
        let box = try rectangle(u: (1.0 / 16, 0.5), v: (0, 0.75))
        // The stored central native knot is 1/8, strictly inside both axes but not
        // either midpoint. Both lower and upper offsets must use that actual anchor.
        if raised {
            #expect(throws: GeometryConversionError.toleranceRejected) {
                _ = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                    maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
            }
        } else {
            let proof = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
            #expect(proof.coveredParameters == box && proof.positionErrorUpperBound >= 2e-9)
            #expect(proof.positionErrorUpperBound <= 1e-6)
        }
    }

    @Test
    func completeStoredNonlinearIdentityCertifiesZeroWithoutInventedPreparationUsage() throws {
        let source = bump()
        let retained = source
        let box = try rectangle()
        let proof = try certifier.certifyPosition(source: source, candidate: retained, over: box,
            maximumPositionError: 1e-12, limits: .standard, tolerance: .standard)
        #expect(proof.coveredParameters == box && proof.positionErrorUpperBound == 0)
        #expect(proof.certifiedBoxCount == 0 && proof.scalarCount == 0)
        #expect(proof.workUnits > 0 && source == retained)
        // Identity still validates the actual requested rectangle and charges its complete scan.
        try expectResourceFailure {
            _ = try certifier.certifyPosition(source: source, candidate: retained, over: box,
                maximumPositionError: 1e-12,
                limits: .init(maximumCertificationBoxes: 1, maximumScalarCount: 1, maximumWorkUnits: 1),
                tolerance: .standard)
        }
    }

    @Test
    func c0RepeatedKnotSidesRemainCoveredWithoutMetricRegularity() throws {
        let source = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 0.5, y: 0, z: 1e-9), .init(x: 1, y: 0, z: 0)],
                           [.init(x: 0, y: 1, z: 0), .init(x: 0.5, y: 1, z: 1e-9), .init(x: 1, y: 1, z: 0)]])
        let proof = try certifier.certifyPosition(source: source, candidate: plane(degree: 3),
            over: rectangle(), maximumPositionError: 1e-8, limits: .standard, tolerance: .standard)
        #expect(proof.positionErrorUpperBound >= 1e-9 && proof.positionErrorUpperBound <= 1e-8 && proof.certifiedBoxCount > 0)
    }

    @Test
    func strictDomainOvershootPeriodicAndDiscontinuousSourcesRefuse() throws {
        let source = plane(degree: 1)
        for box in [try rectangle(u: (-Double.leastNonzeroMagnitude, 1)),
                    try rectangle(v: (0, Double(1).nextUp))] {
            do {
                _ = try certifier.certifyPosition(source: source, candidate: source, over: box,
                    maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
                Issue.record("A strict original-domain overshoot was admitted.")
            } catch let error as KernelError {
                #expect(error.code == .invalidInput)
            }
        }
        var periodic = source
        periodic.isUPeriodic = true
        do {
            _ = try certifier.certifyPosition(source: periodic, candidate: source, over: rectangle(),
                maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
            Issue.record("An unsupported periodic native chart was admitted.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
        let discontinuous = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 0.5, y: 0, z: 1), .init(x: 1, y: 0, z: 1)],
                           [.init(x: 0, y: 1, z: 0), .init(x: 0.5, y: 1, z: 0), .init(x: 0.5, y: 1, z: 1), .init(x: 1, y: 1, z: 1)]])
        #expect(throws: GeometryError.invalidDistance(2)) {
            _ = try certifier.certifyPosition(source: discontinuous, candidate: source, over: rectangle(),
                maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
        }
    }

    @Test
    func exactUsageBoundariesAndSubdivisionCapacityAreEnforced() throws {
        let source = plane(degree: 3), candidate = plane(degree: 1, height: 1e-9)
        let box = try rectangle()
        let proof = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-8, limits: .standard, tolerance: .standard)
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits)
        let repeated = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: 1e-8, limits: exact, tolerance: .standard)
        #expect(repeated == proof)
        for limits in [NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: 1,
                            maximumScalarCount: proof.scalarCount - 1, maximumWorkUnits: proof.workUnits),
                       NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: 1,
                            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits - 1),
                       NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: 1,
                            maximumScalarCount: 1, maximumWorkUnits: 1)] {
            try expectResourceFailure {
                _ = try certifier.certifyPosition(source: source, candidate: candidate, over: box,
                    maximumPositionError: 1e-8, limits: limits, tolerance: .standard)
            }
        }
        var curved = plane(degree: 3)
        for j in curved.controlPoints.indices {
            curved.controlPoints[j][1].z = 1e-4
            curved.controlPoints[j][2].z = 1e-4
        }
        try expectResourceFailure {
            _ = try certifier.certifyPosition(source: source, candidate: curved, over: box,
                maximumPositionError: 1e-4,
                limits: .init(maximumCertificationBoxes: 1,
                    maximumScalarCount: NativeSurfacePositionCertificationLimits.standard.maximumScalarCount,
                    maximumWorkUnits: NativeSurfacePositionCertificationLimits.standard.maximumWorkUnits),
                tolerance: .standard)
        }
        #expect(source == plane(degree: 3) && candidate == plane(degree: 1, height: 1e-9))
    }

    @Test
    func invalidOptionsAndActualSourceErrorsRemainTyped() throws {
        let source = plane(degree: 1)
        #expect(throws: GeometryConversionError.invalidInput("Native position certification requires a finite positive distance and finite native rectangle.")) {
            _ = try certifier.certifyPosition(source: source, candidate: source, over: rectangle(),
                maximumPositionError: 0, limits: .standard, tolerance: .standard)
        }
        #expect(throws: GeometryConversionError.invalidInput("Native position certification requires positive finite resource limits.")) {
            _ = try certifier.certifyPosition(source: source, candidate: source, over: rectangle(),
                maximumPositionError: 1e-6,
                limits: .init(maximumCertificationBoxes: 0, maximumScalarCount: 1, maximumWorkUnits: 1),
                tolerance: .standard)
        }
        var invalid = source
        invalid.weights[0][0] = 0
        #expect(throws: GeometryError.invalidDistance(0)) {
            _ = try certifier.certifyPosition(source: invalid, candidate: source, over: rectangle(),
                maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
        }
    }

    @Test
    func cancellationRefusesBeforeIdentityOrPreparationPublication() async throws {
        let source = bump()
        let box = try rectangle()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try certifier.certifyPosition(source: source, candidate: source, over: box,
                maximumPositionError: 1e-6, limits: .standard, tolerance: .standard)
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled position certification published evidence.")
        } catch is CancellationError {}
    }

    private func expectResourceFailure(_ operation: () throws -> Void) rethrows {
        do {
            try operation()
            Issue.record("An exhausted native position certification published evidence.")
        } catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else {
                Issue.record("The refusal had the wrong conversion reason: \(error).")
                return
            }
        }
    }

    private func rectangle(u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1),
            v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func plane(degree: Int, u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1),
        collapsed: Bool = false, height: Double = 0) -> BSplineSurface3D {
        let uKnots = Array(repeating: u.0, count: degree + 1) + Array(repeating: u.1, count: degree + 1)
        let vKnots = Array(repeating: v.0, count: degree + 1) + Array(repeating: v.1, count: degree + 1)
        let xs = (0...degree).map { uKnots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        let ys = (0...degree).map { vKnots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        return BSplineSurface3D(uDegree: degree, vDegree: degree, uKnots: uKnots, vKnots: vKnots,
            controlPoints: ys.map { y in xs.map { x in Point3D(x: x, y: collapsed ? 0 : y, z: height) } })
    }

    private func bump(amplitude: Double = 1e-3) -> BSplineSurface3D {
        let knots: [Double] = [0, 0, 0, 0, 1.0 / 16, 3.0 / 32, 1.0 / 8, 5.0 / 32, 3.0 / 16, 1, 1, 1, 1]
        let coordinates = (0..<9).map { (knots[$0 + 1] + knots[$0 + 2] + knots[$0 + 3]) / 3 }
        let controls = (0..<9).map { j in (0..<9).map { i in
            Point3D(x: coordinates[i], y: coordinates[j], z: i == 4 && j == 4 ? amplitude : 0)
        } }
        return BSplineSurface3D(uDegree: 3, vDegree: 3, uKnots: knots, vKnots: knots,
            controlPoints: controls, weights: Array(repeating: Array(repeating: 1, count: 9), count: 9))
    }
}
