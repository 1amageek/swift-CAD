import CADCore
import CADGeometry
import CADTopology

/// Owns the actual face-bound Native self-product for offset result admission.
enum OriginalOffsetNativeSelfContact {
    static func prepare<A: ExactScalarAdmission & ~Copyable>(surface: BSplineSurface3D,
        domain: SurfaceParameterBox, faceID: FaceID, original: ValidatedBRepModel,
        selection: OriginalNativeBoundaryDomain.Selection, limits: OriginalDomainIdentityLimits,
        maximumMaps: Int, maximumPairs: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws -> OriginalExactNativeMaterialSelfContacts {
        try a.checkpoint()
        let residual = try OriginalExactSurfaceSelfContactPreparer.native(surface:surface,domain:domain,
            tolerance:original.tolerance,limits:limits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        let raw = residual.raw
        let first = try OriginalExactFaceBoundaryIssuer(source:.firstSurface(raw),faceID:faceID,
            original:original,domainLimits:limits,using:&a)
        let second = try OriginalExactFaceBoundaryIssuer(source:.secondSurface(raw),faceID:faceID,
            original:original,domainLimits:limits,using:&a)
        return try DefaultOriginalExactNativeMaterialSelfContactQuery().contacts(in:residual,
            first:first.domain,second:second.domain,selection:selection,domainLimits:limits,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
    }
    static func validate(surface: BSplineSurface3D, domain: SurfaceParameterBox,
        faceID: FaceID, original: ValidatedBRepModel, limits: OffsetFeasibilityLimits,
        invocation: OffsetFeasibilityInvocation) throws {
        let options = limits.surfaceIntersectionOptions
        let count = invocation.maximumSpanCount
        let domainLimits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:limits.remainingSourceDepth),
            maximumTransportDepth:limits.maximumAlgebraicDepth,maximumCharts:count,
            maximumFamilies:count,maximumIdentityProofs:count)
        let cellLimits = try ExactRealCellLimits(maximumStoredCells:options.maximumSubdivisionCells,
            maximumRootsPerStack:options.maximumRootAttempts)
        let topologyLimits = try ExactRealTopologyLimits(maximumGeneratedCells:options.maximumSubdivisionCells,
            maximumRootsPerStack:options.maximumRootAttempts,maximumClosures:options.maximumSubdivisionCells,
            maximumAttachmentPieces:options.maximumContinuationPointCount,
            maximumComponents:options.maximumSeedCount)
        var a = OffsetExactScalarAdmission(invocation:invocation,maximumDepth:limits.maximumAlgebraicDepth)
        let selected = try prepare(surface:surface,domain:domain,faceID:faceID,original:original,
            selection:.closed,limits:domainLimits,maximumMaps:count,maximumPairs:count,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        for pair in selected.firstRefinements {
            for included in pair.parameters.pullback.region.included {
                try a.consumeWork(1)
                if included {
                    try a.checkpoint()
                    throw KernelError(phase:.topology,code:.topologyFailure,tolerance:original.tolerance,
                        message:"Original offset result self-intersects at distinct material parameters.")
                }
            }
        }
        try a.checkpoint()
    }
}
