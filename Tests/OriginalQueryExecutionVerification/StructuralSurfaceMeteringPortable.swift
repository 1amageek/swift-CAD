import CADCore
import Synchronization
@testable import CADGeometry

@main
struct StructuralSurfaceMeteringPortable {
    enum Failure: Error { case mismatch, missingRefusal }
    private final class WorkLog: Sendable {
        let state = Mutex<[Int]>([])
    }
    private final class CancellationState: Sendable {
        let state = Mutex((work: 0, cancelled: false))
    }
    static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.mismatch }
    }
    static func original(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return original(retained.originalError) }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure { return original(retained) }
        return error
    }
    static func refusal(_ matches: (ExactScalarFailure) -> Bool, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let scalar = original(error) as? ExactScalarFailure, matches(scalar) else { throw error }
            return
        }
        throw Failure.missingRefusal
    }
    static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 16, maximumTransportDepth: 16, maximumSubdivisionDepth: 32))
    }
    static func native() -> BSplineSurface3D {
        .init(uDegree: 2, vDegree: 1, uKnots: [0,0,0,1,1,1], vKnots: [0,0,1,1],
            controlPoints: [
                [.init(x: 0,y: 0,z: 0.25), .init(x: 0.5,y: 0,z: -0.25), .init(x: 1,y: 0,z: 0.25)],
                [.init(x: 0,y: 1,z: 0.25), .init(x: 0.5,y: 1,z: -0.25), .init(x: 1,y: 1,z: 0.25)]])
    }
    static func surfaceSequence(_ surface: Surface3D) throws -> [Int] {
        let observed = WorkLog()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            consumeWorkUnits: { units in observed.state.withLock { $0.append(units) } })
        var admission = try execution(budget)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &admission)
        let result = observed.state.withLock { $0 }
        try require(result.reduce(0,+) == budget.snapshot.work && budget.snapshot.storageBytes == 0)
        return result
    }
    static func exactDebitSequences() throws {
        let source = native()
        // Frozen original traversal: record, Native header/counts, knots, rows, weights, tail.
        let expected = [1,8,6,4,2,2,6,4,3,3,3,3,3,3,3,3,3,3,3,3,4]
        try require(try surfaceSequence(.bSpline(source)) == expected)
        try require(expected.reduce(0,+) == 73 && source == native())
        let plane = Surface3D.plane(.init(origin: .origin, normal: .unitZ))
        try require(try surfaceSequence(plane) == [1,4])
        try require(try surfaceSequence(.cylinder(.init(origin: .origin, axis: .unitZ, radius: 1))) == [1,5])
        let analytic: [(AnalyticSurface3D,[Int])] = [
            (.plane(origin: .origin, normal: .unitZ),[1,1,6]),
            (.cylinder(origin: .origin,axis: .unitZ,radius: 1),[1,1,5]),
            (.cone(apex: .origin,axis: .unitZ,halfAngle: 0.5),[1,1,3]),
            (.sphere(center: .origin,radius: 1),[1,1,2]),
            (.torus(center: .origin,axis: .unitZ,majorRadius: 2,minorRadius: 1),[1,1,4])]
        for (surface, fees) in analytic { try require(try surfaceSequence(.analytic(surface)) == fees) }
        try require(try surfaceSequence(.procedural(.offset(.init(source: plane,distance: 0.25)))) == [1,1,1,1,4,1])
        let observed = WorkLog()
        let budget = try OriginalQueryBudget(consumeWorkUnits: { units in observed.state.withLock { $0.append(units) } })
        var admission = try execution(budget)
        let curve = Curve3D.bSpline(.init(degree: 2,knots: [0,0,0,1,1,1],
            controlPoints: [.origin,.init(x: 0.5,y: 1,z: 0),.init(x: 1,y: 0,z: 0)]))
        try GeometryStructuralComparisonWork.charge(curve: curve,using: &admission)
        try require(observed.state.withLock { $0 } == [1,6,6,3,3,6,3,3,3,3,2])
    }
    static func exactAndCumulativeWork() throws {
        let source = native()
        let budget = try OriginalQueryBudget(workLimit: 73,storageByteLimit: 0)
        var exact = try execution(budget)
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),using: &exact)
        try require(budget.snapshot.work == 73 && budget.snapshot.storageBytes == 0)
        try refusal({ if case .resourceLimit(.work) = $0 { true } else { false } }) {
            try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),using: &exact)
        }
        let lower = try OriginalQueryBudget(workLimit: 72,storageByteLimit: 0)
        var limited = try execution(lower)
        try refusal({ if case .resourceLimit(.work) = $0 { true } else { false } }) {
            try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),using: &limited)
        }
        try require(lower.snapshot.work == 69 && lower.snapshot.storageBytes == 0)
        let cumulative = try OriginalQueryBudget(workLimit: 146,storageByteLimit: 0)
        var first = try execution(cumulative)
        var second = try execution(cumulative)
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),using: &first)
        try GeometryStructuralComparisonWork.charge(surface: .bSpline(source),using: &second)
        try require(cumulative.snapshot.work == 146 && source == native())
    }
    static func overflowIsTypedAndAtomic() throws {
        for surface in [Surface3D.bSpline(native()), .plane(.init(origin: .origin,normal: .unitZ))] {
            let budget = try OriginalQueryBudget()
            try budget.consumeWork(Int.max - 1)
            var admission = try execution(budget)
            try refusal({ if case .countOverflow = $0 { true } else { false } }) {
                try GeometryStructuralComparisonWork.charge(surface: surface,using: &admission)
            }
            try require(budget.snapshot.work == Int.max && budget.snapshot.storageBytes == 0)
        }
    }
    static func cancellationPreservesDebitBoundary() throws {
        let stopped = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var entry = try execution(stopped)
        try refusal({ if case .cancelled = $0 { true } else { false } }) {
            try GeometryStructuralComparisonWork.charge(surface: .bSpline(native()),using: &entry)
        }
        try require(stopped.snapshot.work == 0 && stopped.snapshot.storageBytes == 0)
        let state = CancellationState()
        let budget = try OriginalQueryBudget(consumeWorkUnits: { units in
            state.state.withLock { $0.work += units; if $0.work == 73 { $0.cancelled = true } }
        },checkpoint: {
            if state.state.withLock({ $0.cancelled }) { throw ExactScalarFailure.cancelled }
        })
        var terminal = try execution(budget)
        try refusal({ if case .cancelled = $0 { true } else { false } }) {
            try GeometryStructuralComparisonWork.charge(surface: .bSpline(native()),using: &terminal)
        }
        try require(budget.snapshot.work == 73 && budget.snapshot.storageBytes == 0)
    }
    static func main() throws {
        try exactDebitSequences()
        print("PASS structural surface original debit sequences")
        try exactAndCumulativeWork()
        print("PASS structural surface exact and cumulative work")
        try overflowIsTypedAndAtomic()
        print("PASS structural surface checked overflow")
        try cancellationPreservesDebitBoundary()
        print("PASS structural surface cancellation")
    }
}
