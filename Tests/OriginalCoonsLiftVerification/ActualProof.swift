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

@main struct ActualCoonsNativePcurveLiftProof {
    typealias Admission = ActualRetainedHostLiftProof.Admission
    typealias Source = RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSnapshot<RetainedHostAdapters.OriginalCoonsAtlasSnapshot>
    typealias Family = RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs<Source>
    typealias Host = RetainedHostAdapters.OriginalFiniteRetainedSurfaceCharts<RetainedHostAdapters.OriginalCoonsAtlasSnapshot>
    typealias Pcurve = RetainedHostAdapters.OriginalFiniteBSplineCharts<BSplineCurve2D>
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        if !value { print("FAIL Native pcurve host line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func children(_ input: SurfaceLiftCurve3D,field: OriginalExactScalarDomain,sourceDepth: Int=8,using a: inout Admission)
        throws -> (RetainedHostAdapters.OriginalSourceBinding<Source>,Host,Pcurve) {
        let l=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:sourceDepth)
        let provider=RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSnapshotProvider(
            host:RetainedHostAdapters.OriginalCoonsAtlasSnapshotProvider(field:field,tolerance:.standard),tolerance:.standard)
        let s=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:l,using:&a)
        try require(s.original.original==input)
        let h=try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceChartPreparer<RetainedHostAdapters.OriginalCoonsAtlasSnapshot>()
            .prepare(source:s.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        let c=try RetainedHostAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>()
            .prepare(source:s.original.originalPcurve,field:field,maximumCharts:2,limits:l,using:&a)
        return (s,h,c)
    }
    nonisolated static func prepare<P: RetainedHostAdapters.OriginalFiniteNativePcurveRetainedAtlasLiftGraphPreparing>(
        _ p: P,source: RetainedHostAdapters.OriginalSourceBinding<Source>,host: Host,pcurve: Pcurve,
        maximumCharts: Int=8,using a: inout Admission) throws -> Family where P.Source == Source {
        try p.prepare(source:source,surface:host,pcurve:pcurve,maximumCharts:maximumCharts,
            limits:.init(remainingSourceDepth:8),using:&a)
    }
    static func main() { do { try run() } catch { print("FAIL Native pcurve retained host");exit(1) } }
    nonisolated static func run() throws {
        try ActualNativePcurveRetainedHostProof.run()
        try ActualCoonsAffineLiftProof.run()
        var a=try Admission();let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:8),maximumTransportDepth:16,
            maximumCharts:8,maximumFamilies:2,maximumIdentityProofs:8)
        let preparer=RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>()
        var held: Family?
        for multi in [true,false] {
            let host=try ActualCoonsAffineLiftProof.shape(multi:multi,using:&a)
            for mode in 0..<3 {
                let coordinates: [Double]=mode==2 ? [0.5,0.5,0.5]:mode==1 ? [1,0.5,0]:[0,0.5,1]
                let curve=BSplineCurve2D(degree:1,knots:[2,2,3,5,5],controlPoints:coordinates.map { .init(x:$0,y:0.5) },weights:[1,2,1])
                let input=SurfaceLiftCurve3D(surface:.procedural(.originalCoons(host)),parameterCurve:.bSpline(curve))
                let (s,h,c)=try children(input,field:f,using:&a)
                let family=try prepare(preparer,source:s,host:h,pcurve:c,using:&a)
                try require(family.graphs.count==(multi ? 8:2))
                try require(family.nativePcurve.source.owns(c.laws[0].chart))
                try require(family.nativePcurve.laws.count==2)
                let issuer=RetainedHostAdapters.DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
                let frame=try issuer.frame(family:family,limits:l,using:&a)
                let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
                let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                let half=try f.dividing(one,f.integer(2,using:&a),using:&a)
                let third=try f.dividing(one,f.integer(3,using:&a),using:&a)
                for (n,d) in [(0,1),(1,4),(1,3),(1,2),(3,4),(1,1)] {
                    let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
                    let q=try f.multiplying(f.integer(3,using:&a),t,using:&a)
                    let u: OriginalExactScalar
                    if mode==2 { u=half }
                    else {
                        let forward: OriginalExactScalar
                        if try f.compare(t,third,using:&a) != .greater {
                            forward=try f.dividing(q,f.adding(one,q,using:&a),using:&a)
                        } else {
                            let r=try f.dividing(f.subtracting(q,one,using:&a),f.integer(2,using:&a),using:&a)
                            forward=try f.dividing(one,f.subtracting(f.integer(2,using:&a),r,using:&a),using:&a)
                        }
                        u=mode==1 ? try f.subtracting(one,forward,using:&a):forward
                    }
                    let tuple=[t,u,half]
                    let found=try full.liftedPositionIncidents(at:tuple,limits:l,using:&a)
                    let sides=(multi ? ((try f.compare(u,half,using:&a) == .equal ? 2:1)*2):1)*(n==1 && d==3 ? 2:1)
                    try require(found.count==sides)
                    for member in found {
                        let ring=member.graph.polynomials,g=member.graph
                        let denominator=try ring.evaluated(g.homogeneous[3],at:tuple,using:&a).value
                        let sourceZ=multi ? zero:try f.dividing(f.multiplying(u,f.subtracting(one,u,using:&a),using:&a),f.integer(4,using:&a),using:&a)
                        for (axis,target) in [u,half,sourceZ].enumerated() {
                            let value=try f.dividing(ring.evaluated(g.homogeneous[axis],at:tuple,using:&a).value,denominator,using:&a)
                            try require(f.compare(value,target,using:&a) == .equal)
                        }
                    }
                    // Public point is a numerical midpoint, not the source-equality oracle.
                    let td=Double(n)/Double(d),qDouble=3*td
                    let forward=td<=1.0/3 ? qDouble/(1+qDouble):1/(2-(qDouble-1)/2)
                    let ud=mode==2 ? 0.5:mode==1 ? 1-forward:forward
                    let point=try input.point(atNormalizedFraction:td,tolerance:.standard)
                    try require(abs(point.x-ud)<=ModelingTolerance.standard.distance)
                    try require(abs(point.y-0.5)<=ModelingTolerance.standard.distance)
                    try require(abs(point.z-(multi ? 0:ud*(1-ud)/4))<=ModelingTolerance.standard.distance)
                    let interval=try RetainedHostAdapters.ExactParameterInterval.checked(field:f,lower:.finite(t),upper:.finite(t),
                        depth:.init(value:32,coefficient:32),using:&a)
                    let selected=try issuer.issue(request:frame.selection(intervals:[[interval]],limits:l,using:&a),family:family,limits:l,using:&a)
                    try require(selected.liftedPositionIncidents(at:tuple,limits:l,using:&a).count==sides)
                }
                if multi && mode==0 {
                    var sourceCost=try Admission();_=try children(input,field:f,using:&sourceCost)
                    var exactSource=try Admission(work:sourceCost.ledger.work,storage:sourceCost.ledger.storageBytes)
                    _=try children(input,field:f,using:&exactSource)
                    var shortSourceWork=try Admission(work:sourceCost.ledger.work-1)
                    try ActualRetainedHostLiftProof.scalarFailure { _=try children(input,field:f,using:&shortSourceWork) }
                    var shortSourceStorage=try Admission(storage:sourceCost.ledger.storageBytes-1)
                    try ActualRetainedHostLiftProof.scalarFailure { _=try children(input,field:f,using:&shortSourceStorage) }
                    for call in [1,sourceCost.calls] {
                        var cancelled=try Admission(cancelAt:call)
                        try ActualRetainedHostLiftProof.scalarFailure { _=try children(input,field:f,using:&cancelled) }
                    }
                    do { _=try children(input,field:f,sourceDepth:0,using:&a);throw ExactScalarFailure.invalidEvidence }
                    catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
                    let clamp=BSplineCurve2D(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:-1e-10,y:0.5),.init(x:0.5,y:0.5)])
                    let bad=SurfaceLiftCurve3D(surface:input.surface,parameterCurve:.bSpline(clamp))
                    do { _=try children(bad,field:f,using:&a);throw ExactScalarFailure.invalidEvidence }
                    catch RetainedHostAdapters.OriginalSourceIssuanceFailure.unsupportedRepresentation {}
                    let foreign=SurfaceLiftCurve3D(surface:.plane(.init(origin:.origin,normal:.init(x:0,y:0,z:1))),parameterCurve:input.parameterCurve)
                    do { _=try children(foreign,field:f,using:&a);throw ExactScalarFailure.invalidEvidence }
                    catch RetainedHostAdapters.OriginalSourceIssuanceFailure.unsupportedRepresentation {}
                }
                let tuple=[third,half,half]
                var measured=try Admission();_=try full.liftedPositionIncidents(at:tuple,limits:l,using:&measured)
                var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
                _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&exact)
                var work=try Admission(work:measured.ledger.work-1)
                do { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&work);throw ExactScalarFailure.invalidEvidence }
                catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
                var storage=try Admission(storage:measured.ledger.storageBytes-1)
                do { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&storage);throw ExactScalarFailure.invalidEvidence }
                catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
                for call in [1,measured.calls] {
                    var cancelled=try Admission(cancelAt:call)
                    do { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
                    catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
                }
                var prepCost=try Admission();_=try prepare(preparer,source:s,host:h,pcurve:c,using:&prepCost)
                var exactPrep=try Admission(work:prepCost.ledger.work,storage:prepCost.ledger.storageBytes)
                _=try prepare(preparer,source:s,host:h,pcurve:c,using:&exactPrep)
                var shortPrep=try Admission(work:prepCost.ledger.work-1)
                try ActualRetainedHostLiftProof.scalarFailure { _=try prepare(preparer,source:s,host:h,pcurve:c,using:&shortPrep) }
                var shortBytes=try Admission(storage:prepCost.ledger.storageBytes-1)
                try ActualRetainedHostLiftProof.scalarFailure { _=try prepare(preparer,source:s,host:h,pcurve:c,using:&shortBytes) }
                for call in [1,prepCost.calls] {
                    var cancelled=try Admission(cancelAt:call)
                    try ActualRetainedHostLiftProof.scalarFailure { _=try prepare(preparer,source:s,host:h,pcurve:c,using:&cancelled) }
                }
                do { _=try prepare(preparer,source:s,host:h,pcurve:c,maximumCharts:family.graphs.count-1,using:&a);throw ExactScalarFailure.invalidEvidence }
                catch RetainedHostAdapters.OriginalSourceIssuanceFailure.chartLimit {}
                let other=try children(input,field:f,using:&a)
                do { _=try prepare(preparer,source:s,host:h,pcurve:other.2,using:&a);throw ExactScalarFailure.invalidEvidence }
                catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
                let empty=try issuer.issue(request:frame.selection(intervals:[[]],limits:l,using:&a),family:family,limits:l,using:&a)
                try require(empty.liftedPositionIncidents(at:tuple,limits:l,using:&a).isEmpty)
                try require(full.liftedPositionIncidents(at:[third,zero,zero],limits:l,using:&a).isEmpty)
                held=family
            }
        }
        guard let held else { throw ExactScalarFailure.invalidEvidence }
        try require(held.graphs[0].admits([try f.integer(0,using:&a),try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),
            try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)],limits:.init(remainingSourceDepth:8),using:&a))
        print("PASS actual Coons atlas Native pcurve authored spans/normalization, weighted/reversed/constant fibers, exact all sides, selections/resources/cancel/foreign binding and detached lifetime")
    }
}
