import CADCore
@testable import CADGeometry
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AdmittedIntersectionRingTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        var maximumWork = 20_000_000
        var maximumStorage = 20_000_000
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else {
                throw failure("Work: used \(work), request \(count), limit \(maximumWork).")
            }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else {
                throw failure("Storage: used \(storage), request \(count), limit \(maximumStorage).")
            }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...24).contains(depth) else { throw failure() }
            try consumeExactWork(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws { throw failure() }
        private func failure(_ detail: String = "Cell depth exceeded its admitted domain.") -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Admitted original-ring test budget was exhausted. \(detail)")
        }
    }

    @Test
    func overflowMonomialsKeepExactArithmeticAndCanonicalHashIdentity() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 12, at: 8, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 12, at: 9, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 12, at: 11, usage: &usage)
        let product = try x.multiplied(by: y, usage: &usage).multiplied(by: z, usage: &usage)
        let differentiated = try product.differentiated(at: 9, usage: &usage)
        #expect(differentiated == (try x.multiplied(by: z, usage: &usage)))
        #expect(try product.dividedExactly(by: y, usage: &usage) == differentiated)
        let coefficients = try product.axisCoefficients(at: 11, usage: &usage)
        #expect(coefficients.count == 2)
        #expect(coefficients[0].isZero)
        #expect(coefficients[1] == (try x.multiplied(by: y, usage: &usage)))
        var values = Array(repeating: ExactRationalCoefficient.one, count: 12)
        values[9] = try .natural(3, usage: &usage)
        values[11] = try .natural(7, usage: &usage)
        #expect(try product.evaluated(at: values, usage: &usage) == .natural(21, usage: &usage))
        let same = try Polynomial.coordinate(variableCount: 10, at: 9, usage: &usage).lifted(to: 12, usage: &usage)
        #expect(try y.matches(same, usage: &usage))
        let sum = try y.adding(same, usage: &usage)
        #expect(try sum.dividedExactly(by: y, usage: &usage) == .constant(variableCount: 12,
            value: .natural(2, usage: &usage), usage: &usage))
        #expect(throws: KernelError.self) { try z.lowered(to: 11, usage: &usage) }
    }

    @Test
    func originalBivariateEmbeddingAndInjectionKeepHigherCoordinates() throws {
        var usage = Admission()
        let law = ExactBivariatePolynomial([
            try .init(u: 2, v: 0): .one,
            try .init(u: 0, v: 1): .one.negated
        ])
        let embedded = try Polynomial.embedding(law, variableCount: 12,
            uCoordinate: 10, vCoordinate: 11, usage: &usage)
        var values = Array(repeating: ExactRationalCoefficient.zero, count: 12)
        values[10] = try .natural(3, usage: &usage)
        values[11] = try .natural(9, usage: &usage)
        #expect(try embedded.evaluated(at: values, usage: &usage).isZero)
        let original = try Polynomial.embedding(law, variableCount: 2,
            uCoordinate: 0, vCoordinate: 1, usage: &usage)
        #expect(embedded == (try original.remapped(to: 12, coordinates: [10, 11], usage: &usage)))
        #expect(throws: KernelError.self) {
            try original.remapped(to: 12, coordinates: [10, 10], usage: &usage)
        }
        let backwards = try embedded.remapped(to: 12, coordinates: Array((0..<12).reversed()), usage: &usage)
        let low = try backwards.lowered(to: 2, usage: &usage)
        #expect(try low.evaluated(at: [.natural(9, usage: &usage), .natural(3, usage: &usage)], usage: &usage).isZero)
    }

    @Test
    func higherCoordinateIdealReductionDoesNotEraseLeadingPowers() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 12, at: 9, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 12, at: 11, usage: &usage)
        let first = try y.subtracting(x, usage: &usage)
        let second = try y.multiplied(by: y, usage: &usage).subtracting(x, usage: &usage)
        let ideal = try ExactIntersectionIdeal.prepare(equations: [first, second],
            variableCount: 12, usage: &usage)
        let expected = try x.multiplied(by: x, usage: &usage).subtracting(x, usage: &usage)
        #expect(ideal.reducedBasis.contains(first))
        #expect(ideal.reducedBasis.contains(expected))
        #expect(try ExactIntersectionGroebnerBasis.reduced(second, by: ideal.reducedBasis, usage: &usage).isZero)
        #expect(ideal.classification == .positiveDimensional)
    }

    @Test
    func gcdAndSquareFreeSupportCrossTheMachineWordBoundary() throws {
        var usage = Admission()
        for axis in [UInt.bitWidth - 1, UInt.bitWidth, UInt.bitWidth + 1] {
            let count = axis + 1
            let x = try Polynomial.coordinate(variableCount: count, at: 0, usage: &usage)
            let z = try Polynomial.coordinate(variableCount: count, at: axis, usage: &usage)
            let one = try Polynomial.constant(variableCount: count, value: .one, usage: &usage)
            let two = try Polynomial.constant(variableCount: count,
                value: .natural(2, usage: &usage), usage: &usage)
            let first = try z.multiplied(by: z, usage: &usage)
                .multiplied(by: x.adding(one, usage: &usage), usage: &usage)
            let second = try z.multiplied(by: x.adding(two, usage: &usage), usage: &usage)
            #expect(try ExactIntersectionPolynomialGCD.gcd(first, second, usage: &usage) == z)
            #expect(try ExactIntersectionPolynomialGCD.squareFree(first, usage: &usage)
                == z.multiplied(by: x.adding(one, usage: &usage), usage: &usage))
        }
    }

    @Test
    func completeProjectionAndAffineIncidenceReachCoordinateTwelve() throws {
        var usage = Admission()
        let law = try Polynomial.coordinate(variableCount: 12, at: 11, usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: nil, upper: nil, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law],
            variableCount: 12, exactDomains: Array(repeating: domain, count: 12),
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        #expect(partition.solutionCells.count == 1)
        let index = try #require(partition.solutionCells.first)
        #expect(partition.cells[index].dimension == 11)
        #expect(partition.cells[index].coordinates.count == 12)
        #expect(try OriginalIntersectionFieldEvaluation.evaluated(law,
            context: partition.cells[index].context, coordinates: partition.cells[index].coordinates,
            maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) == .zero)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
            maximumDepth: 24, usage: &usage)
        #expect(incidence.attachments.count == 1)
        #expect(try incidence.connectedComponents(usage: &usage).components.count == 1)
        #expect(try #require(incidence.closures.first).source.variableCount == 12)
    }

    @Test
    func quantifiedTruthRetainsTenFreeCoordinatesAndOriginalSuffix() throws {
        var usage = Admission()
        let law = try Polynomial.coordinate(variableCount: 11, at: 10, usage: &usage)
        let program = try ExactIntersectionBooleanProgram(polynomialCount: 1,
            instructions: [.atom(0, .zero)], usage: &usage)
        let exists = try ExactIntersectionQuantifiedCells.prepare(polynomials: [law], program: program,
            variableCount: 11, freeVariableCount: 10, quantifiers: [.exists], maximumDepth: 24, usage: &usage)
        #expect(exists.freeCells.count == 1)
        #expect(exists.freeCells[0].value)
        #expect(try #require(exists.freePartition).tower.variableCount == 10)
        let forall = try ExactIntersectionQuantifiedCells.prepare(polynomials: [law], program: program,
            variableCount: 11, freeVariableCount: 10, quantifiers: [.forall], maximumDepth: 24, usage: &usage)
        #expect(forall.freeCells.count == 1)
        #expect(!forall.freeCells[0].value)
    }

    @Test
    func nonmonicClosureRetainsFiveCoordinatesAndBothOriginalEnds() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 5, at: 3, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 5, at: 4, usage: &usage)
        let one = try Polynomial.constant(variableCount: 5, value: .one, usage: &usage)
        let law = try x.multiplied(by: y, usage: &usage).subtracting(one, usage: &usage)
        let zero = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let half = try ExactRationalCoefficient.one.divided(by: two, usage: &usage)
        let domains = [zero, zero, zero,
            try OriginalRationalParameterDomain(lower: .one, upper: two, usage: &usage),
            try OriginalRationalParameterDomain(lower: half, upper: .one, usage: &usage)]
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law],
            variableCount: 5, exactDomains: domains,
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let interior = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let closure = try OriginalIntersectionCellClosure.prepare(partition: partition,
            cellIndex: interior, allowAffineProofs: false, maximumDepth: 24, usage: &usage)
        guard case .finiteBranch(let proof) = closure.proof else {
            Issue.record("The whole nonmonic branch must retain its exact nonvanishing leading-coefficient proof.")
            return
        }
        #expect(proof.sectionWitnesses.contains { $0.nonvanishingLeading != nil })
        #expect(proof.sectionWitnesses.compactMap { $0.nonvanishingLeading }.allSatisfy {
            $0.exclusions.count == 1
        })
        #expect(closure.freePartition.tower.variableCount == 5)
        #expect(closure.includedCells.count == 3)
        let context = try OriginalSingularFieldContext(usage: &usage)
        for point in [[ExactRationalCoefficient.zero, .zero, .zero, .one, .one],
            [.zero, .zero, .zero, two, half]] {
            let values = try point.map {
                try OriginalSingularFieldElement.constant($0, in: context, maximumDepth: 24, usage: &usage)
            }
            var member = false
            for index in closure.includedCells {
                let condition = try OriginalIntersectionCellCondition(partition: closure.freePartition,
                    cellIndex: index, usage: &usage)
                if try condition.contains(context: context, coordinates: values, maximumDepth: 24, usage: &usage) {
                    member = true; break
                }
            }
            #expect(member)
        }
    }

    @Test
    func nonvanishingLeadingIsProvedOverIrrationalOriginalCuts() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let squared = try x.multiplied(by: x, usage: &usage)
        func cut(_ value: Int, usage: inout Admission) throws -> Polynomial {
            try squared.subtracting(.constant(variableCount: 2,
                value: .natural(value, usage: &usage), usage: &usage), usage: &usage)
        }
        let leading = try cut(2, usage: &usage)
        let lowerCut = try cut(3, usage: &usage)
        let upperCut = try cut(5, usage: &usage)
        let law = try leading.multiplied(by: y, usage: &usage).subtracting(
            .constant(variableCount: 2, value: .one, usage: &usage), usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: .one,
            upper: .natural(3, usage: &usage), usage: &usage)
        let all = try OriginalRationalParameterDomain(lower: nil, upper: nil, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law],
            variableCount: 2, exactDomains: [domain, all], partitionPolynomials: [lowerCut, upperCut],
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let index = try #require(partition.solutionCells.first {
            let cell = partition.cells[$0], offset = partition.partitionSignOffset
            return cell.dimension == 1 && cell.signs[offset] == .positive && cell.signs[offset + 1] == .negative
        })
        let closure = try OriginalIntersectionCellClosure.prepare(partition: partition,
            cellIndex: index, maximumDepth: 24, usage: &usage)
        guard case .finiteBranch(let proof) = closure.proof else {
            Issue.record("Irrational cuts require whole original nonvanishing proof.")
            return
        }
        let witness = try #require(proof.sectionWitnesses.compactMap { $0.nonvanishingLeading }.first)
        #expect(witness.exclusions.count == 2)
        #expect(witness.exclusions.allSatisfy { if case .beforeLower = $0.side { true } else { false } })
        #expect(closure.includedCells.count == 3)
        for end in closure.includedCells where end != index {
            #expect(partition.cells[end].dimension == 0)
            #expect(try OriginalIntersectionFieldEvaluation.evaluated(law,
                context: partition.cells[end].context, coordinates: partition.cells[end].coordinates,
                maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) == .zero)
        }
    }

    @Test
    func invalidOverflowPowersAndIndependentLimitsFailExplicitly() throws {
        var usage = Admission()
        var invalid = Array(repeating: 0, count: 12)
        invalid[10] = -1; invalid[11] = 1
        #expect(throws: KernelError.self) {
            try Polynomial.monomial(variableCount: 12, powers: invalid, coefficient: .one, usage: &usage)
        }
        var maximum = Array(repeating: 0, count: 12)
        maximum[11] = Int.max
        let source = try Polynomial.monomial(variableCount: 12, powers: maximum,
            coefficient: .one, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 12, at: 11, usage: &usage)
        #expect(throws: KernelError.self) { try source.multiplied(by: z, usage: &usage) }
        var exhaustedStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) {
            try Polynomial.coordinate(variableCount: 12, at: 11, usage: &exhaustedStorage)
        }
        #expect(exhaustedStorage.storage == 0)
        var exhaustedWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) {
            try Polynomial.coordinate(variableCount: 12, at: 11, usage: &exhaustedWork)
        }
        #expect(exhaustedWork.storage == 0)
    }
}
