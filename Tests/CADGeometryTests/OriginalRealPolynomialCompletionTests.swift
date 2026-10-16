import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(1)))
struct OriginalRealPolynomialCompletionTests {
    private final class Budget: Sendable {
        private struct State { var work = 0, storage = 0, cells = 0, coefficientCells = 0 }
        private let state = Mutex(State())
        private let maximumWork: Int, maximumStorage: Int, maximumCells: Int, maximumCoefficientCells: Int
        init(work: Int = 20_000_000, storage: Int = 20_000_000,
            cells: Int = 100_000, coefficientCells: Int = 100_000) {
            maximumWork = work; maximumStorage = storage
            maximumCells = cells; maximumCoefficientCells = coefficientCells
        }
        var usage: GeometryTestScalarRecorder { instrument() }
        func instrument(onWork: @escaping (Int) -> Void = { _ in },
            onStorage: @escaping (Int) -> Void = { _ in },
            onValue: @escaping (Int) -> Void = { _ in },
            onCoefficient: @escaping (Int) -> Void = { _ in }) -> GeometryTestScalarRecorder {
            .init(maximumValueDepth: 24, maximumCoefficientDepth: 24, observeWork: { count in
                try self.state.withLock { s in
                    guard count <= self.maximumWork - s.work else { throw Self.exhausted() }; s.work += count
                }
            
                onWork(count)
            }, observeStorageWords: { count in
                try self.state.withLock { s in
                    guard count <= self.maximumStorage - s.storage else { throw Self.exhausted() }; s.storage += count
                }
            
                onStorage(count)
            }, observeValueCell: { depth in
                try self.state.withLock { s in
                    guard depth <= 24, s.cells < self.maximumCells else { throw Self.exhausted() }; s.cells += 1
                }
            
                onValue(depth)
            }, observeCoefficientCell: { depth in
                try self.state.withLock { s in
                    guard depth <= 24, s.coefficientCells < self.maximumCoefficientCells else { throw Self.exhausted() }
                    s.coefficientCells += 1
                }
            
                onCoefficient(depth)
            })
        }
        private static func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original polynomial completion fixture exhausted its independent caller allowance.")
        }
    }
    private final class CallbackObserver: Sendable {
        private let base: Budget
        private let cancelAt: Int?
        private let completed = Mutex(0)
        init(base: Budget, cancelAt: Int? = nil) { self.base = base; self.cancelAt = cancelAt }
        var count: Int { completed.withLock { $0 } }
        var usage: GeometryTestScalarRecorder {
            base.instrument(onWork: { _ in self.didComplete() },
                onStorage: { _ in self.didComplete() }, onValue: { _ in self.didComplete() },
                onCoefficient: { _ in self.didComplete() })
        }
        private func didComplete() {
            let final = completed.withLock { $0 += 1; return $0 == cancelAt }
            if final { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    private let resolver: any OriginalPolynomialRelationResolving = DefaultOriginalPolynomialRelationResolver()

    private func rationalInput(_ laws: [OriginalRationalPolynomial], count: Int,
        instructions: [OriginalPolynomialPredicate.Instruction], domains: [OriginalRationalParameterDomain],
        usage: inout GeometryTestScalarRecorder) throws -> OriginalPolynomialRelation {
        try .init(variableCount: count, polynomials: laws,
            predicate: .init(polynomialCount: laws.count, instructions: instructions, usage: &usage),
            domains: domains, usage: &usage)
    }

    @Test(arguments: [3, 4])
    func everyPublicGeometricDimensionRetainsClosedCellComponents(count: Int) throws {
        for dimension in 0...count {
            let budget = Budget(work: 10_000_000, storage: 10_000_000); var usage = budget.usage
            var laws: [OriginalRationalPolynomial] = []
            var instructions: [OriginalPolynomialPredicate.Instruction] = [.literal(true)]
            for axis in dimension..<count {
                laws.append(try .coordinate(variableCount: count, at: axis, usage: &usage))
                instructions.append(.sign(polynomial: laws.count - 1, .zero)); instructions.append(.and)
            }
            let domain = try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &usage)
            let input = try rationalInput(laws, count: count, instructions: instructions,
                domains: Array(repeating: domain, count: count), usage: &usage)
            let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
            #expect(result.components.count == 1 && result.components[0].dimension == dimension)
            #expect(Set(result.cells.map { $0.dimension }) == Set(0...dimension))
            #expect(result.cells.allSatisfy { $0.sample.count == count && $0.sourceSigns.allSatisfy { $0 == .zero } })
            #expect(result.components[0].cellIdentifiers.count == result.cells.count)
            #expect(result.cells.allSatisfy { result.components[0].cellIdentifiers.contains($0.identifier) })
            #expect(try result.contains(rationalPoint: Array(repeating: .zero, count: count),
                maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
            if dimension < count {
                var outside = Array(repeating: ExactRationalCoefficient.zero, count: count); outside[dimension] = .one
                #expect(try !result.contains(rationalPoint: outside, maximumDepth: 24,
                    maximumCoefficientDepth: 0, usage: &usage))
            }
        }
    }

    @Test func mixedPlaneAndIsolatedPointRemainSeparateCompleteComponents() throws {
        let budget = Budget(work: 10_000_000, storage: 10_000_000); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
        let z = try OriginalRationalPolynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
        let atOne = try z.subtracting(.constant(variableCount: 3, value: .one, usage: &usage), usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &usage)
        let input = try rationalInput([z,x,y,atOne], count: 3, instructions: [
            .sign(polynomial: 0, .zero), .sign(polynomial: 1, .zero),
            .sign(polynomial: 2, .zero), .and, .sign(polynomial: 3, .zero), .and, .or
        ], domains: [domain,domain,domain], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        #expect(result.components.map { $0.dimension }.sorted() == [0,2])
        #expect(result.components.flatMap { $0.cellIdentifiers }.count == result.cells.count)
        #expect(try result.contains(rationalPoint: [.one,.one.negated,.zero], maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: &usage))
        #expect(try result.contains(rationalPoint: [.zero,.zero,.one], maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: &usage))
        #expect(try !result.contains(rationalPoint: [.one,.zero,.one], maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: &usage))
    }

    @Test func fourCoordinateSingularCrossingRetainsEveryExceptionalBranch() throws {
        let budget = Budget(work: 10_000_000, storage: 10_000_000); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 0, usage: &usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 1, usage: &usage)
        let z = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 2, usage: &usage)
        let w = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 3, usage: &usage)
        let crossing = try x.multiplied(by: y, usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: .one.negated, upper: .one, usage: &usage)
        let fixed = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let input = try rationalInput([crossing,z,w], count: 4, instructions: [
            .sign(polynomial: 0, .zero), .sign(polynomial: 1, .zero), .and,
            .sign(polynomial: 2, .zero), .and
        ], domains: [domain,domain,fixed,fixed], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        #expect(result.components.count == 1 && result.components[0].dimension == 1)
        let half = try ExactRationalCoefficient.one.divided(by: .originalDouble(2, usage: &usage), usage: &usage)
        var branchOwners: [OriginalRealRelation.CellIdentifier] = []
        for point: [ExactRationalCoefficient] in [[half,.zero,.zero,.zero], [half.negated,.zero,.zero,.zero],
            [.zero,half,.zero,.zero], [.zero,half.negated,.zero,.zero]] {
            var owners: [OriginalRealRelation.CellIdentifier] = []
            for cell in result.cells where cell.dimension == 1 {
                if try result.contains(rationalPoint: point, inCell: cell.identifier,
                    maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage) { owners.append(cell.identifier) }
            }
            #expect(owners.count == 1)
            branchOwners.append(try #require(owners.first))
        }
        #expect(branchOwners[0] != branchOwners[1])
        #expect(branchOwners[0] != branchOwners[2] && branchOwners[0] != branchOwners[3])
        #expect(branchOwners[1] != branchOwners[2] && branchOwners[1] != branchOwners[3])
        for point: [ExactRationalCoefficient] in [[.zero,.zero,.zero,.zero], [.one,.zero,.zero,.zero],
            [.one.negated,.zero,.zero,.zero], [.zero,.one,.zero,.zero], [.zero,.one.negated,.zero,.zero]] {
            #expect(try result.contains(rationalPoint: point, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
        }
        #expect(try !result.contains(rationalPoint: [.one,.one,.zero,.zero], maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: &usage))
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            var refused = Budget(cells: 0).usage
            try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &refused)
        }
    }

    @Test func repeatedCloseRootsRetainTwoOriginalFourCoordinateIdentities() throws {
        let budget = Budget(work: 10_000_000, storage: 10_000_000); var usage = budget.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 0, usage: &usage)
        let station = try ExactRationalCoefficient.one.divided(by: .originalDouble(1024, usage: &usage), usage: &usage)
        let other = try x.subtracting(.constant(variableCount: 4, value: station, usage: &usage), usage: &usage)
        let product = try x.multiplied(by: other, usage: &usage)
        var laws = [try product.multiplied(by: product, usage: &usage)]
        var instructions: [OriginalPolynomialPredicate.Instruction] = [.sign(polynomial: 0, .zero)]
        for axis in 1..<4 {
            laws.append(try .coordinate(variableCount: 4, at: axis, usage: &usage))
            instructions.append(.sign(polynomial: axis, .zero)); instructions.append(.and)
        }
        let interval = try OriginalRationalParameterDomain(lower: .zero, upper: station, usage: &usage)
        let fixed = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let input = try rationalInput(laws, count: 4, instructions: instructions,
            domains: [interval,fixed,fixed,fixed], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        #expect(result.cells.count == 2 && result.components.count == 2)
        #expect(result.cells.allSatisfy { $0.dimension == 0 && $0.sample.count == 4 })
        #expect(result.cells[0].identifier != result.cells[1].identifier)
        for point: [ExactRationalCoefficient] in [[.zero,.zero,.zero,.zero],[station,.zero,.zero,.zero]] {
            #expect(try result.contains(rationalPoint: point, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage))
        }
        let midpoint = try station.divided(by: .originalDouble(2, usage: &usage), usage: &usage)
        #expect(try !result.contains(rationalPoint: [midpoint,.zero,.zero,.zero], maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: &usage))
        for cell in result.cells {
            let enclosed = try cell.sample[0].enclosed(maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
            #expect(enclosed.lower == enclosed.upper)
            #expect(enclosed.lower == .zero || enclosed.lower == station)
        }
    }

    @Test func terminalAdmissionCannotPublishANonemptyRelation() async throws {
        let construction = Budget(); var usage = construction.usage
        let domain = try OriginalRationalParameterDomain(nil, usage: &usage)
        let input = try rationalInput([], count: 1, instructions: [.literal(true)], domains: [domain], usage: &usage)
        let baseline = CallbackObserver(base: Budget())
        var baselineAdmission = baseline.usage
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &baselineAdmission)
        #expect(result.cells.count == 1 && result.components[0].dimension == 1)
        let finalOrdinal = baseline.count
        let cancelled = CallbackObserver(base: Budget(), cancelAt: finalOrdinal)
        let task = Task {
            var cancelledAdmission = cancelled.usage
            return try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &cancelledAdmission)
        }
        do { _ = try await task.value; Issue.record("The last normal-return admission published a cancelled relation.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(cancelled.count == finalOrdinal)
    }

    @Test(arguments: [false, true])
    func terminalAdmissionCannotPublishTrueOrFalseMembership(included: Bool) async throws {
        let construction = Budget(); var usage = construction.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let input = try rationalInput([x], count: 1, instructions: [.sign(polynomial: 0, .zero)],
            domains: [domain], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        let point: [ExactRationalCoefficient] = [included ? .zero : .one]
        let baseline = CallbackObserver(base: Budget())
        var baselineAdmission = baseline.usage
        #expect(try result.contains(rationalPoint: point, maximumDepth: 24,
            maximumCoefficientDepth: 0, usage: &baselineAdmission) == included)
        let finalOrdinal = baseline.count
        let cancelled = CallbackObserver(base: Budget(), cancelAt: finalOrdinal)
        let task = Task {
            var cancelledAdmission = cancelled.usage
            return try result.contains(rationalPoint: point, maximumDepth: 24,
                maximumCoefficientDepth: 0, usage: &cancelledAdmission)
        }
        do { _ = try await task.value; Issue.record("The last normal-return admission published cancelled membership.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(cancelled.count == finalOrdinal)
    }

    @Test func emptyMembershipRejectsNormalReturnEntryCancellation() async throws {
        let construction = Budget(); var usage = construction.usage
        let domain = try OriginalRationalParameterDomain(nil, usage: &usage)
        let input = try rationalInput([], count: 1, instructions: [.literal(false)], domains: [domain], usage: &usage)
        let result = try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        let cancelled = CallbackObserver(base: Budget(), cancelAt: 1)
        let task = Task {
            var cancelledAdmission = cancelled.usage
            return try result.contains(rationalPoint: [.zero], maximumDepth: 24,
                maximumCoefficientDepth: 0, usage: &cancelledAdmission)
        }
        do { _ = try await task.value; Issue.record("An empty relation published cancelled false membership.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(cancelled.count == 1)
    }

    private func releasedOrderedInput(positive: Bool, dimension: Int, usage: inout GeometryTestScalarRecorder)
        throws -> OriginalRealRelation {
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let two = try OriginalRationalPolynomial.constant(variableCount: 1, value: .originalDouble(2, usage: &usage), usage: &usage)
        let quadratic = try x.multiplied(by: x, usage: &usage).subtracting(two, usage: &usage)
        let all = try OriginalRationalParameterDomain(nil, usage: &usage)
        let rootsInput = try rationalInput([quadratic], count: 1,
            instructions: [.sign(polynomial: 0, .zero)], domains: [all], usage: &usage)
        let roots = try resolver.decompose(rootsInput, maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        let scalar = try #require(positive ? roots.cells.last?.sample[0] : roots.cells.first?.sample[0])
        let minusOne = try OriginalAlgebraicCoordinate.rational(.one.negated, usage: &usage)
        let law = try OriginalOrderedPolynomial(variableCount: 4, terms: [
            .init(coefficient: scalar, powers: [0,0,0,0]), .init(coefficient: minusOne, powers: [1,0,0,0])
        ], maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 1,
            instructions: [.sign(polynomial: 0, dimension == 4 ? .positive : .zero)], usage: &usage)
        let fixed = try OriginalRationalParameterDomain(lower: .zero, upper: .zero, usage: &usage)
        let input = try OriginalPolynomialRelation(variableCount: 4, orderedPolynomials: [law], predicate: predicate,
            domains: [all, dimension == 0 ? fixed : all, dimension == 0 ? fixed : all,
                dimension == 0 ? fixed : all], usage: &usage)
        return try resolver.decompose(input, maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
    }

    @Test(arguments: [false, true], [0, 3, 4])
    func releasedOrderedSourcesRetainConjugatesDimensionsAndRefinement(positive: Bool, dimension: Int) throws {
        let budget = Budget(); var usage = budget.usage
        let result = try releasedOrderedInput(positive: positive, dimension: dimension, usage: &usage)
        #expect(result.components.count == 1 && result.components[0].dimension == dimension)
        #expect(result.cells.allSatisfy { $0.sample.count == 4 && $0.sourceSigns == [dimension == 4 ? .positive : .zero] })
        let retainedSample = try #require(result.cells.first?.sample[0])
        let initial = try retainedSample.enclosed(maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        let width = try ExactRationalCoefficient.one.divided(by: .originalDouble(1024, usage: &usage), usage: &usage)
        let refined = try initial.refined(maximumWidth: width, maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
        #expect(try refined.lower.subtracting(initial.lower, usage: &usage).canonicalSign >= 0)
        #expect(try initial.upper.subtracting(refined.upper, usage: &usage).canonicalSign >= 0)
        #expect(try width.subtracting(refined.upper.subtracting(refined.lower, usage: &usage), usage: &usage).canonicalSign >= 0)
        if dimension != 4 {
            let sample = try #require(result.cells.first?.sample[0])
                .enclosed(maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
                .refined(maximumWidth: width, maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage)
            #expect(positive ? sample.lower.canonicalSign > 0 : sample.upper.canonicalSign < 0)
            #expect(try !result.contains(rationalPoint: [.zero,.zero,.zero,.zero], maximumDepth: 24,
                maximumCoefficientDepth: 24, usage: &usage))
        } else {
            #expect(try result.contains(rationalPoint: [.zero,.zero,.zero,.zero], maximumDepth: 24,
                maximumCoefficientDepth: 24, usage: &usage) == positive)
        }
        #expect(try !result.contains(rationalPoint: [.originalDouble(2, usage: &usage),.zero,.zero,.zero],
            maximumDepth: 24, maximumCoefficientDepth: 24, usage: &usage))
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try retainedSample.enclosed(maximumDepth: 24, maximumCoefficientDepth: 0, usage: &usage)
        }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try result.contains(rationalPoint: [.zero,.zero,.zero,.zero], maximumDepth: 24,
                maximumCoefficientDepth: 0, usage: &usage)
        }
    }
}
