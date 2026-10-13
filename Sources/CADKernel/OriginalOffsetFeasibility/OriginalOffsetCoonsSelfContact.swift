import CADCore
import CADGeometry
import CADTopology

/// Consumes complete global exclusion as a proof for every face material subset.
enum OriginalOffsetCoonsSelfContact {
    typealias Base = OriginalExactScalarDomain
    typealias Source = OriginalCoonsAtlasSnapshot
    typealias Evidence = OriginalRationalChartReceipt<Source,Int,Base>
    typealias Cover = OriginalIssuedDomainCover<Source,Int,Base>
    typealias Contacts = OriginalIssuedGraphSelfContacts<Source,Evidence,Cover,Evidence,Cover>

    static func prepare<A: ExactScalarAdmission & ~Copyable>(surface: OriginalCoonsSurface3D,
        tolerance: ModelingTolerance, limits: OriginalDomainIdentityLimits, maximumPairs: Int,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws -> Contacts {
        try OriginalExactSurfaceSelfContactPreparer.coons(surface:surface,tolerance:tolerance,
            limits:limits,maximumPairs:maximumPairs,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
    }

    static func validate(surface: OriginalCoonsSurface3D, tolerance: ModelingTolerance,
        limits: OffsetFeasibilityLimits, invocation: OffsetFeasibilityInvocation) throws {
        let options = limits.surfaceIntersectionOptions, count = invocation.maximumSpanCount
        let domain = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:limits.remainingSourceDepth),
            maximumTransportDepth:limits.maximumAlgebraicDepth,maximumCharts:count,
            maximumFamilies:count,maximumIdentityProofs:count)
        let cells = try ExactRealCellLimits(maximumStoredCells:options.maximumSubdivisionCells,
            maximumRootsPerStack:options.maximumRootAttempts)
        let topology = try ExactRealTopologyLimits(maximumGeneratedCells:options.maximumSubdivisionCells,
            maximumRootsPerStack:options.maximumRootAttempts,maximumClosures:options.maximumSubdivisionCells,
            maximumAttachmentPieces:options.maximumContinuationPointCount,maximumComponents:options.maximumSeedCount)
        var a = OffsetExactScalarAdmission(invocation:invocation,maximumDepth:limits.maximumAlgebraicDepth)
        let contacts = try prepare(surface:surface,tolerance:tolerance,limits:domain,
            maximumPairs:options.maximumSubdivisionCells,cellLimits:cells,topologyLimits:topology,using:&a)
        for refinement in contacts.refinements {
            for included in refinement.pullback.region.included {
                try a.consumeWork(1)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Actual generated Coons result
                // callers still need both exact material predicates for a nonempty
                // global residual before contact or exclusion can be certified.
                guard !included else {
                    throw KernelError(phase:.topology,code:.unsupportedCapability,tolerance:tolerance,
                        message:"Coons result contact requires both retained material predicates.")
                }
            }
        }
        try a.checkpoint()
    }
}
