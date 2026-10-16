import CADCore
import CADGeometry

/// Cumulative source invocation owner shared by closed-frame correction queries.
package final class CurvedSweepSourceBudget: Sendable {
    package let budget: OriginalQueryBudget
    package let limits: OriginalQueryExecutionLimits
    package let contributions: [OriginalQueryContributionHandle]
    private let tolerance: ModelingTolerance
    package let maximumDepth = 20
    package let maximumSpanCount: Int

    package init(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        self.tolerance = tolerance
        contributions = []
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        maximumSpanCount = requirements.maximumControlPointCount
        let bytes = requirements.maximumScalarCount.multipliedReportingOverflow(by: MemoryLayout<Double>.stride)
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        budget = try OriginalQueryBudget(workLimit: requirements.maximumWorkUnits,
            storageByteLimit: bytes.partialValue)
        limits = try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: maximumDepth, maximumSubdivisionDepth: maximumDepth,
            maximumSpans: maximumSpanCount, maximumScalarSlots: requirements.maximumScalarCount)
    }

    package init(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate()
        self.tolerance = tolerance
        budget = execution.budget
        limits = execution.effectiveLimits
        contributions = try execution.retainActiveContributionHandles()
        maximumSpanCount = min(execution.effectiveLimits.maximumSpans,
            GeometryConversionRequirements(maximumPositionError: tolerance.distance,
                maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance).maximumControlPointCount)
    }

    package func consume(depth: Int, using execution: inout OriginalQueryExecution) throws {
        guard depth >= 0, depth <= maximumDepth else { throw exhausted() }
        try execution.visitGeometricCell(depth: depth)
    }

    /// A later query owns independent local scopes and the same cumulative budget.
    package func execution() throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
    }

    private func exhausted() -> KernelError {
        KernelError(phase: .evaluation, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The curved sweep exhausted its original source or geometric depth allowance.")
    }
}
