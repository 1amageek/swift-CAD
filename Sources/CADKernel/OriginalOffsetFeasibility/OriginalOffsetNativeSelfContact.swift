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
        typealias Field = OriginalExactNativeSelfContacts.Field
        let field = try Field.base(field:ExactRationalScalarDomain(),maximumExtensionLevel:32,using:&a)
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:original.tolerance))
            .bind(surface,limits:limits.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space = try issuer.prepare(source:source,field:field,limits:limits,using:&a)
        func interval(_ box: ScalarInterval) throws -> ExactParameterInterval<Field.Value> {
            try .checked(field:field,lower:.finite(field.binary64(exactly:box.lower,using:&a)),
                upper:.finite(field.binary64(exactly:box.upper,using:&a)),depth:.init(value:0,coefficient:0),using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<Field.Value>].self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactParameterInterval<Field.Value>.self))
        let request = try space.frame.selection(intervals:[[interval(domain.u)],[interval(domain.v)]],limits:limits,using:&a)
        let cover = try issuer.issue(space:space,request:request,limits:limits,using:&a)
        let raw = try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:cover,second:cover,
            domainLimits:limits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
        let residual = try DefaultOriginalExactNativeSelfContactQuery().contacts(in:raw,domainLimits:limits,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
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
