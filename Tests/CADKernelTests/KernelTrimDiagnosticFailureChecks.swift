import CADCore
import CADGeometry
import CADModeling
import CADTopology
import Synchronization
@testable import CADKernel

struct KernelTrimDiagnosticFailureChecks {
    enum Failure: Error { case mismatch, missingValue, missingRefusal }

    private final class WorkCounter: Sendable {
        private let state = Mutex(0)
        func add(_ units: Int) { state.withLock { $0 += units } }
        var value: Int { state.withLock { $0 } }
    }

    private static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.mismatch }
    }

    private static func requireValue<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw Failure.missingValue }
        return value
    }

    private static func execution(work: Int = 8_388_608) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try .init(workLimit: work, storageByteLimit: 268_435_456),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .admitted, stage: .request))
    }

    private static func crossingLines() -> (BRepSewingEdge, BRepSewingEdge) {
        let first = BRepSewingEdge(stableID: "horizontal",
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: -1, endParameter: 1,
            startPoint: .init(x: -1, y: 0, z: 0), endPoint: .init(x: 1, y: 0, z: 0),
            surfaceParameterCurve: .constantV(v: 0, uStart: -1, uEnd: 1))
        let second = BRepSewingEdge(stableID: "vertical",
            curve: .line(Line3D(origin: .origin, direction: .unitY)),
            startParameter: -1, endParameter: 1,
            startPoint: .init(x: 0, y: -1, z: 0), endPoint: .init(x: 0, y: 1, z: 0),
            surfaceParameterCurve: .constantU(u: 0, vStart: -1, vEnd: 1))
        return (first, second)
    }

    private static func containsDiagnostic(_ text: String, _ needle: String) -> Bool {
        if needle.isEmpty { return true }
        for index in text.utf8.indices {
            if text.utf8[index...].starts(with: needle.utf8) { return true }
        }
        return false
    }

    static func crossingLinesRetainTheirNonemptyContact() throws {
        let edges = crossingLines()
        var execution = try execution()
        let result = try ExactTrimEdgeIntersector().intersections(edges.0, edges.1,
            tolerance: .standard, using: &execution)
        guard case .subdivisionPoints(let points) = result else { throw Failure.mismatch }
        try require(points == [.origin])
        try require(execution.budget.snapshot.work > 1)
    }

    static func trimContactLowerWorkRefusalRetainsItsOriginalClassification() throws {
        let edges = crossingLines()
        var execution = try execution(work: 1)
        do {
            _ = try ExactTrimEdgeIntersector().intersections(edges.0, edges.1,
                tolerance: .standard, using: &execution)
        } catch {
            let failure = try requireValue(error as? OriginalQueryFailure)
            try require(execution.budget.snapshot.work == 1)
            let scalar = try requireValue(failure.originalError as? ExactScalarFailure)
            guard case .resourceLimit(.work) = scalar else { throw Failure.mismatch }
            try require(failure.kernelFailure.code == .resourceLimitExceeded)
            try require(failure.context.operation == .boundary)
            try require(failure.context.entry == .admitted)
            try require(failure.context.stage == .relation)
            try require(failure.context.resource?.axis == .work)
            try require(containsDiagnostic(failure.kernelFailure.message, "whole-span coincidence classification"))
            return
        }
        throw Failure.missingRefusal
    }

    static func lowerTrimCallerCancellationRetainsItsOriginalCause() throws {
        let observed = WorkCounter()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            consumeWorkUnits: { units in observed.add(units) },
            checkpoint: {
                if observed.value >= 1 { throw CancellationError() }
            })
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .admitted, stage: .request))
        do {
            let edges = crossingLines()
            _ = try ExactTrimEdgeIntersector().intersections(edges.0, edges.1,
                tolerance: .standard, using: &execution)
        } catch {
            try require(budget.snapshot.work == 1)
            try require(observed.value == 1)
            try require(error is CancellationError)
            return
        }
        throw Failure.missingRefusal
    }
}
