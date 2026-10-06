import CADCore
@testable import CADGeometry
import Testing

@Suite("Original single-cell Coons intersection sources")
struct OriginalCoonsIntersectionSourceTests {
    private enum Failure: Error { case work, storage, cell, coefficient }
    private struct Budget: RationalAlgebraAdmitting {
        var work = 0, words = 0, cells = 0, storageCalls = 0
        var maximumWork = 80_000_000, maximumWords = 80_000_000, maximumCells = 80_000_000
        var cancelAtStorageCall: Int?
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw Failure.work }; work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumWords - words else { throw Failure.storage }
            words += count; storageCalls += 1
            if storageCalls == cancelAtStorageCall { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth == 0, cells < maximumCells else { throw Failure.cell }; cells += 1
        }
        mutating func visitCoefficientCell(depth: Int) throws { throw Failure.coefficient }
    }
    private let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-10)
    private func q(_ value: Double, _ usage: inout Budget) throws -> ExactRationalCoefficient {
        try .originalDouble(value, usage: &usage)
    }
    private func box(_ u0: Double = 0, _ u1: Double = 1,
        _ v0: Double = 0, _ v1: Double = 1) throws -> SurfaceParameterBox {
        try .init(u: .init(lower: u0, upper: u1), v: .init(lower: v0, upper: v1))
    }
    private func traversal(_ native: BSplineCurve3D, lower: Double, upper: Double,
        reversed: Bool = false, owner: Int? = nil, usage: inout Budget) throws -> OriginalCurveRootSpan3D {
        let raw = try OriginalCurveRootSpan3D(source: .bSpline(native),
            start: .authored(lower), end: .authored(upper), nativeSpanIndex: owner,
            maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: 0,
            tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
            maximumSpanCount: 2, remainingSourceDepth: 0, maximumAlgebraicDepth: 0)
        return reversed ? raw.reversed() : raw
    }
    private func source(weighted: Bool = true, reversed: Bool = false,
        multiple: Bool = false, cornerMismatch: Bool = false, usage: inout Budget) throws -> OriginalCoonsSurface3D {
        var bottom = multiple
            ? BSplineCurve3D(degree: 1, knots: [-2, -2, 1, 4, 4],
                controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .init(x: 2, y: 0, z: 0)])
            : BSplineCurve3D(degree: 2, knots: [-2, -2, -2, 4, 4, 4],
                controlPoints: [.origin, .init(x: 1, y: 0, z: weighted ? 1 : 0), .init(x: 2, y: 0, z: 0)],
                weights: weighted ? [1, 2, 1] : [1, 1, 1])
        if reversed { bottom.controlPoints.reverse(); bottom.weights.reverse() }
        let top = BSplineCurve3D(degree: 1, knots: [7, 7, 10, 10],
            controlPoints: [.init(x: 0, y: 2, z: 0), .init(x: 2, y: 2, z: 0)], weights: weighted ? [1, 3] : [1, 1])
        let left = BSplineCurve3D(degree: 1, knots: [1, 1, 5, 5],
            controlPoints: [.init(x: cornerMismatch ? tolerance.distance / 2 : 0, y: 0, z: 0),
                .init(x: 0, y: 2, z: 0)], weights: weighted ? [2, 1] : [1, 1])
        let right = BSplineCurve3D(degree: 1, knots: [-5, -5, -1, -1],
            controlPoints: [.init(x: 2, y: 0, z: 0), .init(x: 2, y: 2, z: 0)], weights: weighted ? [1, 2] : [1, 1])
        return try .init(vMinimumBoundary: traversal(bottom, lower: -2, upper: 4, reversed: reversed,
                owner: multiple ? nil : 2, usage: &usage),
            vMaximumBoundary: traversal(top, lower: 7, upper: 10, owner: 1, usage: &usage),
            uMinimumBoundary: traversal(left, lower: 1, upper: 5, owner: 1, usage: &usage),
            uMaximumBoundary: traversal(right, lower: -5, upper: -1, owner: 1, usage: &usage),
            tolerance: tolerance, usage: &usage)
    }
    private func issue(_ source: OriginalCoonsSurface3D, domain: SurfaceParameterBox? = nil,
        depth: Int = 1, usage: inout Budget) throws -> OriginalCoonsSurfacePolynomial {
        try .init(source: source, over: domain ?? box(), remainingSourceDepth: depth,
            tolerance: tolerance, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func weightedNonunitDirectedNativeLawUsesExactCorners(reversed: Bool) throws {
        var usage = Budget(); let raw = try source(reversed: reversed, usage: &usage)
        let receipt = try issue(raw, usage: &usage)
        #expect(receipt.source == raw && receipt.originalAtlas.cells.count == 1)
        #expect(receipt.boundaries[0].parameterMap.offset == (try q(reversed ? 4 : -2, &usage)))
        #expect(receipt.boundaries[0].parameterMap.gain == (try q(reversed ? -6 : 6, &usage)))
        #expect(receipt.boundaries[1].parameterMap.offset == (try q(7, &usage)))
        let half = try q(0.5, &usage)
        let w = try receipt.denominator.evaluated(atU: half, v: half, usage: &usage)
        #expect(w == (try q(6.75, &usage)))
        let expected = [try q(1.25, &usage), ExactRationalCoefficient.one,
            try ExactRationalCoefficient.one.divided(by: q(3, &usage), usage: &usage)]
        for axis in 0..<3 {
            #expect(try receipt.homogeneous[axis].evaluated(atU: half, v: half, usage: &usage)
                .divided(by: w, usage: &usage) == expected[axis])
        }
        var product = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        for index in 0..<4 {
            let piece = try #require(receipt.originalAtlas.boundaryPieces[index].first)
            let weight = index < 2 ? piece.homogeneous[3]
                : try piece.homogeneous[3].exchangedAxes(usage: &usage)
            product = try product.multiplied(by: weight, usage: &usage)
        }
        #expect(receipt.denominator == product)
        #expect(receipt.originalAtlas.corners[0] == [.zero, .zero, .zero])
        #expect(receipt.originalAtlas.corners[3] == [try q(2, &usage), try q(2, &usage), .zero])
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedDifferentialAtlasKeepsExactQuotientsAndNormal() throws {
        var usage = Budget(); let raw = try source(usage: &usage)
        let receipt = try issue(raw, usage: &usage)
        let differential = try #require(OriginalCoonsRationalDifferentialAtlas.prepared(raw, usage: &usage))
        let cell = try #require(differential.cells.first)
        let half = try q(0.5, &usage)
        let w = try receipt.denominator.evaluated(atU: half, v: half, usage: &usage)
        let w2 = try w.multiplied(by: w, usage: &usage)
        let du = [try q(17, &usage).divided(by: q(12, &usage), usage: &usage),
            try q(2, &usage).divided(by: q(3, &usage), usage: &usage), .zero]
        let dv = [half, try q(16, &usage).divided(by: q(9, &usage), usage: &usage),
            try q(-2, &usage).divided(by: q(3, &usage), usage: &usage)]
        for axis in 0..<3 {
            #expect(try cell.tangentU[axis].evaluated(atU: half, v: half, usage: &usage)
                == du[axis].multiplied(by: w2, usage: &usage))
            #expect(try cell.tangentV[axis].evaluated(atU: half, v: half, usage: &usage)
                == dv[axis].multiplied(by: w2, usage: &usage))
            let i = (axis + 1) % 3, j = (axis + 2) % 3
            let expected = try du[i].multiplied(by: dv[j], usage: &usage)
                .subtracting(du[j].multiplied(by: dv[i], usage: &usage), usage: &usage)
                .multiplied(by: w2.multiplied(by: w2, usage: &usage), usage: &usage)
            #expect(try cell.normal[axis].evaluated(atU: half, v: half, usage: &usage) == expected)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func multiCellDifferentialSupportSurvivesNarrowIntersectionRefusal() throws {
        var usage = Budget(); let raw = try source(weighted: false, multiple: true, usage: &usage)
        let homogeneous = try #require(OriginalCoonsHomogeneousAtlas.prepared(raw, usage: &usage))
        let differential = try #require(OriginalCoonsRationalDifferentialAtlas.prepared(raw, usage: &usage))
        #expect(homogeneous.cells.count == 2 && differential.cells.count == 2)
        let half = try q(0.5, &usage)
        for (index, cell) in differential.cells.enumerated() {
            let u = try q(index == 0 ? 0.25 : 0.75, &usage)
            #expect(try cell.tangentU[0].evaluated(atU: u, v: half, usage: &usage) == q(2, &usage))
            #expect(try cell.tangentV[1].evaluated(atU: u, v: half, usage: &usage) == q(2, &usage))
            #expect(try cell.normal[2].evaluated(atU: u, v: half, usage: &usage) == q(4, &usage))
        }
        expectCode(.unsupportedCapability) { _ = try issue(raw, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func closedSubdomainsAndReleasedSourceOwnOriginalTraversal() throws {
        var usage = Budget()
        let receipt = try { () throws -> OriginalCoonsSurfacePolynomial in
            let raw = try source(reversed: true, usage: &usage)
            return try issue(raw, domain: box(0.25, 0.75, 0.25, 0.75), usage: &usage)
        }()
        #expect(receipt.domain == (try box(0.25, 0.75, 0.25, 0.75)))
        #expect(receipt.boundaries[0].traversal == receipt.source.vMinimumBoundary)
        var copy = receipt.boundaries[0].source
        copy.controlPoints[0] = .init(x: 100, y: 100, z: 100); copy.weights[0] = 100
        #expect(copy != receipt.boundaries[0].source)
        for pair in [(0.0, 0.0), (1.0, 1.0), (0.5, 0.0)] {
            let singleton = try issue(receipt.source, domain: box(pair.0, pair.0, pair.1, pair.1), usage: &usage)
            #expect(singleton.uDomain.lower == singleton.uDomain.upper && singleton.vDomain.lower == singleton.vDomain.upper)
        }
        for invalid in [try box(-Double.leastNonzeroMagnitude, 1), try box(0, 1.nextUp),
            try box(0, 1, -Double.leastNonzeroMagnitude, 1), try box(0, 1, 0, 1.nextUp)] {
            expectCode(.invalidInput) { _ = try issue(receipt.source, domain: invalid, usage: &usage) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactCornerToleranceAndStructuralDepthAreIndependent() throws {
        var usage = Budget()
        #expect(throws: GeometryConversionError.self) { _ = try source(cornerMismatch: true, usage: &usage) }
        let raw = try source(usage: &usage)
        expectCode(.resourceLimitExceeded) { _ = try issue(raw, depth: 0, usage: &usage) }
        #expect(try issue(raw, depth: 1, usage: &usage).source == raw)
        #expect(throws: GeometryConversionError.self) {
            _ = try OriginalCoonsSurfacePolynomial(source: raw, over: box(), remainingSourceDepth: 1,
                tolerance: .standard, usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveRelationUsesRawNativeParameterAndTwoDenominatorGuards() throws {
        var usage = Budget(); let raw = try source(usage: &usage); let coons = try issue(raw, usage: &usage)
        let curve = try OriginalRationalCurvePolynomial(source: coons.boundaries[0].source,
            spanIndex: 2, tolerance: tolerance, usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: curve.lowerParameter, upper: curve.upperParameter, usage: &usage)
        let receipt = try coons.curveRelation(curve: curve, curveDomain: domain, usage: &usage)
        guard case .curve(let retained) = receipt.target, case .rational(let laws) = receipt.relation.polynomials else {
            Issue.record("Coons CS lost original source ownership."); return
        }
        #expect(receipt.coons.source == raw && retained.source == curve.source)
        #expect(receipt.relation.variableCount == 3 && receipt.relation.domains[0] == domain)
        for point in [[-2.0, 0.0, 0.0], [1.0, 0.5, 0.0], [4.0, 1.0, 0.0]] {
            let values = try point.map { try q($0, &usage) }
            for law in laws.prefix(3) { #expect(try law.original.evaluated(at: values, usage: &usage).isZero) }
        }
        try checkGuards(receipt.relation, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceRelationKeepsAllFourOriginalParameters() throws {
        var usage = Budget(); let raw = try source(weighted: false, usage: &usage)
        let coons = try issue(raw, usage: &usage)
        let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [7, 7, 10, 10], vKnots: [-2, -2, 0, 0],
            controlPoints: [[.origin, .init(x: 2, y: 0, z: 0)], [.init(x: 0, y: 2, z: 0), .init(x: 2, y: 2, z: 0)]])
        let domain = try box(7, 10, -2, 0)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: native, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
        let owners = try prepared.originalIntersectionNativeSpans(over: domain, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
        let owner = try #require(owners.first)
        let surface = try OriginalRationalSurfacePolynomial(source: native, native: owner, domain: domain,
            view: .unitZ, tolerance: tolerance, usage: &usage)
        let receipt = try coons.surfaceRelation(surface: surface, usage: &usage)
        guard case .surface(let retained) = receipt.target, case .rational(let laws) = receipt.relation.polynomials else {
            Issue.record("Coons SSI lost original source ownership."); return
        }
        #expect(retained.source == native && receipt.relation.variableCount == 4)
        for point in [[0.0, 0.0, 7.0, -2.0], [0.5, 0.5, 8.5, -1.0], [1.0, 1.0, 10.0, 0.0]] {
            let values = try point.map { try q($0, &usage) }
            for law in laws.prefix(3) { #expect(try law.original.evaluated(at: values, usage: &usage).isZero) }
        }
        try checkGuards(receipt.relation, usage: &usage)
    }

    private func checkGuards(_ relation: OriginalPolynomialRelation, usage: inout Budget) throws {
        try RationalAlgebraStorage.retain(relation.predicate.original.maximumStackCount, of: Bool.self, usage: &usage)
        var scratch: [Bool] = []; scratch.reserveCapacity(relation.predicate.original.maximumStackCount)
        #expect(try relation.predicate.original.evaluate(signs: [.zero, .zero, .zero, .positive, .positive], scratch: &scratch, usage: &usage))
        #expect(try !relation.predicate.original.evaluate(signs: [.zero, .zero, .zero, .zero, .positive], scratch: &scratch, usage: &usage))
        #expect(try !relation.predicate.original.evaluate(signs: [.zero, .zero, .zero, .positive, .zero], scratch: &scratch, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func cumulativeWorkWordsAndCellAdmissionRefuseSourceAndAdapter() throws {
        var construction = Budget(); let raw = try source(usage: &construction)
        var measured = Budget(); let coons = try issue(raw, usage: &measured)
        var exact = Budget(maximumWork: measured.work, maximumWords: measured.words, maximumCells: measured.cells)
        #expect(try issue(raw, usage: &exact).homogeneous == coons.homogeneous)
        var work = Budget(maximumWork: measured.work - 1)
        #expect(throws: Failure.self) { _ = try issue(raw, usage: &work) }
        var words = Budget(maximumWords: measured.words - 1)
        #expect(throws: Failure.self) { _ = try issue(raw, usage: &words) }
        var cells = Budget(maximumCells: 0)
        #expect(throws: Failure.self) { _ = try issue(raw, usage: &cells) }
        let curve = try OriginalRationalCurvePolynomial(source: coons.boundaries[0].source,
            spanIndex: 2, tolerance: tolerance, usage: &construction)
        let domain = try OriginalRationalParameterDomain(lower: curve.lowerParameter, upper: curve.upperParameter, usage: &construction)
        var adapter = Budget(); _ = try coons.curveRelation(curve: curve, curveDomain: domain, usage: &adapter)
        var tight = Budget(maximumWords: adapter.words - 1)
        #expect(throws: Failure.self) { _ = try coons.curveRelation(curve: curve, curveDomain: domain, usage: &tight) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func entryAndFinalCallbackCancellationCannotPublish(adapter: Bool) async throws {
        var construction = Budget(); let raw = try source(usage: &construction)
        let coons = try issue(raw, usage: &construction)
        let curve = try OriginalRationalCurvePolynomial(source: coons.boundaries[0].source,
            spanIndex: 2, tolerance: tolerance, usage: &construction)
        let domain = try OriginalRationalParameterDomain(lower: curve.lowerParameter, upper: curve.upperParameter, usage: &construction)
        var measured = Budget()
        if adapter { _ = try coons.curveRelation(curve: curve, curveDomain: domain, usage: &measured) }
        else { _ = try issue(raw, usage: &measured) }
        for entry in [false, true] {
            let finalCall = measured.storageCalls
            let cancelled = try await Task {
                if entry { withUnsafeCurrentTask { $0?.cancel() } }
                var usage = Budget(cancelAtStorageCall: entry ? nil : finalCall)
                do {
                    if adapter { _ = try coons.curveRelation(curve: curve, curveDomain: domain, usage: &usage) }
                    else { _ = try issue(raw, usage: &usage) }
                    return false
                } catch is CancellationError { return true }
            }.value
            #expect(cancelled)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func differentialTypedStorageAndFinalCallbackCannotPublishPartialAtlas() async throws {
        var construction = Budget(); let raw = try source(usage: &construction)
        var measured = Budget()
        let atlas = try #require(OriginalCoonsRationalDifferentialAtlas.prepared(raw, usage: &measured))
        var exact = Budget(maximumWork: measured.work, maximumWords: measured.words, maximumCells: measured.cells)
        let repeated = try #require(OriginalCoonsRationalDifferentialAtlas.prepared(raw, usage: &exact))
        #expect(repeated.cells.first?.normal == atlas.cells.first?.normal)
        var tight = Budget(maximumWords: measured.words - 1)
        #expect(throws: Failure.self) {
            _ = try OriginalCoonsRationalDifferentialAtlas.prepared(raw, usage: &tight)
        }
        let finalCall = measured.storageCalls
        let cancelled = try await Task {
            var usage = Budget(cancelAtStorageCall: finalCall)
            do {
                _ = try OriginalCoonsRationalDifferentialAtlas.prepared(raw, usage: &usage)
                return false
            } catch is CancellationError { return true }
        }.value
        #expect(cancelled)
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &construction)
        var stripMeasured = Budget()
        let stripped = try OriginalCoonsRationalDifferentialAtlas.strip([u, u, .zero],
            alongU: true, upper: false, usage: &stripMeasured)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &construction)
        #expect(stripped == [one, one, .zero])
        var stripTight = Budget(maximumWords: stripMeasured.words - 1)
        #expect(throws: Failure.self) {
            _ = try OriginalCoonsRationalDifferentialAtlas.strip([u, u, .zero],
                alongU: true, upper: false, usage: &stripTight)
        }
    }
    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Original Coons issuer unexpectedly succeeded.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected original Coons failure: \(error)") }
    }
}
