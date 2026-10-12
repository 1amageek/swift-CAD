import CADCore

/// One ordinary finite physical-phase query, with exact coverage beside numerical representatives.
struct OriginalAngularPlanePublicProducer {
    private typealias Base = OriginalPiScalarDomain
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    private typealias CurveSource = OriginalAnalyticCoordinateSnapshot
    private typealias PlaneSource = OriginalPlaneSnapshot

    func resolve(curve:Curve3D,surface:Surface3D,options:CurveSurfaceIntersectionOptions,
        tolerance:ModelingTolerance,invocation:CurveSurfaceQueryInvocation? = nil) throws -> CurveSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary angular/plane publication selects
        // this direct positive-turn profile only. Other primitives, phases and planes
        // retain their existing dispatch until their whole pair authority is connected.
        guard case .originalAngularTransport(let arc)=curve,
            case .circle(let circle)=arc.source,circle.normal == .unitZ,
            case .physicalRadianArc(let start,let end,let turns)=arc.transport,
            start == .zero,end == .one,turns == 1,
            case .analytic(.plane(let planeOrigin,let planeNormal))=surface,
            planeNormal == .unitX,planeOrigin.x == circle.center.x,
            let range=options.curveRange,range.lower.isFinite,range.upper.isFinite else { return nil }
        do {
            try options.validate(tolerance:tolerance)
            let usage=try NativeCurveSurfacePointAllowance(options:options,invocation:invocation)
            var a=Admission(usage:usage,maximumDepth:usage.maximumAlgebraicDepth)
            try a.checkpoint();try invocation?.consume(depth:0)
            let sourceLimits=try OriginalSourceIssuanceLimits(
                remainingSourceDepth:invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts=min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells,options.maximumSubdivisionCells)
            let limits=try OriginalDomainIdentityLimits(source:sourceLimits,maximumTransportDepth:usage.maximumAlgebraicDepth,
                maximumCharts:charts,maximumFamilies:1,maximumIdentityProofs:0)
            let f=try Base(using:&a)
            let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateCurveSnapshotProvider(tolerance:tolerance))
                .bind(curve,limits:sourceLimits,using:&a)
            let law=try DefaultOriginalPhysicalAnalyticCoordinateIssuer<CurveSource,Base>()
                .issue(source:source,field:f,limits:sourceLimits,using:&a)
            let curveIssuer=DefaultOriginalAnalyticDomainIssuer<CurveSource,Base>()
            let curveFrame=try curveIssuer.frame(law:law,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:[ExactParameterInterval<OriginalPiValue>].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalPiValue>.self))
            let request=try curveFrame.selection(intervals:[[interval(range,field:f,using:&a)]],limits:limits,using:&a)
            let curveCover=try curveIssuer.issue(request:request,law:law,limits:limits,using:&a)
            let target=try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:tolerance))
                .bind(surface,limits:sourceLimits,using:&a)
            let one=try f.integer(1,using:&a)
            let basis=try DefaultOriginalPlaneBasisIssuer<PlaneSource,Base>()
                .issue(source:target,field:f,firstLength:one,normalLength:one,limits:sourceLimits,using:&a)
            let planeIssuer=DefaultOriginalPlaneDomainIssuer<PlaneSource,Base>()
            let planeFrame=try planeIssuer.frame(basis:basis,limits:limits,using:&a)
            let full=try planeFrame.fullSelection(limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<OriginalPiValue>].self))
            var axes:[[ExactParameterInterval<OriginalPiValue>]]=[];axes.reserveCapacity(2)
            for axis in 0..<2 {
                try a.consumeWork(1)
                let selected=axis == 0 ? options.surfaceURange:options.surfaceVRange
                if let selected {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactParameterInterval<OriginalPiValue>.self))
                    axes.append([try interval(selected,field:f,using:&a)])
                } else {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:full.axes[axis].intervalCount,of:ExactParameterInterval<OriginalPiValue>.self))
                    axes.append(Array(full.axes[axis].intervals))
                }
            }
            let planeRequest=try planeFrame.selection(intervals:axes,limits:limits,using:&a)
            let planeCover=try planeIssuer.issue(request:planeRequest,basis:basis,limits:limits,using:&a)
            let geometryLimits=try NativeExactPublicLimits.unboundedStructure()
            let original=try DefaultOriginalAngularPlaneRelationCompiler<CurveSource,PlaneSource>()
                .resolve(curve:curveCover,plane:planeCover,maximumPairs:options.maximumCandidateCount,
                    maximumExtensionLevel:Int.max,limits:limits,cellLimits:geometryLimits.cells,
                    topologyLimits:geometryLimits.topology,using:&a)
            let geometry=try OriginalAngularPlaneGeometricRelations.resolve(original,limits:limits,
                geometryLimits:geometryLimits,maximumPoints:options.maximumCandidateCount,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:geometry.exactPoints.count,of:CurveSurfaceIntersection.self))
            var points:[CurveSurfaceIntersection]=[];points.reserveCapacity(geometry.exactPoints.count)
            for point in geometry.exactPoints {
                try a.consumeWork(1)
                points.append(try numerical(point,arc:arc,planeOrigin:planeOrigin,options:options,tolerance:tolerance,using:&a))
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:CurveSurfaceIntersectionResult.self))
            let result=CurveSurfaceIntersectionResult(points:points,overlaps:[],originalAngularPlaneRelation:geometry)
            try a.checkpoint();return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error,tolerance:tolerance) }
    }

    private func interval(_ range:ScalarInterval,field:Base,using a:inout Admission) throws -> ExactParameterInterval<OriginalPiValue> {
        let lower=try field.binary64(exactly:range.lower,using:&a),upper=try field.binary64(exactly:range.upper,using:&a)
        return try .checked(field:field,lower:.finite(lower),upper:.finite(upper),depth:.init(value:0,coefficient:0),using:&a)
    }

    private func numerical(_ point:OriginalAngularPlaneExactPoint,arc:OriginalAngularTransportCurve3D,
        planeOrigin:Point3D,options:CurveSurfaceIntersectionOptions,tolerance:ModelingTolerance,
        using a:inout Admission) throws -> CurveSurfaceIntersection {
        guard let request=options.curveRange else { throw NativeExactRelationFailure.invalidDomain }
        let f=point.original.curve.law.field,basis=point.original.plane.law
        var lower=max(0,request.lower),upper=min(1,request.upper)
        guard lower <= upper,
            try f.compare(f.binary64(exactly:lower,using:&a),point.parameter,using:&a) != .greater,
            try f.compare(point.parameter,f.binary64(exactly:upper,using:&a),using:&a) != .greater else {
            throw NativeExactRelationFailure.invalidDomain
        }
        for iteration in 1...options.maximumIterations {
            try a.consumeWork(1)
            let midpoint=lower*0.5+upper*0.5
            let order=try f.compare(point.parameter,f.binary64(exactly:midpoint,using:&a),using:&a)
            if order == .less { upper=midpoint } else if order == .greater { lower=midpoint }
            else { lower=midpoint;upper=midpoint }
            let bounds=try originalBounds(arc,over:.init(lower:lower,upper:upper),tolerance:tolerance,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OutwardScalarInterval.self))
            var uvBounds:[OutwardScalarInterval]=[];uvBounds.reserveCapacity(2)
            for axis in 0..<2 {
                let vector=axis == 0 ? basis.u:basis.v
                var total=OutwardScalarInterval.exact(0)
                for coordinate in 0..<3 {
                    try a.consumeWork(1)
                    let gain=try unitComponent(vector[coordinate],field:f,using:&a)
                    let origin=coordinate == 0 ? planeOrigin.x:coordinate == 1 ? planeOrigin.y:planeOrigin.z
                    total=total+(bounds[coordinate] - .exact(origin)) * .exact(gain)
                }
                uvBounds.append(total)
            }
            var certified=true,residual=0.0
            for axis in 0..<3 {
                try certify(point.position[axis],in:bounds[axis],field:f,using:&a)
                let width=(bounds[axis].upper-bounds[axis].lower).nextUp
                if !width.isFinite { certified=false }
                residual=(residual+width).nextUp
            }
            for axis in 0..<2 {
                try certify(point.uv[axis],in:uvBounds[axis],field:f,using:&a)
                let width=(uvBounds[axis].upper-uvBounds[axis].lower).nextUp
                if !width.isFinite { certified=false }
                residual=(residual+width).nextUp
            }
            if !certified || !residual.isFinite || residual > tolerance.distance { continue }
            let t=lower*0.5+upper*0.5
            let x=try representative(bounds[0],request:nil),y=try representative(bounds[1],request:nil),z=try representative(bounds[2],request:nil)
            let u=try representative(uvBounds[0],request:options.surfaceURange)
            let v=try representative(uvBounds[1],request:options.surfaceVRange)
            try a.checkpoint()
            return try .init(point:.init(x:x,y:y,z:z),curveParameter:t,surfaceU:u,surfaceV:v,
                kind:.transverse,residual:residual,iterations:iteration)
        }
        throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
            message:"Original angular point refinement exhausted the caller iteration ceiling.")
    }

    private func originalBounds(_ arc:OriginalAngularTransportCurve3D,over range:ScalarInterval,
        tolerance:ModelingTolerance,using a:inout Admission) throws -> [OutwardScalarInterval] {
        // Lend the same value-local allowance to the synchronous legacy interval callbacks.
        var usage=a.usage
        defer { a.usage=usage }
        let jet=try arc.intervalTaylorJet(over:range,throughOrder:0,tolerance:tolerance,
            consumeWork:{ try usage.consumeExactWork(1) },consumeStorage:{ try usage.retainBytes($0) })
        try usage.retainBytes(exactScalarPayloadBytes(count:3,of:OutwardScalarInterval.self))
        return [try jet.x.coefficient(0,0),try jet.y.coefficient(0,0),try jet.z.coefficient(0,0)]
    }
    private func unitComponent(_ value:OriginalPiValue,field:Base,using a:inout Admission) throws -> Double {
        for candidate in -1...1 {
            try a.consumeWork(1)
            if try field.compare(value,field.integer(candidate,using:&a),using:&a) == .equal { return Double(candidate) }
        }
        throw NativeExactRelationFailure.unsupportedCoverage
    }
    private func certify(_ value:OriginalPiValue,in bounds:OutwardScalarInterval,
        field:Base,using a:inout Admission) throws {
        guard bounds.lower.isFinite,bounds.upper.isFinite,bounds.lower <= bounds.upper else {
            throw ExactScalarFailure.unresolved
        }
        guard try field.compare(field.binary64(exactly:bounds.lower,using:&a),value,using:&a) != .greater,
            try field.compare(value,field.binary64(exactly:bounds.upper,using:&a),using:&a) != .greater else {
            throw NativeExactRelationFailure.invalidDomain
        }
    }
    private func representative(_ bounds:OutwardScalarInterval,request:ScalarInterval?) throws -> Double {
        var value=bounds.lower*0.5+bounds.upper*0.5
        if let request { value=max(request.lower,min(request.upper,value)) }
        guard value.isFinite,value >= bounds.lower,value <= bounds.upper else { throw ExactScalarFailure.unresolved }
        return value
    }
}
