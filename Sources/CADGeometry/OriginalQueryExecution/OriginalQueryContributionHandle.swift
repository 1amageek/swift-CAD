/// Immutable attribution authority retained by prepared source and output owners.
public struct OriginalQueryContributionHandle: Sendable {
    public let budget: OriginalQueryBudget
    let id: Int
    public let storageByteQuantum: Int
    public let workLimit: Int?
    public let sourceTextByteLimit: Int?
    public let allocationPolicy: OriginalQueryAllocationPolicy
    public let executionLimits: OriginalQueryExecutionLimits?
    public var remainingWorkUnits: Int { max(0, (workLimit ?? Int.max) - snapshot.work) }
    public var remainingSourceTextBytes: Int { max(0, (sourceTextByteLimit ?? Int.max) - snapshot.sourceTextBytes) }
    public var snapshot: OriginalQueryBudgetSnapshot { budget.contributionSnapshot(self) }
}
