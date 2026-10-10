#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry
import RetainedHostAdapters
@testable import CallerAdapters

@main struct DerivativeCurveRollingBallProof {
    typealias Legacy=RetainedRollingBallProof
    typealias Admission=Legacy.Admission
    typealias Family=Legacy.Family
    nonisolated static func curve(x: Double=0,y: Double=0,weighted: Bool,projected: Bool,reverse: Bool,
        using a: inout Admission) throws -> Curve3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let native=BSplineCurve3D(degree:1,knots:[0,0,0.5,1,1],
                controlPoints:[0.0,0.5,1].map { .init(x:x,y:y,z:$0) },weights:weighted ? [1,1,2]:nil)
            let span=try OriginalCurveRootSpan3D(source:.bSpline(native),start:.authored(reverse ? 1:0),end:.authored(reverse ? 0:1),
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:2,maximumAlgebraicDepth:0)
            let constraints: [OriginalPlaneDerivativeConstraint]=projected ? [
                .init(surface:.plane(.init(origin:.origin,normal:.init(x:0,y:1,z:1))),order:.curvature)]:[]
            return .originalPlaneDerivative(try .init(source:span,startConstraints:constraints,endConstraints:constraints,
                tolerance:.standard,usage:&usage,remainingSourceDepth:3))
        }.value
    }
    nonisolated static func expected(_ t: OriginalExactScalar,weighted: Bool,projected: Bool,reverse: Bool,
        field f: OriginalExactScalarDomain,using a: inout Admission) throws -> [OriginalExactScalar] {
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let u=reverse ? try f.subtracting(one,t,using:&a):t
        let half=try f.dividing(one,two,using:&a)
        let upper=try f.compare(u,half,using:&a) == .greater
        let g=weighted && upper ?
            try f.dividing(f.subtracting(f.multiplying(f.integer(3,using:&a),u,using:&a),one,using:&a),f.multiplying(two,u,using:&a),using:&a):u
        if !projected { return [z,g] }
        func polynomial(_ coefficients: [Int],divisor: Int=1) throws -> OriginalExactScalar {
            var value=z
            for coefficient in coefficients.reversed() {
                value=try f.adding(f.multiplying(value,t,using:&a),f.integer(coefficient,using:&a),using:&a)
            }
            return try f.dividing(value,f.integer(divisor,using:&a),using:&a)
        }
        let firstStart=weighted && reverse ? -0.5:reverse ? -1.0:1.0
        let firstEnd=weighted && !reverse ? 0.5:reverse ? -1.0:1.0
        let secondStart=weighted && reverse ? -1.0:0.0,secondEnd=weighted && !reverse ? -1.0:0.0
        let bases=[try polynomial([0,1,0,-6,8,-3]),try polynomial([0,0,0,-4,7,-3]),
            try polynomial([0,0,1,-3,3,-1],divisor:2),try polynomial([0,0,0,1,-2,1],divisor:2)]
        var delta=z
        for (basis,derivative) in zip(bases,[firstStart,firstEnd,secondStart,secondEnd]) {
            delta=try f.subtracting(delta,f.dividing(f.multiplying(basis,f.binary64(exactly:derivative,using:&a),using:&a),two,using:&a),using:&a)
        }
        return [delta,try f.adding(g,delta,using:&a)]
    }
    nonisolated static func numericExpected(_ t: Double,weighted: Bool,projected: Bool,reverse: Bool) -> [Double] {
        let u=reverse ? 1-t:t,g=weighted && u>0.5 ? (3*u-1)/(2*u):u
        if !projected { return [0,g] }
        let h10=t-6*t*t*t+8*t*t*t*t-3*t*t*t*t*t,h11 = -4*t*t*t+7*t*t*t*t-3*t*t*t*t*t
        let h20=0.5*t*t-1.5*t*t*t+1.5*t*t*t*t-0.5*t*t*t*t*t,h21=0.5*t*t*t-t*t*t*t+0.5*t*t*t*t*t
        let d10=weighted && reverse ? -0.5:reverse ? -1.0:1.0,d11=weighted && !reverse ? 0.5:reverse ? -1.0:1.0
        let d20=weighted && reverse ? -1.0:0.0,d21=weighted && !reverse ? -1.0:0.0
        let delta = -(d10*h10+d11*h11+d20*h20+d21*h21)/2
        return [delta,g+delta]
    }
    nonisolated static func childChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        for weighted in [false,true] { for projected in [false,true] { for reverse in [false,true] {
            let input=try curve(weighted:weighted,projected:projected,reverse:reverse,using:&a)
            let family=try Legacy.child(input,field:f,using:&a)
            guard case .derivativeCurve(let retained)=family.coverage else { throw ExactScalarFailure.invalidEvidence }
            try Legacy.require(family.graphs.count==2 && retained.laws.count==2)
            for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
                let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
                let target=try expected(t,weighted:weighted,projected:projected,reverse:reverse,field:f,using:&a)
                var count=0
                for graph in family.graphs {
                    if try graph.admits([t],limits:.init(remainingSourceDepth:6),using:&a) {
                        count+=1
                        guard case .derivativeCurve(let law)=graph.evidence else { throw ExactScalarFailure.invalidEvidence }
                        try Legacy.require(retained.source.owns(law.chart) && graph.layout.auxiliaries.isEmpty)
                        let r=graph.polynomials,denominator=try r.evaluated(graph.homogeneous[3],at:[t],using:&a).value
                        for (axis,value) in [try f.integer(0,using:&a),target[0],target[1]].enumerated() {
                            try Legacy.require(f.compare(f.dividing(r.evaluated(graph.homogeneous[axis],at:[t],using:&a).value,denominator,using:&a),value,using:&a) == .equal)
                        }
                    }
                }
                try Legacy.require(count==(n==1 && d==2 ? 2:1))
                // Numerical approximation accuracy is distinct from exact graph equality.
                let actual=try input.point(at:Double(n)/Double(d),tolerance:.standard)
                let numeric=numericExpected(Double(n)/Double(d),weighted:weighted,projected:projected,reverse:reverse)
                try Legacy.require(abs(actual.x)<1e-12 && abs(actual.y-numeric[0])<1e-12 && abs(actual.z-numeric[1])<1e-12)
            }
        } } }
        print("PASS direct derivative child laws: actual weighted/projected/reversed original Hermite curves, all closed sides and exact XYZ/T/owners")
    }
    nonisolated static func family(weighted: Bool,projected: Bool,reverse: Bool,mixed: Bool=false,
        field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Family {
        let center=try curve(weighted:weighted,projected:projected,reverse:reverse,using:&a)
        let first: Curve3D,second: Curve3D
        if mixed {
            let values=reverse ? [1.0,0.5,0]:[0.0,0.5,1]
            first = .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:values.map { .init(x:3,y:4,z:$0) }))
            second = .surfaceLift(.init(surface:try Legacy.host(x:3,y:-4,coons:true,using:&a),parameterCurve:Legacy.nativePcurve(reverse:reverse)))
        } else {
            first=try curve(x:3,y:4,weighted:weighted,projected:projected,reverse:reverse,using:&a)
            second=try curve(x:3,y:-4,weighted:weighted,projected:projected,reverse:reverse,using:&a)
        }
        let original=CallerAdapters.RollingBallBlendSurface3D(centerSpine:center,firstContact:first,secondContact:second,radius:5,tolerance:.standard)
        let l=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:7)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:CallerAdapters.OriginalGraphRollingBallSnapshotProvider(field:f)).bind(original,limits:l,using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer(),cl=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:6)
        let c=try p.prepare(source:source.original.originalCenter,field:f,maximumCharts:8,limits:cl,using:&a)
        let x=try p.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:8,limits:cl,using:&a)
        let y=try p.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:8,limits:cl,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
            .prepare(source:source,center:c,first:x,second:y,maximumCharts:32,limits:l,using:&a)
    }
    nonisolated static func tuple(t: OriginalExactScalar,mixed: Bool,reverse: Bool,field f: OriginalExactScalarDomain,
        using a: inout Admission) throws -> [OriginalExactScalar] {
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),five=try f.integer(5,using:&a)
        var result=[t,try f.dividing(one,f.integer(2,using:&a),using:&a)]
        if mixed { result.append(reverse ? try f.subtracting(one,t,using:&a):t);result.append(z) }
        result.append(five);result.append(five);result.append(try f.dividing(f.integer(3,using:&a),five,using:&a));return result
    }
    nonisolated static func check(_ family: Family,weighted: Bool,projected: Bool,reverse: Bool,mixed: Bool,
        using a: inout Admission) throws {
        let f=family.field,l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:7),maximumTransportDepth:16,maximumCharts:32,maximumFamilies:8,maximumIdentityProofs:8)
        try Legacy.require(family.graphs.count==(mixed ? 32:8))
        let issuer=RetainedHostAdapters.DefaultOriginalRollingBallGraphDomainIssuer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
            let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),q=try tuple(t:t,mixed:mixed,reverse:reverse,field:f,using:&a)
            let found=try full.liftedPositionIncidents(at:q,limits:l,using:&a),target=try expected(t,weighted:weighted,projected:projected,reverse:reverse,field:f,using:&a)
            try Legacy.require(found.count==(n==1 && d==2 ? (mixed ? 16:8):1))
            for member in found {
                let g=member.graph,r=g.polynomials,denominator=try r.evaluated(g.homogeneous[3],at:q,using:&a).value
                for (axis,value) in [try f.integer(5,using:&a),target[0],target[1]].enumerated() {
                    try Legacy.require(f.compare(f.dividing(r.evaluated(g.homogeneous[axis],at:q,using:&a).value,denominator,using:&a),value,using:&a) == .equal)
                }
            }
            let actual=try family.source.original.original.point(u:Double(n)/Double(d),v:0.5)
            let numeric=numericExpected(Double(n)/Double(d),weighted:weighted,projected:projected,reverse:reverse)
            try Legacy.require(abs(actual.x-5)<1e-12 && abs(actual.y-numeric[0])<1e-12 && abs(actual.z-numeric[1])<1e-12)
        }
        let q=try tuple(t:half,mixed:mixed,reverse:reverse,field:f,using:&a),third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,closed: Bool=true) throws -> RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:.init(value:32,coefficient:32),using:&a)
        }
        func selected(_ ranges: [[RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar>]]) throws -> RetainedHostAdapters.OriginalRollingBallGraphDomainCover<Legacy.Source,Legacy.Evidence,Legacy.Coverage> {
            try issuer.issue(request:frame.selection(intervals:ranges,limits:l,using:&a),family:family,limits:l,using:&a)
        }
        let strict=try selected([[interval(third,f.subtracting(one,third,using:&a),closed:false)],[interval(z,one)]])
        try Legacy.require(strict.liftedPositionIncidents(at:tuple(t:third,mixed:mixed,reverse:reverse,field:f,using:&a),limits:l,using:&a).isEmpty)
        let singleton=try selected([[interval(half,half)],[interval(half,half)]])
        try Legacy.require(singleton.liftedPositionIncidents(at:q,limits:l,using:&a).count==(mixed ? 16:8))
        let disconnected=try selected([[interval(z,third),interval(f.subtracting(one,third,using:&a),one)],[interval(z,one)]])
        try Legacy.require(disconnected.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        let empty=try selected([[],[]]);try Legacy.require(empty.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        var wrong=q;wrong[wrong.count-3]=try f.integer(-5,using:&a)
        try Legacy.require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        var cost=try Admission();_=try full.liftedPositionIncidents(at:q,limits:l,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try full.liftedPositionIncidents(at:q,limits:l,using:&exact)
        for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls)] {
            var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
            do { _=try full.liftedPositionIncidents(at:q,limits:l,using:&failed);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
        }
    }
    static func main() { do { try run() } catch { print("FAIL direct derivative curve rolling-ball uncaught failure");exit(1) } }
    nonisolated static func run() throws {
        try Legacy.run()
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try childChecks(field:f,using:&a)
        try DerivativeRollingBallProof.childChecks(field:f,using:&a)
        var held: Family?
        for (weighted,projected,reverse,mixed) in [(true,true,false,false),(true,true,true,false),(false,false,true,true)] {
            var preparation=try Admission(work:300_000_000,storage:1_073_741_824)
            let prepared=try family(weighted:weighted,projected:projected,reverse:reverse,mixed:mixed,field:f,using:&preparation)
            var query=try Admission(work:300_000_000,storage:1_073_741_824)
            try check(prepared,weighted:weighted,projected:projected,reverse:reverse,mixed:mixed,using:&query);held=prepared
            try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth),using:&query)
            do { try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth-1),using:&query);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        }
        print("PASS direct derivative rolling-ball and mixed product: weighted projected/reversed exact XYZ/T, eight/sixteen incidents, all selections/guards and query budgets")
        var cost=try Admission();_=try family(weighted:false,projected:false,reverse:false,field:f,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try family(weighted:false,projected:false,reverse:false,field:f,using:&exact)
        var short=try Admission(work:cost.ledger.work-1);try Legacy.scalarFailure { _=try family(weighted:false,projected:false,reverse:false,field:f,using:&short) }
        var bytes=try Admission(storage:cost.ledger.storageBytes-1);try Legacy.scalarFailure { _=try family(weighted:false,projected:false,reverse:false,field:f,using:&bytes) }
        for call in [1,cost.calls] {
            var failed=try Admission(cancelAt:call);try Legacy.scalarFailure { _=try family(weighted:false,projected:false,reverse:false,field:f,using:&failed) }
        }
        var cancelled=try Admission();cancelled.ledger.cancel();try Legacy.scalarFailure { _=try family(weighted:false,projected:false,reverse:false,field:f,using:&cancelled) }
        guard let held else { throw ExactScalarFailure.invalidEvidence }
        let wrong=try family(weighted:false,projected:false,reverse:false,field:f,using:&a)
        do {
            _=try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
                .prepare(source:held.source,center:wrong.center,first:held.first,second:held.second,maximumCharts:32,limits:.init(remainingSourceDepth:7),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
        let q=try tuple(t:f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),mixed:true,reverse:true,field:f,using:&a)
        var incidents=0
        for graph in held.graphs { if try graph.admits(q,limits:.init(remainingSourceDepth:7),using:&a) { incidents+=1 } }
        try Legacy.require(incidents==16)
        print("PASS direct derivative resources/cancel/lifetime: exact preparation ceilings, one-less, depth, entry/final callback, foreign binding and detached owners")
    }
}
