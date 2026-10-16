import CADCore
import CADGeometry

/// Applies complete original-source exclusion to every material subset of its face.
enum OriginalOffsetDraftedSelfContact {
    static func validate(_ wall:OriginalDraftedRuledSurface3D,tolerance:ModelingTolerance,
        limits:OffsetFeasibilityLimits,using execution:inout OriginalQueryExecution) throws {
        try wall.validate(tolerance:tolerance)
        let options=limits.surfaceIntersectionOptions,count=min(execution.effectiveLimits.maximumSpans, limits.surfaceIntersectionOptions.maximumSubdivisionCells)
        let domain=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:limits.remainingSourceDepth),
            maximumTransportDepth:limits.maximumAlgebraicDepth,maximumCharts:count,
            maximumFamilies:count,maximumIdentityProofs:count)
        _ = try OriginalDraftedSelfExclusion.prepare(wall,limits:domain,
            maximumPairs:options.maximumSubdivisionCells,using:&execution)
        try execution.checkpoint()
    }
}
