import CADCore
@testable import CADGeometry
import Testing

@Suite("Original denominator guarded equation normalization")
struct NativeGuardedNormalizationTests {
    @Test(.timeLimit(.minutes(1)))
    func retainedDivisionsExcludeOnlyGuardZeroAndPreserveOriginalRank() throws {
        var usage = OriginalRelationUsage(consumeWork: { _ in }, retainStorage: { _ in },
            visitCell: { _ in }, visitCoefficientCell: { _ in })
        let one = try ExactIntersectionPolynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let half = try one.scaled(by: .originalDouble(0.5, usage: &usage), usage: &usage)
        let t = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let guardPolynomial = try t.adding(one, usage: &usage)
        let root = try t.subtracting(half, usage: &usage)
        let repeated = try root.multiplied(by: root, usage: &usage)
        let first = try repeated.multiplied(by: guardPolynomial, usage: &usage)
            .multiplied(by: guardPolynomial, usage: &usage)
        let u = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 1, usage: &usage).subtracting(half, usage: &usage)
        let v = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: 2, usage: &usage).subtracting(half, usage: &usage)
        let equations = [first, u, v, try .zero(variableCount: 3)]
        let receipt = try OriginalGuardedIntersectionEquations.prepare(equations: equations,
            denominatorGuards: [guardPolynomial], variableCount: 3, usage: &usage)
        #expect(receipt.originalEquations == equations && receipt.denominatorGuards == [guardPolynomial])
        #expect(receipt.normalizedEquations == [repeated, u, v, try .zero(variableCount: 3)])
        #expect(receipt.divisions.count == 2)
        for division in receipt.divisions {
            #expect(try division.factor.multiplied(by: division.quotient, usage: &usage).matches(division.dividend, usage: &usage))
            #expect(try division.factor.multiplied(by: division.guardQuotient, usage: &usage).matches(receipt.guardProduct, usage: &usage))
        }
        let station = try ExactRationalCoefficient.originalDouble(0.5, usage: &usage)
        let guardZero = [ExactRationalCoefficient.one.negated, station, station]
        #expect(try receipt.guardProduct.evaluated(at: guardZero, usage: &usage).isZero)
        #expect(try first.evaluated(at: guardZero, usage: &usage).isZero)
        #expect(try !repeated.evaluated(at: guardZero, usage: &usage).isZero)
        let domains = try [OriginalRationalParameterDomain(.init(lower: -2, upper: 1), usage: &usage),
            OriginalRationalParameterDomain(.init(lower: 0, upper: 1), usage: &usage),
            OriginalRationalParameterDomain(.init(lower: 0, upper: 1), usage: &usage)]
        let raw = try OriginalRationalIntersectionStrata.prepare(equations: equations, variableCount: 3,
            exactDomains: domains, nonzeroPolynomials: [guardPolynomial], thomEncoding: true,
            pruneExcludedPrefixes: true, maximumDepth: 32, usage: &usage)
        let normalizedIdeal = try ExactIntersectionIdeal.prepare(equations: receipt.normalizedEquations,
            variableCount: 3, usage: &usage)
        let normalized = try OriginalRationalIntersectionStrata.prepare(ideal: normalizedIdeal,
            exactDomains: domains, nonzeroPolynomials: receipt.denominatorGuards, thomEncoding: true,
            originalRankEquations: receipt.originalEquations, pruneExcludedPrefixes: true, maximumDepth: 32, usage: &usage)
        #expect(normalized.jacobian.equations == equations)
        #expect(raw.partition.solutionCells.count == 1 && normalized.partition.solutionCells.count == 1)
        #expect(raw.strata.first?.originalJacobianRank == 2 && normalized.strata.first?.originalJacobianRank == 2)
        for partition in [raw.partition, normalized.partition] {
            let index = try #require(partition.solutionCells.first)
            let cell = partition.cells[index]
            #expect(cell.dimension == 0)
            for coordinate in cell.coordinates {
                let target = try OriginalSingularFieldElement.constant(station, in: cell.context, maximumDepth: 32, usage: &usage)
                #expect(try coordinate.subtracting(target, maximumDepth: 32, usage: &usage)
                    .sign(maximumDepth: 32, usage: &usage) == .zero)
            }
        }
    }
}
