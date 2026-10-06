import CADCore
import CADGeometry

/// Retains immutable original coedges without materializing a second curve array.
struct OriginalParameterLoopCurveView: RandomAccessCollection, Hashable, Sendable {
    typealias Index = Int
    typealias Element = SurfaceParameterCurve

    private enum Storage: Sendable {
        case authored([SurfaceParameterCurve])
        case original(Loop)
    }
    private let storage: Storage

    init(curves: [SurfaceParameterCurve]) { storage = .authored(curves) }
    init(validatedLoop: Loop,consumeWork: @Sendable (Int) throws -> Void) throws {
        for use in validatedLoop.coedges {
            try Task.checkCancellation(); try consumeWork(0)
            guard use.surfaceParameterCurve != nil else { throw TopologyError.invalidTrim(use.edgeID) }
        }
        storage = .original(validatedLoop)
    }

    func index(after position: Int) -> Int { position+1 }
    func index(before position: Int) -> Int { position-1 }
    var startIndex: Int { 0 }
    var endIndex: Int {
        switch storage {
        case .authored(let curves): return curves.count
        case .original(let loop): return loop.coedges.count
        }
    }
    subscript(position: Int) -> SurfaceParameterCurve {
        switch storage {
        case .authored(let curves): return curves[position]
        case .original(let loop):
            // Constructor admission established presence in this immutable buffer.
            // No mutation entry point or independently supplied loop can reach it.
            return loop.coedges[position].surfaceParameterCurve!
        }
    }
    static func == (first: Self, second: Self) -> Bool {
        guard first.count == second.count else { return false }
        for index in first.indices where first[index] != second[index] { return false }
        return true
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for curve in self { hasher.combine(curve) }
    }
}
