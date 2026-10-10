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

@main struct DerivativeLiftHostProof {
    typealias Admission=ActualRetainedHostLiftProof.Admission
    typealias Host=RetainedHostAdapters.OriginalPlaneDerivativeSurfaceSnapshot
    typealias Native=RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSnapshot<Host>
    typealias Affine=RetainedHostAdapters.OriginalRetainedAtlasSurfaceLiftSnapshot<Host>
    typealias Limits=RetainedHostAdapters.OriginalSourceIssuanceLimits
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        if !value { print("FAIL derivative lift host line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func host<P: RetainedHostAdapters.OriginalRetainedLiftHostSnapshotting>(_ provider: P,
        _ input: Surface3D,using a: inout Admission) throws -> RetainedHostAdapters.OriginalSourceBinding<Host> where P.Source==Host {
        try provider.bindHost(input,limits:.init(remainingSourceDepth:2),using:&a)
    }
    nonisolated static func native(_ input: SurfaceLiftCurve3D,field f: OriginalExactScalarDomain,using a: inout Admission)
        throws -> RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs<Native> {
        let l=try Limits(remainingSourceDepth:3)
        let provider=RetainedHostAdapters.OriginalNativePcurveRetainedAtlasLiftSnapshotProvider(
            host:RetainedHostAdapters.OriginalPlaneDerivativeSurfaceSnapshotProvider(field:f,tolerance:.standard),tolerance:.standard)
        let s=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:l,using:&a)
        let h=try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceChartPreparer<Host>()
            .prepare(source:s.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        let p=try RetainedHostAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>()
            .prepare(source:s.original.originalPcurve,field:f,maximumCharts:2,limits:l,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Native>()
            .prepare(source:s,surface:h,pcurve:p,maximumCharts:8,limits:l,using:&a)
    }
    nonisolated static func affine(_ input: SurfaceLiftCurve3D,field f: OriginalExactScalarDomain,using a: inout Admission)
        throws -> RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs<Affine> {
        let l=try Limits(remainingSourceDepth:3)
        let provider=RetainedHostAdapters.OriginalRetainedAtlasSurfaceLiftSnapshotProvider(
            host:RetainedHostAdapters.OriginalPlaneDerivativeSurfaceSnapshotProvider(field:f,tolerance:.standard),field:f,tolerance:.standard)
        let s=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:l,using:&a)
        let h=try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceChartPreparer<Host>()
            .prepare(source:s.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        let p=try RetainedHostAdapters.DefaultOriginalFiniteRetainedCurveChartPreparer<RetainedHostAdapters.OriginalAffinePcurveSnapshot>()
            .prepare(source:s.original.originalPcurve,maximumCharts:1,limits:l,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Affine>()
            .prepare(source:s,surface:h,pcurve:p,maximumCharts:4,limits:l,using:&a)
    }
    nonisolated static func check<S: RetainedHostAdapters.OriginalLiftGraphSourceReading>(
        _ family: RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs<S>,input: SurfaceLiftCurve3D,
        mode: Int,weighted: Bool,projected: Bool,using a: inout Admission) throws {
        let f=family.field,l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),
            maximumTransportDepth:16,maximumCharts:8,maximumFamilies:2,maximumIdentityProofs:8)
        let issuer=RetainedHostAdapters.DefaultOriginalRetainedSurfaceLiftDomainIssuer<S>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        for (n,d) in [(0,1),(1,4),(1,2),(3,4),(1,1)] {
            let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
            let u=mode==2 ? half:t,v=mode==2 ? try f.subtracting(one,t,using:&a):mode==3 ? try f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a):t
            let tuple=[t,u,v],found=try full.liftedPositionIncidents(at:tuple,limits:l,using:&a)
            let numericT=Double(n)/Double(d),numericU=mode==2 ? 0.5:numericT,numericV=mode==2 ? 1-numericT:mode==3 ? 0.75:numericT
            let expectedY=weighted && numericV>0.5 ? try f.dividing(f.subtracting(f.multiplying(f.integer(3,using:&a),v,using:&a),one,using:&a),f.multiplying(f.integer(2,using:&a),v,using:&a),using:&a):v
            let numericY=weighted && numericV>0.5 ? (3*numericV-1)/(2*numericV):numericV
            let expectedZ=numericU*(1-numericU)*DerivativeHostShape.expected(numericV,weighted:weighted,projected:projected)
            let expectedSides=(numericU==0.5 ? 2:1)*(numericV==0.5 ? 2:1)*(mode==0 && numericT==0.5 ? 2:1)
            try require(found.count==expectedSides)
            for member in found {
                let g=member.graph,r=g.polynomials,denominator=try r.evaluated(g.homogeneous[3],at:tuple,using:&a).value
                for (axis,target) in [u,expectedY,try f.binary64(exactly:expectedZ,using:&a)].enumerated() {
                    let actual=try f.dividing(r.evaluated(g.homogeneous[axis],at:tuple,using:&a).value,denominator,using:&a)
                    try require(f.compare(actual,target,using:&a) == .equal)
                }
            }
            let actual=try input.point(atNormalizedFraction:numericT,tolerance:.standard)
            try require(abs(actual.x-numericU)<1e-9 && abs(actual.y-numericY)<1e-9 && abs(actual.z-expectedZ)<1e-9)
        }
        let tuple=[half,half,mode==3 ? try f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a):half]
        let count=try full.liftedPositionIncidents(at:tuple,limits:l,using:&a).count
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a),twoThirds=try f.adding(third,third,using:&a)
        func selected(_ ranges: [RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar>]) throws -> RetainedHostAdapters.OriginalRetainedSurfaceLiftDomainCover<S> {
            try issuer.issue(request:frame.selection(intervals:[ranges],limits:l,using:&a),family:family,limits:l,using:&a)
        }
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,closed: Bool=true) throws -> RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:.init(value:32,coefficient:32),using:&a)
        }
        let strict=try selected([interval(third,twoThirds,closed:false)])
        try require(strict.liftedPositionIncidents(at:tuple,limits:l,using:&a).count==count)
        var boundary=tuple;boundary[0]=third
        try require(strict.liftedPositionIncidents(at:boundary,limits:l,using:&a).isEmpty)
        let singleton=try selected([interval(half,half)])
        try require(singleton.liftedPositionIncidents(at:tuple,limits:l,using:&a).count==count)
        let disconnected=try selected([interval(zero,third),interval(twoThirds,one)])
        try require(disconnected.liftedPositionIncidents(at:tuple,limits:l,using:&a).isEmpty)
        let empty=try selected([]);try require(empty.liftedPositionIncidents(at:tuple,limits:l,using:&a).isEmpty)
        var wrong=tuple;wrong[1]=zero
        try require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        var measured=try Admission();_=try full.liftedPositionIncidents(at:tuple,limits:l,using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&exact)
        for (work,bytes,cancel) in [(measured.ledger.work-1,400_000_000,nil),(100_000_000,measured.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,measured.calls)] {
            var failed=try Admission(work:work,storage:bytes,cancelAt:cancel)
            do { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&failed);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
        }
    }
    static func main() { do { try run() } catch { print("FAIL derivative host uncaught failure");exit(1) } }
    nonisolated static func run() throws {
        try ActualNativePcurveRetainedHostProof.run()
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let provider=RetainedHostAdapters.OriginalPlaneDerivativeSurfaceSnapshotProvider(field:f,tolerance:.standard)
        var held: RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs<Native>?
        var retainedInput: SurfaceLiftCurve3D?
        for weighted in [false,true] { for projected in [false,true] {
            let original=try DerivativeHostShape.shape(weighted:weighted,projected:projected,using:&a)
            let surface=Surface3D.procedural(.originalPlaneDerivative(original))
            let binding=try host(provider,surface,using:&a)
            try require(binding.original.original==original && binding.sourceDepth==2)
            for mode in 0..<4 {
                let pcurve: SurfaceParameterCurve
                switch mode {
                case 0:pcurve = .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0.5),.init(x:1,y:1)]))
                case 1:pcurve = .affine(origin:.init(x:0,y:0),direction:.init(x:1,y:1),startParameter:0,endParameter:1)
                case 2:pcurve = .constantU(u:0.5,vStart:1,vEnd:0)
                default:pcurve = .constantV(v:0.75,uStart:0,uEnd:1)
                }
                let input=SurfaceLiftCurve3D(surface:surface,parameterCurve:pcurve)
                if mode==0 {
                    let family=try native(input,field:f,using:&a)
                    try require(family.graphs.count==8 && family.surfaceSource.original.original==original)
                    try check(family,input:input,mode:mode,weighted:weighted,projected:projected,using:&a)
                    held=family;retainedInput=input
                } else {
                    let family=try affine(input,field:f,using:&a)
                    try require(family.graphs.count==4 && family.surfaceSource.original.original==original)
                    try check(family,input:input,mode:mode,weighted:weighted,projected:projected,using:&a)
                }
            }
            var copied=original.construction.construction;copied.controlPoints[0][0] = .init(x:9,y:9,z:9)
            try require(binding.original.original.construction.construction.controlPoints[0][0] == .origin)
        } }
        print("PASS derivative actual host/lift/DI: weighted/projected constructors, Native/affine/constant/reversed pcurves, eight incidents, original XYZ/UV and all requests")
        guard let held else { throw ExactScalarFailure.invalidEvidence }
        do {
        guard let input=retainedInput else { throw ExactScalarFailure.invalidEvidence }
        var measured=try Admission(work:300_000_000,storage:1_073_741_824);_=try native(input,field:f,using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes);_=try native(input,field:f,using:&exact)
        for (work,bytes,cancel) in [(measured.ledger.work-1,1_073_741_824,nil),(300_000_000,measured.ledger.storageBytes-1,nil),(300_000_000,1_073_741_824,1),(300_000_000,1_073_741_824,measured.calls)] {
            var failed=try Admission(work:work,storage:bytes,cancelAt:cancel)
            try ActualRetainedHostLiftProof.scalarFailure { _=try native(input,field:f,using:&failed) }
        }
        var cancelled=try Admission();cancelled.ledger.cancel()
        try ActualRetainedHostLiftProof.scalarFailure { _=try native(input,field:f,using:&cancelled) }
        do { _=try provider.bindHost(input.surface,limits:.init(remainingSourceDepth:1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        do { _=try provider.bindHost(.plane(.init(origin:.origin,normal:.init(x:0,y:0,z:1))),limits:.init(remainingSourceDepth:2),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        }
        retainedInput=nil
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        var incidents=0
        for graph in held.graphs { if try graph.admits([half,half,half],limits:.init(remainingSourceDepth:3),using:&a) { incidents+=1 } }
        try require(incidents==8)
        try held.admitProof(limits:.init(remainingSourceDepth:3),using:&a)
        do { try held.admitProof(limits:.init(remainingSourceDepth:2),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        print("PASS derivative host resources/depth/cancel/lifetime: exact preparation/query ceilings, one-less, entry/final callback, COW and retained owners")
    }
}
