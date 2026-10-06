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
                throw failure("Work: used \(work), request \(count), limit \(maximumWork), storage \(storage)")
            }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else {
                throw failure("Storage: used \(storage), request \(count), limit \(maximumStorage)")
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

    private struct CoefficientAdmission: RationalAlgebraAdmitting {
        var depths: [Int] = []
        var maximumDepth = 12
        mutating func consumeExactWork(_ count: Int) throws {}
        mutating func retainExactStorage(_ count: Int) throws {}
        mutating func visitExactCell(depth: Int) throws {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "A coefficient root was relabeled as a parameter root.")
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...maximumDepth).contains(depth) else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "A coefficient root exceeded its independent inherited depth.")
            }
            depths.append(depth)
        }
    }

    @Test
    func rootUnionEqualityRetainsItsIndependentCoefficientAdmission() throws {
        var construction = Admission()
        let context = try OriginalSingularFieldContext(usage: &construction)
        let law = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [.constant(.one.negated, in: context, maximumDepth: 0, usage: &construction),
                .constant(.one, in: context, maximumDepth: 0, usage: &construction)],
            maximumDepth: 0, usage: &construction)
        let two = try ExactRationalCoefficient.natural(2, usage: &construction)
        var first = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .zero, upper: two, excludesLower: false, excludesUpper: false, depth: 7),
            admissionDomain: .coefficient(maximumDepth: 12))
        var second = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .zero, upper: two, excludesLower: false, excludesUpper: false, depth: 9),
            admissionDomain: .coefficient(maximumDepth: 12))
        var usage = CoefficientAdmission()
        #expect(try OriginalRationalIntersectionCells.ordered(&first, &second, maximumDepth: 0, usage: &usage) == 0)
        let refined = try first.refinedOnce(maximumDepth: 0, forSeparation: true, usage: &usage)
        #expect(refined.isolation.depth == 9 && refined.isolation.lower == .one && refined.isolation.upper == .one)
        let value = try refined.value(maximumDepth: 0, usage: &usage)
        #expect(value.context.depth == 0 && value.context.coefficientDepth == 9)
        #expect(!usage.depths.isEmpty && usage.depths.allSatisfy { $0 >= 9 && $0 <= 12 })
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
    func quantifiedLeafRetainsUnknownIrrelevantAtomsAndRequiredFailures() throws {
        var construction = Admission()
        let rational = try OriginalSingularFieldContext(usage: &construction)
        let two = try ExactRationalCoefficient.natural(2, usage: &construction)
        let source = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &construction),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &construction),
                .constant(.one, in: rational, maximumDepth: 24, usage: &construction)], maximumDepth: 24, usage: &construction)
        let root = OriginalSingularFieldRoot(polynomial: source,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let value = try root.value(maximumDepth: 24, usage: &construction)
        let q = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &construction)
        let g = try q.multiplied(by: q, usage: &construction).subtracting(
            .constant(variableCount: 1, value: two, usage: &construction), usage: &construction)
        let zero = try Polynomial.constant(variableCount: 1, value: .zero, usage: &construction)
        for expected in [false, true] {
            let program = try ExactIntersectionBooleanProgram(polynomialCount: 2,
                instructions: [.atom(0, expected ? .zero : .positive), .atom(1, .positive), expected ? .or : .and],
                usage: &construction)
            var scratch: [Bool?] = []; scratch.reserveCapacity(program.maximumStackCount)
            var bounded = Admission(maximumStorage: 1)
            let leaf = try ExactIntersectionQuantifiedCells.evaluateLeaf(polynomials: [zero, g], program: program,
                context: value.context, coordinates: [value], inheritedSigns: [nil, nil], maximumDepth: 24,
                scratch: &scratch, usage: &bounded)
            #expect(leaf.value == expected && leaf.signs[0] == .zero && leaf.signs[1] == nil)
            #expect(bounded.storage == 1)
            #expect(try program.partialValue(signs: leaf.signs, scratch: &scratch, usage: &bounded) == expected)
        }
        let required = try ExactIntersectionBooleanProgram(polynomialCount: 2,
            instructions: [.atom(0, .zero), .atom(1, .positive), .and], usage: &construction)
        var scratch: [Bool?] = []; scratch.reserveCapacity(required.maximumStackCount)
        var bounded = Admission(maximumStorage: 1)
        #expect(throws: KernelError.self) {
            try ExactIntersectionQuantifiedCells.evaluateLeaf(polynomials: [zero, g], program: required,
                context: value.context, coordinates: [value], inheritedSigns: [nil, nil], maximumDepth: 24,
                scratch: &scratch, usage: &bounded)
        }
        let universal = try ExactIntersectionBooleanProgram(polynomialCount: 2,
            instructions: [.atom(0, .positive), .atom(0, .negative), .or, .atom(1, .negative), .or], usage: &construction)
        let proof = try ExactIntersectionQuantifiedCells.prepare(polynomials: [q, g], program: universal,
            variableCount: 1, freeVariableCount: 0, quantifiers: [.forall], maximumDepth: 24, usage: &construction)
        #expect(proof.closedTruth == true && proof.tower.levels[0].sources == [q, g])
        let decision = try #require(proof.decisions.last)
        #expect(decision.children.count == decision.totalChildCount && decision.totalChildCount == 7)
        #expect(decision.children.contains { $0.signs[1] == nil })
        for child in decision.children {
            #expect(try universal.partialValue(signs: child.signs, scratch: &scratch, usage: &construction) == child.value)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func nonmonicClosureRetainsFiveCoordinatesAndBothOriginalEnds(forceQuantified: Bool, negativeLeading: Bool) throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 5, at: 3, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 5, at: 4, usage: &usage)
        let one = try Polynomial.constant(variableCount: 5, value: .one, usage: &usage)
        let law = try x.multiplied(by: y, usage: &usage).subtracting(one, usage: &usage)
        let zero = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let half = try ExactRationalCoefficient.one.divided(by: two, usage: &usage)
        let lowerX = negativeLeading ? two.negated : .one
        let upperX = negativeLeading ? .one.negated : two
        let lowerY = negativeLeading ? .one.negated : half
        let upperY = negativeLeading ? half.negated : .one
        let domains = [zero, zero, zero,
            try OriginalRationalParameterDomain(lower: lowerX, upper: upperX, usage: &usage),
            try OriginalRationalParameterDomain(lower: lowerY, upper: upperY, usage: &usage)]
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law],
            variableCount: 5, exactDomains: domains,
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let interior = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let closure: OriginalIntersectionCellClosure
        let forcedIncidence: OriginalRationalIntersectionIncidence?
        if forceQuantified {
            let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
                allowAffineClosureProofs: false, allowFiniteBranchClosureProofs: false,
                maximumDepth: 24, usage: &usage)
            closure = try #require(incidence.closures.first { $0.source.cellIndex == interior })
            forcedIncidence = incidence
            let attachments = incidence.attachments.filter { $0.sourceCellIndex == interior }
            #expect(partition.solutionCells.count == 3)
            #expect(Set(attachments.map(\.targetCellIndex)) == Set(partition.solutionCells))
            #expect(Set(attachments.map(\.refinedTargetCellIndex)) == Set(closure.includedCells))
            let components = try incidence.connectedComponents(usage: &usage)
            #expect(components.components.count == 1)
            #expect(Set(try #require(components.components.first).cellIndexes) == Set(partition.solutionCells))
        } else {
            forcedIncidence = nil
            closure = try OriginalIntersectionCellClosure.prepare(partition: partition,
                cellIndex: interior, allowAffineProofs: false, maximumDepth: 24, usage: &usage)
        }
        if forceQuantified {
            guard case .quantified(let proof) = closure.proof else {
                Issue.record("The actual forced general closure path was replaced by a sufficient theorem."); return
            }
            #expect(proof.tower.variableCount == 7 && proof.freeVariableCount == 5)
            #expect(proof.quantifiers.count == 2)
            #expect(closure.candidateCoordinateMap == [0,1,2,6,7])
            #expect(closure.predicateReduction?.candidateCoordinate == 7)
            #expect(closure.freeSupportReduction?.candidateCoordinate == 4)
            #expect(proof.freeDomainEquations == closure.source.polynomials.enumerated()
                .filter { closure.source.signs[$0.offset] == .zero && !$0.element.isZero }.map(\.element))
            #expect(proof.freePartition?.cells.allSatisfy { $0.admissionDepth >= partition.cells[interior].admissionDepth } == true)
            #expect(closure.includedCells.count >= 3)
            #expect(closure.freePartition.domains.count == domains.count)
            #expect(!closure.freePartition.excludedDomainPrefixes.isEmpty)
            for receipt in closure.freePartition.excludedDomainPrefixes {
                #expect(receipt.lowerEndpoint ? receipt.sign == .negative : receipt.sign == .positive)
                #expect(closure.freePartition.cells[receipt.parentCell].coordinates.count == receipt.axis + 1)
            }
            let eliminated = try #require(closure.predicateReduction).equationIndex
            for index in closure.source.signs.indices where closure.source.signs[index] == .zero && index != eliminated {
                #expect(!proof.tower.levels[0].sources[index].isZero)
            }
            var noWork = Admission(maximumWork: 0)
            #expect(throws: KernelError.self) {
                try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
                    allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &noWork)
            }
            var noStorage = Admission(maximumStorage: 0)
            #expect(throws: KernelError.self) {
                try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: interior,
                    allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &noStorage)
            }
        } else {
            guard case .finiteBranch(let proof) = closure.proof else {
                Issue.record("The whole nonmonic branch must retain its exact nonvanishing leading-coefficient proof."); return
            }
            #expect(proof.sectionWitnesses.contains { $0.nonvanishingLeading != nil })
            #expect(proof.sectionWitnesses.compactMap { $0.nonvanishingLeading }.allSatisfy { $0.exclusions.count == 1 })
            #expect(closure.includedCells.count == 3)
        }
        #expect(closure.freePartition.tower.variableCount == 5)
        let context = try OriginalSingularFieldContext(usage: &usage)
        for point in [[ExactRationalCoefficient.zero, .zero, .zero, lowerX, upperY],
            [.zero, .zero, .zero, upperX, lowerY]] {
            let values = try point.map {
                try OriginalSingularFieldElement.constant($0, in: context, maximumDepth: 24, usage: &usage)
            }
            var member = false
            if let incidence = forcedIncidence {
                for index in partition.solutionCells where partition.cells[index].dimension == 0 {
                    let condition = try OriginalIntersectionCellCondition(partition: partition, cellIndex: index, usage: &usage)
                    if try condition.contains(context: context, coordinates: values, maximumDepth: 24, usage: &usage) {
                        member = incidence.attachments.contains { $0.sourceCellIndex == interior && $0.targetCellIndex == index }
                        break
                    }
                }
            } else {
                for index in closure.includedCells {
                    let condition = try OriginalIntersectionCellCondition(partition: closure.freePartition,
                        cellIndex: index, usage: &usage)
                    if try condition.contains(context: context, coordinates: values, maximumDepth: 24, usage: &usage) {
                        member = true; break
                    }
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
    func cancelledForcedQuantifiedClosurePublishesNoProof() async throws {
        var usage = Admission()
        let domain = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
            exactDomains: [domain], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let index = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var admission = Admission()
            do {
                _ = try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: index,
                    allowAffineProofs: false, allowFiniteBranchProofs: false, maximumDepth: 24, usage: &admission)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
    }

    @Test
    func rootSeparationReusesOriginalSturmAuthorityAndInheritedDepth() throws {
        var usage = Admission()
        let law = ExactBivariatePolynomial([try .init(u: 2, v: 0): .one,
            try .init(u: 0, v: 0): try .natural(2, usage: &usage).negated])
        let root = try ExactAlgebraicRealRoot(polynomial: law,
            isolation: .init(lower: .one, upper: .natural(2, usage: &usage),
                isRationalStation: false, isolationDepth: 7,
                excludesLowerEndpoint: false, excludesUpperEndpoint: false), usage: &usage)
        let width = try ExactRationalCoefficient.originalDouble(0.25, usage: &usage)
        let separated = try root.refinedForSeparation(maximumWidth: width, maximumDepth: 24, usage: &usage)
        let localized = try root.refined(maximumWidth: width, maximumDepth: 24, usage: &usage)
        let sturm = try ExactUnivariateSturmSequence(law, usage: &usage)
        for result in [separated, localized] {
            #expect(result.polynomial == root.polynomial)
            #expect(result.isolation.isolationDepth >= 7 && result.isolation.isolationDepth <= 24)
            #expect(try sturm.count(lower: result.isolation.lower, upper: result.isolation.upper,
                excludesLower: result.isolation.excludesLowerEndpoint,
                excludesUpper: result.isolation.excludesUpperEndpoint, usage: &usage) == 1)
            #expect(!(try result.isolation.upper.subtracting(result.isolation.lower, usage: &usage)
                .subtracting(width, usage: &usage)).isPositive)
        }
        #expect(separated.isolation.lower.canonicalDenominatorWords.reduce(0) { $0 + $1.nonzeroBitCount } == 1)
        #expect(separated.isolation.upper.canonicalDenominatorWords.reduce(0) { $0 + $1.nonzeroBitCount } == 1)
        #expect(throws: KernelError.self) {
            try root.refinedForSeparation(maximumWidth: width, maximumDepth: 7, usage: &usage)
        }
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try root.refinedForSeparation(maximumWidth: width, maximumDepth: 24, usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try root.refinedForSeparation(maximumWidth: width, maximumDepth: 24, usage: &noStorage) }
    }

    @Test
    func identicalRationalRootIsolationReusesItsOriginalReceipt() throws {
        var construction = Admission()
        let two = try ExactRationalCoefficient.natural(2, usage: &construction)
        let law = ExactBivariatePolynomial([try .init(u: 2, v: 0): .one,
            try .init(u: 0, v: 0): two.negated])
        let root = try ExactAlgebraicRealRoot(polynomial: law,
            isolation: .init(lower: .one, upper: two, isRationalStation: false,
                isolationDepth: 7, excludesLowerEndpoint: false, excludesUpperEndpoint: false), usage: &construction)
        var noStorage = Admission(maximumStorage: 0)
        let retained = try root.retainingIsolation(root.isolation, usage: &noStorage)
        #expect(retained.polynomial == root.polynomial && retained.isolation.lower == root.isolation.lower)
        #expect(retained.isolation.upper == root.isolation.upper && retained.isolation.isolationDepth == 7)
        #expect(noStorage.storage == 0 && noStorage.work > 0)
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try root.retainingIsolation(root.isolation, usage: &noWork) }
        var coefficient = CoefficientAdmission()
        var domain = OriginalScalarRootDomainAdmission(base: coefficient, domain: .coefficient(maximumDepth: 12))
        _ = try root.retainingIsolation(root.isolation, usage: &domain)
        coefficient = domain.base
        #expect(coefficient.depths == [7])
        var tooShallow = OriginalScalarRootDomainAdmission(base: CoefficientAdmission(maximumDepth: 6), domain: .coefficient(maximumDepth: 6))
        #expect(throws: KernelError.self) { try root.retainingIsolation(root.isolation, usage: &tooShallow) }
        let wider = ExactUnivariateRootIsolator.Root(lower: .zero, upper: two, isRationalStation: false,
            isolationDepth: 7, excludesLowerEndpoint: false, excludesUpperEndpoint: false)
        #expect(throws: KernelError.self) { try root.retainingIsolation(wider, usage: &construction) }
        let excluded = ExactUnivariateRootIsolator.Root(lower: .one, upper: two, isRationalStation: false,
            isolationDepth: 7, excludesLowerEndpoint: true, excludesUpperEndpoint: false)
        #expect(throws: KernelError.self) { try root.retainingIsolation(excluded, usage: &noStorage) }
    }

    @Test(arguments: [false, true])
    func affineRootSeparationReusesAncestorDepthWithoutReset(negativeSlope: Bool) throws {
        var usage = Admission()
        let rational = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let law = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.one, in: rational, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let ancestor = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let x = try ancestor.value(maximumDepth: 24, usage: &usage)
        let offset = try OriginalSingularFieldElement.constant(.originalDouble(-0.03125, usage: &usage),
            in: x.context, maximumDepth: 24, usage: &usage)
        let affine = try (negativeSlope ? x.negated(maximumDepth: 24, usage: &usage) : x)
            .adding(offset, maximumDepth: 24, usage: &usage)
        let derivedLaw = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [affine.negated(maximumDepth: 24, usage: &usage),
                .constant(.one, in: x.context, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let four = try ExactRationalCoefficient.natural(4, usage: &usage)
        let derived = OriginalSingularFieldRoot(polynomial: derivedLaw,
            isolation: .init(lower: four.negated, upper: four, excludesLower: false, excludesUpper: false, depth: 24))
        let first = try derived.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &usage)
        let result = try first.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &usage)
        #expect(result.polynomial.context === derivedLaw.context)
        #expect(result.isolation.depth == 24)
        #expect(result.retainedRationalImageAncestor!.isolation.isolationDepth > ancestor.isolation.depth)
        #expect(result.retainedRationalImageAncestor!.isolation.isolationDepth <= 24)
        let sequence = try OriginalSingularFieldSturm(derivedLaw, maximumDepth: 24, usage: &usage)
        #expect(try sequence.count(lower: result.isolation.lower, upper: result.isolation.upper,
            excludesLower: result.isolation.excludesLower, excludesUpper: result.isolation.excludesUpper,
            maximumDepth: 24, usage: &usage) == 1)
        #expect(!(try result.isolation.upper.subtracting(result.isolation.lower, usage: &usage)
            .subtracting(.originalDouble(0.5, usage: &usage), usage: &usage)).isPositive)
        #expect(try affine.subtracting(.constant(result.isolation.lower, in: x.context,
            maximumDepth: 24, usage: &usage), maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) != .negative)
        #expect(try affine.subtracting(.constant(result.isolation.upper, in: x.context,
            maximumDepth: 24, usage: &usage), maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) != .positive)
        #expect(throws: KernelError.self) { try derived.refinedOnce(maximumDepth: 23, forSeparation: true, usage: &usage) }
        let exhaustedAncestor = ancestor.retainingIsolation(.init(lower: .one, upper: two,
            excludesLower: false, excludesUpper: false, depth: 24))
        let exhaustedX = try exhaustedAncestor.value(maximumDepth: 24, usage: &usage)
        let exhaustedLaw = try OriginalSingularFieldPolynomial(context: exhaustedX.context,
            coefficients: [exhaustedX.negated(maximumDepth: 24, usage: &usage),
                .constant(.one, in: exhaustedX.context, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let exhausted = OriginalSingularFieldRoot(polynomial: exhaustedLaw,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 24))
        #expect(throws: KernelError.self) { try exhausted.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &usage) }
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try derived.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try derived.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &noStorage) }
    }

    @Test(arguments: [false, true], [false, true])
    func linearFractionalRootSeparationContractsOriginalAncestorPole(negativeImage: Bool, endpointPole: Bool) throws {
        var usage = Admission()
        let rational = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let law = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.one, in: rational, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let ancestor = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: endpointPole ? .one : .zero, upper: two,
                excludesLower: endpointPole, excludesUpper: false, depth: 7))
        let x = try ancestor.value(maximumDepth: 24, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: x.context, maximumDepth: 24, usage: &usage)
        let image = try x.adding(one, maximumDepth: 24, usage: &usage)
            .divided(by: x.subtracting(one, maximumDepth: 24, usage: &usage), maximumDepth: 24, usage: &usage)
        let value = try negativeImage ? image.negated(maximumDepth: 24, usage: &usage) : image
        let derivedLaw = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [value.negated(maximumDepth: 24, usage: &usage), one], maximumDepth: 24, usage: &usage)
        let sixteen = try ExactRationalCoefficient.natural(16, usage: &usage)
        let derived = OriginalSingularFieldRoot(polynomial: derivedLaw,
            isolation: .init(lower: sixteen.negated, upper: sixteen,
                excludesLower: false, excludesUpper: false, depth: 24))
        let first = try derived.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &usage)
        let result = try first.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &usage)
        let retainedAncestor = try #require(result.retainedRationalImageAncestor)
        #expect((try retainedAncestor.isolation.lower.subtracting(.one, usage: &usage)).isPositive)
        #expect(retainedAncestor.isolation.isolationDepth > 7 && retainedAncestor.isolation.isolationDepth <= 24)
        #expect(result.isolation.depth == 24 && result.polynomial.context === derivedLaw.context)
        let sequence = try OriginalSingularFieldSturm(derivedLaw, maximumDepth: 24, usage: &usage)
        #expect(try sequence.count(lower: result.isolation.lower, upper: result.isolation.upper,
            excludesLower: result.isolation.excludesLower, excludesUpper: result.isolation.excludesUpper,
            maximumDepth: 24, usage: &usage) == 1)
        #expect(negativeImage ? result.isolation.upper.isNegative : result.isolation.lower.isPositive)
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try derived.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try derived.refinedOnce(maximumDepth: 24, forSeparation: true, usage: &noStorage) }
    }

    @Test
    func orderedFieldIdentitiesRetainAlgebraicBuffersAndUndefinedSourceDenominators() throws {
        var usage = Admission()
        let rational = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let law = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.one, in: rational, maximumDepth: 24, usage: &usage)],
            maximumDepth: 24, usage: &usage)
        let root = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let value = try root.value(maximumDepth: 24, usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: value.context, maximumDepth: 24, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: value.context, maximumDepth: 24, usage: &usage)
        var noStorage = Admission(maximumStorage: 0)
        let results = try [value.adding(zero, maximumDepth: 24, usage: &noStorage),
            zero.adding(value, maximumDepth: 24, usage: &noStorage),
            value.multiplied(by: one, maximumDepth: 24, usage: &noStorage),
            one.multiplied(by: value, maximumDepth: 24, usage: &noStorage),
            value.divided(by: one, maximumDepth: 24, usage: &noStorage)]
        for result in results {
            #expect(result.context === value.context)
            #expect(try result.subtracting(value, maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) == .zero)
        }
        #expect(noStorage.storage == 0)
        #expect(throws: KernelError.self) { try zero.divided(by: zero, maximumDepth: 24, usage: &usage) }
        guard case .extended(let zeroLaw, _) = zero.storage,
            case .extended(let numerator, _) = value.storage else { Issue.record("An algebraic field lost its extended source laws."); return }
        let undefined = OriginalSingularFieldElement(context: value.context, storage: .extended(numerator, zeroLaw))
        #expect(throws: KernelError.self) {
            try zero.multiplied(by: undefined, maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage)
        }
    }

    @Test
    func structuralConstantPublicationRejectsFinalCallbackCancellation() async throws {
        struct CallbackAdmission: RationalAlgebraAdmitting {
            var cancelOnWork = false
            var cancelAtStorage = 0
            var storageCallbacks = 0
            mutating func consumeExactWork(_ count: Int) throws {
                if cancelOnWork { withUnsafeCurrentTask { $0?.cancel() } }
            }
            mutating func retainExactStorage(_ count: Int) throws {
                storageCallbacks += 1
                if storageCallbacks == cancelAtStorage { withUnsafeCurrentTask { $0?.cancel() } }
            }
            mutating func visitExactCell(depth: Int) throws {}
            mutating func visitCoefficientCell(depth: Int) throws {}
        }
        var construction = Admission()
        let context = try OriginalSingularFieldContext(usage: &construction)
        let borrowRefused = await Task { () -> Bool in
            var usage = CallbackAdmission(cancelOnWork: true)
            do {
                _ = try OriginalSingularFieldElement.constant(.one, in: context, maximumDepth: 24, usage: &usage)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(borrowRefused)
        let constructionRefused = await Task { () -> Bool in
            var usage = CallbackAdmission(cancelAtStorage: 2)
            do {
                _ = try OriginalSingularFieldContext(usage: &usage)
                return false
            } catch is CancellationError { return usage.storageCallbacks == 2 }
            catch { return false }
        }.value
        #expect(constructionRefused)
    }

    @Test
    func immutableStructuralConstantsRetainOnlyTheirFieldOwner() async throws {
        var construction = Admission()
        let rational = try OriginalSingularFieldContext(usage: &construction)
        let two = try ExactRationalCoefficient.natural(2, usage: &construction)
        let law = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &construction),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &construction),
                .constant(.one, in: rational, maximumDepth: 24, usage: &construction)], maximumDepth: 24, usage: &construction)
        let root = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let value = try root.value(maximumDepth: 24, usage: &construction)
        var noStorage = Admission(maximumStorage: 0)
        for context in [rational, value.context] {
            for constant in [ExactRationalCoefficient.zero, .one] {
                let retained = try OriginalSingularFieldElement.constant(constant, in: context,
                    maximumDepth: 24, usage: &noStorage)
                #expect(retained.context === context)
                #expect(try retained.rationalValue(usage: &noStorage) == constant)
                let sign = try retained.sign(maximumDepth: 24, usage: &noStorage)
                #expect(sign == (constant.isZero ? .zero : .positive))
            }
        }
        let rationalOne = try OriginalSingularFieldElement.constant(.one, in: rational, maximumDepth: 24, usage: &construction)
        let embedded = try rationalOne.embedded(in: value.context, maximumDepth: 24, usage: &noStorage)
        #expect(embedded.context === value.context && noStorage.storage == 0 && noStorage.work > 0)
        #expect(throws: KernelError.self) { try OriginalSingularFieldElement.constant(two, in: value.context,
            maximumDepth: 24, usage: &noStorage) }
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try OriginalSingularFieldElement.constant(.one, in: value.context,
            maximumDepth: 24, usage: &noWork) }
        #expect(throws: KernelError.self) { try rationalOne.embedded(in: value.context, maximumDepth: 24, usage: &noWork) }
        var constructionRefused = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try OriginalSingularFieldContext(usage: &constructionRefused) }
        #expect(throws: KernelError.self) { try root.value(maximumDepth: 24, usage: &constructionRefused) }
        if case .extended(let zero, let unit) = value.context.constantAuthority {
            #expect(zero.isZero && unit.degree == 0)
            #expect(zero.context === rational && unit.context === rational)
        } else { Issue.record("An extended structural authority lost its parent owner.") }
        let cancelled = await Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            var usage = Admission()
            do {
                _ = try OriginalSingularFieldElement.constant(.one, in: value.context, maximumDepth: 24, usage: &usage)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
    }

    @Test
    func canonicalFieldDivisionRetainsExactQuotientRemainderAndFailures() throws {
        var usage = Admission()
        let rational = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let source = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.one, in: rational, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let root = OriginalSingularFieldRoot(polynomial: source,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let x = try root.value(maximumDepth: 24, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: x.context, maximumDepth: 24, usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: x.context, maximumDepth: 24, usage: &usage)
        let divisor = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [x.negated(maximumDepth: 24, usage: &usage), one], maximumDepth: 24, usage: &usage)
        let quotient = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [one, zero, one], maximumDepth: 24, usage: &usage)
        let remainder = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [x], maximumDepth: 24, usage: &usage)
        let dividend = try divisor.multiplied(by: quotient, maximumDepth: 24, usage: &usage)
            .adding(remainder, maximumDepth: 24, usage: &usage)
        let result = try dividend.divided(by: divisor, maximumDepth: 24, usage: &usage)
        #expect(result.quotient.context === dividend.context && result.remainder.context === dividend.context)
        #expect(result.quotient.degree == quotient.degree && result.remainder.degree < divisor.degree)
        let difference = try result.quotient.multiplied(by: divisor, maximumDepth: 24, usage: &usage)
            .adding(result.remainder, maximumDepth: 24, usage: &usage)
            .subtracting(dividend, maximumDepth: 24, usage: &usage)
        #expect(difference.isZero)
        #expect(try result.remainder.subtracting(remainder, maximumDepth: 24, usage: &usage).isZero)
        #expect(try result.quotient.subtracting(quotient, maximumDepth: 24, usage: &usage).isZero)
        var noWork = Admission(maximumWork: 0)
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try dividend.divided(by: divisor, maximumDepth: 24, usage: &noWork) }
        #expect(throws: KernelError.self) { try dividend.divided(by: divisor, maximumDepth: 24, usage: &noStorage) }
        #expect(throws: KernelError.self) { try dividend.divided(by: divisor, maximumDepth: 0, usage: &usage) }
        let zeroDivisor = try OriginalSingularFieldPolynomial(context: x.context, coefficients: [], maximumDepth: 24, usage: &usage)
        #expect(throws: KernelError.self) { try dividend.divided(by: zeroDivisor, maximumDepth: 24, usage: &usage) }
        let foreign = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(.one, in: rational, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        #expect(throws: KernelError.self) { try dividend.divided(by: foreign, maximumDepth: 24, usage: &usage) }
    }

    @Test
    func polynomialUnitProductsRetainSourceBuffersAndAdmission() throws {
        var construction = Admission()
        let rational = try OriginalSingularFieldContext(usage: &construction)
        let two = try ExactRationalCoefficient.natural(2, usage: &construction)
        let source = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &construction),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &construction),
                .constant(.one, in: rational, maximumDepth: 24, usage: &construction)], maximumDepth: 24, usage: &construction)
        let root = OriginalSingularFieldRoot(polynomial: source,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let x = try root.value(maximumDepth: 24, usage: &construction)
        let one = try OriginalSingularFieldElement.constant(.one, in: x.context, maximumDepth: 24, usage: &construction)
        let unit = try OriginalSingularFieldPolynomial(context: x.context, coefficients: [one],
            maximumDepth: 24, usage: &construction)
        let original = try OriginalSingularFieldPolynomial(context: x.context, coefficients: [x, one],
            maximumDepth: 24, usage: &construction)
        var noStorage = Admission(maximumStorage: 0)
        let left = try unit.multiplied(by: original, maximumDepth: 24, usage: &noStorage)
        let right = try original.multiplied(by: unit, maximumDepth: 24, usage: &noStorage)
        #expect(left.context === original.context && right.context === original.context)
        #expect(left.degree == original.degree && right.degree == original.degree && noStorage.storage == 0)
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try original.multiplied(by: unit, maximumDepth: 24, usage: &noWork) }
        let inherited = try OriginalSingularFieldPolynomial(context: x.context, coefficients: [one, x],
            maximumDepth: 24, usage: &construction)
        #expect(throws: KernelError.self) { try inherited.multiplied(by: unit, maximumDepth: 0, usage: &construction) }
        let oneLaw = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(.one, in: rational, maximumDepth: 24, usage: &construction)],
            maximumDepth: 24, usage: &construction)
        let zeroLaw = try OriginalSingularFieldPolynomial(context: rational, coefficients: [],
            maximumDepth: 24, usage: &construction)
        let undefined = OriginalSingularFieldElement(context: x.context, storage: .extended(oneLaw, zeroLaw))
        let undefinedLaw = try OriginalSingularFieldPolynomial(context: x.context, coefficients: [undefined, one],
            maximumDepth: 24, usage: &construction)
        let retainedUndefined = try undefinedLaw.multiplied(by: unit, maximumDepth: 24, usage: &construction)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: x.context, maximumDepth: 24, usage: &construction)
        #expect(throws: KernelError.self) { try retainedUndefined.evaluated(at: zero, maximumDepth: 24, usage: &construction)
            .sign(maximumDepth: 24, usage: &construction) }
    }

    @Test
    func nonlinearFieldRootLinearSignsRetainOriginalSturmAuthority() throws {
        var usage = Admission()
        let rational = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let original = try OriginalSingularFieldPolynomial(context: rational,
            coefficients: [.constant(two.negated, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.zero, in: rational, maximumDepth: 24, usage: &usage),
                .constant(.one, in: rational, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let ancestors = try OriginalSingularFieldRoot.allRealRoots(original, inheritedDepth: 7, maximumDepth: 24, usage: &usage)
        let ancestor = try #require(ancestors.last)
        let x = try ancestor.value(maximumDepth: 24, usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: x.context, maximumDepth: 24, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: x.context, maximumDepth: 24, usage: &usage)
        let source = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [x.negated(maximumDepth: 24, usage: &usage), zero, one], maximumDepth: 24, usage: &usage)
        let roots = try OriginalSingularFieldRoot.allRealRoots(source, inheritedDepth: ancestor.isolation.depth,
            maximumDepth: 24, usage: &usage)
        let positive = try #require(roots.last)
        let negative = try #require(roots.first)
        let againstParent = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [x.negated(maximumDepth: 24, usage: &usage), one], maximumDepth: 24, usage: &usage)
        let againstOne = try OriginalSingularFieldPolynomial(context: x.context,
            coefficients: [one.negated(maximumDepth: 24, usage: &usage), one], maximumDepth: 24, usage: &usage)
        for _ in 0..<3 {
            #expect(try positive.sign(of: againstParent, maximumDepth: 24, usage: &usage) == .negative)
            #expect(try positive.sign(of: againstOne, maximumDepth: 24, usage: &usage) == .positive)
            #expect(try negative.sign(of: againstParent, maximumDepth: 24, usage: &usage) == .negative)
        }
        #expect(positive.polynomial.context === source.context && positive.polynomial.degree == source.degree)
        #expect(positive.isolation.depth >= ancestor.isolation.depth)
        #expect(throws: KernelError.self) {
            try positive.sign(of: againstParent, maximumDepth: positive.isolation.depth - 1, usage: &usage)
        }
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try positive.sign(of: againstParent, maximumDepth: 24, usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try positive.sign(of: againstParent, maximumDepth: 24, usage: &noStorage) }
    }

    @Test
    func commonWholeLawCountsReuseOriginalSturmWithoutMergingDistinctRoots() throws {
        var usage = Admission()
        let context = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let four = try ExactRationalCoefficient.natural(4, usage: &usage)
        func constant(_ value: ExactRationalCoefficient, usage: inout Admission) throws -> OriginalSingularFieldElement {
            try .constant(value, in: context, maximumDepth: 24, usage: &usage)
        }
        let quadratic = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [constant(two.negated, usage: &usage), constant(.zero, usage: &usage),
                constant(.one, usage: &usage)], maximumDepth: 24, usage: &usage)
        let quartic = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [constant(four.negated, usage: &usage), constant(.zero, usage: &usage),
                constant(.zero, usage: &usage), constant(.zero, usage: &usage), constant(.one, usage: &usage)],
            maximumDepth: 24, usage: &usage)
        let firstRoots = try OriginalSingularFieldRoot.allRealRoots(quadratic, inheritedDepth: 7,
            maximumDepth: 24, usage: &usage)
        let secondRoots = try OriginalSingularFieldRoot.allRealRoots(quartic, inheritedDepth: 9,
            maximumDepth: 24, usage: &usage)
        #expect(firstRoots.count == 2 && secondRoots.count == 2)
        var first = try #require(firstRoots.last), second = try #require(secondRoots.last)
        #expect(first.polynomial.degree == 2 && second.polynomial.degree == 4)
        #expect(try OriginalRationalIntersectionCells.ordered(&first, &second, maximumDepth: 24, usage: &usage) == 0)
        #expect(first.isolation.depth == second.isolation.depth && first.isolation.depth >= 9)
        #expect(try OriginalRationalIntersectionCells.ordered(&second, &first, maximumDepth: 24, usage: &usage) == 0)
        var distinct = try #require(firstRoots.first)
        #expect(try OriginalRationalIntersectionCells.ordered(&distinct, &second, maximumDepth: 24, usage: &usage) == -1)
        let inside = OriginalSingularFieldRoot.Isolation(lower: .one, upper: two,
            excludesLower: false, excludesUpper: false, depth: first.isolation.depth)
        #expect(try first.countOriginalRoots(in: inside, maximumDepth: 24, usage: &usage) == 1)
        let before = OriginalSingularFieldRoot.Isolation(lower: first.isolation.lower, upper: .one,
            excludesLower: first.isolation.excludesLower, excludesUpper: false, depth: first.isolation.depth)
        #expect(try first.countOriginalRoots(in: before, maximumDepth: 24, usage: &usage) == 0)
        let expanded = try OriginalSingularFieldRoot.Isolation(lower: first.isolation.lower.subtracting(.one, usage: &usage),
            upper: first.isolation.upper, excludesLower: false, excludesUpper: first.isolation.excludesUpper,
            depth: first.isolation.depth)
        #expect(throws: KernelError.self) { try first.countOriginalRoots(in: expanded, maximumDepth: 24, usage: &usage) }
        let reset = OriginalSingularFieldRoot.Isolation(lower: inside.lower, upper: inside.upper,
            excludesLower: inside.excludesLower, excludesUpper: inside.excludesUpper, depth: first.isolation.depth - 1)
        #expect(throws: KernelError.self) { try first.countOriginalRoots(in: reset, maximumDepth: 24, usage: &usage) }
        if first.isolation.excludesLower {
            let changedEndpoint = OriginalSingularFieldRoot.Isolation(lower: first.isolation.lower, upper: first.isolation.upper,
                excludesLower: false, excludesUpper: first.isolation.excludesUpper, depth: first.isolation.depth)
            #expect(throws: KernelError.self) { try first.countOriginalRoots(in: changedEndpoint, maximumDepth: 24, usage: &usage) }
        }
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try first.countOriginalRoots(in: inside, maximumDepth: 24, usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try first.countOriginalRoots(in: inside, maximumDepth: 24, usage: &noStorage) }
    }

    @Test(arguments: [false, true])
    func overlappingLinearRootOrderUsesOriginalParentSigns(negativeLeading: Bool) throws {
        var usage = Admission()
        let context = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let law = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [.constant(two.negated, in: context, maximumDepth: 24, usage: &usage),
                .constant(.zero, in: context, maximumDepth: 24, usage: &usage),
                .constant(.one, in: context, maximumDepth: 24, usage: &usage)], maximumDepth: 24, usage: &usage)
        let ancestor = OriginalSingularFieldRoot(polynomial: law,
            isolation: .init(lower: .one, upper: two, excludesLower: false, excludesUpper: false, depth: 7))
        let x = try ancestor.value(maximumDepth: 24, usage: &usage)
        let offset = try OriginalSingularFieldElement.constant(.originalDouble(0.03125, usage: &usage),
            in: x.context, maximumDepth: 24, usage: &usage)
        let orientation = try OriginalSingularFieldElement.constant(negativeLeading ? .one.negated : .one,
            in: x.context, maximumDepth: 24, usage: &usage)
        func linear(_ value: OriginalSingularFieldElement, usage: inout Admission) throws -> OriginalSingularFieldPolynomial {
            try .init(context: x.context, coefficients: [value.negated(maximumDepth: 24, usage: &usage)
                .multiplied(by: orientation, maximumDepth: 24, usage: &usage), orientation], maximumDepth: 24, usage: &usage)
        }
        let firstLaw = try linear(x.subtracting(offset, maximumDepth: 24, usage: &usage), usage: &usage)
        let secondLaw = try linear(x.adding(offset, maximumDepth: 24, usage: &usage), usage: &usage)
        var first = OriginalSingularFieldRoot(polynomial: firstLaw,
            isolation: .init(lower: .zero, upper: two, excludesLower: false, excludesUpper: false, depth: 10))
        var second = OriginalSingularFieldRoot(polynomial: secondLaw,
            isolation: .init(lower: .zero, upper: two, excludesLower: false, excludesUpper: false, depth: 14))
        #expect(try OriginalRationalIntersectionCells.ordered(&first, &second, maximumDepth: 24, usage: &usage) == -1)
        #expect(try OriginalRationalIntersectionCells.ordered(&second, &first, maximumDepth: 24, usage: &usage) == 1)
        #expect(first.isolation.depth == 10 && second.isolation.depth == 14)
        #expect(first.isolation.lower == .zero && second.isolation.upper == two)
        var equal = first.retainingIsolation(.init(lower: .one, upper: two,
            excludesLower: false, excludesUpper: false, depth: 17))
        #expect(try OriginalRationalIntersectionCells.ordered(&first, &equal, maximumDepth: 24, usage: &usage) == 0)
        #expect(first.isolation.depth == 17 && equal.isolation.depth == 17)
        #expect(first.isolation.lower == .one && first.isolation.upper == two)
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try OriginalRationalIntersectionCells.ordered(&first, &second, maximumDepth: 24, usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try OriginalRationalIntersectionCells.ordered(&first, &second, maximumDepth: 24, usage: &noStorage) }
    }

    @Test
    func rootUnionPreservesAnAlreadyNarrowBracketAtItsDepthLimit() throws {
        var usage = Admission()
        let context = try OriginalSingularFieldContext(usage: &usage)
        func constant(_ value: ExactRationalCoefficient, usage: inout Admission) throws -> OriginalSingularFieldElement {
            try .constant(value, in: context, maximumDepth: 24, usage: &usage)
        }
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let quadratic = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [constant(two.negated, usage: &usage), constant(.zero, usage: &usage), constant(.one, usage: &usage)],
            maximumDepth: 24, usage: &usage)
        let linear = try OriginalSingularFieldPolynomial(context: context,
            coefficients: [constant(two.negated, usage: &usage), constant(.one, usage: &usage)],
            maximumDepth: 24, usage: &usage)
        let lower = try ExactRationalCoefficient.natural(7, usage: &usage).divided(by: .natural(5, usage: &usage), usage: &usage)
        let upper = try ExactRationalCoefficient.natural(3, usage: &usage).divided(by: two, usage: &usage)
        var narrow = OriginalSingularFieldRoot(polynomial: quadratic,
            isolation: .init(lower: lower, upper: upper, excludesLower: false, excludesUpper: false, depth: 24))
        var broad = try OriginalSingularFieldRoot(polynomial: linear,
            isolation: .init(lower: two.negated, upper: .natural(3, usage: &usage), excludesLower: false, excludesUpper: false, depth: 0))
        #expect(try OriginalRationalIntersectionCells.ordered(&narrow, &broad, maximumDepth: 24, usage: &usage) == -1)
        #expect(narrow.isolation.depth == 24 && narrow.isolation.lower == lower && narrow.isolation.upper == upper)
        #expect(broad.isolation.lower == two && broad.isolation.upper == two)
    }

    @Test
    func originalMagnitudeDivisionReconstructsMultiLimbInputsAndCanonicalFractions() throws {
        var usage = Admission()
        let numerators: [[UInt32]] = [[UInt32.max, UInt32.max], [7, 0, 1], [0, 0, UInt32.max], [13, 2, 3, 4]]
        let divisors: [[UInt32]] = [[1], [3], [UInt32.max], [0, 1], [1, 1], [UInt32.max, UInt32.max]]
        for words in numerators {
            let numerator = ExactNaturalMagnitude(words)
            for divisorWords in divisors {
                let divisor = ExactNaturalMagnitude(divisorWords)
                let (quotient, remainder) = try numerator.quotientAndRemainder(dividingBy: divisor, usage: &usage)
                #expect(try quotient.multiplied(by: divisor, usage: &usage).adding(remainder, usage: &usage) == numerator)
                #expect(remainder.compared(to: divisor) < 0)
            }
        }
        let third = try ExactRationalCoefficient.one.divided(by: .natural(3, usage: &usage), usage: &usage)
        #expect(try third.adding(third, usage: &usage) == .natural(2, usage: &usage).divided(by: .natural(3, usage: &usage), usage: &usage))
        #expect(try third.subtracting(third, usage: &usage) == .zero)
        let dyadic = try ExactRationalCoefficient.originalDouble(0.125, usage: &usage)
        #expect(try dyadic.adding(dyadic, usage: &usage) == .originalDouble(0.25, usage: &usage))
        #expect(try ExactNaturalMagnitude.gcd(.init([UInt32.max]), .init([3]), usage: &usage) == .init([3]))
        for (first, second) in [(ExactNaturalMagnitude([7, 13, 19]), .one), (.one, ExactNaturalMagnitude([7, 13, 19]))] {
            var scalar = Admission(maximumWork: 1, maximumStorage: 0)
            #expect(try ExactNaturalMagnitude.gcd(first, second, usage: &scalar) == .one)
            #expect(scalar.work == 1 && scalar.storage == 0)
        }
        #expect(try ExactNaturalMagnitude.gcd(.init([UInt32.max, UInt32.max]), .init([1, 1]), usage: &usage) == .init([1, 1]))
        #expect(try ExactNaturalMagnitude.gcd(.init([0, 0, 1]), .init([1, 0, 1]), usage: &usage) == .one)
        var noWork = Admission(maximumWork: 0)
        #expect(throws: KernelError.self) { try ExactNaturalMagnitude([7, 0, 1]).quotientAndRemainder(dividingBy: .init([1, 1]), usage: &noWork) }
        var noStorage = Admission(maximumStorage: 0)
        #expect(throws: KernelError.self) { try ExactNaturalMagnitude([7, 0, 1]).quotientAndRemainder(dividingBy: .init([3]), usage: &noStorage) }
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
