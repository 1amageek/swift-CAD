#if !hasFeature(Embedded)
import Foundation

/// Immutable binding for validating source codecs nested in canonical Native output.
package struct NativeOriginalSourceEncodingContext: Sendable {
    package static let key = CodingUserInfoKey(rawValue: "swift-cad.original-source-encoding-context")!
    private let budget: OriginalQueryBudget
    private let limits: OriginalQueryExecutionLimits
    private let contributions: [OriginalQueryContributionHandle]

    package init(using execution: inout OriginalQueryExecution) throws {
        budget = execution.budget
        limits = execution.effectiveLimits
        contributions = try execution.retainActiveContributionHandles()
    }

    package static func execution(from encoder: any Encoder) throws -> OriginalQueryExecution {
        guard let installed = encoder.userInfo[key] else {
            return try OriginalQueryExecution.independentGeometry()
        }
        guard let context = installed as? Self else {
            throw NativeRationalSourceDecodingError.invalidCallerContext
        }
        try context.budget.checkpoint()
        return try OriginalQueryExecution(budget: context.budget, limits: context.limits,
            contributions: context.contributions)
    }
}
#endif
