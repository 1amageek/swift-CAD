import CADCore
@testable import CADGeometry
import Testing

@Suite("Full original rational projection")
struct IntersectionProjectionTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0, storage = 0
        var maximumWork = 10_000_000, maximumStorage = 10_000_000
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw exhausted() }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw exhausted() }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            throw rationalAlgebraFailure("Projection cannot invent geometric roots.")
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            throw rationalAlgebraFailure("Rational projection cannot invent coefficient roots.")
        }
        private func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                  message: "Projection test caller exhausted its independent admission.")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func principalZeroMatchesIndependentBivariateResultantIncludingRowSwaps() throws {
        var usage = Admission()
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let quadratic = try v.multiplied(by: v, usage: &usage).subtracting(u, usage: &usage)
        let linear = try v.adding(u, usage: &usage)
        let cubic = try quadratic.multiplied(by: v, usage: &usage).adding(one, usage: &usage)
        let weighted = try u.multiplied(by: quadratic, usage: &usage).adding(v, usage: &usage)
        for (a, b) in [(quadratic, linear), (linear, cubic), (weighted, cubic), (one, cubic)] {
            let expected = try ExactBivariateResultant().eliminatingV(a, b, usage: &usage)
            let first = try Polynomial.embedding(a, variableCount: 3, uCoordinate: 0, vCoordinate: 2, usage: &usage)
            let second = try Polynomial.embedding(b, variableCount: 3, uCoordinate: 0, vCoordinate: 2, usage: &usage)
            let actual = try ExactIntersectionSubresultants.principal(first, second, axis: 2, usage: &usage)
            #expect(actual.first == (try Polynomial.embedding(expected, variableCount: 3,
                uCoordinate: 0, vCoordinate: 2, usage: &usage)))
            for coefficient in actual {
                #expect(try coefficient.axisCoefficients(at: 2, usage: &usage).count <= 1)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func principalCoefficientsDetectRepeatedRootMultiplicity() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let one = try Polynomial.constant(variableCount: 2, value: .one, usage: &usage)
        let two = try Polynomial.constant(variableCount: 2, value: .natural(2, usage: &usage), usage: &usage)
        let four = try Polynomial.constant(variableCount: 2, value: .natural(4, usage: &usage), usage: &usage)
        let p = try y.multiplied(by: y, usage: &usage).subtracting(x, usage: &usage)
        let derivative = try p.differentiated(at: 1, usage: &usage)
        let simple = try ExactIntersectionSubresultants.principal(p, derivative, axis: 1, usage: &usage)
        #expect(simple == [try x.multiplied(by: four, usage: &usage).scaled(by: .one.negated, usage: &usage), two])
        let factor = try y.subtracting(one, usage: &usage)
        let repeated = try factor.multiplied(by: factor, usage: &usage)
            .multiplied(by: factor, usage: &usage)
        let multiple = try ExactIntersectionSubresultants.principal(repeated,
            repeated.differentiated(at: 1, usage: &usage), axis: 1, usage: &usage)
        #expect(multiple.count == 3 && multiple[0].isZero && multiple[1].isZero)
        #expect(multiple[2] == (try Polynomial.constant(variableCount: 2,
            value: .natural(3, usage: &usage), usage: &usage)))
    }

    @Test(.timeLimit(.minutes(1)))
    func reductaRetainDegreeDropNullificationAndPairContacts() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        // x*z^2 + y*z + x nullifies its entire z fiber only at x=y=0.
        let p = try x.multiplied(by: z.multiplied(by: z, usage: &usage), usage: &usage)
            .adding(y.multiplied(by: z, usage: &usage), usage: &usage).adding(x, usage: &usage)
        let q = try z.subtracting(one, usage: &usage)
        let projected = try ExactIntersectionProjection.prepare(sources: [p, q, y],
            variableCount: 3, axis: 2, usage: &usage)
        #expect(projected.sources == [p, q, y])
        #expect(projected.polynomials.contains(x) && projected.polynomials.contains(y))
        let contact = try x.scaled(by: .natural(2, usage: &usage), usage: &usage).adding(y, usage: &usage)
        #expect(projected.polynomials.contains(try contact.monic(usage: &usage)))
        for coefficient in projected.polynomials {
            #expect(!coefficient.isZero && !coefficient.isConstant)
            #expect(try coefficient.axisCoefficients(at: 2, usage: &usage).count == 1)
        }
        let duplicate = try ExactIntersectionProjection.prepare(sources: [p, p],
            variableCount: 3, axis: 2, usage: &usage)
        for (index, coefficient) in duplicate.polynomials.enumerated() {
            #expect(!duplicate.polynomials.dropFirst(index + 1).contains(coefficient))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedFactorQuotientsPreserveOriginalMultiplicityAndIndependentAdmission() throws {
        var construction = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &construction)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &construction)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &construction)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &construction)
        let common = try z.subtracting(x, usage: &construction)
        let first = try z.subtracting(y, usage: &construction)
        let second = try z.subtracting(one, usage: &construction)
        let product = try common.multiplied(by: first, usage: &construction)
        let repeated = try product.multiplied(by: product, usage: &construction)
            .scaled(by: .natural(2, usage: &construction), usage: &construction)
        // Repeated originals must normalize before any quotient can reuse that proof.
        // The overlapping products require further splitting and duplicate suppression.
        let sources = [repeated, try common.multiplied(by: second, usage: &construction),
            try first.multiplied(by: second, usage: &construction), product]
        var usage = Admission()
        let projection = try ExactIntersectionProjection.prepare(sources: sources,
            variableCount: 3, axis: 2, usage: &usage)
        var reference = Admission()
        let factors = try ExactIntersectionProjection.prepare(sources: [common, first, second],
            variableCount: 3, axis: 2, usage: &reference)
        #expect(projection.sources == sources)
        #expect(projection.polynomials.count == factors.polynomials.count)
        #expect(factors.polynomials.allSatisfy { projection.polynomials.contains($0) })
        let expected = [x, y, try x.subtracting(y, usage: &construction),
            try x.subtracting(one, usage: &construction), try y.subtracting(one, usage: &construction)]
        var normalized: [Polynomial] = []
        for polynomial in expected { normalized.append(try polynomial.monic(usage: &construction)) }
        #expect(normalized.allSatisfy { projection.polynomials.contains($0) })
        #expect(projection.polynomials.count == normalized.count)

        // The measured successful ledger is sufficient without a private allowance.
        var exact = Admission(maximumWork: usage.work, maximumStorage: usage.storage)
        let bounded = try ExactIntersectionProjection.prepare(sources: sources,
            variableCount: 3, axis: 2, usage: &exact)
        #expect(bounded.sources == sources && bounded.polynomials == projection.polynomials)
        #expect(exact.work == usage.work && exact.storage == usage.storage)
        var work = Admission(maximumWork: usage.work - 1, maximumStorage: usage.storage)
        do {
            _ = try ExactIntersectionProjection.prepare(sources: sources,
                variableCount: 3, axis: 2, usage: &work)
            Issue.record("Insufficient caller work cannot publish a shared-factor projection.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
        #expect(work.work <= work.maximumWork && work.storage <= work.maximumStorage)
        var storage = Admission(maximumWork: usage.work, maximumStorage: usage.storage - 1)
        do {
            _ = try ExactIntersectionProjection.prepare(sources: sources,
                variableCount: 3, axis: 2, usage: &storage)
            Issue.record("Insufficient caller storage cannot publish a shared-factor projection.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
        #expect(storage.work <= storage.maximumWork && storage.storage <= storage.maximumStorage)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactDivisionPreservesMultivariateIdentityAndRejectsRemainders() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let divisor = try x.adding(y, usage: &usage)
        let expected = try z.adding(x.multiplied(by: y, usage: &usage), usage: &usage)
        let product = try divisor.multiplied(by: expected, usage: &usage)
        #expect(try product.dividedExactly(by: divisor, usage: &usage) == expected)
        #expect(throws: KernelError.self) { _ = try z.dividedExactly(by: divisor, usage: &usage) }
        #expect(throws: KernelError.self) {
            _ = try product.dividedExactly(by: .zero(variableCount: 3), usage: &usage)
        }
        #expect(try Polynomial.zero(variableCount: 3).axisCoefficients(at: 2, usage: &usage).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func fullTowerRetainsCriticalLociAtEveryOriginalAxis() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let xy = try x.multiplied(by: x, usage: &usage).adding(y.multiplied(by: y, usage: &usage), usage: &usage)
        let source = try z.multiplied(by: z, usage: &usage).adding(xy, usage: &usage)
        let tower = try ExactIntersectionProjectionTower.prepare(sources: [source], variableCount: 3, usage: &usage)
        #expect(tower.levels.map(\.axis) == [2, 1, 0])
        #expect(tower.levels[0].sources == [source])
        #expect(tower.levels[0].polynomials.contains(xy))
        // The computational support removes repeated factors; the original law remains above.
        #expect(tower.levels[1].polynomials.contains(x))
        #expect(tower.levels[2].sources.contains(x))
        #expect(tower.levels[2].polynomials.isEmpty)
        // This retains the real isolated origin's critical loci; it does not call the complex surface a real surface.
        for level in tower.levels {
            for polynomial in level.polynomials {
                for axis in level.axis..<3 {
                    #expect(try polynomial.axisCoefficients(at: axis, usage: &usage).count == 1)
                }
            }
        }
        let empty = try ExactIntersectionProjectionTower.prepare(sources: [], variableCount: 3, usage: &usage)
        #expect(empty.levels.count == 3 && empty.levels.allSatisfy { $0.polynomials.isEmpty })
    }

    @Test(.timeLimit(.minutes(1)))
    func sparseHugeDegreeCannotOverflowProjectionAllocation() throws {
        var usage = Admission()
        let huge = try Polynomial.monomial(variableCount: 2, powers: (0, Int.max, 0, 0, 0),
            coefficient: .one, usage: &usage)
        #expect(throws: KernelError.self) {
            _ = try huge.axisCoefficients(at: 1, usage: &usage)
        }
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionProjectionTower.prepare(sources: [huge], variableCount: 2, usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidBindingAndIndependentLimitsRejectWholeProjection() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let p = try y.multiplied(by: y, usage: &usage).subtracting(x, usage: &usage)
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionProjection.prepare(sources: [p], variableCount: 2, axis: 2, usage: &usage)
        }
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionSubresultants.principal(p, .zero(variableCount: 3), axis: 1, usage: &usage)
        }
        var work = usage; work.maximumWork = work.work
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionProjection.prepare(sources: [p], variableCount: 2, axis: 1, usage: &work)
        }
        var storage = usage; storage.maximumStorage = storage.storage
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionProjection.prepare(sources: [p], variableCount: 2, axis: 1, usage: &storage)
        }
        #expect(storage.storage == usage.storage)
        var laterWork = usage; laterWork.maximumWork = laterWork.work + 20
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionProjection.prepare(sources: [p], variableCount: 2, axis: 1, usage: &laterWork)
        }
        #expect(laterWork.work > usage.work && laterWork.storage > usage.storage)
        var laterStorage = usage; laterStorage.maximumStorage = laterStorage.storage + 60
        #expect(throws: KernelError.self) {
            _ = try ExactIntersectionProjection.prepare(sources: [p], variableCount: 2, axis: 1, usage: &laterStorage)
        }
        #expect(laterStorage.work > usage.work && laterStorage.storage > usage.storage)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledProjectionCannotReturnAnUnchargedPreparedSet() async throws {
        let result = try await Task { () throws -> Int in
            var usage = Admission()
            let source = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
            let previous = usage.work
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ExactIntersectionProjection.prepare(sources: [source], variableCount: 2, axis: 1, usage: &usage)
                Issue.record("Cancelled projection cannot publish its set.")
            } catch is CancellationError { return usage.work - previous }
            return -1
        }.value
        #expect(result == 0)
    }
}
