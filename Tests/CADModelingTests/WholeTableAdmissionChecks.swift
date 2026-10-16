import CADCore
import CADGeometry
import CADIR
import CADModeling
import Synchronization

enum WholeTableAdmissionChecks {
    struct Failure: Error { let message: String }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws {
            let count = state.withLock { value in value += 1; return value }
            if count == stop { throw CancellationError() }
        }
    }

    private struct Fixture {
        let table: ParameterTable
        let base: ParameterID
        let doubled: ParameterID
        let dependent: ParameterID
        let independent: ParameterID
        let deep: ParameterID
    }

    private static func fixture() -> Fixture {
        let base = Parameter(name: "base", expression: .constant(.length(2, unit: .meter)), kind: .length)
        let doubled = Parameter(name: "doubled", expression: .multiply(.reference(base.id), .constant(.scalar(2))), kind: .length)
        let dependent = Parameter(name: "dependent", expression: .add(.reference(doubled.id), .constant(.length(1, unit: .meter))), kind: .length)
        let independent = Parameter(name: "independent", expression: .constant(.length(7, unit: .meter)), kind: .length)
        let deep = Parameter(name: "deep", expression: .add(.constant(.scalar(1)),
            .add(.constant(.scalar(2)), .add(.constant(.scalar(3)), .constant(.scalar(4))))), kind: .scalar)
        return Fixture(table: .init(parameters: [base.id: base, doubled.id: doubled,
            dependent.id: dependent, independent.id: independent, deep.id: deep]),
            base: base.id, doubled: doubled.id, dependent: dependent.id,
            independent: independent.id, deep: deep.id)
    }

    private static func execution(_ budget: OriginalQueryBudget,
        valueDepth: Int = 64, sourceDepth: Int = 256) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: valueDepth,
            maximumCoefficientDepth: 0, remainingSourceDepth: sourceDepth,
            maximumTransportDepth: 0, maximumSubdivisionDepth: 0))
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    private static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let failure = error as? ExactScalarFailure {
            if case .admissionRejected(let cause) = failure { return original(cause) }
            if case .cancelled = failure { return CancellationError() }
        }
        return error
    }

    private static func resource(_ error: any Error, axis: OriginalQueryResourceAxis,
        limit: Int) -> Bool {
        if let failure = error as? OriginalQueryFailure {
            if let observation = failure.context.resource, observation.axis == axis,
                observation.limit == .known(limit),
                case .known(let used) = observation.used,
                case .known(let requested) = observation.requested {
                return used <= limit && requested > limit - used
            }
            return resource(failure.originalError, axis: axis, limit: limit)
        }
        if let failure = error as? ExactScalarFailure,
            case .admissionRejected(let cause) = failure {
            return resource(cause, axis: axis, limit: limit)
        }
        return false
    }

    private static func checkValues(_ actual: ResolvedParameterTable, _ fixture: Fixture) throws {
        try require(actual.values.count == 5 && actual.names.count == 5,
            "Whole-table resolution omitted a dependent or unreferenced root.")
        try require(try actual.value(for: fixture.base) == .length(2, unit: .meter), "The original base quantity changed.")
        try require(try actual.value(for: fixture.doubled) == .length(4, unit: .meter), "The first dependency changed its units or value.")
        try require(try actual.value(for: fixture.dependent) == .length(5, unit: .meter), "The complete dependency chain changed.")
        try require(try actual.value(for: fixture.independent) == .length(7, unit: .meter), "An unreferenced root was not resolved.")
        try require(try actual.value(for: fixture.deep) == .scalar(10), "The original nested arithmetic changed.")
        try require(actual.names["dependent"] == fixture.dependent && actual.names["independent"] == fixture.independent,
            "The output name index lost its original parameter identities.")
    }

    static func completeRootsRetainOriginalUnitsAndValues() throws {
        let fixture = fixture()
        let resolver: any ParameterResolving = ParameterResolver()
        let ordinary = try resolver.resolve(fixture.table)
        let budget = try OriginalQueryBudget()
        var caller = try execution(budget)
        let actual = try resolver.resolve(fixture.table, using: &caller)
        try checkValues(actual, fixture)
        try require(actual.values == ordinary.values && actual.names == ordinary.names,
            "Ordinary and direct whole-table entries selected different resolution laws.")
        try require(budget.snapshot.work > 0 && budget.snapshot.storageBytes > 0 && caller.activeContributionCount == 0,
            "Whole-table resolution did not consume real caller work/storage or restore its scope.")
    }

    private static func parameterFailure(_ table: ParameterTable, expected: ParameterError) throws {
        let resolver: any ParameterResolving = ParameterResolver()
        do {
            _ = try resolver.resolve(table)
            throw Failure(message: "The ordinary resolver accepted an invalid source table.")
        } catch {
            guard let failure = original(error) as? ParameterError, failure == expected else { throw error }
        }
        var caller = try execution(OriginalQueryBudget())
        do {
            _ = try resolver.resolve(table, using: &caller)
            throw Failure(message: "The direct resolver accepted an invalid source table.")
        } catch {
            guard let failure = original(error) as? ParameterError, failure == expected else { throw error }
        }
        try require(caller.activeContributionCount == 0, "Invalid table resolution leaked a caller scope.")
    }

    static func originalRejectionsKeepTheirOrderAndCause() throws {
        let foreign = ParameterID()
        let invalid = Parameter(name: "invalid name", expression: .reference(foreign), kind: .scalar)
        let wrongKey = ParameterID()
        try parameterFailure(.init(parameters: [wrongKey: invalid]),
            expected: .tableKeyMismatch(key: wrongKey, parameterID: invalid.id))
        try parameterFailure(.init(parameters: [invalid.id: invalid]), expected: .invalidName("invalid name"))
        let first = Parameter(name: "same", expression: .constant(.scalar(1)), kind: .scalar)
        let second = Parameter(name: "same", expression: .reference(foreign), kind: .scalar)
        try parameterFailure(.init(parameters: [first.id: first, second.id: second]), expected: .duplicateName("same"))
        let missing = Parameter(name: "missing", expression: .reference(foreign), kind: .scalar)
        try parameterFailure(.init(parameters: [missing.id: missing]), expected: .unknownReference(foreign))
        let cycleID = ParameterID()
        let cycle = Parameter(id: cycleID, name: "cycle", expression: .reference(cycleID), kind: .scalar)
        try parameterFailure(.init(parameters: [cycle.id: cycle]), expected: .cycleDetected([cycleID, cycleID]))
        let mismatch = Parameter(name: "kind", expression: .constant(.scalar(1)), kind: .length)
        try parameterFailure(.init(parameters: [mismatch.id: mismatch]),
            expected: .kindMismatch(parameterID: mismatch.id, expected: .length, actual: .scalar))
        let unit = Parameter(name: "units", expression: .add(.constant(.length(1, unit: .meter)),
            .constant(.scalar(1))), kind: .length)
        var caller = try execution(OriginalQueryBudget())
        do {
            _ = try ParameterResolver().resolve(.init(parameters: [unit.id: unit]), using: &caller)
            throw Failure(message: "Incompatible original units were accepted.")
        } catch {
            guard let failure = original(error) as? UnitError,
                case .incompatibleQuantity(let operation, let lhs, let rhs) = failure,
                operation == "add", lhs == .length, rhs == .scalar else { throw error }
        }
    }

    static func exactWorkAndTypedStorageCeilings() throws {
        let fixture = fixture()
        let resolver: any ParameterResolving = ParameterResolver()
        let baselineBudget = try OriginalQueryBudget(allocationPolicy: .bytes)
        var baseline = try execution(baselineBudget)
        _ = try resolver.resolve(fixture.table, using: &baseline)
        let needed = baselineBudget.snapshot
        try require(needed.work > 0 && needed.storageBytes > 0, "Whole-table costs were not measured from actual operations.")
        let exactBudget = try OriginalQueryBudget(workLimit: needed.work,
            storageByteLimit: needed.storageBytes, allocationPolicy: .bytes)
        var exact = try execution(exactBudget)
        try checkValues(resolver.resolve(fixture.table, using: &exact), fixture)
        try require(exactBudget.snapshot.work == needed.work && exactBudget.snapshot.storageBytes == needed.storageBytes,
            "Exact whole-table allowances changed the operation sequence.")
        for axis in [OriginalQueryResourceAxis.work, .storageBytes] {
            for limit in [0, (axis == .work ? needed.work : needed.storageBytes) - 1] {
                let budget = try OriginalQueryBudget(workLimit: axis == .work ? limit : nil,
                    storageByteLimit: axis == .storageBytes ? limit : nil, allocationPolicy: .bytes)
                var caller = try execution(budget)
                var published = false
                do {
                    _ = try resolver.resolve(fixture.table, using: &caller)
                    published = true
                    throw Failure(message: "Whole-table output escaped its exact work/storage ceiling.")
                } catch {
                    guard resource(error, axis: axis, limit: limit) else { throw error }
                }
                let used = axis == .work ? budget.snapshot.work : budget.snapshot.storageBytes
                try require(!published && used <= limit && caller.activeContributionCount == 0,
                    "A denied table debit published, overcommitted, or leaked a caller scope.")
            }
        }
    }

    static func independentSourceAndValueDepths() throws {
        let fixture = fixture()
        var validation = try execution(OriginalQueryBudget())
        try fixture.table.validate(using: &validation)
        var baseline = try execution(OriginalQueryBudget())
        _ = try ParameterResolver().resolve(fixture.table, using: &baseline)
        let source = baseline.sourceDepth, value = baseline.valueDepth
        try require(source > 0 && value > 0 && baseline.coefficientDepth == 0
            && baseline.geometricDepth == 0 && baseline.transportDepth == 0,
            "Table dependency/source ancestry was merged with unrelated numeric/geometric axes.")
        try require(source == validation.sourceDepth,
            "Modeling scalar DFS introduced a source-depth requirement beyond the existing IR validator.")
        var exact = try execution(OriginalQueryBudget(), valueDepth: value, sourceDepth: source)
        try checkValues(ParameterResolver().resolve(fixture.table, using: &exact), fixture)
        for axis in [OriginalQueryResourceAxis.sourceDepth, .valueDepth] {
            let limit = (axis == .sourceDepth ? source : value) - 1
            var caller = try execution(OriginalQueryBudget(), valueDepth: axis == .valueDepth ? limit : value,
                sourceDepth: axis == .sourceDepth ? limit : source)
            do {
                _ = try ParameterResolver().resolve(fixture.table, using: &caller)
                throw Failure(message: "A table dependency escaped its independent depth ceiling.")
            } catch {
                guard resource(error, axis: axis, limit: limit) else { throw error }
            }
        }
        var zeroValidation = try execution(OriginalQueryBudget(), sourceDepth: 0)
        do {
            try fixture.table.validate(using: &zeroValidation)
            throw Failure(message: "The existing IR source-validation depth contract was silently weakened.")
        } catch {
            guard resource(error, axis: .sourceDepth, limit: 0) else { throw error }
        }
        var zeroResolution = try execution(OriginalQueryBudget(), sourceDepth: 0)
        do {
            _ = try ParameterResolver().resolve(fixture.table, using: &zeroResolution)
            throw Failure(message: "Whole-table resolution skipped the required IR source validation.")
        } catch {
            guard resource(error, axis: .sourceDepth, limit: 0) else { throw error }
        }
    }

    static func selectedContributionsAndPrefixRemainCumulative() throws {
        let fixture = fixture()
        var baseline = try execution(OriginalQueryBudget())
        let selected = try baseline.makeContributionHandle(allocationPolicy: .bytes)
        try baseline.withContributionScope(selected) { caller in
            let before = caller.localWork
            try caller.consumeWork(7)
            try checkValues(ParameterResolver().resolve(fixture.table, using: &caller), fixture)
            try require(caller.activeContributionCount == 1 && selected.snapshot.work == caller.localWork - before,
                "Whole-table resolution lost its selected work owner or accepted prefix.")
        }
        let needed = selected.snapshot
        try require(baseline.activeContributionCount == 0, "The completed table scope was not restored.")
        for limit in [needed.work, needed.work - 1] {
            var caller = try execution(OriginalQueryBudget())
            let handle = try caller.makeContributionHandle(workLimit: limit,
                storageByteLimit: needed.storageBytes, allocationPolicy: .bytes)
            var published = false
            do {
                try caller.withContributionScope(handle) { caller in
                    try caller.consumeWork(7)
                    _ = try ParameterResolver().resolve(fixture.table, using: &caller)
                }
                published = true
                try require(limit == needed.work, "A selected N−1 table scope was ignored.")
            } catch {
                guard limit == needed.work - 1, resource(error, axis: .work, limit: limit) else { throw error }
            }
            try require(published == (limit == needed.work) && handle.snapshot.work <= limit && caller.activeContributionCount == 0,
                "A selected table allowance was reset, overcommitted, or leaked.")
        }
    }

    static func entryInteriorAndFinalCancellationPublishNothing() throws {
        let fixture = fixture()
        let checkpoints = Checkpoints()
        var baseline = try execution(OriginalQueryBudget(checkpoint: { try checkpoints.check() }))
        _ = try ParameterResolver().resolve(fixture.table, using: &baseline)
        try require(checkpoints.count > 3, "The full table did not expose interior caller checkpoints.")
        for stop in [1, checkpoints.count / 2, checkpoints.count] {
            let probe = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try probe.check() })
            var caller = try execution(budget)
            var published = false
            do {
                _ = try ParameterResolver().resolve(fixture.table, using: &caller)
                published = true
                throw Failure(message: "A cancelled table invocation published its output.")
            } catch {
                guard original(error) is CancellationError else { throw error }
            }
            try require(!published && probe.count == stop && caller.activeContributionCount == 0,
                "Table cancellation moved checkpoints or leaked caller scope state.")
            if stop == 1 { try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                "Entry cancellation committed table work or scratch storage.") }
        }
    }

    private static func retainedOutput() throws -> (ResolvedParameterTable, ParameterID) {
        let fixture = fixture()
        var source = fixture.table
        let copy = source
        var caller = try execution(OriginalQueryBudget())
        let result = try ParameterResolver().resolve(source, using: &caller)
        source.parameters.removeAll()
        try require(source.parameters.isEmpty && copy == fixture.table,
            "Resolving or editing a table mutated the retained authored COW copy.")
        try checkValues(result, fixture)
        return (result, fixture.dependent)
    }

    static func outputSurvivesSourceAndCallerRelease() throws {
        let (retained, parameterID) = try retainedOutput()
        var reader = try execution(OriginalQueryBudget())
        let value = try ParameterResolver().evaluate(.reference(parameterID), parameters: retained,
            variables: [:], using: &reader)
        try require(value == .length(5, unit: .meter) && retained.names["dependent"] == parameterID,
            "A resolved output lost its keys, values or independent reader after source/caller release.")
    }

    private struct LegacyResolver: ParameterResolving {
        func resolve(_ table: ParameterTable) throws -> ResolvedParameterTable {
            throw Failure(message: "An admitted table call fell back to an external ordinary resolver.")
        }
        func evaluate(_ expression: CADExpression, parameters: ResolvedParameterTable,
            variables: [String: Quantity]) throws -> Quantity {
            throw Failure(message: "Whole-table resolution invoked an unrelated expression provider.")
        }
        func evaluate(_ expression: CADExpression, parameters: ResolvedParameterTable,
            variables: [String: Quantity], using execution: inout OriginalQueryExecution) throws -> Quantity {
            throw Failure(message: "Whole-table resolution invoked an unrelated expression provider.")
        }
    }

    static func legacyProviderExplicitlyRefusesDirectCapability() throws {
        let provider: any ParameterResolving = LegacyResolver()
        let budget = try OriginalQueryBudget()
        var caller = try execution(budget)
        do {
            _ = try provider.resolve(fixture().table, using: &caller)
            throw Failure(message: "A legacy provider fabricated direct whole-table capability.")
        } catch let failure as KernelError {
            try require(failure.phase == .evaluation && failure.code == .unsupportedCapability
                && failure.message == "Parameter resolver does not implement caller-execution whole-table resolution.",
                "A legacy table provider changed its explicit capability failure.")
        }
        try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
            "An unsupported table provider ran an ordinary fallback before refusal.")
    }
}
