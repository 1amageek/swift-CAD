import CADCore
import CADGeometry
import Testing

@Suite("Original polynomial continuation position certification", .timeLimit(.minutes(2)))
struct PolynomialSurfaceContinuationPositionCertificationTests {
    private let certifier: any GeometryPolynomialSurfaceContinuationPositionCertifying = CertifiedPolynomialSurfaceContinuationPositionCertifier()

    @Test(arguments: [false, true])
    func sourceAdmissionDistinguishesUnsupportedWeightsFromFiniteOriginalSpans(multispan: Bool) throws {
        var source = arch()
        if multispan {
            source = BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [[.origin, .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                    [.init(x: 0, y: 1, z: 0), .init(x: 0.5, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        } else { source.weights[0][1] = 2 }
        try source.validate(tolerance: .standard)
        let original = source
        if multispan {
            let request = try certifier.prepareContinuationRequest(source: source,
                over: rectangle(u: (-0.25, 1.25)), maximumPositionError: 1e-7,
                limits: .standard, tolerance: .standard)
            #expect(request.source == original && request.admittedWorkUnits > 0)
        } else {
            do {
                _ = try certifier.prepareContinuationRequest(source: source,
                    over: rectangle(u: (-0.25, 1.25)), maximumPositionError: 1e-7,
                    limits: .standard, tolerance: .standard)
                Issue.record("Varying weights produced a polynomial fitting receipt.")
            } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        }
        #expect(source == original)
    }

    @Test
    func preparedReceiptRetainsOriginalOwnershipAndComposesWithTheDirectOperation() throws {
        var source = arch()
        let original = source, candidate = cubicArch(), box = try rectangle(u: (-0.25, 1.25))
        let request = try certifier.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        source.weights[0][1] = 2
        source.controlPoints[0][0].z = 10
        var borrowedCopy = request.source
        borrowedCopy.uKnots[0] = -1
        #expect(request.source == original && request.source != source && request.source != borrowedCopy)
        #expect(request.parameters == box && request.maximumPositionError == 1e-7)
        #expect(request.limits == .standard && request.tolerance == .standard)
        #expect(request.admittedScalarCount > 0 && request.admittedWorkUnits > 0 && request.admittedBoxCount == 0)
        let prepared = try certifier.certifyContinuationPosition(preparedRequest: request, candidate: candidate)
        let direct = try certify(original, candidate, box)
        #expect(prepared == direct && prepared.positionErrorUpperBound <= 1e-7)
        #expect(prepared.scalarCount > request.admittedScalarCount && prepared.workUnits > request.admittedWorkUnits)
    }

    @Test
    func paidAdmissionPrefixCannotBeResetByCandidateCertification() throws {
        let source = arch(), candidate = cubicArch(), box = try rectangle(u: (-0.25, 1.25))
        let standardRequest = try certifier.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: 1e-7, limits: .standard, tolerance: .standard)
        let proof = try certifier.certifyContinuationPosition(preparedRequest: standardRequest, candidate: candidate)
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits)
        let exactRequest = try certifier.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: 1e-7, limits: exact, tolerance: .standard)
        #expect(try certifier.certifyContinuationPosition(preparedRequest: exactRequest, candidate: candidate) == proof)
        // This allowance fits the entire suffix by itself. Resetting paid source
        // work would admit it; correctly retaining the prefix must exhaust it.
        let missingPrefix = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount,
            maximumWorkUnits: proof.workUnits - standardRequest.admittedWorkUnits)
        let boundedRequest = try certifier.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: 1e-7, limits: missingPrefix, tolerance: .standard)
        try expectResourceFailure {
            _ = try certifier.certifyContinuationPosition(preparedRequest: boundedRequest, candidate: candidate)
        }
        let admissionOnly = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: 1,
            maximumScalarCount: standardRequest.admittedScalarCount,
            maximumWorkUnits: standardRequest.admittedWorkUnits)
        let admissionRequest = try certifier.prepareContinuationRequest(source: source, over: box,
            maximumPositionError: 1e-7, limits: admissionOnly, tolerance: .standard)
        #expect(admissionRequest.admittedWorkUnits == standardRequest.admittedWorkUnits)
        try expectResourceFailure {
            _ = try certifier.certifyContinuationPosition(preparedRequest: admissionRequest, candidate: candidate)
        }
        // A failed suffix does not mutate an immutable receipt or other invocations.
        #expect(try certifier.certifyContinuationPosition(preparedRequest: standardRequest, candidate: candidate) == proof)
    }

    @Test
    func preparedRequestStillAdmitsTheActualCandidateFamilyAndStrictChart() throws {
        let request = try certifier.prepareContinuationRequest(source: arch(),
            over: rectangle(u: (-0.25, 1.25)), maximumPositionError: 1e-7,
            limits: .standard, tolerance: .standard)
        do {
            _ = try certifier.certifyContinuationPosition(preparedRequest: request,
                candidate: cubicArch(u: (-0.125, 1.125)))
            Issue.record("A receipt was used to bypass the candidate's actual support.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
        var rational = cubicArch()
        rational.weights[0][1] = 2
        do {
            _ = try certifier.certifyContinuationPosition(preparedRequest: request, candidate: rational)
            Issue.record("A receipt was used to bypass the candidate's polynomial family.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        #expect(try certifier.certifyContinuationPosition(preparedRequest: request, candidate: cubicArch()).positionErrorUpperBound <= 1e-7)
    }

    @Test
    func cancellationAfterSourceAdmissionDoesNotPublishACertificate() async throws {
        let request = try certifier.prepareContinuationRequest(source: arch(),
            over: rectangle(u: (-0.25, 1.25)), maximumPositionError: 1e-7,
            limits: .standard, tolerance: .standard)
        let candidate = cubicArch()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try certifier.certifyContinuationPosition(preparedRequest: request, candidate: candidate)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled receipt certification published evidence.")
        } catch is CancellationError {}
        #expect(request.source == arch() && request.admittedBoxCount == 0)
    }

    @Test(arguments: [false, true])
    func independentlyAuthoredCubicArchCoversTheExtendedOriginalLaw(collapsed: Bool) throws {
        let source = arch(collapsed: collapsed)
        let candidate = cubicArch(collapsed: collapsed)
        let retainedSource = source, retainedCandidate = candidate
        let box = try rectangle(u: (-0.25, 1.25))
        let proof = try certify(source, candidate, box)
        #expect(proof.coveredParameters == box && proof.positionErrorUpperBound <= 1e-7)
        #expect(proof.certifiedBoxCount == 1 && proof.scalarCount > 0 && proof.workUnits > 0)
        // This literal point is outside the original support. Its polynomial law is
        // independent of native continuation, collocation and certifier helpers.
        let literal = Point3D(x: collapsed ? 0 : 0.02 * 1.2,
            y: collapsed ? 0 : 0.02 * 0.6, z: 0.02 * 1.2 * (1 - 1.2))
        #expect(try (candidate.point(u: 1.2, v: 0.6, tolerance: .standard) - literal).length <= 1e-13)
        #expect(source == retainedSource && candidate == retainedCandidate)
    }

    @Test
    func displacedIndependentCandidateHasDefiniteOriginalDerivedExcess() throws {
        let source = arch()
        var candidate = cubicArch()
        candidate.controlPoints[1][1].z += 1e-3
        let retained = candidate
        // At the rectangle center both cubic basis factors are 3/8.
        let literalCenter = Point3D(x: 0.01, y: 0.01, z: 0.005 + 9e-3 / 64)
        #expect(try (candidate.point(u: 0.5, v: 0.5, tolerance: .standard) - literalCenter).length <= 1e-13)
        #expect(throws: GeometryConversionError.toleranceRejected) {
            _ = try certify(source, candidate, rectangle(u: (-0.25, 1.25)))
        }
        #expect(candidate == retained)
    }

    @Test
    func asymmetricNonunitChartsAndCommonNonunitWeightsRetainThePolynomial() throws {
        let source = arch(u: (2, 5), v: (-3, 1), weight: 7)
        let candidate = cubicArch(originalU: (2, 5), originalV: (-3, 1),
            u: (1, 6), v: (-4, 2), weight: 3)
        let proof = try certify(source, candidate, rectangle(u: (1, 6), v: (-4, 2)))
        #expect(proof.positionErrorUpperBound <= 1e-7 && proof.certifiedBoxCount == 1)
        let normalizedU = (5.75 - 2) / 3.0, normalizedV = (-3.5 + 3) / 4.0
        let literal = Point3D(x: 0.02 * normalizedU, y: 0.02 * normalizedV,
            z: 0.02 * normalizedU * (1 - normalizedU))
        #expect(try (candidate.point(u: 5.75, v: -3.5, tolerance: .standard) - literal).length <= 1e-13)
    }

    @Test
    func paidUsageBoundaryIsReproducibleAndOneLessRefuses() throws {
        let source = arch(), candidate = cubicArch()
        let box = try rectangle(u: (-0.25, 1.25))
        let proof = try certify(source, candidate, box)
        let exact = NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: proof.certifiedBoxCount,
            maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits)
        #expect(try certify(source, candidate, box, limits: exact) == proof)
        for limit in [NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: 1,
                maximumScalarCount: proof.scalarCount - 1, maximumWorkUnits: proof.workUnits),
            NativeSurfacePositionCertificationLimits(maximumCertificationBoxes: 1,
                maximumScalarCount: proof.scalarCount, maximumWorkUnits: proof.workUnits - 1)] {
            try expectResourceFailure { _ = try certify(source, candidate, box, limits: limit) }
        }
        #expect(source == arch() && candidate == cubicArch())
    }

    @Test
    func unresolvedHullSubdividesTheSameDifferenceNetAndChargesEveryCell() throws {
        let source = flat(degree: 1)
        var candidate = flat(degree: 3)
        for row in candidate.controlPoints.indices {
            candidate.controlPoints[row][1].z = 1e-4
            candidate.controlPoints[row][2].z = 1e-4
        }
        // The complete difference hull starts at 100um while the literal maximum
        // 3*A*t*(1-t) is 75um. A hull excess cannot be a tolerance rejection.
        let box = try rectangle()
        let proof = try certify(source, candidate, box, distance: 8e-5)
        #expect(proof.certifiedBoxCount == 3)
        #expect(proof.positionErrorUpperBound >= 7.5e-5 && proof.positionErrorUpperBound <= 8e-5)
        try expectResourceFailure {
            _ = try certify(source, candidate, box, distance: 8e-5,
                limits: .init(maximumCertificationBoxes: 1,
                    maximumScalarCount: NativeSurfacePositionCertificationLimits.standard.maximumScalarCount,
                    maximumWorkUnits: NativeSurfacePositionCertificationLimits.standard.maximumWorkUnits))
        }
    }

    @Test
    func candidateSupportIsStrictWhileOriginalPolynomialContinuationIsExplicit() throws {
        let source = arch(), candidate = cubicArch()
        for box in [try rectangle(u: (-0.25, Double(1.25).nextUp)),
                    try rectangle(u: (-0.25, 1.25), v: (0, Double(1).nextUp))] {
            do {
                _ = try certify(source, candidate, box)
                Issue.record("Candidate support overshoot was certified.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        // Closed endpoints themselves are allowed, and the original stored
        // source rectangle is smaller than this complete requested rectangle.
        #expect(try certify(source, candidate, rectangle(u: (-0.25, 1.25))).certifiedBoxCount == 1)
    }

    @Test
    func unsupportedFamiliesAndActualMalformedOriginalInputsRemainDistinct() throws {
        let candidate = cubicArch()
        var periodic = arch()
        periodic.isUPeriodic = true
        var rational = arch()
        rational.weights[0][1] = 2
        var nonclamped = arch()
        nonclamped.uKnots = [-0.1, 0, 0, 1, 1, 1.1]
        for source in [periodic, rational, nonclamped] {
            do {
                _ = try certify(source, candidate, rectangle(u: (-0.25, 1.25)))
                Issue.record("An unsupported continuation family published evidence.")
            } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        }
        var rationalCandidate = candidate
        rationalCandidate.weights[0][1] = 2
        do {
            _ = try certify(arch(), rationalCandidate, rectangle(u: (-0.25, 1.25)))
            Issue.record("A varying-weight candidate published polynomial evidence.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        var invalid = arch()
        invalid.weights[0][0] = 0
        #expect(throws: GeometryError.invalidDistance(0)) {
            _ = try certify(invalid, candidate, rectangle(u: (-0.25, 1.25)))
        }
    }

    @Test
    func invalidOptionsRefuseBeforePublication() throws {
        #expect(throws: GeometryConversionError.invalidInput("Polynomial continuation requires a finite positive distance and rectangle.")) {
            _ = try certify(arch(), cubicArch(), rectangle(u: (-0.25, 1.25)), distance: 0)
        }
        #expect(throws: GeometryConversionError.invalidInput("Native position certification requires positive finite resource limits.")) {
            _ = try certify(arch(), cubicArch(), rectangle(u: (-0.25, 1.25)),
                limits: .init(maximumCertificationBoxes: 0, maximumScalarCount: 1, maximumWorkUnits: 1))
        }
    }

    @Test
    func cancellationDoesNotPublishOrMutateOriginalInputs() async throws {
        let source = arch(), candidate = cubicArch(), box = try rectangle(u: (-0.25, 1.25))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try certify(source, candidate, box)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled polynomial continuation published evidence.")
        } catch is CancellationError {}
        #expect(source == arch() && candidate == cubicArch())
    }

    private func certify(_ source: BSplineSurface3D, _ candidate: BSplineSurface3D,
        _ box: SurfaceParameterBox, distance: Double = 1e-7,
        limits: NativeSurfacePositionCertificationLimits = .standard) throws -> NativeSurfacePositionCertificate {
        try certifier.certifyContinuationPosition(source: source, candidate: candidate, over: box,
            maximumPositionError: distance, limits: limits, tolerance: .standard)
    }

    private func rectangle(u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1)) throws -> SurfaceParameterBox {
        .init(u: try ScalarInterval(lower: u.0, upper: u.1), v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func arch(u: (Double, Double) = (0, 1), v: (Double, Double) = (0, 1),
        weight: Double = 1, collapsed: Bool = false) -> BSplineSurface3D {
        let points = (0...1).map { row in
            (0...2).map { column in
                Point3D(x: collapsed ? 0 : 0.01 * Double(column),
                    y: collapsed ? 0 : 0.02 * Double(row), z: column == 1 ? 0.01 : 0)
            }
        }
        return .init(uDegree: 2, vDegree: 1,
            uKnots: [u.0, u.0, u.0, u.1, u.1, u.1], vKnots: [v.0, v.0, v.1, v.1],
            controlPoints: points, weights: Array(repeating: Array(repeating: weight, count: 3), count: 2))
    }

    private func cubicArch(originalU: (Double, Double) = (0, 1), originalV: (Double, Double) = (0, 1),
        u: (Double, Double) = (-0.25, 1.25), v: (Double, Double) = (0, 1),
        weight: Double = 1, collapsed: Bool = false) -> BSplineSurface3D {
        // Independent power-to-Bernstein formula for s*t*(1-t) on the target
        // chart, with linear XY. No production elevation/continuation is called.
        let a = (u.0 - originalU.0) / (originalU.1 - originalU.0)
        let width = (u.1 - u.0) / (originalU.1 - originalU.0)
        let b = (v.0 - originalV.0) / (originalV.1 - originalV.0)
        let vWidth = (v.1 - v.0) / (originalV.1 - originalV.0)
        let c0 = 0.02 * a * (1 - a), c1 = 0.02 * (1 - 2 * a) * width
        let c2 = -0.02 * width * width
        var points: [[Point3D]] = []
        for row in 0...3 {
            var line: [Point3D] = []
            for column in 0...3 {
                let t = Double(column) / 3
                let quadratic = Double(column * (column - 1)) / 6
                line.append(.init(x: collapsed ? 0 : 0.02 * (a + width * t),
                    y: collapsed ? 0 : 0.02 * (b + vWidth * Double(row) / 3),
                    z: c0 + c1 * t + c2 * quadratic))
            }
            points.append(line)
        }
        return .init(uDegree: 3, vDegree: 3,
            uKnots: Array(repeating: u.0, count: 4) + Array(repeating: u.1, count: 4),
            vKnots: Array(repeating: v.0, count: 4) + Array(repeating: v.1, count: 4),
            controlPoints: points, weights: Array(repeating: Array(repeating: weight, count: 4), count: 4))
    }

    private func flat(degree: Int) -> BSplineSurface3D {
        .init(uDegree: degree, vDegree: degree,
            uKnots: Array(repeating: 0, count: degree + 1) + Array(repeating: 1, count: degree + 1),
            vKnots: Array(repeating: 0, count: degree + 1) + Array(repeating: 1, count: degree + 1),
            controlPoints: Array(repeating: Array(repeating: .origin, count: degree + 1), count: degree + 1))
    }

    private func expectResourceFailure(_ body: () throws -> Void) rethrows {
        do {
            try body()
            Issue.record("Exhausted continuation resources published evidence.")
        } catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else {
                Issue.record("Unexpected conversion refusal: \(error).")
                return
            }
        }
    }
}
