import CADCore
@testable import CADGeometry
import Testing

@Suite("Monotone original projection factor refinement", .timeLimit(.minutes(1)))
struct IntersectionProjectionFactorRefinementTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private enum AdmissionFailure: Error, Equatable { case work, storage, depth }
    private struct Admission: RationalAlgebraAdmitting {
        var maximumWork = 80_000_000
        var maximumStorage = 268_435_456
        var work = 0
        var storage = 0
        var cells = 0
        var allowCells = false
        var cancelAtWork: Int?
        var cancelAtStorage: Int?
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw AdmissionFailure.work }
            work += count
            if work == cancelAtWork { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw AdmissionFailure.storage }
            storage += count
            if storage == cancelAtStorage { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func visitExactCell(depth: Int) throws {
            guard allowCells, depth >= 0, depth <= 24 else { throw AdmissionFailure.depth }
            cells += 1
        }
    }
    private struct Fixture: Sendable {
        let sources: [Polynomial]
        let factors: [Polynomial]
        let expected: [Polynomial]
    }
    private func fixture(usage: inout Admission) throws -> Fixture {
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let sum = try x.adding(y, usage: &usage)
        let early = try z.subtracting(x, usage: &usage)
        let a = try z.subtracting(y, usage: &usage)
        let b = try z.subtracting(one, usage: &usage)
        let c = try z.adding(one, usage: &usage)
        let d = try z.subtracting(sum, usage: &usage)
        let ab = try a.multiplied(by: b, usage: &usage)
        let repeated = try ab.multiplied(by: ab, usage: &usage).scaled(by: two, usage: &usage)
        let ac = try a.multiplied(by: c, usage: &usage)
        let bcd = try b.multiplied(by: c, usage: &usage).multiplied(by: d, usage: &usage)
        let duplicate = try ab.scaled(by: two.negated, usage: &usage)
        // Splitting ab/ac appends b and c, which still share factors with bcd.
        // The earlier factor is coprime to all originals and all exact divisors.
        let sources = [early, repeated, ac, bcd, duplicate,
            try Polynomial.zero(variableCount: 3), one]
        // Full projection of the five monic linear z laws consists of their
        // constant terms and pair-contact differences; leading/derivative
        // coefficients and the contact between z-1 and z+1 are constants.
        let rawExpected = [x, y, sum,
            try x.subtracting(y, usage: &usage),
            try x.subtracting(one, usage: &usage), try x.adding(one, usage: &usage),
            try y.subtracting(one, usage: &usage), try y.adding(one, usage: &usage),
            try sum.subtracting(one, usage: &usage), try sum.adding(one, usage: &usage)]
        var expected: [Polynomial] = []
        for value in rawExpected { expected.append(try value.monic(usage: &usage)) }
        return Fixture(sources: sources, factors: [early, a, b, c, d], expected: expected)
    }

    @Test(arguments: [false, true])
    func overlappingProductsRetainTheCompleteKnownProjection(reverseSources: Bool) throws {
        var preparation = Admission()
        let laws = try fixture(usage: &preparation)
        let sources: [Polynomial] = reverseSources ? Array(laws.sources.reversed()) : laws.sources
        var usage = Admission()
        let projection = try ExactIntersectionProjection.prepare(sources: sources, variableCount: 3, axis: 2, usage: &usage)
        #expect(projection.sources == sources && projection.axis == 2)
        #expect(projection.polynomials.count == laws.expected.count)
        for expected in laws.expected { #expect(projection.polynomials.contains(expected)) }
        for (index, polynomial) in projection.polynomials.enumerated() {
            #expect(!polynomial.isZero && !polynomial.isConstant)
            #expect(!projection.polynomials.dropFirst(index + 1).contains(polynomial))
            let coefficients = try polynomial.axisCoefficients(at: 2, usage: &preparation)
            #expect(coefficients.count == 1)
        }
        var reference = Admission()
        let separated = try ExactIntersectionProjection.prepare(sources: laws.factors,
            variableCount: 3, axis: 2, usage: &reference)
        #expect(separated.polynomials.count == projection.polynomials.count)
        for polynomial in separated.polynomials { #expect(projection.polynomials.contains(polynomial)) }
        #expect(usage.cells == 0 && reference.cells == 0)
    }

    @Test func closedOriginalDomainsRetainTheEntireSelectedCommonLine() throws {
        var preparation = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &preparation)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &preparation)
        let one = try Polynomial.constant(variableCount: 2, value: .one, usage: &preparation)
        let first = try x.multiplied(by: y, usage: &preparation)
        let second = try x.multiplied(by: y.subtracting(one, usage: &preparation), usage: &preparation)
        let sources = [first, second]
        let domains = [
            try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &preparation),
            try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &preparation)]
        var usage = Admission(); usage.allowCells = true
        let partition = try OriginalRationalIntersectionCells.prepare(equations: sources, variableCount: 2,
            exactDomains: domains, maximumDepth: 24, usage: &usage)
        #expect(partition.equations == sources && partition.domains == domains)
        #expect(partition.solutionCells.count == 3)
        var dimensions: [Int] = []
        for index in partition.solutionCells {
            let cell = partition.cells[index]
            #expect(cell.signs[0] == .zero && cell.signs[1] == .zero)
            dimensions.append(cell.dimension)
        }
        // x*y=x*(y-1)=0 forces x=0 for every real y; the closed y domain
        // contains both endpoints and the complete open segment between them.
        #expect(dimensions.sorted() == [0, 0, 1])
        #expect(usage.cells > 0)
    }

    @Test func exactCallerLimitsAndInvalidSourceRingRemainExplicit() throws {
        var preparation = Admission()
        let laws = try fixture(usage: &preparation)
        var measured = Admission()
        let result = try ExactIntersectionProjection.prepare(sources: laws.sources,
            variableCount: 3, axis: 2, usage: &measured)
        var exact = Admission(); exact.maximumWork = measured.work; exact.maximumStorage = measured.storage
        let bounded = try ExactIntersectionProjection.prepare(sources: laws.sources,
            variableCount: 3, axis: 2, usage: &exact)
        #expect(bounded.sources == result.sources && bounded.polynomials == result.polynomials)
        var noWork = Admission(); noWork.maximumWork = measured.work - 1
        #expect(throws: AdmissionFailure.work) {
            try ExactIntersectionProjection.prepare(sources: laws.sources, variableCount: 3, axis: 2, usage: &noWork)
        }
        #expect(noWork.work <= noWork.maximumWork)
        var noStorage = Admission(); noStorage.maximumStorage = measured.storage - 1
        #expect(throws: AdmissionFailure.storage) {
            try ExactIntersectionProjection.prepare(sources: laws.sources, variableCount: 3, axis: 2, usage: &noStorage)
        }
        #expect(noStorage.storage <= noStorage.maximumStorage)
        let wrongRing = try Polynomial.zero(variableCount: 2)
        #expect(throws: KernelError.self) {
            try ExactIntersectionProjection.prepare(sources: [wrongRing], variableCount: 3, axis: 2, usage: &preparation)
        }
        #expect(throws: KernelError.self) {
            try ExactIntersectionProjection.prepare(sources: laws.sources, variableCount: 3, axis: 3, usage: &preparation)
        }
    }

    @Test(arguments: [0, 1, 2])
    func callerCancellationCannotPublishARefinedProjection(callback: Int) async throws {
        var preparation = Admission()
        let laws = try fixture(usage: &preparation)
        var measured = Admission()
        _ = try ExactIntersectionProjection.prepare(sources: laws.sources, variableCount: 3, axis: 2, usage: &measured)
        let finalWork = measured.work, finalStorage = measured.storage
        let cancelled = try await Task {
            var usage = Admission()
            if callback == 0 { withUnsafeCurrentTask { $0?.cancel() } }
            if callback == 1 { usage.cancelAtWork = finalWork }
            if callback == 2 { usage.cancelAtStorage = finalStorage }
            do {
                _ = try ExactIntersectionProjection.prepare(sources: laws.sources, variableCount: 3, axis: 2, usage: &usage)
                Issue.record("A cancelled projection refinement published a completed set.")
                return false
            } catch is CancellationError {
                if callback == 0 { return usage.work == 0 && usage.storage == 0 }
                return callback == 1 ? usage.work == finalWork : usage.storage == finalStorage
            }
        }.value
        #expect(cancelled)
    }
}
