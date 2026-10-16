import CADCore
import CADGeometry
import Synchronization

/// Issues one immutable silhouette policy on the original drawing budget.
public struct DrawingSilhouetteAdmission: Sendable {
    private final class Issuance: Sendable {
        enum State: Sendable { case unused, preparing, issued(SurfaceSilhouetteContext) }
        let state = Mutex<State>(.unused)
    }
    private let drawing: DrawingExchangeOwner
    private let issuance: Issuance

    public init(usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws {
        try usage.validateExecution(execution)
        try usage.check()
        try execution.chargeSource(records: 1, work: 1, storageBytes: MemoryLayout<Issuance.State>.stride)
        drawing = usage; issuance = Issuance()
    }
    public func createContext(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
        maximumDepth: Int, maximumAlgebraicDepth: Int, maximumSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteContext {
        try drawing.validateExecution(execution); try drawing.check()
        guard maximumWork <= drawing.maximumWork, maximumStorage <= drawing.maximumBytes / MemoryLayout<UInt32>.stride,
            maximumCells <= drawing.resources.limits.maximumEntities, maximumSourceDepth <= drawing.maximumNesting,
            maximumAlgebraicDepth <= drawing.maximumAlgebraicDepth,
            maximumDepth <= drawing.maximumCurveSubdivisionDepth else {
            throw ExportError.invalidMesh("Silhouette proof capability exceeds its composing drawing invocation.")
        }
        try issuance.state.withLock { state in
            guard case .unused = state else { throw ExportError.invalidMesh("Silhouette admission already issued its invocation policy.") }
            state = .preparing
        }
        let result = try SurfaceSilhouetteContext(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth, using: &execution)
        issuance.state.withLock { $0 = .issued(result) }
        return result
    }
    public func belongsToSameInvocation(as usage: DrawingExchangeOwner,
        silhouetteContext: SurfaceSilhouetteContext) -> Bool {
        guard usage.sharesAccountingOwner(with: drawing), silhouetteContext.budget === drawing.resources.originalBudget else { return false }
        return issuance.state.withLock { state in
            guard case .issued(let original) = state else { return false }
            return silhouetteContext.sharesAccountingOwner(with: original)
        }
    }
}
