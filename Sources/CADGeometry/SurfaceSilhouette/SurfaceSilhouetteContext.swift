import CADCore

/// Immutable silhouette policy and persistent attribution in the original common budget.
public final class SurfaceSilhouetteContext: Sendable {
    public let contribution: OriginalQueryContributionHandle
    public let retainedContributions: [OriginalQueryContributionHandle]
    private let rootLimits: OriginalQueryExecutionLimits
    public let limits: OriginalQueryExecutionLimits
    public var budget: OriginalQueryBudget { contribution.budget }
    public let maximumWork: Int
    public let maximumCells: Int
    public let maximumStorage: Int
    public let maximumDepth: Int
    public let maximumAlgebraicDepth: Int
    public let maximumSourceDepth: Int
    public var work: Int { contribution.snapshot.work }
    public var cells: Int { contribution.snapshot.cellVisits }
    public var storage: Int {
        let bytes = contribution.snapshot.storageBytes
        return bytes / 4 + (bytes % 4 == 0 ? 0 : 1)
    }

    public convenience init(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
        maximumDepth: Int, maximumAlgebraicDepth: Int = 32, maximumSourceDepth: Int = 16) throws {
        let limits = try Self.policy(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth)
        let budget = try OriginalQueryBudget(workLimit: maximumWork,
            storageByteLimit: exactScalarPayloadBytes(count: maximumStorage, of: UInt32.self),
            cellLimit: maximumCells, allocationPolicy: .uint32WordWork)
        var execution = OriginalQueryExecution(budget: budget, limits: limits)
        try self.init(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth,
            using: &execution)
    }
    public init(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
        maximumDepth: Int, maximumAlgebraicDepth: Int = 32, maximumSourceDepth: Int = 16,
        using execution: inout OriginalQueryExecution) throws {
        rootLimits = execution.effectiveLimits
        limits = try Self.policy(maximumWork: maximumWork, maximumCells: maximumCells,
            maximumStorage: maximumStorage, maximumDepth: maximumDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth)
        self.maximumWork = maximumWork; self.maximumCells = maximumCells
        self.maximumStorage = maximumStorage; self.maximumDepth = maximumDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth; self.maximumSourceDepth = maximumSourceDepth
        contribution = try execution.makeContributionHandle(workLimit: maximumWork,
            storageByteLimit: exactScalarPayloadBytes(count: maximumStorage, of: UInt32.self),
            cellLimit: maximumCells, storageByteQuantum: 4, allocationPolicy: .uint32WordWork, executionLimits: limits)
        retainedContributions = try execution.withContributionScope(contribution) { execution in
            try execution.retainActiveContributionHandles()
        }
    }
    public func execution() throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: budget, limits: rootLimits, contributions: retainedContributions)
    }
    public func sharesAccountingOwner(with other: SurfaceSilhouetteContext) -> Bool { self === other }
    public func withExecution<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        try execution.withContributionScopes(retainedContributions, body)
    }
    private static func policy(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
        maximumDepth: Int, maximumAlgebraicDepth: Int, maximumSourceDepth: Int) throws -> OriginalQueryExecutionLimits {
        guard maximumWork > 0, maximumCells > 0, maximumStorage > 0,
            maximumDepth >= 0, (0...32).contains(maximumAlgebraicDepth), (0...16).contains(maximumSourceDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Silhouette admission requires explicit positive caller limits.")
        }
        return try .init(maximumValueDepth: maximumDepth, maximumCoefficientDepth: maximumAlgebraicDepth,
            maximumCells: maximumCells, remainingSourceDepth: maximumSourceDepth,
            maximumSubdivisionDepth: maximumDepth)
    }
}
