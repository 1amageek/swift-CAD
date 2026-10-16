import CADCore
import CADGeometry

/// Immutable lifetime owner shared by construction views of one original curve.
package final class OriginalCurveSpanSource: Sendable {
    package let curve: Curve3D
    package let budget: OriginalQueryBudget?
    package let limits: OriginalQueryExecutionLimits?
    package let contributions: [OriginalQueryContributionHandle]
    package let prepared: PreparedCurveDifferentialEncloser?
    package let preparationTolerance: ModelingTolerance?

    package init(curve: Curve3D) {
        self.curve = curve; contributions = []; budget = nil; limits = nil; prepared = nil; preparationTolerance = nil
    }

    package init(curve: Curve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        self.curve = curve; budget = execution.budget; limits = execution.effectiveLimits; contributions = try execution.retainActiveContributionHandles(); preparationTolerance = tolerance
        prepared = try PreparedCurveDifferentialEncloser(curve: curve,
            tolerance: tolerance, remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
    }
}
