import CADCore
@testable import CADGeometry
import Testing

@Suite("Original quantified intersection incidence")
struct IntersectionIncidenceTests {
    private typealias Polynomial = ExactIntersectionPolynomial
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0, storage = 0, cells = 0
        var maximumWork = 10_000_000, maximumStorage = 10_000_000
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw exhausted("work") }; work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw exhausted("storage") }; storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= 24, cells < 100_000 else { throw exhausted("cells/depth") }; cells += 1
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            throw rationalAlgebraFailure("Rational incidence may not invent coefficient roots.")
        }
        private func exhausted(_ reason: String) -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                  message: "The original incidence caller exhausted \(reason): work=\(work), storage=\(storage), cells=\(cells).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func predicateCoordinatesPreserveEveryOriginalExponent() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let original = try x.multiplied(by: x, usage: &usage).multiplied(by: y, usage: &usage)
        let mapped = try original.remapped(to: 9, coordinates: [8, 7], usage: &usage)
        let values: [ExactRationalCoefficient] = [.zero, .zero, .zero, .zero, .zero, .zero, .zero,
            try .natural(3, usage: &usage), try .natural(2, usage: &usage)]
        #expect(try mapped.evaluated(at: values, usage: &usage) == .natural(12, usage: &usage))
        #expect(try mapped.differentiated(at: 8, usage: &usage).evaluated(at: values, usage: &usage) == .natural(12, usage: &usage))
        let coefficients = try mapped.axisCoefficients(at: 8, usage: &usage)
        #expect(coefficients.count == 3 && coefficients[0].isZero && coefficients[1].isZero)
        #expect(try coefficients[2].evaluated(at: values, usage: &usage) == .natural(3, usage: &usage))
        #expect(throws: KernelError.self) { try original.remapped(to: 9, coordinates: [8, 8], usage: &usage) }
        #expect(throws: KernelError.self) { try original.remapped(to: 9, coordinates: [8, 9], usage: &usage) }
        #expect(try Polynomial.zero(variableCount: 10).variableCount == 10)
        #expect(throws: KernelError.self) { try Polynomial.zero(variableCount: 0) }
        #expect(throws: KernelError.self) {
            try Polynomial.monomial(variableCount: 9, powers: (0,0,0,0,0,0,0,0,Int.max), coefficient: .one, usage: &usage)
                .multiplied(by: .coordinate(variableCount: 9, at: 8, usage: &usage), usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func derivativeSignsDistinguishEqualOriginalSignRoots() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let equation = try x.multiplied(by: x, usage: &usage)
            .subtracting(.constant(variableCount: 1, value: .one, usage: &usage), usage: &usage)
        let original = try OriginalRationalIntersectionCells.prepare(equations: [equation], variableCount: 1,
            domains: [nil], maximumDepth: 24, usage: &usage)
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCellCondition(partition: original, cellIndex: original.solutionCells[0], usage: &usage)
        }
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [equation], variableCount: 1,
            domains: [nil], thomEncoding: true, maximumDepth: 24, usage: &usage)
        #expect(partition.solutionCells.count == 2)
        let a = try OriginalIntersectionCellCondition(partition: partition, cellIndex: partition.solutionCells[0], usage: &usage)
        let b = try OriginalIntersectionCellCondition(partition: partition, cellIndex: partition.solutionCells[1], usage: &usage)
        let left = partition.cells[a.cellIndex], right = partition.cells[b.cellIndex]
        #expect(left.signs[0] == .zero && right.signs[0] == .zero)
        #expect(try a.contains(context: left.context, coordinates: left.coordinates, maximumDepth: 24, usage: &usage))
        #expect(try b.contains(context: right.context, coordinates: right.coordinates, maximumDepth: 24, usage: &usage))
        #expect(try !a.contains(context: right.context, coordinates: right.coordinates, maximumDepth: 24, usage: &usage))
        #expect(try !b.contains(context: left.context, coordinates: left.coordinates, maximumDepth: 24, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func quantifierOrderAndNullifiedFibersUseEveryOriginalChild() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let difference = try y.subtracting(x, usage: &usage)
        let program = try ExactIntersectionBooleanProgram(polynomialCount: 1, instructions: [.atom(0, .zero)], usage: &usage)
        let trueOrder = try ExactIntersectionQuantifiedCells.prepare(polynomials: [difference], program: program,
            variableCount: 2, freeVariableCount: 0, quantifiers: [.forall, .exists], maximumDepth: 24, usage: &usage)
        let falseOrder = try ExactIntersectionQuantifiedCells.prepare(polynomials: [difference], program: program,
            variableCount: 2, freeVariableCount: 0, quantifiers: [.exists, .forall], maximumDepth: 24, usage: &usage)
        #expect(trueOrder.closedTruth == true && falseOrder.closedTruth == false)
        let hyperbola = try x.multiplied(by: y, usage: &usage)
            .subtracting(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage)
        let free = try ExactIntersectionQuantifiedCells.prepare(polynomials: [hyperbola], program: program,
            variableCount: 2, freeVariableCount: 1, quantifiers: [.exists], maximumDepth: 24, usage: &usage)
        #expect(free.closedTruth == nil && free.freeCells.count == 3)
        for truth in free.freeCells {
            let cell = try #require(free.freePartition).cells[truth.cellIndex]
            #expect(truth.value == (try cell.coordinates[0].sign(maximumDepth: 24, usage: &usage) != .zero))
        }
        let universal = try ExactIntersectionQuantifiedCells.prepare(polynomials: [hyperbola], program: program,
            variableCount: 2, freeVariableCount: 0, quantifiers: [.forall, .exists], maximumDepth: 24, usage: &usage)
        #expect(universal.closedTruth == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func quantifiedNinthCoordinateDoesNotDisappear() throws {
        var usage = Admission()
        let first = try Polynomial.coordinate(variableCount: 9, at: 0, usage: &usage)
        let last = try Polynomial.coordinate(variableCount: 9, at: 8, usage: &usage)
        let law = try last.subtracting(first, usage: &usage)
        let program = try ExactIntersectionBooleanProgram(polynomialCount: 1, instructions: [.atom(0, .zero)], usage: &usage)
        let result = try ExactIntersectionQuantifiedCells.prepare(polynomials: [law], program: program,
            variableCount: 9, freeVariableCount: 8, quantifiers: [.exists], maximumDepth: 24, usage: &usage)
        #expect(!result.freeCells.isEmpty && result.freeCells.allSatisfy { $0.value })
        #expect(result.tower.variableCount == 9 && result.decisions.contains { $0.axis == 8 })
    }

    @Test(.timeLimit(.minutes(1)))
    func openIntervalClosureIncludesOnlyItsExactClosedEndpoints() throws {
        var usage = Admission()
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
            domains: [try .init(lower: 0, upper: 1)], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let source = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let closure = try OriginalIntersectionCellClosure.prepare(partition: partition, cellIndex: source,
            maximumDepth: 24, usage: &usage)
        var endpoints = 0, exterior = 0
        for index in closure.freePartition.cells.indices where closure.freePartition.cells[index].coordinates.count == 1 {
            let cell = closure.freePartition.cells[index]
            let truth = closure.includedCells.contains(index)
            let zero = try cell.coordinates[0].sign(maximumDepth: 24, usage: &usage)
            let one = try OriginalSingularFieldElement.constant(.one, in: cell.context, maximumDepth: 24, usage: &usage)
            let upper = try cell.coordinates[0].subtracting(one, maximumDepth: 24, usage: &usage)
                .sign(maximumDepth: 24, usage: &usage)
            #expect(truth == (zero != .negative && upper != .positive))
            if zero == .zero || upper == .zero { endpoints += 1; #expect(truth) }
            if zero == .negative || upper == .positive { exterior += 1; #expect(!truth) }
        }
        #expect(endpoints == 2 && exterior > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalIncidenceRetainsBothEndpointAttachments() throws {
        var usage = Admission()
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
            domains: [try .init(lower: -1, upper: 1)], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let source = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition, maximumDepth: 24, usage: &usage)
        let attached = Set(incidence.attachments.filter { $0.sourceCellIndex == source }.map { $0.targetCellIndex })
        #expect(attached == Set(partition.solutionCells))
        for index in partition.solutionCells where index != source {
            #expect(incidence.attachments.filter { $0.sourceCellIndex == index }.allSatisfy { $0.targetCellIndex == index })
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [3, 4])
    func originalThreeAndFourCoordinateBranchesRetainEndpointIncidence(count: Int) throws {
            var usage = Admission()
            var equations: [Polynomial] = []
            for axis in 1..<count {
                equations.append(try .coordinate(variableCount: count, at: axis, usage: &usage))
            }
            var domains: [ScalarInterval?] = Array(repeating: nil, count: count)
            domains[0] = try .init(lower: -1, upper: 1)
            let partition = try OriginalRationalIntersectionCells.prepare(equations: equations, variableCount: count,
                domains: domains, thomEncoding: true, maximumDepth: 24, usage: &usage)
            #expect(partition.solutionCells.count == 3)
            let branch = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
            let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
                maximumDepth: 24, usage: &usage)
            let attached = Set(incidence.attachments.filter { $0.sourceCellIndex == branch }.map { $0.targetCellIndex })
            #expect(attached == Set(partition.solutionCells))
            for endpoint in partition.solutionCells where endpoint != branch {
                #expect(incidence.attachments.filter { $0.sourceCellIndex == endpoint }.allSatisfy { $0.targetCellIndex == endpoint })
            }
            #expect(incidence.closures.allSatisfy { $0.freePartition.tower.variableCount == count })
            #expect(incidence.closures.contains { if case .finiteBranch = $0.proof { true } else { false } })
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedProgramsAndIndependentCallerLimitsFail() throws {
        var usage = Admission()
        #expect(throws: KernelError.self) { try ExactIntersectionBooleanProgram(polynomialCount: 1, instructions: [.atom(1, .zero)], usage: &usage) }
        #expect(throws: KernelError.self) { try ExactIntersectionBooleanProgram(polynomialCount: 0, instructions: [.and], usage: &usage) }
        #expect(throws: KernelError.self) { try ExactIntersectionBooleanProgram(polynomialCount: 0, instructions: [.literal(true), .literal(false)], usage: &usage) }
        let polynomial = try Polynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let program = try ExactIntersectionBooleanProgram(polynomialCount: 1, instructions: [.atom(0, .zero)], usage: &usage)
        var noWork = Admission(); noWork.maximumWork = 0
        #expect(throws: KernelError.self) {
            try ExactIntersectionQuantifiedCells.prepare(polynomials: [polynomial], program: program, variableCount: 1,
                freeVariableCount: 0, quantifiers: [.exists], maximumDepth: 24, usage: &noWork)
        }
        var noStorage = Admission(); noStorage.maximumStorage = 0
        #expect(throws: KernelError.self) {
            try ExactIntersectionQuantifiedCells.prepare(polynomials: [polynomial], program: program, variableCount: 1,
                freeVariableCount: 0, quantifiers: [.exists], maximumDepth: 24, usage: &noStorage)
        }
        #expect(throws: KernelError.self) {
            try ExactIntersectionQuantifiedCells.prepare(polynomials: [polynomial], program: program, variableCount: 1,
                freeVariableCount: 0, quantifiers: [], maximumDepth: 24, usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unknownAtomsCannotBecomeWholeCellTruth() throws {
        var usage = Admission()
        let program = try ExactIntersectionBooleanProgram(polynomialCount: 2,
            instructions: [.atom(0, .zero), .atom(1, .positive), .and], usage: &usage)
        var scratch: [Bool?] = []; scratch.reserveCapacity(program.maximumStackCount)
        #expect(try program.partialValue(signs: [.zero, nil], scratch: &scratch, usage: &usage) == nil)
        #expect(try program.partialValue(signs: [.negative, nil], scratch: &scratch, usage: &usage) == false)
        #expect(try program.partialValue(signs: [nil, .positive], scratch: &scratch, usage: &usage) == nil)
        #expect(try program.partialValue(signs: [.zero, .positive], scratch: &scratch, usage: &usage) == true)
        let disjunction = try ExactIntersectionBooleanProgram(polynomialCount: 2,
            instructions: [.atom(0, .zero), .atom(1, .positive), .or], usage: &usage)
        #expect(try disjunction.partialValue(signs: [.zero, nil], scratch: &scratch, usage: &usage) == true)
        #expect(try disjunction.partialValue(signs: [.negative, nil], scratch: &scratch, usage: &usage) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactConstantFractionsPreserveTheirOriginalOwnerAndRejectZeroDenominators() throws {
        var usage = Admission()
        let context = try OriginalSingularFieldContext(usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let three = try ExactRationalCoefficient.natural(3, usage: &usage)
        let a = try OriginalSingularFieldElement(context: context,
            storage: .original(.constant(two, usage: &usage), .constant(three.negated, usage: &usage)))
        let b = try OriginalSingularFieldElement.constant(.one, in: context, maximumDepth: 24, usage: &usage)
        #expect(try a.sign(maximumDepth: 24, usage: &usage) == .negative)
        let sum = try a.adding(b, maximumDepth: 24, usage: &usage)
        #expect(sum.context === context)
        #expect(try sum.rationalValue(usage: &usage) == .one.divided(by: three, usage: &usage))
        #expect(try a.multiplied(by: a, maximumDepth: 24, usage: &usage).rationalValue(usage: &usage)
            == two.multiplied(by: two, usage: &usage).divided(by: three.multiplied(by: three, usage: &usage), usage: &usage))
        #expect(try a.divided(by: a, maximumDepth: 24, usage: &usage).rationalValue(usage: &usage) == .one)
        let invalid = try OriginalSingularFieldElement(context: context,
            storage: .original(.constant(.zero, usage: &usage), .constant(.zero, usage: &usage)))
        #expect(throws: KernelError.self) { try invalid.sign(maximumDepth: 24, usage: &usage) }
        #expect(throws: KernelError.self) { try invalid.rationalValue(usage: &usage) }
        #expect(throws: KernelError.self) { try invalid.adding(b, maximumDepth: 24, usage: &usage) }
        #expect(throws: KernelError.self) { try invalid.multiplied(by: b, maximumDepth: 24, usage: &usage) }
        let foreign = try OriginalSingularFieldContext(usage: &usage)
        let foreignValue = try OriginalSingularFieldElement.constant(.one, in: foreign, maximumDepth: 24, usage: &usage)
        #expect(throws: KernelError.self) { try a.adding(foreignValue, maximumDepth: 24, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPrefixExclusionPreservesTheCompleteNullifiedFiber() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [x], variableCount: 2,
            domains: [nil, nil], thomEncoding: true, pruneExcludedPrefixes: true, maximumDepth: 24, usage: &usage)
        #expect(partition.solutionCells.count == 1 && partition.excludedPrefixes.count == 2)
        let cell = partition.cells[try #require(partition.solutionCells.first)]
        #expect(cell.dimension == 1 && cell.signs[0] == .zero)
        for excluded in partition.excludedPrefixes {
            #expect(excluded.equationIndex == 0 && excluded.sign != .zero)
            let prefix = partition.cells[try #require(excluded.parentCell)]
            #expect(prefix.coordinates.count == 1)
            #expect(try prefix.coordinates[0].sign(maximumDepth: 24, usage: &usage) == excluded.sign)
        }
        let empty = try OriginalRationalIntersectionCells.prepare(equations: [
            .constant(variableCount: 2, value: .one, usage: &usage)], variableCount: 2,
            domains: [nil, nil], pruneExcludedPrefixes: true, maximumDepth: 24, usage: &usage)
        #expect(empty.solutionCells.isEmpty && empty.excludedPrefixes.count == 1)
        #expect(empty.excludedPrefixes[0].parentCell == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledIncidenceCannotPublishAnyPartialClosure() async throws {
        let charged = try await Task { () throws -> Int in
            var usage = Admission()
            let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
                domains: [try .init(lower: -1, upper: 1)], thomEncoding: true, maximumDepth: 24, usage: &usage)
            let previous = usage.work
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try OriginalRationalIntersectionIncidence.prepare(partition: partition, maximumDepth: 24, usage: &usage)
                Issue.record("Cancelled incidence cannot publish any closure.")
            } catch is CancellationError { return usage.work - previous }
            return -1
        }.value
        #expect(charged == 0)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func nonlinearThreeCoordinateBranchesMeetOnlyTheirOriginalBoundary(cusp: Bool) throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let xSquared = try x.multiplied(by: x, usage: &usage)
        let law = try (cusp ? y.multiplied(by: y, usage: &usage) : y)
            .subtracting(cusp ? xSquared.multiplied(by: x, usage: &usage) : xSquared, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law, z], variableCount: 3,
            domains: [try .init(lower: 0, upper: 1), try .init(lower: -1, upper: 1), nil],
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let origin = try #require(try partition.solutionCells.first { index in
            let cell = partition.cells[index]
            if cell.dimension != 0 { return false }
            return try cell.coordinates[0].rationalValue(usage: &usage) == .zero
        })
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
            maximumDepth: 24, usage: &usage)
        let branches = partition.solutionCells.filter { partition.cells[$0].dimension == 1 }
        #expect(branches.count == (cusp ? 2 : 1))
        for branch in branches {
            let attached = Set(incidence.attachments.filter { $0.sourceCellIndex == branch }.map { $0.targetCellIndex })
            #expect(attached.contains(origin) && attached.contains(branch) && attached.count == 3)
            #expect(attached.filter { partition.cells[$0].dimension == 1 } == [branch])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func recursiveGCDPreservesContentAndOriginalMultiplicity() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let common = try x.adding(y, usage: &usage)
        let other = try z.adding(one, usage: &usage)
        let a = try common.multiplied(by: common, usage: &usage).multiplied(by: other, usage: &usage)
        let b = try common.multiplied(by: x.adding(one, usage: &usage), usage: &usage)
        #expect(try ExactIntersectionPolynomialGCD.gcd(a, b, usage: &usage) == common)
        #expect(try ExactIntersectionPolynomialGCD.gcd(a, .zero(variableCount: 3), usage: &usage) == a.monic(usage: &usage))
        let repeated = try a.multiplied(by: other, usage: &usage).multiplied(by: other, usage: &usage)
        let squareFree = try ExactIntersectionPolynomialGCD.squareFree(repeated, usage: &usage)
        #expect(squareFree == (try common.multiplied(by: other, usage: &usage).monic(usage: &usage)))
        #expect(try repeated.dividedExactly(by: squareFree, usage: &usage)
            .multiplied(by: squareFree, usage: &usage) == repeated)
        let projection = try ExactIntersectionProjection.prepare(sources: [repeated, a, b], variableCount: 3,
            axis: 2, usage: &usage)
        #expect(projection.sources == [repeated, a, b])
        #expect(throws: KernelError.self) {
            try ExactIntersectionPolynomialGCD.gcd(a, .coordinate(variableCount: 2, at: 1, usage: &usage), usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func fourCoordinateRegionUsesWholeQuantifiedClosureRatherThanBranchSamples() throws {
        var usage = Admission()
        let z = try Polynomial.coordinate(variableCount: 4, at: 2, usage: &usage)
        let w = try Polynomial.coordinate(variableCount: 4, at: 3, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [z, w], variableCount: 4,
            domains: [try .init(lower: 0, upper: 1), try .init(lower: 0, upper: 1), nil, nil],
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let interior = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 2 })
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition,
            allowAffineClosureProofs: false, maximumDepth: 24, usage: &usage)
        let closure = try #require(incidence.closures.first { $0.source.cellIndex == interior })
        let components = try incidence.connectedComponents(usage: &usage)
        #expect(components.components.count == 1)
        #expect(Set(try #require(components.components.first).cellIndexes) == Set(partition.solutionCells))
        guard case .quantified(let proof) = closure.proof else {
            Issue.record("A region cannot use a one-dimensional monic certificate."); return
        }
        #expect(proof.tower.variableCount == 7 && proof.freeVariableCount == 4 && !closure.includedCells.isEmpty)
        #expect(closure.candidateCoordinateMap == [5,6,2,3])
        for truth in proof.freeCells {
            let cell = closure.freePartition.cells[truth.cellIndex]
            let one = try OriginalSingularFieldElement.constant(.one, in: cell.context, maximumDepth: 24, usage: &usage)
            var inside = true
            for axis in 0..<2 {
                if try cell.coordinates[axis].sign(maximumDepth: 24, usage: &usage) == .negative { inside = false }
                if try cell.coordinates[axis].subtracting(one, maximumDepth: 24, usage: &usage)
                    .sign(maximumDepth: 24, usage: &usage) == .positive { inside = false }
            }
            for axis in 2..<4 {
                #expect(try cell.coordinates[axis].sign(maximumDepth: 24, usage: &usage) == .zero)
            }
            #expect(truth.value == inside)
        }
        let ideal = try #require(closure.predicateIdeal)
        #expect(!ideal.originalEquations.isEmpty)
        for (index, sign) in closure.source.signs.enumerated() where sign == .zero {
            #expect(closure.originalPredicates[index] == proof.tower.levels[0].sources[index])
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func exactComponentsSeparateSheetsAndJoinCrossings(crossing: Bool) throws {
        var usage = Admission()
        let count = crossing ? 4 : 3
        let x = try Polynomial.coordinate(variableCount: count, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: count, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: count, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: count, value: .one, usage: &usage)
        var equations = [try crossing ? x.multiplied(by: y, usage: &usage)
            : y.multiplied(by: y.subtracting(one, usage: &usage), usage: &usage), z]
        if crossing { equations.append(try Polynomial.coordinate(variableCount: count, at: 3, usage: &usage)) }
        let interval = try ScalarInterval(lower: -1, upper: 1)
        let strata = try OriginalRationalIntersectionStrata.prepare(equations: equations, variableCount: count,
            domains: crossing ? [interval, interval, nil, nil] : [interval, nil, nil],
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: strata.partition,
            maximumDepth: 24, usage: &usage)
        let result = try incidence.connectedComponents(usage: &usage)
        #expect(result.components.count == (crossing ? 1 : 2))
        #expect(Set(result.components.flatMap { $0.cellIndexes }) == Set(strata.partition.solutionCells))
        #expect(result.components.reduce(0) { $0 + $1.cellIndexes.count } == strata.partition.solutionCells.count)
        for component in result.components {
            for index in component.attachmentIndexes {
                #expect(component.cellIndexes.contains(incidence.attachments[index].sourceCellIndex))
                #expect(component.cellIndexes.contains(incidence.attachments[index].targetCellIndex))
            }
        }
        var noWork = Admission(); noWork.maximumWork = 0
        #expect(throws: KernelError.self) { try incidence.connectedComponents(usage: &noWork) }
        var noStorage = Admission(); noStorage.maximumStorage = 0
        #expect(throws: KernelError.self) { try incidence.connectedComponents(usage: &noStorage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func excludedStationCannotJoinOtherwiseIncidentBranches() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let one = try Polynomial.constant(variableCount: 3, value: .one, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [y, z], variableCount: 3,
            domains: [try .init(lower: -1, upper: 1), nil, nil], partitionPolynomials: [x],
            nonzeroPolynomials: [x], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition, maximumDepth: 24, usage: &usage)
        #expect(try incidence.connectedComponents(usage: &usage).components.count == 2)
        let allExcluded = try OriginalRationalIntersectionCells.prepare(equations: [y, z], variableCount: 3,
            domains: [nil, nil, nil], nonzeroPolynomials: [y], thomEncoding: true, maximumDepth: 24, usage: &usage)
        #expect(allExcluded.solutionCells.isEmpty && !allExcluded.cells.isEmpty)
        #expect(throws: KernelError.self) {
            try OriginalRationalIntersectionCells.prepare(equations: [y, z], variableCount: 3,
                domains: [nil, nil, nil], nonzeroPolynomials: [.coordinate(variableCount: 2, at: 0, usage: &usage)],
                thomEncoding: true, maximumDepth: 24, usage: &usage)
        }
        let empty = try OriginalRationalIntersectionCells.prepare(equations: [one], variableCount: 3,
            domains: [nil, nil, nil], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let noIncidence = try OriginalRationalIntersectionIncidence.prepare(partition: empty, maximumDepth: 24, usage: &usage)
        #expect(try noIncidence.connectedComponents(usage: &usage).components.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalCloseSheetsRemainDistinctWithoutRelaxingRootDepth() throws {
        var usage = Admission()
        let y = try Polynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try Polynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let gap = try ExactRationalCoefficient.originalDouble(1e-12, usage: &usage)
        let lower = try ExactRationalCoefficient.originalDouble(1.0 / 3.0, usage: &usage)
        let upper = try lower.adding(gap, usage: &usage)
        let firstLaw = try y.subtracting(.constant(variableCount: 3, value: lower, usage: &usage), usage: &usage)
        let second = try y.subtracting(.constant(variableCount: 3, value: upper, usage: &usage), usage: &usage)
        let law = try firstLaw.multiplied(by: second, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [law, z], variableCount: 3,
            domains: [try .init(lower: -1, upper: 1), nil, nil], partitionPolynomials: [firstLaw, second],
            thomEncoding: true, maximumDepth: 24, usage: &usage)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: partition, maximumDepth: 24, usage: &usage)
        let components = try incidence.connectedComponents(usage: &usage)
        #expect(components.components.count == 2)
        for component in components.components {
            let first = try #require(component.cellIndexes.first)
            let height = try #require(try partition.cells[first].coordinates[1].rationalValue(usage: &usage))
            #expect(height == lower || height == upper)
            for index in component.cellIndexes {
                #expect(try partition.cells[index].coordinates[1].rationalValue(usage: &usage) == height)
                #expect(partition.cells[index].admissionDepth <= 24)
            }
        }
        // The x coordinate remains free on each original sheet, not a sampled point set.
        #expect(components.components.allSatisfy { component in
            component.cellIndexes.contains { partition.cells[$0].dimension == 1 }
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func unboundMonicCellsAndCancelledEmptyIncidenceFailBeforePublication() async throws {
        var usage = Admission()
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 1,
            domains: [nil], thomEncoding: true, maximumDepth: 24, usage: &usage)
        for index in [-1, partition.cells.count] {
            #expect(throws: KernelError.self) {
                try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: index, maximumDepth: 24, usage: &usage)
            }
        }
        let cancelled = try await Task { () throws -> Bool in
            var admission = Admission()
            let one = try Polynomial.constant(variableCount: 1, value: .one, usage: &admission)
            let empty = try OriginalRationalIntersectionCells.prepare(equations: [one], variableCount: 1,
                domains: [nil], thomEncoding: true, maximumDepth: 24, usage: &admission)
            let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: empty, maximumDepth: 24, usage: &admission)
            withUnsafeCurrentTask { $0?.cancel() }
            var failures = 0
            do { _ = try OriginalRationalIntersectionIncidence.prepare(partition: empty, maximumDepth: 24, usage: &admission) }
            catch is CancellationError { failures += 1 }
            do { _ = try incidence.connectedComponents(usage: &admission) }
            catch is CancellationError { failures += 1 }
            return failures == 2
        }.value
        #expect(cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPoleOrLowerCallerDepthCannotIssueMonicIncidence() throws {
        var usage = Admission()
        let x = try Polynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try Polynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let one = try Polynomial.constant(variableCount: 2, value: .one, usage: &usage)
        let hyperbola = try x.multiplied(by: y, usage: &usage).subtracting(one, usage: &usage)
        let partition = try OriginalRationalIntersectionCells.prepare(equations: [hyperbola], variableCount: 2,
            domains: [try .init(lower: 0, upper: 1), nil], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let branch = try #require(partition.solutionCells.first { partition.cells[$0].dimension == 1 })
        #expect(try OriginalFiniteBranchClosure.prepare(partition: partition, cellIndex: branch,
            maximumDepth: 24, usage: &usage) == nil)
        let two = try Polynomial.constant(variableCount: 2, value: .natural(2, usage: &usage), usage: &usage)
        let irrational = try x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage)
        let tower = try OriginalRationalIntersectionCells.prepare(equations: [irrational], variableCount: 2,
            domains: [nil, try .init(lower: 0, upper: 1)], thomEncoding: true, maximumDepth: 24, usage: &usage)
        let source = try #require(tower.solutionCells.first { tower.cells[$0].dimension == 1 })
        #expect(tower.cells[source].admissionDepth > 0)
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCellClosure.prepare(partition: tower, cellIndex: source, maximumDepth: 0, usage: &usage)
        }
    }
}
