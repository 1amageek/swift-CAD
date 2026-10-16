import CADCore
import CADGeometry
import Synchronization

/// Retains one cumulative construction owner and immutable policy for query entries.
package final class OriginalSpanConstructionOwner: Sendable {
    private struct Configuration: Sendable {
        let budget: OriginalQueryBudget
        let limits: OriginalQueryExecutionLimits
        let contributions: [OriginalQueryContributionHandle]
    }
    private let tolerance: ModelingTolerance
    private let configured: Configuration?
    private let state = Mutex<Configuration?>(nil)

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance; configured = nil
    }
    package init(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        self.tolerance = tolerance
        configured = Configuration(budget: execution.budget, limits: execution.effectiveLimits,
            contributions: try execution.retainActiveContributionHandles())
    }
    package func execution() throws -> OriginalQueryExecution {
        if let configured { return try OriginalQueryExecution(budget: configured.budget, limits: configured.limits, contributions: configured.contributions) }
        let configuration = try state.withLock { current in
            if let current { return current }
            let owner = try CurvedSweepSourceBudget(tolerance: tolerance)
            let created = Configuration(budget: owner.budget, limits: owner.limits, contributions: owner.contributions)
            current = created
            return created
        }
        return try OriginalQueryExecution(budget: configuration.budget, limits: configuration.limits, contributions: configuration.contributions)
    }
}
