import CADCore

struct OriginalSphereConeNodePublicProducer {
    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,using a: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        guard let node=OriginalSphereConeNodeCurveSnapshotProvider.traversal(curve) else { return nil }
        do {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Generated node curves currently own
            // complete plane0/Y/uX contacts. Other required targets need their retained
            // original branch/UV receipt before this public route can succeed.
            guard OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(surface) else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try options.validate(tolerance:tolerance)
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts=min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans),options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth: a.effectiveLimits.maximumTransportDepth,
                maximumCharts:charts,maximumFamilies: min(charts, a.effectiveLimits.maximumFamilies),maximumIdentityProofs:0)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalSphereConeNodeCurveSnapshotProvider()).bind(curve,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: .init(source: source))
            let target=try DefaultOriginalSourceBindingIssuer(provider:OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance:tolerance)).bind(surface,limits:sourceLimits,using:&a)
            try a.admitSourceDepth(target.sourceDepth)
            a.context = a.context.retaining(second: .init(source: target))
            a.context = a.context.at(stage: .relation)
            let relation=try OriginalSphereConeNodePlaneRelation.resolve(source:source,target:target,options:options,limits:limits,using:&a)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:relation.ordinals.count,of:CurveSurfaceIntersection.self))
            var points:[CurveSurfaceIntersection]=[];points.reserveCapacity(relation.ordinals.count)
            if !relation.isEmpty {
                let input=node.source.original
                let cone=node.source.sphereIsFirst ? input.second:input.first
                guard case .analytic(.cone(_,_,let physicalAngle))=cone else { throw OriginalSourceIssuanceFailure.invalidSource }
                let trig=try trigonometry(physicalAngle,tolerance:tolerance,using:&a)
                let xx = OutwardScalarInterval.exact(1) - OutwardScalarInterval.exact(2)*trig.sine*trig.sine
                let zz = OutwardScalarInterval.exact(node.branch==0 ? 2:-2)*trig.sine*trig.cosine
                for ordinal in relation.ordinals {
                    try a.consumeWork(1)
                    let x=ordinal==1 ? xx:OutwardScalarInterval.exact(1)
                    let z=ordinal==1 ? zz:OutwardScalarInterval.exact(0)
                    let u=try representative(x,range:options.surfaceURange)
                    let v=try representative(-z,range:options.surfaceVRange)
                    let residual=(x.upper-x.lower+2*(z.upper-z.lower)).nextUp
                    guard residual.isFinite,residual<=tolerance.distance else { throw ExactScalarFailure.unresolved }
                    points.append(try .init(point:.init(x:u,y:0,z:-v),curveParameter:Double(ordinal)*0.5,
                        surfaceU:u,surfaceV:v,kind:.transverse,residual:residual,iterations:1))
                }
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:points,overlaps:[],originalSphereConeNodeRelation:relation)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance,context:a.context) }
    }
    private func trigonometry(_ angle:Double,tolerance:ModelingTolerance,using a:inout OriginalQueryExecution) throws -> (cosine:OutwardScalarInterval,sine:OutwardScalarInterval) {
        return try CertifiedRotationTrigonometry.evaluate(.exact(angle),tolerance:tolerance,using: &a)
    }
    private func representative(_ bound:OutwardScalarInterval,range:ScalarInterval?) throws -> Double {
        var value=bound.lower*0.5+bound.upper*0.5
        if let r=range { value=max(r.lower,min(r.upper,value)) }
        guard value.isFinite,value>=bound.lower,value<=bound.upper else { throw ExactScalarFailure.unresolved }
        return value
    }
}
