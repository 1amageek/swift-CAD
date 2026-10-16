import CADCore
import CADGeometry

/// Creates the common cumulative owner once at the edge-offset feature operation entry.
enum EdgeOffsetQueryExecution {
    static func make(limits: EdgeOffsetConversionLimits?, tolerance: ModelingTolerance)
        throws -> OriginalQueryExecution {
        guard let limits else { return try .kernelOriginal() }
        try limits.validate(tolerance: tolerance)
        return OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: limits.maximumWork,
            storageByteLimit: limits.maximumStorageBytes),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.remainingSourceDepth,
                maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
                maximumSpans: limits.maximumSpanCount, maximumNativeSpans: limits.maximumSpanCount),
            context: .init(operation: .conversion, entry: .ordinary, stage: .request))
    }
}
