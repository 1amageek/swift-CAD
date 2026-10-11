import CADCore

/// Publishes a checked whole-support exclusion beside the ordinary empty arrays.
struct OriginalCertifiedApexPlanePublicProducer {
    private typealias Base = OriginalPhysicalAngleScalarDomain
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    private typealias Interval = ExactParameterInterval<Base.Value>

    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,invocation:CurveSurfaceQueryInvocation? = nil) throws -> CurveSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This ordinary certified-source route
        // selects only the checked apex/plane capability. Other certified branches
        // retain their existing dispatch until whole source/request exclusion or
        // complete contact authority is connected to their public results.
        guard OriginalCertifiedSphereConeApexSnapshotProvider.supports(curve),
            OriginalCertifiedSphereConeApexSnapshotProvider.supportsPlane(surface),
            case .certifiedIntersection(.sphereCone(let original))=curve,
            case .analytic(.cone(_,_,let halfAngle))=original.coneSurface,
            let range=options.curveRange,range.lower.isFinite,range.upper.isFinite else { return nil }
        do {
            try options.validate(tolerance:tolerance)
            let usage=try NativeCurveSurfacePointAllowance(options:options,invocation:invocation)
            var a=Admission(usage:usage,maximumDepth:usage.maximumAlgebraicDepth)
            try a.checkpoint();try invocation?.consume(depth:0)
            let sourceLimits=try OriginalSourceIssuanceLimits(
                remainingSourceDepth:invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts=min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells,options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,
                maximumTransportDepth:usage.maximumAlgebraicDepth,maximumCharts:charts,
                maximumFamilies:0,maximumIdentityProofs:0)
            let field=try Base(originalRadians:halfAngle,using:&a)
            let source=try DefaultOriginalSourceBindingIssuer(
                provider:OriginalCertifiedSphereConeApexSnapshotProvider(field:field,tolerance:tolerance))
                .bind(curve,limits:sourceLimits,using:&a)
            let target=try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:tolerance))
                .bind(surface,limits:sourceLimits,using:&a)
            let one=try field.integer(1,using:&a)
            let basis=try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,Base>()
                .issue(source:target,field:field,firstLength:one,normalLength:one,limits:sourceLimits,using:&a)
            let exclusion=try DefaultOriginalCertifiedSphereConeApexPlaneSeparationIssuer()
                .issue(source:source,plane:basis,limits:sourceLimits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Interval.self))
            let curveIntervals=[try interval(range,field:field,using:&a)]
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[Interval].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Interval.self))
            let planeIntervals=[[try interval(options.surfaceURange,field:field,using:&a)],
                [try interval(options.surfaceVRange,field:field,using:&a)]]
            let original=try OriginalCertifiedApexPlaneExclusion.resolve(exclusion:exclusion,
                curveIntervals:curveIntervals,planeIntervals:planeIntervals,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:[],overlaps:[],originalCertifiedApexPlaneExclusion:original)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance) }
    }

    private func interval(_ range:ScalarInterval?,field:Base,using a:inout Admission) throws -> Interval {
        let depth=try ExactScalarDepth(value:0,coefficient:0)
        guard let range else {
            return try .checked(field:field,lower:.negativeInfinity,upper:.positiveInfinity,depth:depth,using:&a)
        }
        return try .checked(field:field,lower:.finite(field.binary64(exactly:range.lower,using:&a)),
            upper:.finite(field.binary64(exactly:range.upper,using:&a)),depth:depth,using:&a)
    }
}
