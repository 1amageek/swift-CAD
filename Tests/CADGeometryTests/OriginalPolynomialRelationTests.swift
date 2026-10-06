import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Public original rational real relations")
struct OriginalPolynomialRelationTests {
    private final class Budget: Sendable {
        private struct State { var work = 0, storage = 0, cells = 0 }
        private let state = Mutex(State())
        private let maximumWork: Int
        private let maximumStorage: Int
        init(work: Int = 10_000_000, storage: Int = 10_000_000) {
            maximumWork = work; maximumStorage = storage
        }
        var consumedWork: Int { state.withLock { $0.work } }
        var usage: OriginalRelationUsage {
            .init(consumeWork: { count in
                try self.state.withLock { state in
                    guard count <= self.maximumWork - state.work else { throw Self.exhausted() }
                    state.work += count
                }
            }, retainStorage: { count in
                try self.state.withLock { state in
                    guard count <= self.maximumStorage - state.storage else { throw Self.exhausted() }
                    state.storage += count
                }
            }, visitCell: { depth in
                try self.state.withLock { state in
                    guard depth <= 24, state.cells < 100_000 else { throw Self.exhausted() }
                    state.cells += 1
                }
            }, visitCoefficientCell: { _ in throw Self.exhausted() })
        }
        private static func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original public relation exhausted its independent caller allowance.")
        }
    }

    private let resolver: any OriginalPolynomialRelationResolving = DefaultOriginalPolynomialRelationResolver()

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func positiveComplexDimensionDoesNotInferRealDimensionOrAbsence(absent: Bool) throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        var law = try x.multiplied(by: x, usage: &usage).adding(y.multiplied(by: y, usage: &usage), usage: &usage)
        if absent { law = try law.adding(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage) }
        let input = try relation([law], instructions: [.sign(polynomial: 0, .zero)], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        #expect(result.components.count == (absent ? 0 : 1))
        #expect(result.cells.count == (absent ? 0 : 1))
        #expect(try result.contains(rationalPoint: [.zero, .zero], maximumDepth: 24, usage: usage) == !absent)
        if !absent { #expect(result.cells.first?.dimension == 0) }
    }

    @Test(.timeLimit(.minutes(1)))
    func verticalAndHorizontalBranchesMeetAtTheOriginalCrossing() throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let law = try x.multiplied(by: y, usage: &usage)
        let input = try relation([law], instructions: [.sign(polynomial: 0, .zero)], bounded: true, usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        #expect(result.components.count == 1 && result.components.first?.dimension == 1)
        #expect(try result.contains(rationalPoint: [.zero, .one], maximumDepth: 24, usage: usage))
        #expect(try result.contains(rationalPoint: [.one, .zero], maximumDepth: 24, usage: usage))
        #expect(try !result.contains(rationalPoint: [.one, .one], maximumDepth: 24, usage: usage))
    }

    @Test(.timeLimit(.minutes(1)))
    func excludedBoundaryCannotConnectTwoOpenOriginalBranches() throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let input = try relation([x,y], instructions: [.sign(polynomial: 1, .zero),
            .sign(polynomial: 0, .zero), .not, .and], bounded: true, usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        #expect(result.components.count == 2 && result.components.allSatisfy { $0.dimension == 1 })
        #expect(try !result.contains(rationalPoint: [.zero, .zero], maximumDepth: 24, usage: usage))
        #expect(try result.contains(rationalPoint: [.one.negated, .zero], maximumDepth: 24, usage: usage))
        #expect(try result.contains(rationalPoint: [.one, .zero], maximumDepth: 24, usage: usage))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func tangentBoundaryRetainsTheWholeCurveOrOnlyItsExactContact(onlyBoundary: Bool) throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let law = try y.subtracting(x.multiplied(by: x, usage: &usage), usage: &usage)
        let boundary: [OriginalPolynomialPredicate.Instruction] = onlyBoundary
            ? [.sign(polynomial: 1, .zero)]
            : [.sign(polynomial: 1, .negative), .not]
        let input = try relation([law,y], instructions: [.sign(polynomial: 0, .zero)] + boundary + [.and], bounded: true, usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        #expect(result.components.count == 1 && result.components.first?.dimension == (onlyBoundary ? 0 : 1))
        #expect(try result.contains(rationalPoint: [.zero,.zero], maximumDepth: 24, usage: usage))
        #expect(try result.contains(rationalPoint: [.one,.one], maximumDepth: 24, usage: usage) == !onlyBoundary)
    }

    @Test(.timeLimit(.minutes(1)))
    func booleanUnionAndUnrestrictedRegionKeepTheirActualDimensions() throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let atOne = try x.subtracting(.constant(variableCount: 1, value: .one, usage: &usage), usage: &usage)
        let input = try relation([x,atOne], instructions: [.sign(polynomial: 0, .zero),
            .sign(polynomial: 1, .zero), .or], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        #expect(result.cells.count == 2 && result.components.count == 2)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 0, instructions: [.literal(true)], usage: &usage)
        let unbounded = try OriginalRationalParameterDomain(nil, usage: &usage)
        let all = try OriginalPolynomialRelation(variableCount: 2, polynomials: [], predicate: predicate,
            domains: [unbounded,unbounded], usage: &usage)
        let region = try resolver.decompose(all, maximumDepth: 24, usage: usage)
        #expect(region.cells.count == 1 && region.components.first?.dimension == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonrepresentableEndpointAndAlgebraicSamplesRetainOriginalValues() throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let three = try ExactRationalCoefficient.originalDouble(3, usage: &usage)
        let third = try ExactRationalCoefficient.one.divided(by: three, usage: &usage)
        let law = try x.subtracting(.constant(variableCount: 1, value: third, usage: &usage), usage: &usage)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 1, instructions: [.sign(polynomial: 0, .zero)], usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: third, upper: third, usage: &usage)
        let input = try OriginalPolynomialRelation(variableCount: 1, polynomials: [law], predicate: predicate,
            domains: [domain], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        let exact = try #require(result.cells.first?.sample.first).enclosed(maximumDepth: 24, usage: usage)
        #expect(exact.lower == third && exact.upper == third)
        let rounded = try ExactRationalCoefficient.originalDouble(1.0/3.0, usage: &usage)
        #expect(try !result.contains(rationalPoint: [rounded], maximumDepth: 24, usage: usage))
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
        let quadratic = try x.multiplied(by: x, usage: &usage)
            .subtracting(.constant(variableCount: 1, value: two, usage: &usage), usage: &usage)
        let roots = try resolver.decompose(relation([quadratic], instructions: [.sign(polynomial: 0, .zero)], usage: &usage),
            maximumDepth: 24, usage: usage)
        #expect(roots.cells.count == 2 && roots.components.count == 2)
        let width = try ExactRationalCoefficient.originalDouble(1.0/1024.0, usage: &usage)
        for cell in roots.cells {
            let initial = try cell.sample[0].enclosed(maximumDepth: 24, usage: usage)
            let refined = try initial.refined(maximumWidth: width, maximumDepth: 24, usage: usage)
            #expect(try refined.lower.subtracting(initial.lower, usage: &usage).canonicalSign >= 0)
            #expect(try initial.upper.subtracting(refined.upper, usage: &usage).canonicalSign >= 0)
            #expect(try width.subtracting(refined.upper.subtracting(refined.lower, usage: &usage), usage: &usage).canonicalSign >= 0)
            #expect(refined.sourceDepth >= initial.sourceDepth)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidBindingAndIndependentLimitsCannotPublishACompleteRelation() throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        #expect(throws: KernelError.self) {
            try OriginalPolynomialPredicate(polynomialCount: 1, instructions: [.sign(polynomial: 1,.zero)], usage: &usage)
        }
        #expect(throws: KernelError.self) {
            try OriginalRationalPolynomial(variableCount: 1, terms: [.init(coefficient: .one, powers: [-1])], usage: &usage)
        }
        let input = try relation([x], instructions: [.sign(polynomial: 0,.zero)], usage: &usage)
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 24, usage: Budget(work: 0).usage) }
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 24, usage: Budget(storage: 0).usage) }
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: -1, usage: usage) }
        let first = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        let second = try resolver.decompose(input, maximumDepth: 24, usage: usage)
        let foreign = try #require(second.cells.first?.identifier)
        #expect(first.cells.first?.identifier != foreign)
        #expect(throws: KernelError.self) {
            try first.contains(rationalPoint: [.zero], inCell: foreign, maximumDepth: 24, usage: usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPublicEntryCannotReturnEvenAnEmptyRelation() async throws {
        let budget = Budget(); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let input = try relation([x], instructions: [.literal(false)], usage: &usage)
        let operationBudget = Budget()
        let gate = Mutex(false)
        let task = Task {
            while !gate.withLock({ $0 }) { await Task.yield() }
            return try resolver.decompose(input, maximumDepth: 24, usage: operationBudget.usage)
        }
        task.cancel(); gate.withLock { $0 = true }
        do { _ = try await task.value; Issue.record("Cancelled original relation published a result.") }
        catch is CancellationError {}
        #expect(operationBudget.consumedWork == 0)
    }

    private func relation(_ polynomials: [OriginalRationalPolynomial],
        instructions: [OriginalPolynomialPredicate.Instruction], bounded: Bool = false,
        usage: inout OriginalRelationUsage) throws -> OriginalPolynomialRelation {
        let count = try #require(polynomials.first?.variableCount)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: polynomials.count, instructions: instructions, usage: &usage)
        let domain = bounded
            ? try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &usage)
            : try OriginalRationalParameterDomain(nil, usage: &usage)
        return try OriginalPolynomialRelation(variableCount: count, polynomials: polynomials,
            predicate: predicate, domains: Array(repeating: domain, count: count), usage: &usage)
    }
}
