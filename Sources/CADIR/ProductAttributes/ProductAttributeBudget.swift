import CADCore
import CADGeometry

/// Product work, target and source-text allowances on the original cumulative owner.
public struct ProductAttributeBudget: Sendable {
    public let limits: ProductAttributeLimits
    private let owner: OriginalQueryBudget
    private let executionLimits: OriginalQueryExecutionLimits
    private let executionContext: OriginalQueryFailureContext
    private let contributions: [OriginalQueryContributionHandle]
    private let source: OriginalQueryContributionHandle
    private let targets: OriginalQueryContributionHandle
    public var consumedWork: Int { source.snapshot.work }
    public var consumedTargets: Int { targets.snapshot.records }
    public var consumedTextBytes: Int { source.snapshot.sourceTextBytes }

    public init(limits: ProductAttributeLimits) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(limits: limits, using: &execution)
    }
    public init(limits: ProductAttributeLimits, using execution: inout OriginalQueryExecution) throws {
        try limits.validate()
        self.limits = limits; owner = execution.budget; executionLimits = execution.effectiveLimits
        executionContext = execution.context
        let sourceScope = try execution.makeContributionHandle(workLimit: limits.maximumWork,
            sourceTextByteLimit: limits.maximumTextBytes)
        source = sourceScope
        targets = try execution.makeContributionHandle(recordLimit: limits.maximumTargets)
        contributions = try execution.withContributionScope(sourceScope) { execution in
            try execution.retainActiveContributionHandles()
        }
    }
    public func execution() throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: owner, limits: executionLimits, context: executionContext, contributions: contributions)
    }
    public func withExecution<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        guard execution.budget === owner else {
            throw ProductAttributeError.invalidSource("Product attribute allowance belongs to another original query.")
        }
        return try execution.withContributionScopes(contributions, body)
    }
    public mutating func charge(work: Int = 0, targets: Int = 0, textBytes: Int = 0) throws {
        var execution = try self.execution()
        try charge(work: work, targets: targets, textBytes: textBytes, using: &execution)
    }
    public mutating func charge(work: Int = 0, targets: Int = 0, textBytes: Int = 0,
        using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        guard work >= 0, targets >= 0, textBytes >= 0,
            work <= limits.maximumWork - consumedWork,
            targets <= limits.maximumTargets - consumedTargets,
            textBytes <= limits.maximumTextBytes - consumedTextBytes else {
            throw ProductAttributeError.resourceLimitExceeded("Cumulative product attribute budget.")
        }
        let targetScope = self.targets
        try withExecution(using: &execution) { execution in
            if targets == 0 {
                try execution.chargeSourceText(work: work, storageBytes: textBytes)
            } else {
                try execution.withContributionScope(targetScope) { execution in
                    try execution.chargeSourceText(records: targets, work: work, storageBytes: textBytes)
                }
            }
        }
    }
}
