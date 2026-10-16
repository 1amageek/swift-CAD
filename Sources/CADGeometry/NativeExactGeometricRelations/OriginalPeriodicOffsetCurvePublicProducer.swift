import CADCore

/// Connects original periodic offset source/DI to complete symbolic geometric CS.
struct OriginalPeriodicOffsetCurvePublicProducer {
    typealias Base = OriginalExactScalarDomain
    typealias Surface = OriginalOffsetSnapshot<BSplineSurface3D>

    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,using a: inout OriginalQueryExecution,
        retainingRelations:Bool=false) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary periodic offset CS currently
        // admits zero distance and stationary two-pole Native curves. General
        // source/curve families require complete symbolic geometric publication.
        guard case .bSpline(let nativeCurve)=curve,nativeCurve.degree==1,nativeCurve.controlPoints.count==2,
            nativeCurve.controlPoints[0]==nativeCurve.controlPoints[1],!nativeCurve.isPeriodic,
            case .procedural(.offset(let offset))=surface,offset.distance==0,
            case .bSpline(let native)=offset.source,native.isUPeriodic || native.isVPeriodic else { return nil }
        do {
            try options.validate(tolerance:tolerance)
            let depth = a.effectiveLimits.maximumValueDepth
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts=min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans),options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth: a.effectiveLimits.maximumTransportDepth,maximumCharts:charts,maximumFamilies: min(2, a.effectiveLimits.maximumFamilies),maximumIdentityProofs:0)
            let f=try Base(maximumValueDepth: a.effectiveLimits.maximumValueDepth, maximumCoefficientDepth: a.effectiveLimits.maximumCoefficientDepth,using:&a)
            let curveSource=try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineCurveSnapshotProvider(tolerance:tolerance)).bind(nativeCurve,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(curveSource.sourceDepth)
            a.context = a.context.retaining(first: .init(source: curveSource))
            let curveFamily=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>().prepare(source:curveSource,field:f,maximumCharts:charts,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .domain)
            let curveSpace=try DefaultOriginalBSplineDomainIssuer<BSplineCurve3D,Base>().prepare(source:curveSource,field:f,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ScalarInterval?.self))
            let curveRequest=try request(curveSpace.frame,ranges:[options.curveRange],field:f,limits:limits,using:&a)
            a.context = a.context.retaining(first: .init(selection: curveRequest))
            let curveCover=try DefaultOriginalIssuedDomainBinder<BSplineCurve3D,OriginalBSplineChartSelection,Base>().bind(laws:curveFamily.laws,request:curveRequest,limits:limits,using:&a)
            a.context = a.context.at(stage: .source)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalOffsetSnapshotProvider(child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:tolerance))).bind(offset,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(second: .init(source: source))
            let child=try DefaultOriginalBSplineFundamentalChartPreparer<BSplineSurface3D>().prepare(source:source.original.originalChild,field:f,maximumCharts:charts,limits:sourceLimits,using:&a)
            let family=try DefaultOriginalPeriodicNativeOffsetLawPreparer<Surface>().prepare(source:source,child:child,maximumCharts:charts,limits:sourceLimits,using:&a)
            a.context = a.context.at(stage: .domain)
            let issuer=DefaultOriginalPeriodicNativeOffsetDomainIssuer<Surface>()
            let space=try issuer.prepare(family:family,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ScalarInterval?.self))
            let selected=try request(space.frame,ranges:[options.surfaceURange,options.surfaceVRange],field:f,limits:limits,using:&a)
            a.context = a.context.retaining(second: .init(selection: selected))
            let cover=try issuer.issue(space:space,request:selected,limits:limits,using:&a)
            a.context = a.context.at(stage: .relation)
            let relation=try DefaultOriginalPeriodicOffsetContactResolver().resolve(curve:curveCover,surface:cover,
                maximumContacts:min(options.maximumCandidateCount, a.effectiveLimits.maximumResults),maximumDegree:min(options.maximumPolynomialDegree, a.effectiveLimits.maximumPolynomialDegree),limits:limits,using:&a)
            if !retainingRelations && !relation.isEmpty {
                throw KernelError(phase:.geometry,code:.nonDiscreteIntersection,tolerance:tolerance,
                    message:"Periodic offset contacts require the complete symbolic result.")
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:[],overlaps:[],originalIssuedGeometricRelation:relation)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance,context:a.context) }
    }
    private func request<S:Sendable>(_ frame:OriginalParameterFrame<S,Base>,ranges:[ScalarInterval?],field:Base,
        limits:OriginalDomainIdentityLimits,using a:inout OriginalQueryExecution) throws -> OriginalParameterSelection<S,Base> {
        let full=try frame.fullSelection(limits:limits,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:ranges.count,of:[ExactParameterInterval<OriginalExactScalar>].self))
        var axes:[[ExactParameterInterval<OriginalExactScalar>]]=[];axes.reserveCapacity(ranges.count)
        for axis in ranges.indices {
            if let range=ranges[axis] {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalExactScalar>.self))
                axes.append([try .checked(field:field,lower:.finite(field.binary64(exactly:range.lower,using:&a)),upper:.finite(field.binary64(exactly:range.upper,using:&a)),depth:.init(value:0,coefficient:0),using:&a)])
            } else {
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:full.axes[axis].intervalCount,of:ExactParameterInterval<OriginalExactScalar>.self))
                axes.append(Array(full.axes[axis].intervals))
            }
        }
        return try frame.selection(intervals:axes,limits:limits,using:&a)
    }
}
