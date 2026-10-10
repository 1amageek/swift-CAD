import CADCore
@testable import CADGeometry
import RetainedHostAdapters
@testable import CallerAdapters

@main struct RetainedRollingBallProof {
    typealias Admission=ActualRetainedHostLiftProof.Admission
    typealias Source=CallerAdapters.OriginalGraphRollingBallSnapshot
    typealias Evidence=CallerAdapters.OriginalRollingBallCurveGraphEvidence
    typealias Coverage=CallerAdapters.OriginalRollingBallCurveGraphCoverage
    typealias Family=RetainedHostAdapters.OriginalFiniteRollingBallGraphs<Source,Evidence,Coverage>
    typealias Child=RetainedHostAdapters.OriginalCompleteCurveGraphs<CallerAdapters.OriginalRollingBallCurveSnapshot,Evidence,Coverage>
    typealias Limits=RetainedHostAdapters.OriginalSourceIssuanceLimits
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        if !value { print("FAIL retained rolling-ball line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func scalarFailure(_ body: () throws -> Void) throws {
        do { try ActualRetainedHostLiftProof.scalarFailure(body) }
        catch ExactScalarFailure.cancelled {}
        catch ExactScalarFailure.resourceLimit(_) {}
    }
    nonisolated static func host(x: Double,y: Double,coons: Bool,using a: inout Admission) throws -> Surface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let stations=[0.0,0.5,1.0]
            let surface=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
                controlPoints:stations.map { v in stations.map { u in Point3D(x:x,y:y+v,z:u) } })
            let issuer=OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of:.bSpline(surface),at:side,maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
            }
            let original=try OriginalCoonsSurface3D(vMinimumBoundary:boundary(.vLower),vMaximumBoundary:boundary(.vUpper),
                uMinimumBoundary:boundary(.uLower),uMaximumBoundary:boundary(.uUpper),tolerance:.standard,usage:&usage)
            if coons { return .procedural(.originalCoons(original)) }
            return .procedural(.originalBoundaryCorrected(try .init(construction:surface,boundaries:original,
                maximumSpanCount:4,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage)))
        }.value
    }
    nonisolated static func nativePcurve(reverse: Bool=false,mode: Int=0) -> SurfaceParameterCurve {
        if mode==1 { return .bSpline(.init(degree:2,knots:[0,0,0,1,1,1],controlPoints:[.init(x:0,y:0),.init(x:1,y:0),.init(x:0,y:0)])) }
        if mode==2 { return .bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0.5,y:0),.init(x:0.5,y:0)])) }
        return .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:(reverse ? [1.0,0.5,0]:[0.0,0.5,1]).map { .init(x:$0,y:0) }))
    }
    nonisolated static func child(_ input: Curve3D,field: OriginalExactScalarDomain,using a: inout Admission) throws -> Child {
        let l=try Limits(remainingSourceDepth:6)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:
            CallerAdapters.OriginalRollingBallCurveSnapshotProvider(field:field,tolerance:.standard)).bind(input,limits:l,using:&a)
        return try CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer().prepare(source:source,field:field,maximumCharts:8,limits:l,using:&a)
    }
    nonisolated static func childChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let quarter=try f.dividing(f.integer(1,using:&a),f.integer(4,using:&a),using:&a)
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),zero=try f.integer(0,using:&a)
        for coons in [true,false] {
            let surface=try host(x:0,y:0,coons:coons,using:&a)
            for native in [true,false] {
                let pcurve: SurfaceParameterCurve=native ? nativePcurve():.constantV(v:0,uStart:0,uEnd:1)
                let input=Curve3D.surfaceLift(.init(surface:surface,parameterCurve:pcurve))
                let family=try child(input,field:f,using:&a)
                switch family.coverage {
                case .coonsNativeLift:try require(coons && native)
                case .coonsLift:try require(coons && !native)
                case .boundaryNativeLift:try require(!coons && native)
                case .boundaryLift:try require(!coons && !native)
                default:throw ExactScalarFailure.invalidEvidence
                }
                try require(family.graphs.count==(native ? 8:4))
                var found=0
                for graph in family.graphs {
                    if try graph.admits([half,half,zero],limits:.init(remainingSourceDepth:6),using:&a) { found+=1 }
                    try require(!graph.admits([quarter,half,zero],limits:.init(remainingSourceDepth:6),using:&a))
                }
                try require(found==(native ? 4:2))
            }
            for mode in [1,2] {
                let family=try child(.surfaceLift(.init(surface:surface,parameterCurve:nativePcurve(mode:mode))),field:f,using:&a)
                let u=mode==1 ? try f.dividing(f.integer(3,using:&a),f.integer(8,using:&a),using:&a):half
                for t in [quarter,try f.subtracting(f.integer(1,using:&a),quarter,using:&a)] {
                    var found=0
                    for graph in family.graphs { if try graph.admits([t,u,zero],limits:.init(remainingSourceDepth:6),using:&a) { found+=1 } }
                    try require(found==(mode==1 ? 1:2))
                }
            }
        }
        print("PASS retained rolling-ball child capabilities: four host/pcurve cases, all sides, wrong UV, nonmonotone and constant fibers")
    }
    nonisolated static func family(swapped: Bool=false,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Family {
        func rail(_ x: Double,_ y: Double,_ coons: Bool,_ native: Bool) throws -> Curve3D {
            .surfaceLift(.init(surface:try host(x:x,y:y,coons:coons,using:&a),parameterCurve:native ? nativePcurve(reverse:swapped):.constantV(v:0,uStart:swapped ? 1:0,uEnd:swapped ? 0:1)))
        }
        let original=try CallerAdapters.RollingBallBlendSurface3D(centerSpine:rail(0,0,!swapped,true),
            firstContact:rail(3,4,swapped,false),secondContact:rail(3,-4,!swapped,false),radius:5,tolerance:.standard)
        let l=try Limits(remainingSourceDepth:7)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:CallerAdapters.OriginalGraphRollingBallSnapshotProvider(field:f))
            .bind(original,limits:l,using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer(),cl=try Limits(remainingSourceDepth:6)
        let center=try p.prepare(source:source.original.originalCenter,field:f,maximumCharts:8,limits:cl,using:&a)
        let first=try p.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:8,limits:cl,using:&a)
        let second=try p.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:8,limits:cl,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>()
            .prepare(source:source,center:center,first:first,second:second,maximumCharts:128,limits:l,using:&a)
    }
    nonisolated static func tuple(t: OriginalExactScalar,reverse: Bool=false,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> [OriginalExactScalar] {
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),five=try f.integer(5,using:&a)
        let u=reverse ? try f.subtracting(one,t,using:&a):t
        return [t,try f.dividing(one,f.integer(2,using:&a),using:&a),u,zero,u,zero,u,zero,five,five,
            try f.dividing(f.integer(3,using:&a),five,using:&a)]
    }
    nonisolated static func check(_ family: Family,reverse: Bool,using a: inout Admission) throws {
        let f=family.field,l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:7),maximumTransportDepth:16,
            maximumCharts:128,maximumFamilies:8,maximumIdentityProofs:8)
        try require(family.graphs.count==128)
        let issuer=RetainedHostAdapters.DefaultOriginalRollingBallGraphDomainIssuer<Source,Evidence,Coverage>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let one=try f.integer(1,using:&a),zero=try f.integer(0,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a),twoThirds=try f.multiplying(third,f.integer(2,using:&a),using:&a)
        for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
            let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),q=try tuple(t:t,reverse:reverse,field:f,using:&a)
            let found=try full.liftedPositionIncidents(at:q,limits:l,using:&a)
            try require(found.count==(n==1 && d==2 ? 16:1))
            for member in found {
                let g=member.graph,r=g.polynomials,denominator=try r.evaluated(g.homogeneous[3],at:q,using:&a).value
                for (axis,target) in [try f.integer(5,using:&a),zero,q[2]].enumerated() {
                    let actual=try f.dividing(r.evaluated(g.homogeneous[axis],at:q,using:&a).value,denominator,using:&a)
                    try require(f.compare(actual,target,using:&a) == .equal)
                }
            }
            // Numerical evaluator accuracy is separate from exact graph equality.
            let numeric=try family.source.original.original.point(u:Double(n)/Double(d),v:0.5)
            try require(abs(numeric.x-5)<1e-12 && abs(numeric.y)<1e-12 && abs(numeric.z-(reverse ? 1-Double(n)/Double(d):Double(n)/Double(d)))<1e-12)
        }
        let knot=try tuple(t:half,reverse:reverse,field:f,using:&a)
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,closed: Bool=true) throws -> RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:.init(value:32,coefficient:32),using:&a)
        }
        func cover(_ intervals: [[RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar>]]) throws -> RetainedHostAdapters.OriginalRollingBallGraphDomainCover<Source,Evidence,Coverage> {
            try issuer.issue(request:frame.selection(intervals:intervals,limits:l,using:&a),family:family,limits:l,using:&a)
        }
        let strict=try cover([[interval(third,twoThirds,closed:false)],[interval(zero,one)]])
        try require(strict.liftedPositionIncidents(at:tuple(t:third,reverse:reverse,field:f,using:&a),limits:l,using:&a).isEmpty)
        try require(strict.liftedPositionIncidents(at:knot,limits:l,using:&a).count==16)
        let singleton=try cover([[interval(half,half)],[interval(half,half)]])
        try require(singleton.liftedPositionIncidents(at:knot,limits:l,using:&a).count==16)
        let disconnected=try cover([[interval(zero,third),interval(twoThirds,one)],[interval(zero,one)]])
        try require(disconnected.liftedPositionIncidents(at:knot,limits:l,using:&a).isEmpty)
        let empty=try cover([[],[]]);try require(empty.liftedPositionIncidents(at:knot,limits:l,using:&a).isEmpty)
        var wrong=knot;wrong[2]=zero
        try require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        wrong=knot;wrong[8]=try f.integer(-5,using:&a)
        try require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        var cost=try Admission();_=try full.liftedPositionIncidents(at:knot,limits:l,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes)
        _=try full.liftedPositionIncidents(at:knot,limits:l,using:&exact)
        for cancel in [1,cost.calls] {
            var cancelled=try Admission(cancelAt:cancel)
            do { _=try full.liftedPositionIncidents(at:knot,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
        }
        var short=try Admission(work:cost.ledger.work-1)
        do { _=try full.liftedPositionIncidents(at:knot,limits:l,using:&short);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
        var bytes=try Admission(storage:cost.ledger.storageBytes-1)
        do { _=try full.liftedPositionIncidents(at:knot,limits:l,using:&bytes);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
        print("PASS retained rolling-ball actual product and DI: 128 triples, sixteen incidents, exact XYZ/UV/positive roots, all requests and query resource/cancel")
    }
    static func main() throws { try run() }
    nonisolated static func run() throws {
        try RetainedLiftCallerProof.run()
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try childChecks(field:f,using:&a)
        var held: Family?,firstFamily: Family?
        for swapped in [false,true] {
            let prepared=try family(swapped:swapped,field:f,using:&a)
            try check(prepared,reverse:swapped,using:&a);held=prepared
            if !swapped { firstFamily=prepared }
            try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth),using:&a)
            do { try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth-1),using:&a);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        }
        var measured=try Admission(work:300_000_000,storage:1_073_741_824)
        _=try family(field:f,using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try family(field:f,using:&exact)
        var short=try Admission(work:measured.ledger.work-1)
        try scalarFailure { _=try family(field:f,using:&short) }
        var bytes=try Admission(storage:measured.ledger.storageBytes-1)
        try scalarFailure { _=try family(field:f,using:&bytes) }
        for cancel in [1,measured.calls] {
            var cancelled=try Admission(cancelAt:cancel)
            try scalarFailure { _=try family(field:f,using:&cancelled) }
        }
        guard let held,let firstFamily else { throw ExactScalarFailure.invalidEvidence }
        do {
            _=try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>()
                .prepare(source:held.source,center:firstFamily.center,first:held.first,second:held.second,maximumCharts:128,
                    limits:.init(remainingSourceDepth:7),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
        let q=try tuple(t:f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),reverse:true,field:f,using:&a)
        var found=0
        for graph in held.graphs { if try graph.admits(q,limits:.init(remainingSourceDepth:7),using:&a) { found+=1 } }
        try require(found==16)
        print("PASS retained rolling-ball resource/cancel/lifetime: exact preparation ceilings, one-less, entry/final callback and detached owners")
    }
}
