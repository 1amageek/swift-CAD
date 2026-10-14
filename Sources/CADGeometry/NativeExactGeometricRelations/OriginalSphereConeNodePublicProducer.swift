import CADCore

struct OriginalSphereConeNodePublicProducer {
    private typealias Admission=NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,invocation:CurveSurfaceQueryInvocation?=nil) throws -> CurveSurfaceIntersectionResult? {
        guard let node=OriginalSphereConeNodeCurveSnapshotProvider.traversal(curve) else { return nil }
        do {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Generated node curves currently own
            // complete plane0/Y/uX contacts. Other required targets need their retained
            // original branch/UV receipt before this public route can succeed.
            guard OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(surface) else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try options.validate(tolerance:tolerance)
            let usage=try NativeCurveSurfacePointAllowance(options:options,invocation:invocation)
            var a=Admission(usage:usage,maximumDepth:usage.maximumAlgebraicDepth)
            try a.checkpoint();try invocation?.consume(depth:0)
            let sourceLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts=min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells,options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth:usage.maximumAlgebraicDepth,
                maximumCharts:charts,maximumFamilies:charts,maximumIdentityProofs:0)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalSphereConeNodeCurveSnapshotProvider()).bind(curve,limits:sourceLimits,using:&a)
            let target=try DefaultOriginalSourceBindingIssuer(provider:OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance:tolerance)).bind(surface,limits:sourceLimits,using:&a)
            let relation=try OriginalSphereConeNodePlaneRelation.resolve(source:source,target:target,options:options,limits:limits,using:&a)
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
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:points,overlaps:[],originalSphereConeNodeRelation:relation)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance) }
    }
    private func trigonometry(_ angle:Double,tolerance:ModelingTolerance,using a:inout Admission) throws -> (cosine:OutwardScalarInterval,sine:OutwardScalarInterval) {
        var numerical=a.usage
        defer { a.usage=numerical }
        return try CertifiedRotationTrigonometry.evaluate(.exact(angle),tolerance:tolerance,consumeWork:{try numerical.consumeExactWork(1)})
    }
    private func representative(_ bound:OutwardScalarInterval,range:ScalarInterval?) throws -> Double {
        var value=bound.lower*0.5+bound.upper*0.5
        if let r=range { value=max(r.lower,min(r.upper,value)) }
        guard value.isFinite,value>=bound.lower,value<=bound.upper else { throw ExactScalarFailure.unresolved }
        return value
    }
}
