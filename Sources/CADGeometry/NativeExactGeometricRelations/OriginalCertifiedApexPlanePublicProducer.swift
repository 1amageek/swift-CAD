import CADCore

/// Publishes a checked whole-support exclusion beside the ordinary empty arrays.
struct OriginalCertifiedApexPlanePublicProducer {
    private typealias Base = OriginalPhysicalAngleScalarDomain
    private typealias Interval = ExactParameterInterval<Base.Value>

    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,using a: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
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
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits=try OriginalSourceIssuanceLimits(
                remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts=min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans),options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,
                maximumTransportDepth: a.effectiveLimits.maximumTransportDepth,maximumCharts:charts,
                maximumFamilies:0,maximumIdentityProofs:0)
            let field=try Base(originalRadians:halfAngle,using:&a)
            let source=try DefaultOriginalSourceBindingIssuer(
                provider:OriginalCertifiedSphereConeApexSnapshotProvider(field:field,tolerance:tolerance))
                .bind(curve,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: .init(source: source))
            let target=try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:tolerance))
                .bind(surface,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(target.sourceDepth)
            a.context = a.context.retaining(second: .init(source: target))
            let one=try field.integer(1,using:&a)
            let basis=try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,Base>()
                .issue(source:target,field:field,firstLength:one,normalLength:one,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .relation)
            let exclusion=try DefaultOriginalCertifiedSphereConeApexPlaneSeparationIssuer()
                .issue(source:source,plane:basis,limits:sourceLimits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Interval.self))
            a.context = a.context.at(stage: .domain)
            let curveIntervals=[try interval(range,field:field,using:&a)]
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[Interval].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Interval.self))
            let planeIntervals=[[try interval(options.surfaceURange,field:field,using:&a)],
                [try interval(options.surfaceVRange,field:field,using:&a)]]
            let original=try OriginalCertifiedApexPlaneExclusion.resolve(exclusion:exclusion,
                curveIntervals:curveIntervals,planeIntervals:planeIntervals,limits:limits,using:&a)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:[],overlaps:[],originalCertifiedApexPlaneExclusion:original)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance,context:a.context) }
    }

    private func interval(_ range:ScalarInterval?,field:Base,using a:inout OriginalQueryExecution) throws -> Interval {
        let depth=try ExactScalarDepth(value:0,coefficient:0)
        guard let range else {
            return try .checked(field:field,lower:.negativeInfinity,upper:.positiveInfinity,depth:depth,using:&a)
        }
        return try .checked(field:field,lower:.finite(field.binary64(exactly:range.lower,using:&a)),
            upper:.finite(field.binary64(exactly:range.upper,using:&a)),depth:depth,using:&a)
    }
}
