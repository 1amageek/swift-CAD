import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OriginalOrderedPolynomialRelationTests {
    private final class Budget: Sendable {
        private struct State { var work = 0, storage = 0, parameterDepth = 0, coefficientDepth = 0 }
        private let state = Mutex(State())
        private let maximumWork: Int, maximumStorage: Int
        init(work: Int = 20_000_000, storage: Int = 20_000_000) {
            maximumWork = work; maximumStorage = storage
        }
        var spent: Int { state.withLock { $0.work } }
        var depths: (parameter: Int, coefficient: Int) { state.withLock { ($0.parameterDepth, $0.coefficientDepth) } }
        var usage: OriginalRelationUsage {
            .init(consumeWork: { count in
                try self.state.withLock { s in
                    guard count <= self.maximumWork - s.work else { throw Self.failure() }; s.work += count
                }
            }, retainStorage: { count in
                try self.state.withLock { s in
                    guard count <= self.maximumStorage - s.storage else { throw Self.failure() }; s.storage += count
                }
            }, visitCell: { depth in
                try self.state.withLock { s in
                    guard depth <= 24 else { throw Self.failure() }; s.parameterDepth = max(s.parameterDepth, depth)
                }
            }, visitCoefficientCell: { depth in
                try self.state.withLock { s in
                    guard depth <= 24 else { throw Self.failure() }; s.coefficientDepth = max(s.coefficientDepth, depth)
                }
            })
        }
        private static func failure() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Public ordered fixture exhausted its unchanged independent allowance.")
        }
    }
    private let resolver: any OriginalPolynomialRelationResolving = DefaultOriginalPolynomialRelationResolver()

    private func originalRoots(positiveOnly: Bool = false, usage: inout OriginalRelationUsage) throws -> OriginalRealRelation {
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let two = try OriginalRationalPolynomial.constant(variableCount: 1, value: .natural(2, usage: &usage), usage: &usage)
        let law = try x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 1,
            instructions: [.sign(polynomial: 0, positiveOnly ? .positive : .zero)], usage: &usage)
        let all = try OriginalRationalParameterDomain(nil, usage: &usage)
        return try resolver.decompose(.init(variableCount: 1, polynomials: [law], predicate: predicate,
            domains: [all], usage: &usage), maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage)
    }
    private func relation(_ laws: [OriginalOrderedPolynomial], signs: [OriginalPolynomialPredicate.Instruction],
        usage: inout OriginalRelationUsage) throws -> OriginalPolynomialRelation {
        let count = try #require(laws.first?.variableCount)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: laws.count, instructions: signs, usage: &usage)
        let all = try OriginalRationalParameterDomain(nil, usage: &usage)
        return try .init(variableCount: count, orderedPolynomials: laws, predicate: predicate,
            domains: Array(repeating: all, count: count), usage: &usage)
    }

    @Test func publicSourceSamplesRetainOppositeConjugatesAndGeometricMembership() throws {
        var usage = Budget().usage
        let roots = try originalRoots(usage: &usage)
        #expect(roots.cells.count == 2)
        let minusOne = try OriginalAlgebraicCoordinate.rational(.one.negated, usage: usage)
        for source in roots.cells {
            let coefficient = source.sample[0]
            let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [
                .init(coefficient: coefficient, powers: [0]), .init(coefficient: minusOne, powers: [1])
            ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
            let result = try resolver.decompose(relation([law], signs: [.sign(polynomial: 0, .positive)], usage: &usage),
                maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
            let initial = try coefficient.enclosed(maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
            let width = try ExactRationalCoefficient.one.divided(by: .natural(4, usage: &usage), usage: &usage)
            let box = try initial.refined(maximumWidth: width, maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
            let positive = box.lower.canonicalSign >= 0
            #expect(result.components.count == 1 && result.components[0].dimension == 1)
            #expect(result.cells.allSatisfy { $0.sample.count == 1 && $0.sourceSigns == [.positive] })
            #expect(try result.contains(rationalPoint: [.zero], maximumDepth: 24,
                maximumCoefficientDepth: 24, usage: usage) == positive)
            #expect(try result.contains(rationalPoint: [.natural(2, usage: &usage)], maximumDepth: 24,
                maximumCoefficientDepth: 24, usage: usage) == false)
            #expect(try result.contains(rationalPoint: [.natural(2, usage: &usage).negated], maximumDepth: 24,
                maximumCoefficientDepth: 24, usage: usage))
        }
    }

    @Test(arguments: [false, true])
    func publicOrderedPositiveComplexDimensionReturnsActualRealPointOrAbsence(absent: Bool) throws {
        var usage = Budget().usage
        let source = try #require(originalRoots(usage: &usage).cells.last).sample[0]
        var terms = [OriginalOrderedPolynomial.Term(coefficient: source, powers: [2,0]),
            .init(coefficient: source, powers: [0,2])]
        if absent { terms.append(.init(coefficient: try .rational(.one, usage: usage), powers: [0,0])) }
        let law = try OriginalOrderedPolynomial(variableCount: 2, terms: terms,
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        let result = try resolver.decompose(relation([law], signs: [.sign(polynomial: 0, .zero)], usage: &usage),
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        #expect(result.cells.count == (absent ? 0 : 1))
        #expect(result.components.count == (absent ? 0 : 1))
        #expect(try result.contains(rationalPoint: [.zero,.zero], maximumDepth: 24,
            maximumCoefficientDepth: 24, usage: usage) == !absent)
        if !absent { #expect(result.cells[0].dimension == 0 && result.cells[0].sample.count == 2) }
    }

    @Test func actualNormalizedSourceDirectionPublishesThroughThePublicWitness() throws {
        let budget = Budget(); var usage = budget.usage
        let context = try OriginalSingularFieldContext(usage: &usage)
        let frame = try OriginalRationalNormalizedFrame(family: .axis2, location: .zero,
            axis1: .unitZ, axis2: nil, axis3: Vector3D(x: 1, y: 1, z: 0), scale: nil,
            lengthGain: .one, adjustments: [], in: context, tolerance: .standard,
            normalizationPolicy: .dimensionlessOriginalDirections, inheritedDepth: 0, maximumDepth: 24, usage: &usage)
        let original = OriginalAlgebraicCoordinate(original: frame.basisZ[0], inheritedDepth: 0)
        let minusOne = try OriginalAlgebraicCoordinate.rational(.one.negated, usage: usage)
        let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [
            .init(coefficient: original, powers: [0]), .init(coefficient: minusOne, powers: [1])
        ], maximumDepth: 0, maximumCoefficientDepth: 24, usage: usage)
        let result = try resolver.decompose(relation([law], signs: [.sign(polynomial: 0, .zero)], usage: &usage),
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        #expect(result.cells.count == 1 && result.cells[0].dimension == 0)
        #expect(result.cells[0].sample.count == 1 && result.cells[0].coefficientAdmissionDepth > 0)
        #expect(budget.depths.coefficient > 0)
        let rounded = try ExactRationalCoefficient.originalDouble(1 / 2.squareRoot(), usage: &usage)
        #expect(try !result.contains(rationalPoint: [rounded], maximumDepth: 24,
            maximumCoefficientDepth: 24, usage: usage))
    }

    @Test func rationalSectorSamplesAndZeroDerivativesPreserveCausalDepth() throws {
        var usage = Budget().usage
        let regions = try originalRoots(positiveOnly: true, usage: &usage)
        let source = try #require(regions.cells.first).sample[0]
        #expect(source.inheritedDepth > source.original.context.depth)
        let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: source, powers: [0])],
            maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage)
        #expect(throws: KernelError.self) {
            try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: source, powers: [0])],
                maximumDepth: 0, maximumCoefficientDepth: 0, usage: usage)
        }
        let derivative = try law.differentiated(at: 0, maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage)
        let input = try relation([derivative], signs: [.sign(polynomial: 0, .zero)], usage: &usage)
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 0, maximumCoefficientDepth: 0, usage: usage) }
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage)
        #expect(result.cells.count == 1 && result.cells[0].dimension == 1)
        #expect(result.cells[0].admissionDepth >= source.inheritedDepth)
    }

    @Test func removedZeroTermsRetainBothSourceDepthDomains() throws {
        var usage = Budget().usage
        let context = try OriginalSingularFieldContext(usage: &usage)
        let zero = OriginalAlgebraicCoordinate(original: try .constant(.zero, in: context, maximumDepth: 0, usage: &usage),
            inheritedDepth: 7, inheritedCoefficientDepth: 5)
        let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: zero, powers: [0])],
            maximumDepth: 7, maximumCoefficientDepth: 5, usage: usage)
        let input = try relation([law], signs: [.sign(polynomial: 0, .zero)], usage: &usage)
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 6, maximumCoefficientDepth: 5, usage: usage) }
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 7, maximumCoefficientDepth: 4, usage: usage) }
        let result = try resolver.decompose(input, maximumDepth: 7, maximumCoefficientDepth: 5, usage: usage)
        #expect(result.cells[0].admissionDepth == 7 && result.cells[0].coefficientAdmissionDepth == 5)
        #expect(throws: KernelError.self) {
            try result.contains(rationalPoint: [.zero], maximumDepth: 7, maximumCoefficientDepth: 4, usage: usage)
        }
    }

    @Test func actualCoefficientTransportAndScalarRefinementRetainInheritedDepths() throws {
        let budget = Budget(); var usage = budget.usage
        let source = try #require(originalRoots(usage: &usage).cells.last).sample[0]
        let inherited = max(6, source.inheritedDepth)
        let value = try OriginalIntersectionCoefficient.prepare(original: source.original, maximumDepth: 24,
            maximumCoefficientDepth: 24, inheritedParameterDepth: inherited, inheritedCoefficientDepth: 5, usage: &usage)
        #expect(value.parameterAdmissionDepth >= inherited && value.coefficientAdmissionDepth >= 5)
        #expect(budget.depths.parameter >= inherited && budget.depths.coefficient >= 5)
        #expect(throws: KernelError.self) {
            try OriginalIntersectionCoefficient.prepare(original: source.original, maximumDepth: inherited - 1,
                maximumCoefficientDepth: 24, inheritedParameterDepth: inherited, usage: &usage)
        }
        let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: source, powers: [1])],
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        let result = try resolver.decompose(relation([law], signs: [.sign(polynomial: 0, .zero)], usage: &usage),
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        let coordinate = result.cells[0].sample[0]
        #expect(coordinate.inheritedCoefficientDepth > 0)
        #expect(throws: KernelError.self) { try coordinate.enclosed(maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage) }
        let enclosure = try coordinate.enclosed(maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        #expect(enclosure.coefficientAdmissionDepth >= coordinate.inheritedCoefficientDepth)
        #expect(throws: KernelError.self) {
            try enclosure.refined(maximumWidth: .one, maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage)
        }
    }

    @Test func independentPublicLimitsAndForeignIdentifiersCannotPublishSuccess() throws {
        var usage = Budget().usage
        let source = try #require(originalRoots(usage: &usage).cells.last).sample[0]
        let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: source, powers: [1])],
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        #expect(throws: KernelError.self) {
            try OriginalOrderedPolynomial(variableCount: 0, terms: [], maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        }
        #expect(throws: KernelError.self) {
            try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: source, powers: [-1])],
                maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        }
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 1, instructions: [.sign(polynomial: 0, .zero)], usage: &usage)
        let domain = try OriginalRationalParameterDomain(nil, usage: &usage)
        #expect(throws: KernelError.self) {
            try OriginalPolynomialRelation(variableCount: 2, orderedPolynomials: [law], predicate: predicate,
                domains: [domain, domain], usage: &usage)
        }
        let input = try relation([law], signs: [.sign(polynomial: 0, .zero)], usage: &usage)
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 0, maximumCoefficientDepth: 24, usage: usage) }
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage) }
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 24, usage: Budget(work: 0).usage) }
        #expect(throws: KernelError.self) { try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 24, usage: Budget(storage: 0).usage) }
        let first = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        let other = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        #expect(throws: KernelError.self) {
            try first.contains(rationalPoint: [.zero], maximumDepth: 24, maximumCoefficientDepth: 0, usage: usage)
        }
        #expect(throws: KernelError.self) {
            try first.contains(rationalPoint: [.zero], inCell: other.cells[0].identifier,
                maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        }
    }

    @Test func publicOrderedCancellationConsumesNoNewWork() async throws {
        var usage = Budget().usage
        let source = try #require(originalRoots(usage: &usage).cells.last).sample[0]
        let law = try OriginalOrderedPolynomial(variableCount: 1, terms: [.init(coefficient: source, powers: [0])],
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: usage)
        let input = try relation([law], signs: [.literal(true)], usage: &usage)
        let budget = Budget(), gate = Mutex(false)
        let task = Task {
            while !gate.withLock({ $0 }) { await Task.yield() }
            return try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 24, usage: budget.usage)
        }
        task.cancel(); gate.withLock { $0 = true }
        do { _ = try await task.value; Issue.record("Cancelled public ordered relation published a result.") }
        catch is CancellationError {}
        #expect(budget.spent == 0)
    }
}
