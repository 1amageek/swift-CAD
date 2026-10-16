import CADCore

/// Immutable issuing resource authority retained beside original source evidence.
struct SurfaceSilhouetteQueryContext: Sendable {
    let budget: OriginalQueryBudget
    let contributions: [OriginalQueryContributionHandle]

    init(retaining execution: inout OriginalQueryExecution) throws {
        budget = execution.budget
        contributions = try execution.retainActiveContributionHandles()
    }
    func withExecution<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        guard execution.budget === budget else { throw ExactScalarFailure.invalidEvidence }
        return try execution.withContributionScopes(contributions, body)
    }
}
