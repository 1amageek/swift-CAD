#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters

@main struct PolylineLiftProof {
    typealias S=OriginalPolylineSurfaceLiftSnapshot
    typealias F=OriginalExactScalarDomain
    typealias Family=OriginalFiniteRetainedSurfaceLiftGraphs<S>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints=0
        let cancelAt: Int?
        init(work: Int=300_000_000,bytes: Int=1_073_741_824,coefficient: Int=32,cancelAt: Int?=nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:coefficient));self.cancelAt=cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints==cancelAt { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Failure: Error { let line: Int }
    nonisolated static func require(_ condition: Bool,line: Int = #line) throws { if !condition { throw Failure(line:line) } }
    nonisolated static func scalarCause(_ failure: OriginalSourceIssuanceFailure) throws -> ExactScalarFailure {
        switch failure { case .scalar(let e),.polynomial(.scalar(let e)):return e;default:throw failure }
    }
    nonisolated static func points(periodic: Bool=false) -> [SurfaceParameter] {
        let h=periodic ? 3.0:0.5
        return [.init(u:0,v:0),.init(u:0,v:0),.init(u:h,v:h),.init(u:2*h,v:h),.init(u:h,v:h)]
    }
    nonisolated static func shape(periodic: Bool=false,points: [SurfaceParameter]?=nil) -> SurfaceLiftCurve3D {
        let host: BSplineSurface3D
        if periodic {
            let xy=[[0.0,0.0],[1,0],[0,1],[0,0]]
            host = .init(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:[-1,0,1,2,3,4],
                controlPoints:xy.map { v in xy.map { u in .init(x:u[0],y:u[1]+v[0],z:v[1]) } },isUPeriodic:true,isVPeriodic:true)
        } else {
            let t=[0.0,0.5,1.0]
            host = .init(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
                controlPoints:t.map { v in t.map { u in .init(x:u,y:v,z:u+v) } },weights:[[1,2,1],[2,4,2],[1,2,1]])
        }
        return .init(surface:.bSpline(host),parameterCurve:.polyline(points ?? self.points(periodic:periodic)))
    }
    nonisolated static func bind(_ shape: SurfaceLiftCurve3D,using a: inout Admission) throws -> OriginalSourceBinding<S> {
        let sl=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let p=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32))
            .bind(shape.parameterCurve,limits:sl,using:&a)
        let s=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineSurfaceLiftSnapshotProvider(pcurve:p,tolerance:.standard))
            .bind(shape,limits:sl,using:&a)
        try require(s.original.originalPcurve.owner === p.owner)
        return s
    }
    nonisolated static func family(_ original: SurfaceLiftCurve3D,using a: inout Admission) throws -> Family {
        let s=try bind(original,using:&a),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let f=s.original.originalPcurve.original.originalField
        let host=try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:s.original.originalSurface,field:f,maximumCharts:4,limits:l,using:&a)
        let p=try DefaultOriginalFiniteRetainedCurveChartPreparer<S.Pcurve>().prepare(source:s.original.originalPcurve,maximumCharts:3,limits:l,using:&a)
        return try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S>().prepare(source:s,surface:host,pcurve:p,maximumCharts:12,limits:l,using:&a)
    }
    nonisolated static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:8),maximumTransportDepth:16,maximumCharts:32,maximumFamilies:2,maximumIdentityProofs:16)
    }
    nonisolated static func value<E: Sendable>(_ g: OriginalParametricGraphReceipt<S,F,E>,at tuple: [F.Value],using a: inout Admission) throws -> [F.Value] {
        let r=g.polynomials,f=g.field,d=try r.evaluated(g.homogeneous[3],at:tuple,using:&a).value
        return try g.homogeneous[0..<3].map { try f.dividing(r.evaluated($0,at:tuple,using:&a).value,d,using:&a) }
    }
    nonisolated static func finite() throws {
        var original=shape(),a=try Admission();let saved=try family(original,using:&a),l=try limits(),f=saved.field
        if case .bSpline(var changed)=original.surface {
            changed.controlPoints[0][0] = .init(x:99,y:99,z:99)
            original = .init(surface:.bSpline(changed),parameterCurve:.polyline([.init(u:99,v:99),.init(u:100,v:100)]))
        }
        try require(saved.graphs.count==12 && saved.pcurveSource.owner === saved.source.original.originalPcurve.owner)
        let issuer=DefaultOriginalRetainedSurfaceLiftDomainIssuer<S>(),frame=try issuer.frame(family:saved,limits:l,using:&a)
        let cover=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:saved,limits:l,using:&a)
        let p=saved.source.original.originalPcurve.original,station=p.originalCellUpperBound(at:0)
        let half=try f.binary64(exactly:0.5,using:&a),zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let tuple=[station,half,half]
        let found=try cover.liftedPositionIncidents(at:tuple,limits:l,using:&a)
        try require(found.count==8)
        for member in found {
            let xyz=try value(member.graph,at:tuple,using:&a)
            for (x,y) in zip(xyz,[half,half,one]) { try require(f.compare(x,y,using:&a) == .equal) }
            try require(member.graph.layout.parameters==[0] && member.graph.layout.auxiliaries==[1,2])
        }
        try require(cover.liftedPositionIncidents(at:[station,half,zero],limits:l,using:&a).isEmpty)
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let exactT=try f.binary64(exactly:t,using:&a),r=p.originalPolynomials
            var visited=false
            for i in 0..<p.originalCellCount {
                if try f.compare(exactT,p.originalCellLowerBound(at:i),using:&a) == .less { continue }
                if try f.compare(exactT,p.originalCellUpperBound(at:i),using:&a) == .greater { continue }
                let h=p.originalCellHomogeneous(at:i)
                let uv=try [r.evaluated(h[0],at:[exactT],using:&a).value,r.evaluated(h[1],at:[exactT],using:&a).value]
                let incident=try cover.liftedPositionIncidents(at:[exactT]+uv,limits:l,using:&a)
                try require(!incident.isEmpty);visited=true
                let actual=try saved.source.original.original.point(atNormalizedFraction:t,tolerance:.standard)
                let xyz=try value(incident[0].graph,at:[exactT]+uv,using:&a)
                for (x,y) in zip(xyz,[actual.x,actual.y,actual.z]) {
                    let bound=try ExactScalarNumericAccess.withAdmission(&a,inherited:x.depth) { usage in try x.original.enclosure(maximumDepth:32,usage:&usage) }.value
                    try require(y>=bound.lower-1e-12 && y<=bound.upper+1e-12)
                }
            }
            try require(visited)
        }
        for kind in 0..<4 {
            let intervals:[ExactParameterInterval<F.Value>]
            if kind==0 { intervals=[try .checked(field:f,lower:.finite(station),upper:.finite(station),depth:p.originalProofDepth,using:&a)] }
            else if kind==1 { intervals=[try .checked(field:f,lower:.finite(station),upper:.finite(one),includesLower:false,includesUpper:false,depth:p.originalProofDepth,using:&a)] }
            else if kind==2 { intervals=[try .checked(field:f,lower:.finite(zero),upper:.finite(station),depth:p.originalProofDepth,using:&a),try .checked(field:f,lower:.finite(p.originalCellUpperBound(at:1)),upper:.finite(one),depth:p.originalProofDepth,using:&a)] }
            else { intervals=[] }
            let selected=try issuer.issue(request:frame.selection(intervals:[intervals],limits:l,using:&a),family:saved,limits:l,using:&a)
            try require(selected.liftedPositionIncidents(at:tuple,limits:l,using:&a).count == (kind==0 || kind==2 ? 8:0))
        }
        print("PASS finite prepared polyline lift, all twelve pairs/eight join sides, exact T/UV and public point/COW/lifetime")
    }
    nonisolated static func periodic(_ original: SurfaceLiftCurve3D?=nil,huge: Bool=false) throws {
        var a=try Admission();let s=try bind(original ?? shape(periodic:true),using:&a),l=try limits(),f=s.original.originalPcurve.original.originalField
        let host=try DefaultOriginalBSplineFundamentalChartPreparer<BSplineSurface3D>().prepare(source:s.original.originalSurface,field:f,maximumCharts:9,limits:l.source,using:&a)
        let p=try DefaultOriginalFiniteRetainedCurveChartPreparer<S.Pcurve>().prepare(source:s.original.originalPcurve,maximumCharts:3,limits:l.source,using:&a)
        let family=try DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<S>().prepare(source:s,surface:host,pcurve:p,maximumCharts:27,limits:l.source,using:&a)
        let issuer=DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S>(),space=try issuer.prepare(family:family,limits:l,using:&a)
        let cover=try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let station=s.original.originalPcurve.original.originalCellUpperBound(at:0)
        let u=try f.binary64(exactly:huge ? 3*Double(sign:.plus,exponent:96,significand:1):3,using:&a)
        let v=try f.binary64(exactly:huge ? 1:3,using:&a),tuple=[station,u,v]
        let found=try cover.liftedPositionIncidents(at:tuple,limits:l,using:&a)
        try require(found.count==8)
        let q=ExactRationalScalarDomain(),zero=try q.integer(0,using:&a)
        for occurrence in found {
            try require(occurrence.relation.graph.admits(tuple,limits:l.source,using:&a))
            if huge { try require(q.compare(occurrence.cycles[0].original,zero,using:&a) == .greater) }
        }
        let wrong=[station,try f.adding(u,f.integer(1,using:&a),using:&a),v]
        try require(cover.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        if !huge {
            let actual=try s.original.original.point(atNormalizedFraction:1,tolerance:.standard)
            try require(actual.x==0 && actual.y==0 && actual.z==0)
            print("PASS periodic prepared polyline lift, independent cycles and all eight seam/join incidents")
        } else { print("PASS arbitrary-size original UV cycles without a finite window") }
    }
    nonisolated static func resources() throws {
        var a=try Admission();let original=shape(),s=try bind(original,using:&a),p=s.original.originalPcurve
        let provider=DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineSurfaceLiftSnapshotProvider(pcurve:p,tolerance:.standard)),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        var measured=try Admission();_=try provider.bind(original,limits:l,using:&measured)
        var exact=try Admission(work:measured.ledger.work,bytes:measured.ledger.storageBytes)
        _=try provider.bind(original,limits:l,using:&exact)
        for kind in 0..<2 {
            var low=try Admission(work:kind==0 ? measured.ledger.work-1:300_000_000,bytes:kind==1 ? measured.ledger.storageBytes-1:1_073_741_824)
            do { _=try provider.bind(original,limits:l,using:&low);throw Failure(line:#line) }
            catch let e as OriginalSourceIssuanceFailure {
                guard case .resourceLimit(let r)=try scalarCause(e) else { throw e };try require(r == (kind==0 ? .work:.storage))
            }
        }
        for tick in [1,max(1,measured.checkpoints/2),measured.checkpoints] {
            var cancelled=try Admission(cancelAt:tick)
            do { _=try provider.bind(original,limits:l,using:&cancelled);throw Failure(line:#line) }
            catch let e as OriginalSourceIssuanceFailure { guard case .cancelled=try scalarCause(e) else { throw e } }
        }
        do { _=try provider.bind(original,limits:.init(remainingSourceDepth:0),using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var depth=try Admission(coefficient:0)
        do { _=try provider.bind(original,limits:l,using:&depth);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        var changed=points();changed[2].u=0.5000000000000001
        do { _=try provider.bind(shape(points:changed),limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        let outside=shape(points:[.init(u:0,v:-Double.leastNonzeroMagnitude),.init(u:1,v:0.5)])
        do { _=try bind(outside,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let priority=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:original.parameterCurve,
            exactBSplineImage:.init(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:1,z:1)]))
        do { _=try provider.bind(priority,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let f=p.original.originalField
        let curve=try DefaultOriginalFiniteRetainedCurveChartPreparer<S.Pcurve>().prepare(source:p,maximumCharts:3,limits:l,using:&a)
        let foreignField=try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let wrongFieldHost=try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:s.original.originalSurface,field:foreignField,maximumCharts:4,limits:l,using:&a)
        do {
            _=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S>().prepare(source:s,surface:wrongFieldHost,pcurve:curve,maximumCharts:12,limits:l,using:&a)
            throw Failure(line:#line)
        } catch let e as OriginalSourceIssuanceFailure { guard case .incompatibleDomain=try scalarCause(e) else { throw e } }
        let other=try bind(original,using:&a)
        let wrongOwnerHost=try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:other.original.originalSurface,field:f,maximumCharts:4,limits:l,using:&a)
        do {
            _=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S>().prepare(source:s,surface:wrongOwnerHost,pcurve:curve,maximumCharts:12,limits:l,using:&a)
            throw Failure(line:#line)
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        let host=try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:s.original.originalSurface,field:f,maximumCharts:4,limits:l,using:&a)
        do {
            _=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S>().prepare(source:s,surface:host,pcurve:curve,maximumCharts:11,limits:l,using:&a)
            throw Failure(line:#line)
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        print("PASS prepared-owner reuse, exact source work/bytes/depth/cancel and foreign/support/priority refusal")
    }
    static func main() {
        do {
            try finite();try periodic();try resources()
            let giant=3*Double(sign:.plus,exponent:96,significand:1)
            try periodic(shape(periodic:true,points:[.init(u:giant,v:0),.init(u:giant,v:1),.init(u:giant,v:2)]),huge:true)
        } catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL prepared polyline Native lift");exit(1)
        }
    }
}
