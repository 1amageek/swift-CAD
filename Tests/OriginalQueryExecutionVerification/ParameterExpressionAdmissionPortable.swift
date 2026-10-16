import CADCore
import CADGeometry
import CADIR
import CADModeling
import Synchronization

/// Exercises the real expression witness and interpreter; no expression is interpreted here.
@main
struct ParameterExpressionAdmissionPortable {
    private struct Failure: Error { let line: UInt; let message: String }
    private struct Input {
        let expression: CADExpression
        let parameters: ResolvedParameterTable
        let variables: [String: Quantity]
        let expected: Quantity
    }
    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var count: Int { state.withLock { $0 } }
        func check() throws {
            let visit = state.withLock { $0 += 1; return $0 }
            if visit == cancelAt { throw ExactScalarFailure.cancelled }
        }
    }
    private final class StopAtWork: Sendable {
        private let work = Mutex(0)
        let threshold: Int
        init(_ threshold: Int) { self.threshold = threshold }
        func record(_ units: Int) { work.withLock { $0 += units } }
        func check() throws {
            if work.withLock({ $0 >= threshold }) { throw ExactScalarFailure.cancelled }
        }
    }
    private static func require(_ value: Bool, _ message: String, line: UInt = #line) throws {
        if !value { throw Failure(line: line, message: message) }
    }
    private static func execution(_ budget: OriginalQueryBudget, valueDepth: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: valueDepth,
            maximumCoefficientDepth: 0, remainingSourceDepth: 0, maximumTransportDepth: 0,
            maximumSubdivisionDepth: 0))
    }
    private static func evaluate(_ input: Input, using execution: inout OriginalQueryExecution) throws -> Quantity {
        let resolver: any ParameterResolving = ParameterResolver()
        return try resolver.evaluate(input.expression, parameters: input.parameters,
            variables: input.variables, using: &execution)
    }
    private static func same(_ value: Quantity, _ expected: Quantity) throws {
        try require(value.kind == expected.kind && abs(value.value - expected.value) < 1e-9,
            "The authored quantity law or unit changed.")
    }
    private static func inputs() -> [Input] {
        let id = ParameterID()
        let compound = CADExpression.divide(
            .add(.hypot(.reference(id), .variable("rise", .length)),
                .multiply(.constant(.length(2, unit: .meter)),
                    .add(.sin(.constant(.angle(.pi / 2, unit: .radian))),
                        .subtract(.cos(.constant(.angle(0, unit: .radian))),
                            .tan(.constant(.angle(0, unit: .radian))))))), .constant(.scalar(3)))
        func coordinates(_ values: [Double]) -> [CADExpression] {
            values.map { .constant(.length($0, unit: .meter)) }
        }
        let line = coordinates([0, 0, 1, 0])
        let cubic = coordinates([0, 0, 1, 0, 2, 0, 3, 0])
        let length = CADExpression.constant(.length(0.5, unit: .meter))
        func bezier(_ expression: CADExpression, _ expected: Double) -> Input {
            .init(expression: expression, parameters: .init(), variables: [:],
                expected: .length(expected, unit: .meter))
        }
        return [
            .init(expression: compound, parameters: .init(values: [id: .length(3, unit: .meter)]),
                variables: ["rise": .length(4, unit: .meter)], expected: .length(3, unit: .meter)),
            bezier(.bezierNaturalExtension(coordinates: line, length: length, coordinateIndex: 0), 1.5),
            bezier(.bezierShapedExtension(shape: .arc(spanCount: 1), coordinates: cubic,
                length: length, coordinateIndex: 0), 3 + 0.5 / 3),
            bezier(.bezierShapedExtension(shape: .soft(spanCount: 1), coordinates: cubic,
                length: length, coordinateIndex: 0), 3 + 0.5 / 3),
            bezier(.bezierShapedExtension(shape: .reflective(degree: 1, coversCurve: true),
                coordinates: line, length: length, coordinateIndex: 0), 1.5),
        ]
    }
    private static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return original(cause)
        }
        return error
    }
    private static func resource(_ expected: ExactResource, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let scalar = original(error) as? ExactScalarFailure,
                case .resourceLimit(let actual) = scalar, actual == expected else { throw error }
            return
        }
        throw Failure(line: #line, message: "A refused expression published a quantity.")
    }
    private static func cancelled(_ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let scalar = original(error) as? ExactScalarFailure, case .cancelled = scalar else { throw error }
            return
        }
        throw Failure(line: #line, message: "A cancelled expression published a quantity.")
    }
    private static func allLawsAndLifetime() throws {
        let resolver: any ParameterResolving = ParameterResolver()
        for input in inputs() {
            let budget = try OriginalQueryBudget()
            let retained: Quantity
            do {
                var admission = try execution(budget)
                retained = try evaluate(input, using: &admission)
                try require(admission.coefficientDepth == 0, "Expression recursion consumed coefficient depth.")
            }
            try same(retained, input.expected)
            let ordinary = try resolver.evaluate(input.expression, parameters: input.parameters,
                variables: input.variables)
            try require(ordinary == retained, "Ordinary and direct numerical semantics diverged.")
            try require(budget.snapshot.work > 0 && budget.snapshot.cellVisits == 0,
                "Expression visits bypassed work or invented geometric root cells.")
        }
        print("PASS parameter actual existential all13 expression laws")
        print("PASS parameter four Core continuation laws and ordinary parity")
        print("PASS parameter returned quantity lifetime")
    }
    private static func exactBoundariesAndReuse() throws {
        for input in inputs() {
            let budget = try OriginalQueryBudget()
            var admission = try execution(budget)
            _ = try evaluate(input, using: &admission)
            let n = budget.snapshot
            _ = try evaluate(input, using: &admission)
            try require(budget.snapshot.work == n.work * 2 && budget.snapshot.storageBytes == n.storageBytes * 2,
                "A repeated expression reset its cumulative admission.")
            let exactBudget = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
            var exact = try execution(exactBudget)
            try same(evaluate(input, using: &exact), input.expected)
            try require(exactBudget.snapshot.work == n.work && exactBudget.snapshot.storageBytes == n.storageBytes,
                "The exact cumulative cost changed.")
            let shortWork = try OriginalQueryBudget(workLimit: n.work - 1)
            var limitedWork = try execution(shortWork)
            try resource(.work) { _ = try evaluate(input, using: &limitedWork) }
            try require(shortWork.snapshot.work <= n.work - 1, "A refused work debit was committed.")
            if n.storageBytes > 0 {
                for limit in [0, n.storageBytes - 1] {
                    let shortStorage = try OriginalQueryBudget(storageByteLimit: limit)
                    var limitedStorage = try execution(shortStorage)
                    try resource(.storage) { _ = try evaluate(input, using: &limitedStorage) }
                    try require(shortStorage.snapshot.storageBytes <= limit, "A refused storage debit was committed.")
                }
            }
        }
        print("PASS parameter cumulative same caller work and bytes")
        print("PASS parameter exact N N-minus-1 work storage and bytes0")
    }
    private static func independentDepth() throws {
        let input = Input(expression: .add(.constant(.scalar(1)),
            .add(.constant(.scalar(2)), .constant(.scalar(3)))), parameters: .init(),
            variables: [:], expected: .scalar(6))
        var exact = try execution(OriginalQueryBudget(), valueDepth: 2)
        try same(evaluate(input, using: &exact), input.expected)
        try require(exact.valueDepth == 2 && exact.coefficientDepth == 0, "Expression depth used the wrong axis.")
        var limited = try execution(OriginalQueryBudget(), valueDepth: 1)
        try resource(.valueDepth) { _ = try evaluate(input, using: &limited) }
        for input in inputs().dropFirst() {
            var bezier = try execution(OriginalQueryBudget(), valueDepth: 1)
            try same(evaluate(input, using: &bezier), input.expected)
        }
        print("PASS parameter independent value depth source0 geometry0 coefficient0")
    }
    private static func errorOrder() throws {
        let resolver: any ParameterResolving = ParameterResolver()
        for expression in [
            CADExpression.add(.constant(.length(1, unit: .meter)), .constant(.scalar(1))),
            .divide(.constant(.scalar(1)), .constant(.scalar(0))),
            .sin(.constant(.length(1, unit: .meter))), .constant(.scalar(.infinity)),
        ] {
            var admission = try execution(OriginalQueryBudget())
            do {
                _ = try resolver.evaluate(expression, parameters: .init(), variables: [:], using: &admission)
                throw Failure(line: #line, message: "An invalid quantity or unit was accepted.")
            } catch is UnitError { }
        }
        let missing = ParameterID()
        var admission = try execution(OriginalQueryBudget())
        do {
            _ = try resolver.evaluate(.add(.reference(missing), .constant(.scalar(.infinity))),
                parameters: .init(), variables: [:], using: &admission)
            throw Failure(line: #line, message: "The first reference failure was ignored.")
        } catch let error as ParameterError {
            guard case .unknownReference(let id) = error, id == missing else { throw error }
        }
        for name in ["missing", "invalid name"] {
            do {
                _ = try resolver.evaluate(.variable(name, .scalar), parameters: .init(),
                    variables: [:], using: &admission)
                throw Failure(line: #line, message: "An invalid or unresolved variable was accepted.")
            } catch is ParameterError { }
        }
        print("PASS parameter original units domain variable and left-before-right errors")
    }
    private static func cancellations() throws {
        for input in inputs() {
            let baseline = try OriginalQueryBudget()
            var measuring = try execution(baseline)
            _ = try evaluate(input, using: &measuring)
            let threshold = baseline.snapshot.work / 2
            let stop = StopAtWork(threshold)
            let budget = try OriginalQueryBudget(consumeWorkUnits: { stop.record($0) }, checkpoint: { try stop.check() })
            var admission = try execution(budget)
            try cancelled { _ = try evaluate(input, using: &admission) }
            try require(budget.snapshot.work >= threshold && budget.snapshot.work < baseline.snapshot.work,
                "Cancellation did not stop before expression output.")
        }
        let counted = Checkpoints()
        let budget = try OriginalQueryBudget(checkpoint: { try counted.check() })
        let literal = Input(expression: .constant(.scalar(1)), parameters: .init(), variables: [:], expected: .scalar(1))
        var measured = try execution(budget)
        _ = try evaluate(literal, using: &measured)
        let terminal = counted.count
        try require(terminal > 1, "The public expression entry has no terminal checkpoint.")
        for ordinal in [1, terminal] {
            let stop = Checkpoints(cancelAt: ordinal)
            let budget = try OriginalQueryBudget(checkpoint: { try stop.check() })
            var admission = try execution(budget)
            try cancelled { _ = try evaluate(literal, using: &admission) }
            try require(budget.snapshot.work == (ordinal == 1 ? 0 : 1),
                "Entry or terminal cancellation changed the actual paid work.")
        }
        let stop = Checkpoints(cancelAt: terminal)
        let invalidBudget = try OriginalQueryBudget(checkpoint: { try stop.check() })
        var invalid = try execution(invalidBudget)
        do {
            let bad = Input(expression: .constant(.scalar(.infinity)), parameters: .init(), variables: [:], expected: .scalar(0))
            _ = try evaluate(bad, using: &invalid)
            throw Failure(line: #line, message: "An invalid quantity returned before cancellation.")
        } catch is UnitError { try require(stop.count == terminal - 1, "Terminal checkpoint preceded quantity validation.") }
        print("PASS parameter entry inner numeric and terminal cancellation")
    }
    static func main() throws {
        try allLawsAndLifetime()
        try exactBoundariesAndReuse()
        try independentDepth()
        try errorOrder()
        try cancellations()
        print("PASS parameter portable all")
    }
}
