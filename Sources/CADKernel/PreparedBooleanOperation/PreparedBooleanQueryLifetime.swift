import CADGeometry

/// Retains cumulative owner, selected contributions and attained preparation evidence.
final class PreparedBooleanQueryLifetime: Sendable {
    let budget: OriginalQueryBudget
    let limits: OriginalQueryExecutionLimits
    let context: OriginalQueryFailureContext
    let depth: OriginalQueryPreparationDepth
    private let contributions: [OriginalQueryContributionHandle]

    private init(budget: OriginalQueryBudget, limits: OriginalQueryExecutionLimits,
        context: OriginalQueryFailureContext, depth: OriginalQueryPreparationDepth,
        contributions: [OriginalQueryContributionHandle]) {
        self.budget = budget; self.limits = limits; self.context = context
        self.depth = depth; self.contributions = contributions
    }

    static func retain(depth: OriginalQueryPreparationDepth,
        using execution: inout OriginalQueryExecution) throws -> PreparedBooleanQueryLifetime {
        try execution.checkpoint()
        try execution.retainStorage(bytes: MemoryLayout<(OriginalQueryBudget,
            OriginalQueryExecutionLimits, OriginalQueryFailureContext,
            OriginalQueryPreparationDepth, [OriginalQueryContributionHandle])>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride)
        let contributions = try execution.retainActiveContributionHandles()
        let result = PreparedBooleanQueryLifetime(budget: execution.budget,
            limits: execution.effectiveLimits, context: execution.context,
            depth: depth, contributions: contributions)
        try execution.checkpoint()
        return result
    }

    func execution() throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: budget, limits: limits,
            context: context.at(stage: .membership), contributions: contributions)
    }

    func withRead<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        try execution.checkpoint()
        try execution.admitSourceDepth(depth.sourceDepth)
        try execution.admitDepth(value: depth.scalar.value, coefficient: depth.scalar.coefficient)
        try execution.admitGeometricDepth(depth.geometricDepth)
        try execution.admitTransportDepth(depth.transportDepth)
        if execution.budget === budget {
            return try execution.withContributionScopes(contributions) { execution in
                try admittedBody(using: &execution)
            }
        }
        return try admittedBody(using: &execution)
        func admittedBody(using execution: inout OriginalQueryExecution) throws -> Result {
            execution.context = execution.context.at(stage: .membership)
            _ = try execution.admitRetainedPreparation(owner: self, budget: budget, work: 0,
                storageBytes: 0, depth: depth.scalar, sourceDepth: depth.sourceDepth,
                geometricDepth: depth.geometricDepth, transportDepth: depth.transportDepth)
            let result = try body(&execution)
            try execution.checkpoint()
            return result
        }
    }
}
