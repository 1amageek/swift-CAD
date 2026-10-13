import CADCore
import CADGeometry

/// Applies complete original-source exclusion to every material subset of its face.
enum OriginalOffsetDraftedSelfContact {
    static func validate(_ wall:OriginalDraftedRuledSurface3D,tolerance:ModelingTolerance,
        limits:OffsetFeasibilityLimits,invocation:OffsetFeasibilityInvocation) throws {
        try wall.validate(tolerance:tolerance)
        let options=limits.surfaceIntersectionOptions,count=invocation.maximumSpanCount
        let domain=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:limits.remainingSourceDepth),
            maximumTransportDepth:limits.maximumAlgebraicDepth,maximumCharts:count,
            maximumFamilies:count,maximumIdentityProofs:count)
        var a=OffsetExactScalarAdmission(invocation:invocation,maximumDepth:limits.maximumAlgebraicDepth)
        _ = try OriginalDraftedSelfExclusion.prepare(wall,limits:domain,
            maximumPairs:options.maximumSubdivisionCells,using:&a)
        try a.checkpoint()
    }
}
