import CADCore
import CADGeometry
import Synchronization

/// One original silhouette proof owner bound to a complete live drawing invocation.
public struct DrawingSilhouetteAdmission: Sendable {
    private final class Issuance: Sendable {
        enum State: Sendable { case unused, preparing, issued(SurfaceSilhouetteUsage) }
        let state = Mutex<State>(.unused)
    }
    private let drawing: DrawingExchangeUsage
    private let lower: SurfaceSilhouetteAdmission
    private let issuance: Issuance

    public init(usage: inout DrawingExchangeUsage) throws {
        try usage.check()
        try usage.charge(entities: 1, work: 1, bytes: MemoryLayout<Issuance.State>.stride)
        let resources = usage.resources
        lower = try SurfaceSilhouetteAdmission(consumeWork: usage.preparationWorkCallback,
            consumeStorage: usage.preparationStorageCallback, consumeCell: { try resources.recordEntities() })
        drawing = usage; issuance = Issuance()
    }

    /// Creates the invocation's lower allowance exactly once; copies retain that owner.
    public func createUsage(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
        maximumDepth: Int, maximumAlgebraicDepth: Int, maximumSourceDepth: Int) throws -> SurfaceSilhouetteUsage {
        try drawing.check()
        guard maximumWork <= drawing.maximumWork, maximumStorage <= drawing.maximumBytes / MemoryLayout<UInt32>.stride,
            maximumCells <= drawing.resources.limits.maximumEntities, maximumSourceDepth <= drawing.maximumNesting,
            maximumAlgebraicDepth <= drawing.maximumAlgebraicDepth,
            maximumDepth <= drawing.maximumCurveSubdivisionDepth else {
            throw ExportError.invalidMesh("Silhouette proof capability exceeds its composing drawing invocation.")
        }
        try issuance.state.withLock { state in
            guard case .unused = state else { throw ExportError.invalidMesh("Silhouette admission already issued its invocation allowance.") }
            state = .preparing
        }
        let result = try SurfaceSilhouetteUsage(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth, admission: lower)
        issuance.state.withLock { $0 = .issued(result) }
        return result
    }

    public func belongsToSameInvocation(as usage: DrawingExchangeUsage,
        silhouetteUsage: SurfaceSilhouetteUsage) -> Bool {
        guard usage.sharesAccountingOwner(with: drawing), silhouetteUsage.sharesAdmission(with: lower) else { return false }
        return issuance.state.withLock { state in
            guard case .issued(let original) = state else { return false }
            return silhouetteUsage.sharesAccountingOwner(with: original)
        }
    }
}
