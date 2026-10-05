import CADCore
import CADGeometry
import Synchronization

/// One immutable callback admission created once for a construction invocation.
package final class OriginalSpanConstructionOwner: Sendable {
    private let tolerance: ModelingTolerance
    private let configured: GeometryConversionAdmission?
    private let state = Mutex<GeometryConversionAdmission?>(nil)

    package init(tolerance: ModelingTolerance, admission: GeometryConversionAdmission?) {
        self.tolerance = tolerance; configured = admission
    }

    package func admission() throws -> GeometryConversionAdmission {
        if let configured { return configured }
        return try state.withLock { current in
            if let current { return current }
            let budget = try CurvedSweepSourceBudget(tolerance: tolerance)
            let created = try GeometryConversionAdmission(maximumSpanCount: budget.maximumSpanCount,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: budget.maximumDepth,
                consumeWork: { try budget.consumeExactWork($0) },
                consumeStorage: { try budget.retainBytes($0) })
            current = created
            return created
        }
    }
}
