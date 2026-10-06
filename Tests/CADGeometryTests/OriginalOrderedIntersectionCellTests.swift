import CADCore
@testable import CADGeometry
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OriginalOrderedIntersectionCellTests {
    private typealias Polynomial = OriginalOrderedIntersectionPolynomial
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0, storage = 0
        var maximumWork = 20_000_000, maximumStorage = 20_000_000
        var maximumParameterDepth = 24, maximumCoefficientDepth = 24
        var parameterDepth = 0, coefficientDepth = 0
        var coefficientVisits = 0
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0, count <= maximumWork - work else { throw failure("work") }; work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= maximumStorage - storage else { throw failure("storage") }; storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumParameterDepth else { throw failure("parameter depth") }
            parameterDepth = max(parameterDepth, depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumCoefficientDepth else { throw failure("coefficient depth") }
            coefficientDepth = max(coefficientDepth, depth); coefficientVisits += 1
        }
        private func failure(_ domain: String) -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original ordered-cell test exhausted \(domain).")
        }
    }

    private func originalRoot(usage: inout Admission) throws -> OriginalSingularFieldElement {
        let rational = try OriginalSingularFieldContext(usage: &usage)
        return try OriginalSingularFieldElement.constant(.natural(2, usage: &usage), in: rational,
            maximumDepth: 0, usage: &usage).nonnegativeSquareRoot(inheritedDepth: 0, maximumDepth: 24,
                admissionDomain: .coefficient(maximumDepth: 24), usage: &usage)
    }
    private func constant(_ value: Int, in context: OriginalSingularFieldContext,
        usage: inout Admission) throws -> OriginalSingularFieldElement {
        let magnitude = try ExactRationalCoefficient.natural(abs(value), usage: &usage)
        return try .constant(value < 0 ? magnitude.negated : magnitude, in: context, maximumDepth: 24, usage: &usage)
    }
    private func term(_ powers: [Int], _ coefficient: OriginalSingularFieldElement,
        usage: inout Admission) throws -> Polynomial.Term {
        .init(power: try .init(powers, variableCount: powers.count, usage: &usage), coefficient: coefficient)
    }
    private func partition(_ polynomials: [Polynomial], instructions: [ExactIntersectionBooleanProgram.Instruction],
        count: Int, maximumDepth: Int = 24, maximumCoefficientDepth: Int = 24,
        usage: inout Admission) throws -> OriginalOrderedIntersectionCells {
        let program = try ExactIntersectionBooleanProgram(polynomialCount: polynomials.count, instructions: instructions, usage: &usage)
        let domain = try OriginalRationalParameterDomain(nil, usage: &usage)
        return try .prepare(polynomials: polynomials, predicate: program, variableCount: count,
            domains: Array(repeating: domain, count: count), maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &usage)
    }

    @Test func exactCoefficientPointDoesNotBecomeAnExtraGeometricDimension() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let polynomial = try Polynomial(variableCount: 1, terms: [
            term([1], constant(1, in: root.context, usage: &usage), usage: &usage),
            term([0], root.negated(maximumDepth: 0, usage: &usage), usage: &usage)
        ], maximumDepth: 0, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([polynomial], instructions: [.atom(0, .zero)], count: 1, maximumDepth: 0, usage: &usage)
        #expect(relation.coefficientSources.count == 1)
        #expect(relation.partition.solutionCells.count == 1)
        let index = try #require(relation.partition.solutionCells.first)
        let cell = relation.partition.cells[index]
        #expect(cell.dimension == 0 && cell.admissionDepth == 0)
        #expect(cell.coefficientAdmissionDepth >= root.context.coefficientDepth)
        let sample = try relation.geometricSample(cellIndex: index, usage: &usage)
        #expect(sample.count == 1)
        let x = try #require(sample.first)
        let two = try constant(2, in: x.context, usage: &usage)
        #expect(try x.multiplied(by: x, maximumDepth: 0, usage: &usage)
            .subtracting(two, maximumDepth: 0, usage: &usage).sign(maximumDepth: 0, usage: &usage) == .zero)
        #expect(try x.sign(maximumDepth: 0, usage: &usage) == .positive)
        #expect(usage.parameterDepth == 0 && usage.coefficientDepth > 0)
    }

    @Test func strictAlgebraicBoundarySeparatesTwoWholeRays() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let polynomial = try Polynomial(variableCount: 1, terms: [
            term([1], constant(1, in: root.context, usage: &usage), usage: &usage),
            term([0], root.negated(maximumDepth: 0, usage: &usage), usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([polynomial], instructions: [.atom(0, .zero), .not], count: 1, usage: &usage)
        #expect(relation.partition.solutionCells.count == 2)
        #expect(relation.partition.solutionCells.allSatisfy { relation.partition.cells[$0].dimension == 1 })
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: relation.partition,
            maximumDepth: 24, usage: &usage)
        #expect(try incidence.connectedComponents(usage: &usage).components.count == 2)
        #expect(incidence.closures.allSatisfy { $0.includedCells.count == 2 })
    }

    @Test func singularVerticalAndHorizontalFibersAreBothRetainedOverOriginalCoefficient() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let polynomial = try Polynomial(variableCount: 2, terms: [
            term([1, 1], constant(1, in: root.context, usage: &usage), usage: &usage),
            term([0, 1], root.negated(maximumDepth: 0, usage: &usage), usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let derivative = try polynomial.differentiated(at: 0,
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([polynomial, derivative], instructions: [.atom(0, .zero)], count: 2, usage: &usage)
        let cells = relation.partition.solutionCells
        #expect(cells.contains { relation.partition.cells[$0].dimension == 0 })
        #expect(cells.filter { relation.partition.cells[$0].dimension == 1 }.count == 4)
        for index in cells {
            let values = try relation.geometricSample(cellIndex: index, usage: &usage)
            #expect(values.count == 2)
            #expect(relation.partition.cells[index].signs[relation.partition.partitionSignOffset] == .zero)
        }
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: relation.partition,
            maximumDepth: 24, usage: &usage)
        #expect(try incidence.connectedComponents(usage: &usage).components.count == 1)
    }

    @Test func positiveComplexDimensionCanHaveOnlyAnIsolatedRealPointWithOrderedCoefficients() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let minusTwo = try constant(-2, in: root.context, usage: &usage)
        let polynomial = try Polynomial(variableCount: 2, terms: [
            term([2, 0], constant(1, in: root.context, usage: &usage), usage: &usage),
            term([1, 0], root.multiplied(by: minusTwo, maximumDepth: 0, usage: &usage), usage: &usage),
            term([0, 0], constant(2, in: root.context, usage: &usage), usage: &usage),
            term([0, 2], constant(1, in: root.context, usage: &usage), usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([polynomial], instructions: [.atom(0, .zero)], count: 2, usage: &usage)
        #expect(relation.partition.solutionCells.count == 1)
        let index = try #require(relation.partition.solutionCells.first)
        #expect(relation.partition.cells[index].dimension == 0)
        let sample = try relation.geometricSample(cellIndex: index, usage: &usage)
        #expect(try sample[sample.startIndex].sign(maximumDepth: 24, usage: &usage) == .positive)
        #expect(try sample[sample.index(after: sample.startIndex)].sign(maximumDepth: 24, usage: &usage) == .zero)
    }

    @Test func correlatedCoefficientsDoNotProduceConjugateCombinations() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let first = try Polynomial(variableCount: 2, terms: [
            term([1, 0], constant(1, in: root.context, usage: &usage), usage: &usage),
            term([0, 0], root.negated(maximumDepth: 0, usage: &usage), usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let second = try Polynomial(variableCount: 2, terms: [
            term([0, 1], constant(1, in: root.context, usage: &usage), usage: &usage),
            term([0, 0], root, usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([first, second], instructions: [.atom(0, .zero), .atom(1, .zero), .and],
            count: 2, usage: &usage)
        #expect(relation.coefficientSources.count == 2)
        #expect(relation.partition.solutionCells.count == 1)
        let index = try #require(relation.partition.solutionCells.first)
        let sample = try relation.geometricSample(cellIndex: index, usage: &usage)
        let x = sample[sample.startIndex], y = sample[sample.index(after: sample.startIndex)]
        #expect(try x.adding(y, maximumDepth: 24, usage: &usage).sign(maximumDepth: 24, usage: &usage) == .zero)
        #expect(try x.sign(maximumDepth: 24, usage: &usage) == .positive)
        #expect(try y.sign(maximumDepth: 24, usage: &usage) == .negative)
    }

    @Test func orderedSourceDepthCannotBeResetByTheRelationCompiler() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let polynomial = try Polynomial(variableCount: 1, terms: [term([0], root, usage: &usage)],
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        #expect(throws: KernelError.self) {
            try partition([polynomial], instructions: [.literal(true)], count: 1,
                maximumCoefficientDepth: 0, usage: &usage)
        }
        let program = try ExactIntersectionBooleanProgram(polynomialCount: 1, instructions: [.literal(true)], usage: &usage)
        let domain = try OriginalRationalParameterDomain(nil, usage: &usage)
        var storage = Admission(); storage.maximumStorage = 0
        #expect(throws: KernelError.self) {
            try OriginalOrderedIntersectionCells.prepare(polynomials: [polynomial], predicate: program,
                variableCount: 1, domains: [domain], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &storage)
        }
        var work = Admission(); work.maximumWork = 0
        #expect(throws: KernelError.self) {
            try OriginalOrderedIntersectionCells.prepare(polynomials: [polynomial], predicate: program,
                variableCount: 1, domains: [domain], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &work)
        }
        #expect(throws: KernelError.self) {
            try partition([polynomial], instructions: [.literal(true)], count: 2, usage: &usage)
        }
    }

    @Test func actualOriginalFieldPlaneLawEmbedsOnlyItsAssignedGeometricAxes() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let field = try OriginalSingularFieldPlanePolynomial(context: root.context, coefficients: [
            try .init(u: 1, v: 0): constant(1, in: root.context, usage: &usage),
            try .init(u: 0, v: 0): root.negated(maximumDepth: 0, usage: &usage)
        ], maximumDepth: 24, usage: &usage)
        let polynomial = try Polynomial.embedding(field, variableCount: 4, uCoordinate: 2, vCoordinate: 3,
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([polynomial], instructions: [.atom(0, .zero)], count: 4, usage: &usage)
        #expect(relation.partition.solutionCells.count == 1)
        let index = try #require(relation.partition.solutionCells.first)
        #expect(relation.partition.cells[index].dimension == 3)
        let sample = try relation.geometricSample(cellIndex: index, usage: &usage)
        #expect(sample.count == 4)
        let value = sample[sample.startIndex + 2]
        #expect(try value.sign(maximumDepth: 24, usage: &usage) == .positive)
        #expect(try value.multiplied(by: value, maximumDepth: 24, usage: &usage)
            .subtracting(constant(2, in: value.context, usage: &usage), maximumDepth: 24, usage: &usage)
            .sign(maximumDepth: 24, usage: &usage) == .zero)
    }

    @Test func equalOriginalCoefficientsReuseTheirProvedFixedAxis() throws {
        var usage = Admission()
        let root = try originalRoot(usage: &usage)
        let polynomial = try Polynomial(variableCount: 2, terms: [
            term([1, 0], root, usage: &usage), term([0, 1], root, usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let relation = try partition([polynomial], instructions: [.atom(0, .zero)], count: 2, usage: &usage)
        #expect(relation.coefficientSources.count == 1)
        #expect(relation.coefficientBindings[0][0].coefficientAxis == relation.coefficientBindings[0][1].coefficientAxis)
        #expect(relation.partition.solutionCells.allSatisfy { relation.partition.cells[$0].dimension <= 1 })
    }

    @Test func rationalLawsDoNotInventAnyCoefficientAxisOrCoefficientAdmission() throws {
        var usage = Admission(); usage.maximumCoefficientDepth = 0
        let context = try OriginalSingularFieldContext(usage: &usage)
        let polynomial = try Polynomial(variableCount: 1, terms: [
            term([1], constant(1, in: context, usage: &usage), usage: &usage)
        ], maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        let relation = try partition([polynomial], instructions: [.atom(0, .zero)], count: 1,
            maximumCoefficientDepth: 0, usage: &usage)
        #expect(relation.coefficientSources.isEmpty)
        #expect(relation.partition.tower.variableCount == 1)
        #expect(relation.partition.solutionCells.count == 1)
        #expect(usage.coefficientVisits == 0)
    }

    @Test func cancellationCannotPublishOrderedCellsOrConsumeAdditionalWork() async throws {
        let work = try await Task {
            var preparation = Admission()
            let root = try originalRoot(usage: &preparation)
            let polynomial = try Polynomial(variableCount: 1, terms: [term([0], root, usage: &preparation)],
                maximumDepth: 24, maximumCoefficientDepth: 24, usage: &preparation)
            let program = try ExactIntersectionBooleanProgram(polynomialCount: 1,
                instructions: [.literal(true)], usage: &preparation)
            let domain = try OriginalRationalParameterDomain(nil, usage: &preparation)
            var usage = Admission()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try OriginalOrderedIntersectionCells.prepare(polynomials: [polynomial], predicate: program,
                    variableCount: 1, domains: [domain], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
                Issue.record("Cancelled ordered relation published geometric cells.")
            } catch is CancellationError { return usage.work }
            return -1
        }.value
        #expect(work == 0)
    }
}
