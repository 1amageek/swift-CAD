import CADCore
import CADGeometry

/// Direct public decomposition and exact result queries, common to all targets.
@available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
enum OriginalRealRelationProof {
    private enum Failure: Error { case incorrectResult, unexpectedSuccess, missingSource }
    private static let depth = 24
    private static var resolver: any OriginalPolynomialRelationResolving { DefaultOriginalPolynomialRelationResolver() }
    private static func require(_ value: Bool) throws {
        guard value else { throw Failure.incorrectResult }
    }
    private static func q(_ value: Double, _ usage: inout OriginalRelationUsage) throws -> ExactRationalCoefficient {
        try .originalDouble(value, usage: &usage)
    }
    private static func rational(_ count: Int, _ laws: [OriginalRationalPolynomial],
        _ instructions: [OriginalPolynomialPredicate.Instruction],
        domains: [OriginalRationalParameterDomain]? = nil,
        usage: inout OriginalRelationUsage) throws -> OriginalPolynomialRelation {
        let predicate = try OriginalPolynomialPredicate(polynomialCount: laws.count,
            instructions: instructions, usage: &usage)
        let all = try OriginalRationalParameterDomain(nil, usage: &usage)
        return try .init(variableCount: count, polynomials: laws, predicate: predicate,
            domains: domains ?? Array(repeating: all, count: count), usage: &usage)
    }
    private static func ordered(_ count: Int, _ laws: [OriginalOrderedPolynomial],
        _ instructions: [OriginalPolynomialPredicate.Instruction],
        domains: [OriginalRationalParameterDomain]? = nil,
        usage: inout OriginalRelationUsage) throws -> OriginalPolynomialRelation {
        let predicate = try OriginalPolynomialPredicate(polynomialCount: laws.count,
            instructions: instructions, usage: &usage)
        let all = try OriginalRationalParameterDomain(nil, usage: &usage)
        return try .init(variableCount: count, orderedPolynomials: laws, predicate: predicate,
            domains: domains ?? Array(repeating: all, count: count), usage: &usage)
    }
    private static func decompose(_ input: OriginalPolynomialRelation,
        usage: OriginalRelationUsage, coefficientDepth: Int = 0) throws -> OriginalRealRelation {
        try resolver.decompose(input, maximumDepth: depth,
            maximumCoefficientDepth: coefficientDepth, usage: usage)
    }
    private static func check(_ result: OriginalRealRelation,
        dimensions: [Int]) throws {
        try require(result.components.count == dimensions.count)
        for dimension in dimensions {
            try require(result.components.filter { $0.dimension == dimension }.count
                == dimensions.filter { $0 == dimension }.count)
        }
        for cell in result.cells {
            try require(cell.sample.count == result.original.variableCount
                && cell.sourceSigns.count == result.original.polynomials.count)
            var membershipCount = 0
            for component in result.components {
                if component.cellIdentifiers.contains(cell.identifier) { membershipCount += 1 }
            }
            try require(membershipCount == 1)
        }
        for component in result.components {
            var actualDimension = -1
            for identifier in component.cellIdentifiers {
                guard let cell = result.cells.first(where: { $0.identifier == identifier }) else {
                    throw Failure.incorrectResult
                }
                actualDimension = max(actualDimension, cell.dimension)
            }
            try require(actualDimension == component.dimension)
        }
    }
    private static func contains(_ result: OriginalRealRelation, _ point: [ExactRationalCoefficient],
        _ expected: Bool, usage: OriginalRelationUsage, coefficientDepth: Int = 0) throws {
        try require(result.contains(rationalPoint: point, maximumDepth: depth,
            maximumCoefficientDepth: coefficientDepth, usage: usage) == expected)
    }
    private static func expectKernelFailure(_ operation: () throws -> Void) throws {
        do { try operation() }
        catch is KernelError { return }
        throw Failure.unexpectedSuccess
    }
    private static func expectAllowanceFailure(_ expected: OriginalRealRelationAllowance.Failure,
        _ operation: () throws -> Void) throws {
        do { try operation() }
        catch let failure as OriginalRealRelationAllowance.Failure {
            try require(failure == expected); return
        }
        throw Failure.unexpectedSuccess
    }

    static nonisolated func run() throws {
        print("Q5_BEGIN_PUBLIC_RINGS_AND_DIMENSIONS")
        try dimensionsAndBinding()
        print("Q5_BEGIN_SINGULAR_MIXED_TOPOLOGY")
        try singularAndMixedTopology()
        print("Q5_BEGIN_EXACT_ROOTS_AND_DOMAINS")
        try domainsAndExactRoots()
        print("Q5_BEGIN_ORDERED_SOURCE_OWNERSHIP")
        try orderedOwnership()
        print("Q5_BEGIN_INDEPENDENT_ADMISSION")
        try independentAdmission()
        print("Q5_PUBLIC_REAL_RELATION_SUCCESS_FAILURE_MATRIX_OK")
    }

    private static func dimensionsAndBinding() throws {
        for count in 1...4 {
            for dimension in 0...count {
                let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
                var laws: [OriginalRationalPolynomial] = []
                var program: [OriginalPolynomialPredicate.Instruction] = [.literal(true)]
                for axis in dimension..<count {
                    laws.append(try .coordinate(variableCount: count, at: axis, usage: &usage))
                    program.append(.sign(polynomial: laws.count - 1, .zero)); program.append(.and)
                }
                let input = try rational(count, laws, program, usage: &usage)
                let result = try decompose(input, usage: usage)
                try check(result, dimensions: [dimension])
                try contains(result, Array(repeating: .zero, count: count), true, usage: usage)
                if dimension < count {
                    var outside = Array(repeating: ExactRationalCoefficient.zero, count: count)
                    outside[dimension] = .one
                    try contains(result, outside, false, usage: usage)
                }
            }
        }
        let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        try expectKernelFailure {
            _ = try OriginalRationalPolynomial.coordinate(variableCount: 0, at: 0, usage: &usage)
        }
        try expectKernelFailure {
            _ = try OriginalRationalPolynomial.coordinate(variableCount: 5, at: 0, usage: &usage)
        }
        try expectKernelFailure {
            _ = try OriginalPolynomialPredicate(polynomialCount: 1,
                instructions: [.sign(polynomial: 1, .zero)], usage: &usage)
        }
        let program = try OriginalPolynomialPredicate(polynomialCount: 1,
            instructions: [.sign(polynomial: 0, .zero)], usage: &usage)
        let all = try OriginalRationalParameterDomain(nil, usage: &usage)
        try expectKernelFailure {
            _ = try OriginalPolynomialRelation(variableCount: 2, polynomials: [x],
                predicate: program, domains: [all, all], usage: &usage)
        }
        print("Q5_PUBLIC_RINGS_1_TO_4_DIMENSIONS_0_TO_4_BINDING_OK")
    }

    private static func singularAndMixedTopology() throws {
        for absent in [false, true] {
            let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
            let x = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
            let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
            var law = try x.multiplied(by: x, usage: &usage).adding(y.multiplied(by: y, usage: &usage), usage: &usage)
            if absent { law = try law.adding(.constant(variableCount: 2, value: .one, usage: &usage), usage: &usage) }
            let result = try decompose(rational(2, [law], [.sign(polynomial: 0, .zero)], usage: &usage), usage: usage)
            try check(result, dimensions: absent ? [] : [0])
            try contains(result, [.zero, .zero], !absent, usage: usage)
        }
        do {
            let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
            let x = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 0, usage: &usage)
            let y = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 1, usage: &usage)
            let z = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 2, usage: &usage)
            let w = try OriginalRationalPolynomial.coordinate(variableCount: 4, at: 3, usage: &usage)
            let xy = try x.multiplied(by: y, usage: &usage)
            let input = try rational(4, [xy, z, w], [.sign(polynomial: 0, .zero),
                .sign(polynomial: 1, .zero), .and, .sign(polynomial: 2, .zero), .and], usage: &usage)
            let result = try decompose(input, usage: usage)
            try check(result, dimensions: [1])
            try contains(result, [.zero, .one, .zero, .zero], true, usage: usage)
            try contains(result, [.one, .one, .zero, .zero], false, usage: usage)
            func owner(of point: [ExactRationalCoefficient], minimumDimension: Int = 0,
                maximumDimension: Int = 1) throws -> OriginalRealRelation.CellIdentifier {
                try contains(result, point, true, usage: usage)
                var selected: OriginalRealRelation.CellIdentifier?
                for cell in result.cells {
                    if try result.contains(rationalPoint: point, inCell: cell.identifier,
                        maximumDepth: depth, maximumCoefficientDepth: 0, usage: usage) {
                        try require(selected == nil && cell.dimension >= minimumDimension
                            && cell.dimension <= maximumDimension)
                        selected = cell.identifier
                    }
                }
                guard let selected else { throw Failure.incorrectResult }
                return selected
            }
            _ = try owner(of: [.zero, .zero, .zero, .zero])
            let verticalPositive = try owner(of: [.zero, .one, .zero, .zero], minimumDimension: 1)
            let verticalNegative = try owner(of: [.zero, .one.negated, .zero, .zero], minimumDimension: 1)
            let horizontalPositive = try owner(of: [.one, .zero, .zero, .zero], minimumDimension: 1)
            let horizontalNegative = try owner(of: [.one.negated, .zero, .zero, .zero], minimumDimension: 1)
            try require(horizontalPositive != horizontalNegative)
            try require(horizontalPositive != verticalPositive && horizontalPositive != verticalNegative)
            try require(horizontalNegative != verticalPositive && horizontalNegative != verticalNegative)
        }
        do {
            let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
            let x = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
            let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
            let cusp = try y.multiplied(by: y, usage: &usage)
                .subtracting(x.multiplied(by: x, usage: &usage).multiplied(by: x, usage: &usage), usage: &usage)
            let result = try decompose(rational(2, [cusp], [.sign(polynomial: 0, .zero)], usage: &usage), usage: usage)
            try check(result, dimensions: [1])
            try contains(result, [.zero, .zero], true, usage: usage)
            try contains(result, [.one, .one], true, usage: usage)
            try contains(result, [.one.negated, .zero], false, usage: usage)
        }
        do {
            let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
            let x = try OriginalRationalPolynomial.coordinate(variableCount: 3, at: 0, usage: &usage)
            let y = try OriginalRationalPolynomial.coordinate(variableCount: 3, at: 1, usage: &usage)
            let z = try OriginalRationalPolynomial.coordinate(variableCount: 3, at: 2, usage: &usage)
            let atOne = try z.subtracting(.constant(variableCount: 3, value: .one, usage: &usage), usage: &usage)
            let input = try rational(3, [x, y, z, atOne], [.sign(polynomial: 2, .zero),
                .sign(polynomial: 0, .zero), .sign(polynomial: 1, .zero), .and,
                .sign(polynomial: 3, .zero), .and, .or], usage: &usage)
            let result = try decompose(input, usage: usage)
            try check(result, dimensions: [2, 0])
            try contains(result, [.zero, .zero, .one], true, usage: usage)
            try contains(result, [.one, .one, .zero], true, usage: usage)
            try contains(result, [.one, .zero, .one], false, usage: usage)
        }
        print("Q5_SINGULAR_EXCEPTIONAL_MIXED_CELLS_COMPONENTS_OK")
    }

    private static func domainsAndExactRoots() throws {
        let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let third = try ExactRationalCoefficient.one.divided(by: q(3, &usage), usage: &usage)
        let close = try ExactRationalCoefficient.one.divided(by: q(1024, &usage), usage: &usage)
        let atClose = try x.subtracting(.constant(variableCount: 1, value: close, usage: &usage), usage: &usage)
        let repeated = try x.multiplied(by: x, usage: &usage)
            .multiplied(by: atClose.multiplied(by: atClose, usage: &usage), usage: &usage)
        let roots = try decompose(rational(1, [repeated], [.sign(polynomial: 0, .zero)], usage: &usage), usage: usage)
        try check(roots, dimensions: [0, 0])
        try contains(roots, [.zero], true, usage: usage); try contains(roots, [close], true, usage: usage)
        try contains(roots, [try close.divided(by: q(2, &usage), usage: &usage)], false, usage: usage)
        let atThird = try x.subtracting(.constant(variableCount: 1, value: third, usage: &usage), usage: &usage)
        let singleton = try OriginalRationalParameterDomain(lower: third, upper: third, usage: &usage)
        let exact = try decompose(rational(1, [atThird], [.sign(polynomial: 0, .zero)],
            domains: [singleton], usage: &usage), usage: usage)
        try check(exact, dimensions: [0])
        guard let sample = exact.cells.first?.sample.first else { throw Failure.missingSource }
        let enclosed = try sample.enclosed(maximumDepth: depth, maximumCoefficientDepth: 0, usage: usage)
        try require(enclosed.lower == third && enclosed.upper == third)
        try contains(exact, [try q(1.0 / 3.0, &usage)], false, usage: usage)
        let closed = try OriginalRationalParameterDomain(lower: .zero, upper: .one, usage: &usage)
        let segment = try decompose(rational(1, [], [.literal(true)], domains: [closed], usage: &usage), usage: usage)
        try check(segment, dimensions: [1]); try contains(segment, [.zero], true, usage: usage)
        try contains(segment, [.one], true, usage: usage)
        let half = try OriginalRationalParameterDomain(lower: .zero, upper: nil, usage: &usage)
        let ray = try decompose(rational(1, [x], [.sign(polynomial: 0, .positive)], domains: [half], usage: &usage), usage: usage)
        try check(ray, dimensions: [1]); try contains(ray, [.zero], false, usage: usage)
        try contains(ray, [.one], true, usage: usage)
        let y = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 1, usage: &usage)
        let xx = try OriginalRationalPolynomial.coordinate(variableCount: 2, at: 0, usage: &usage)
        let open = try decompose(rational(2, [xx, y], [.sign(polynomial: 1, .zero),
            .sign(polynomial: 0, .zero), .not, .and], usage: &usage), usage: usage)
        try check(open, dimensions: [1, 1]); try contains(open, [.zero, .zero], false, usage: usage)
        try contains(open, [.one, .zero], true, usage: usage)
        try contains(open, [.one.negated, .zero], true, usage: usage)
        print("Q5_EXACT_REPEATED_CLOSE_ROOTS_OPEN_CLOSED_UNBOUNDED_DOMAINS_OK")
    }

    private static func publicRootSources() throws -> (OriginalAlgebraicCoordinate, OriginalAlgebraicCoordinate) {
        let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let law = try x.multiplied(by: x, usage: &usage)
            .subtracting(.constant(variableCount: 1, value: q(2, &usage), usage: &usage), usage: &usage)
        let result = try decompose(rational(1, [law], [.sign(polynomial: 0, .zero)], usage: &usage), usage: usage)
        try check(result, dimensions: [0, 0])
        guard result.cells.count == 2, let first = result.cells[0].sample.first,
            let second = result.cells[1].sample.first else { throw Failure.missingSource }
        return (first, second)
    }

    private static func orderedInput(_ source: OriginalAlgebraicCoordinate,
        usage: inout OriginalRelationUsage) throws -> OriginalPolynomialRelation {
        let minusOne = try OriginalAlgebraicCoordinate.rational(.one.negated, usage: usage)
        let law = try OriginalOrderedPolynomial(variableCount: 4, terms: [
            .init(coefficient: source, powers: [0, 0, 0, 0]),
            .init(coefficient: minusOne, powers: [1, 0, 0, 0])],
            maximumDepth: depth, maximumCoefficientDepth: depth, usage: usage)
        return try ordered(4, [law], [.sign(polynomial: 0, .zero)], usage: &usage)
    }
    private static func orderedOwnership() throws {
        let ledger = OriginalRealRelationAllowance(work: 20_000_000, bytes: 80_000_000); var usage = ledger.usage
        let first = try releasedOrderedResult(positive: false)
        let second = try releasedOrderedResult(positive: true)
        try check(first, dimensions: [3]); try check(second, dimensions: [3])
        try contains(first, [.zero, .zero, .zero, .zero], false, usage: usage, coefficientDepth: depth)
        guard let a = first.cells.first?.sample.first, let b = second.cells.first?.sample.first else { throw Failure.missingSource }
        let ea = try a.enclosed(maximumDepth: depth, maximumCoefficientDepth: depth, usage: usage)
        let eb = try b.enclosed(maximumDepth: depth, maximumCoefficientDepth: depth, usage: usage)
        try require(first.cells[0].coefficientAdmissionDepth > 0 && second.cells[0].coefficientAdmissionDepth > 0)
        let width = try ExactRationalCoefficient.one.divided(by: q(1024, &usage), usage: &usage)
        let refined = try ea.refined(maximumWidth: width, maximumDepth: depth,
            maximumCoefficientDepth: depth, usage: usage)
        try require(try refined.lower.subtracting(ea.lower, usage: &usage).canonicalSign >= 0
            && ea.upper.subtracting(refined.upper, usage: &usage).canonicalSign >= 0)
        try require(try width.subtracting(refined.upper.subtracting(refined.lower, usage: &usage), usage: &usage).canonicalSign >= 0)
        try require(refined.sourceDepth >= ea.sourceDepth && refined.coefficientAdmissionDepth >= ea.coefficientAdmissionDepth)
        let refinedB = try eb.refined(maximumWidth: width, maximumDepth: depth,
            maximumCoefficientDepth: depth, usage: usage)
        try require(try refinedB.lower.subtracting(eb.lower, usage: &usage).canonicalSign >= 0
            && eb.upper.subtracting(refinedB.upper, usage: &usage).canonicalSign >= 0)
        try require(try width.subtracting(refinedB.upper.subtracting(refinedB.lower, usage: &usage), usage: &usage).canonicalSign >= 0)
        try require(refinedB.sourceDepth >= eb.sourceDepth && refinedB.coefficientAdmissionDepth >= eb.coefficientAdmissionDepth)
        try require(try refinedB.lower.subtracting(refined.upper, usage: &usage).isPositive)
        guard let foreign = second.cells.first?.identifier else { throw Failure.missingSource }
        try expectKernelFailure {
            _ = try first.contains(rationalPoint: [.zero, .zero, .zero, .zero], inCell: foreign,
                maximumDepth: depth, maximumCoefficientDepth: depth, usage: usage)
        }
        let sources = try publicRootSources()
        let zero = try OriginalAlgebraicCoordinate.rational(.zero, usage: usage)
        let singletonLaw = try OriginalOrderedPolynomial(variableCount: 1, terms: [
            .init(coefficient: sources.1, powers: [1]), .init(coefficient: zero, powers: [0])],
            maximumDepth: depth, maximumCoefficientDepth: depth, usage: usage)
        let point = try decompose(ordered(1, [singletonLaw], [.sign(polynomial: 0, .zero)], usage: &usage),
            usage: usage, coefficientDepth: depth)
        try check(point, dimensions: [0]); try contains(point, [.zero], true, usage: usage, coefficientDepth: depth)
        let regionInput = try orderedInput(sources.1, usage: &usage)
        guard case .ordered(let regionLaws) = regionInput.polynomials else { throw Failure.missingSource }
        let region = try decompose(ordered(4, regionLaws, [.sign(polynomial: 0, .positive)], usage: &usage),
            usage: usage, coefficientDepth: depth)
        try check(region, dimensions: [4])
        try contains(region, [.zero, .zero, .zero, .zero], true, usage: usage, coefficientDepth: depth)
        try contains(region, [try q(2, &usage), .zero, .zero, .zero], false, usage: usage, coefficientDepth: depth)
        print("Q5_PUBLIC_ORDERED_CONJUGATES_RELEASED_SOURCE_REFINEMENT_OWNERSHIP_OK")
    }

    private static func releasedOrderedResult(positive: Bool) throws -> OriginalRealRelation {
        let sources = try publicRootSources()
        let ledger = OriginalRealRelationAllowance(work: 20_000_000, bytes: 80_000_000)
        var usage = ledger.usage
        let input = try orderedInput(positive ? sources.1 : sources.0, usage: &usage)
        return try decompose(input, usage: usage, coefficientDepth: depth)
    }

    private static func independentAdmission() throws {
        let preparation = OriginalRealRelationAllowance(); var usage = preparation.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let input = try rational(1, [x], [.sign(polynomial: 0, .zero)], usage: &usage)
        try expectAllowanceFailure(.work) { _ = try decompose(input, usage: OriginalRealRelationAllowance(work: 0).usage) }
        try expectAllowanceFailure(.storage) { _ = try decompose(input, usage: OriginalRealRelationAllowance(bytes: 0).usage) }
        try expectAllowanceFailure(.cells) { _ = try decompose(input, usage: OriginalRealRelationAllowance(cells: 0).usage) }
        let sources = try publicRootSources()
        let issued = try orderedInput(sources.1, usage: &usage)
        try expectAllowanceFailure(.coefficientCells) {
            _ = try decompose(issued, usage: OriginalRealRelationAllowance(coefficientCells: 0).usage, coefficientDepth: depth)
        }
        try expectAllowanceFailure(.parameter) {
            _ = try decompose(issued, usage: OriginalRealRelationAllowance(parameterDepth: 0).usage, coefficientDepth: depth)
        }
        try expectAllowanceFailure(.coefficient) {
            _ = try decompose(issued, usage: OriginalRealRelationAllowance(coefficientDepth: 0).usage, coefficientDepth: depth)
        }
        try expectKernelFailure {
            _ = try resolver.decompose(issued, maximumDepth: 0, maximumCoefficientDepth: depth, usage: usage)
        }
        try expectKernelFailure {
            _ = try resolver.decompose(issued, maximumDepth: depth, maximumCoefficientDepth: 0, usage: usage)
        }
        let measured = OriginalRealRelationAllowance()
        _ = try decompose(input, usage: measured.usage)
        let counts = measured.counts
        try require(counts.work > 0 && counts.bytes > 0 && counts.cells > 0)
        let exact = OriginalRealRelationAllowance(work: counts.work, bytes: counts.bytes, cells: counts.cells)
        _ = try decompose(input, usage: exact.usage)
        try expectAllowanceFailure(.storage) {
            _ = try decompose(input, usage: OriginalRealRelationAllowance(bytes: counts.bytes - 1).usage)
        }
        print("Q5_INDEPENDENT_WORK_STORAGE_CELLS_PARAMETER_COEFFICIENT_REFUSAL_OK")
    }

    private enum TerminalCase: CaseIterable, Sendable { case positive, empty, member, nonmember }
    private struct TerminalInput: Sendable {
        let positive: OriginalPolynomialRelation
        let empty: OriginalPolynomialRelation
        let result: OriginalRealRelation
    }
    private static func terminalInput() throws -> TerminalInput {
        let ledger = OriginalRealRelationAllowance(); var usage = ledger.usage
        let x = try OriginalRationalPolynomial.coordinate(variableCount: 1, at: 0, usage: &usage)
        let positive = try rational(1, [x], [.sign(polynomial: 0, .zero)], usage: &usage)
        let empty = try rational(1, [x], [.sign(polynomial: 0, .zero),
            .sign(polynomial: 0, .zero), .not, .and], usage: &usage)
        return try .init(positive: positive, empty: empty, result: decompose(positive, usage: usage))
    }
    private static func terminal(_ input: TerminalInput, kind: TerminalCase, usage: OriginalRelationUsage) throws {
        switch kind {
        case .positive: try require(!decompose(input.positive, usage: usage).cells.isEmpty)
        case .empty: try require(decompose(input.empty, usage: usage).cells.isEmpty)
        case .member: try contains(input.result, [.zero], true, usage: usage)
        case .nonmember: try contains(input.result, [.one], false, usage: usage)
        }
    }
    static nonisolated func cancellation() async throws {
        let input = try terminalInput()
        for kind in TerminalCase.allCases {
            switch kind {
            case .positive: print("Q5_BEGIN_POSITIVE_DECOMPOSITION_CANCELLATION")
            case .empty: print("Q5_BEGIN_EMPTY_DECOMPOSITION_CANCELLATION")
            case .member: print("Q5_BEGIN_TRUE_MEMBERSHIP_CANCELLATION")
            case .nonmember: print("Q5_BEGIN_FALSE_MEMBERSHIP_CANCELLATION")
            }
            let measured = OriginalRealRelationAllowance(); try terminal(input, kind: kind, usage: measured.usage)
            let ordinal = measured.counts.callbacks
            try require(ordinal > 0)
            for atEntry in [false, true] {
                let ledger = OriginalRealRelationAllowance(cancelAtCallback: atEntry ? nil : ordinal)
                let operation = Task {
                    if atEntry { withUnsafeCurrentTask { $0?.cancel() } }
                    try terminal(input, kind: kind, usage: ledger.usage)
                }
                do { try await operation.value; throw Failure.unexpectedSuccess }
                catch is CancellationError {
                    try require(ledger.counts.callbacks == (atEntry ? 0 : ordinal))
                }
            }
        }
        print("Q5_PUBLIC_POSITIVE_EMPTY_TRUE_FALSE_FINAL_CALLBACK_CANCELLATION_OK")
    }
}
