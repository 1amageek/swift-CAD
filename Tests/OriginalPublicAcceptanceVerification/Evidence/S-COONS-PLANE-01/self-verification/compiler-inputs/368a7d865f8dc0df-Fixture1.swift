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

struct PolylineAtlasLiftProof {
    typealias Admission=PolylineLiftProof.Admission
    typealias F=OriginalExactScalarDomain
    nonisolated static func require(_ condition: Bool,line: Int = #line) throws {
        if !condition { print("FAIL atlas polyline line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func shape(multi: Bool,using a: inout Admission) throws -> (OriginalCoonsSurface3D,OriginalBoundaryCorrectedSurface3D) {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let t=multi ? [0.0,0.5,1.0]:[0.0,1.0],knots=multi ? [0.0,0,0.5,1,1]:[0.0,0,1,1]
            let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:knots,vKnots:knots,
                controlPoints:t.map { v in t.map { u in .init(x:u,y:v,z:0) } })
            let issuer=OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ b: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of:.bSpline(native),at:b,maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
            }
            let lower: OriginalCurveRootSpan3D
            if multi { lower=try boundary(.vLower) }
            else {
                lower=try .init(source:.bSpline(.init(degree:2,knots:[0,0,0,1,1,1],
                    controlPoints:[.origin,.init(x:0.5,y:0,z:0.25),.init(x:1,y:0,z:0)])),start:.authored(0),end:.authored(1),
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:1,remainingSourceDepth:0,maximumAlgebraicDepth:0)
            }
            let coons=try OriginalCoonsSurface3D(vMinimumBoundary:lower,vMaximumBoundary:boundary(.vUpper),
                uMinimumBoundary:boundary(.uLower),uMaximumBoundary:boundary(.uUpper),tolerance:.standard,usage:&usage)
            let correction=try OriginalBoundaryCorrectedSurface3D(construction:native,boundaries:coons,
                maximumSpanCount:4,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage)
            return (coons,correction)
        }.value
    }
    nonisolated static func prepared<P: OriginalRetainedLiftHostSnapshotting>(_ host: P,
        input: SurfaceLiftCurve3D,pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>,using a: inout Admission)
        throws -> OriginalFiniteRetainedSurfaceLiftGraphs<OriginalPolylineRetainedAtlasLiftSnapshot<P.Source>> {
        typealias S=OriginalPolylineRetainedAtlasLiftSnapshot<P.Source>
        let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let s=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineRetainedAtlasLiftSnapshotProvider(host:host,pcurve:pcurve))
            .bind(input,limits:l,using:&a)
        try require(s.original.originalPcurve.owner === pcurve.owner)
        let surface=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<P.Source>().prepare(source:s.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        let curve=try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalPolylinePcurveSnapshot>().prepare(source:pcurve,maximumCharts:3,limits:l,using:&a)
        return try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S>().prepare(source:s,surface:surface,pcurve:curve,maximumCharts:12,limits:l,using:&a)
    }
    nonisolated static func check<H>(_ family: OriginalFiniteRetainedSurfaceLiftGraphs<OriginalPolylineRetainedAtlasLiftSnapshot<H>>,
        multi: Bool,corrected: Bool=false,using a: inout Admission) throws {
        typealias S=OriginalPolylineRetainedAtlasLiftSnapshot<H>
        let l=try PolylineLiftProof.limits(),f=family.field,p=family.pcurveSource.original
        try require(family.graphs.count==(multi ? 12:3))
        let issuer=DefaultOriginalRetainedSurfaceLiftDomainIssuer<S>(),frame=try issuer.frame(family:family,limits:l,using:&a)
        let cover=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let station=p.originalCellUpperBound(at:0),half=try f.binary64(exactly:0.5,using:&a)
        let tuple=[station,half,half],found=try cover.liftedPositionIncidents(at:tuple,limits:l,using:&a)
        try require(found.count==(multi ? 8:2))
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        for member in found {
            let g=member.graph,r=g.polynomials,denominator=try r.evaluated(g.homogeneous[3],at:tuple,using:&a).value
            let z=multi ? zero:try f.dividing(one,f.integer(16,using:&a),using:&a)
            for (axis,target) in [half,half,z].enumerated() {
                let actual=try f.dividing(r.evaluated(g.homogeneous[axis],at:tuple,using:&a).value,denominator,using:&a)
                try require(f.compare(actual,target,using:&a) == .equal)
            }
            try require(g.layout.parameters==[0] && g.layout.auxiliaries==[1,2])
        }
        try require(cover.liftedPositionIncidents(at:[station,half,zero],limits:l,using:&a).isEmpty)
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let exact=try f.binary64(exactly:t,using:&a),ring=p.originalPolynomials
            var visited=false
            for index in 0..<p.originalCellCount {
                if try f.compare(exact,p.originalCellLowerBound(at:index),using:&a) == .less { continue }
                if try f.compare(exact,p.originalCellUpperBound(at:index),using:&a) == .greater { continue }
                let h=p.originalCellHomogeneous(at:index)
                let u=try ring.evaluated(h[0],at:[exact],using:&a).value,v=try ring.evaluated(h[1],at:[exact],using:&a).value
                let all=try cover.liftedPositionIncidents(at:[exact,u,v],limits:l,using:&a);try require(!all.isEmpty);visited=true
                let g=all[0].graph,r=g.polynomials,d=try r.evaluated(g.homogeneous[3],at:[exact,u,v],using:&a).value
                var blend=v
                if corrected {
                    let v2=try f.multiplying(v,v,using:&a),v3=try f.multiplying(v2,v,using:&a)
                    let v4=try f.multiplying(v3,v,using:&a),v5=try f.multiplying(v4,v,using:&a)
                    blend=try f.adding(f.subtracting(f.multiplying(f.integer(10,using:&a),v3,using:&a),f.multiplying(f.integer(15,using:&a),v4,using:&a),using:&a),f.multiplying(f.integer(6,using:&a),v5,using:&a),using:&a)
                }
                let z=multi ? zero:try f.dividing(f.multiplying(f.multiplying(u,f.subtracting(one,u,using:&a),using:&a),f.subtracting(one,blend,using:&a),using:&a),f.integer(2,using:&a),using:&a)
                let numeric=try family.source.original.original.point(atNormalizedFraction:t,tolerance:.standard)
                for (axis,target) in [u,v,z].enumerated() {
                    let actual=try f.dividing(r.evaluated(g.homogeneous[axis],at:[exact,u,v],using:&a).value,d,using:&a)
                    try require(f.compare(actual,target,using:&a) == .equal)
                    let enclosure=try ExactScalarNumericAccess.withAdmission(&a,inherited:actual.depth) { usage in
                        try actual.original.enclosure(maximumDepth:32,usage:&usage)
                    }.value
                    let value=axis==0 ? numeric.x:axis==1 ? numeric.y:numeric.z
                    try require(value>=enclosure.lower-1e-9 && value<=enclosure.upper+1e-9)
                }
            }
            try require(visited)
        }
        for kind in 0..<4 {
            let ranges: [ExactParameterInterval<F.Value>]
            if kind==0 { ranges=[try .checked(field:f,lower:.finite(station),upper:.finite(station),depth:p.originalProofDepth,using:&a)] }
            else if kind==1 { ranges=[try .checked(field:f,lower:.finite(station),upper:.finite(one),includesLower:false,includesUpper:false,depth:p.originalProofDepth,using:&a)] }
            else if kind==2 { ranges=[try .checked(field:f,lower:.finite(zero),upper:.finite(station),depth:p.originalProofDepth,using:&a),try .checked(field:f,lower:.finite(p.originalCellUpperBound(at:1)),upper:.finite(one),depth:p.originalProofDepth,using:&a)] }
            else { ranges=[] }
            let selected=try issuer.issue(request:frame.selection(intervals:[ranges],limits:l,using:&a),family:family,limits:l,using:&a)
            try require(selected.liftedPositionIncidents(at:tuple,limits:l,using:&a).count == (kind==0 || kind==2 ? (multi ? 8:2):0))
        }
    }
    nonisolated static func resources() throws {
        var a=try Admission();let host=try shape(multi:true,using:&a).0,curve=SurfaceParameterCurve.polyline(PolylineLiftProof.points())
        let p=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32)).bind(curve,limits:.init(remainingSourceDepth:8),using:&a)
        let f=p.original.originalField,input=SurfaceLiftCurve3D(surface:.procedural(.originalCoons(host)),parameterCurve:curve)
        let provider=DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineRetainedAtlasLiftSnapshotProvider(host:OriginalCoonsAtlasSnapshotProvider(field:f,tolerance:.standard),pcurve:p))
        let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        var measured=try Admission();let source=try provider.bind(input,limits:l,using:&measured)
        var exact=try Admission(work:measured.ledger.work,bytes:measured.ledger.storageBytes);_=try provider.bind(input,limits:l,using:&exact)
        for kind in 0..<2 {
            var low=try Admission(work:kind==0 ? measured.ledger.work-1:300_000_000,bytes:kind==1 ? measured.ledger.storageBytes-1:1_073_741_824)
            do { _=try provider.bind(input,limits:l,using:&low);throw ExactScalarFailure.invalidEvidence }
            catch let e as OriginalSourceIssuanceFailure { guard case .resourceLimit(let r)=try PolylineLiftProof.scalarCause(e) else { throw e };try require(r == (kind==0 ? .work:.storage)) }
        }
        for tick in [1,measured.checkpoints/2,measured.checkpoints] {
            var cancelled=try Admission(cancelAt:tick)
            do { _=try provider.bind(input,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
            catch let e as OriginalSourceIssuanceFailure { guard case .cancelled=try PolylineLiftProof.scalarCause(e) else { throw e } }
        }
        do { _=try provider.bind(input,limits:.init(remainingSourceDepth:source.sourceDepth-1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var shallow=try Admission(coefficient:0)
        do { _=try provider.bind(input,limits:l,using:&shallow);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        var changed=PolylineLiftProof.points();changed[2].u=0.5000000000000001
        do { _=try provider.bind(.init(surface:input.surface,parameterCurve:.polyline(changed)),limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        let outsideCurve=SurfaceParameterCurve.polyline([.init(u:0,v:-Double.leastNonzeroMagnitude),.init(u:1,v:0.5)])
        let outside=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32)).bind(outsideCurve,limits:l,using:&a)
        let outsideProvider=DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineRetainedAtlasLiftSnapshotProvider(host:OriginalCoonsAtlasSnapshotProvider(field:f,tolerance:.standard),pcurve:outside))
        do { _=try outsideProvider.bind(.init(surface:input.surface,parameterCurve:outsideCurve),limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let priority=SurfaceLiftCurve3D(surface:input.surface,parameterCurve:curve,exactBSplineImage:.init(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:1,z:1)]))
        do { _=try provider.bind(priority,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        typealias S=OriginalPolylineRetainedAtlasLiftSnapshot<OriginalCoonsAtlasSnapshot>
        let preparer=DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S>()
        let surface=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalCoonsAtlasSnapshot>().prepare(source:source.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        let charts=try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalPolylinePcurveSnapshot>().prepare(source:p,maximumCharts:3,limits:l,using:&a)
        do { _=try preparer.prepare(source:source,surface:surface,pcurve:charts,maximumCharts:11,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        let other=try provider.bind(input,limits:l,using:&a)
        let wrongOwner=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalCoonsAtlasSnapshot>().prepare(source:other.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        do { _=try preparer.prepare(source:source,surface:wrongOwner,pcurve:charts,maximumCharts:12,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        let foreign=try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let wrongField=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineRetainedAtlasLiftSnapshotProvider(host:OriginalCoonsAtlasSnapshotProvider(field:foreign,tolerance:.standard),pcurve:p)).bind(input,limits:l,using:&a)
        let wrongSurface=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalCoonsAtlasSnapshot>().prepare(source:wrongField.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        do { _=try preparer.prepare(source:wrongField,surface:wrongSurface,pcurve:charts,maximumCharts:12,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch let e as OriginalSourceIssuanceFailure { guard case .incompatibleDomain=try PolylineLiftProof.scalarCause(e) else { throw e } }
        print("PASS prepared atlas source exact work/bytes/depth/cancel and foreign/support/priority refusal")
    }
    nonisolated static func run() throws {
        for multi in [true,false] {
            var a=try Admission();let hosts=try shape(multi:multi,using:&a),curve=SurfaceParameterCurve.polyline(PolylineLiftProof.points())
            let p=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32)).bind(curve,limits:.init(remainingSourceDepth:8),using:&a)
            let f=p.original.originalField
            var input=SurfaceLiftCurve3D(surface:.procedural(.originalCoons(hosts.0)),parameterCurve:curve)
            let coons=try prepared(OriginalCoonsAtlasSnapshotProvider(field:f,tolerance:.standard),input:input,pcurve:p,using:&a)
            input=SurfaceLiftCurve3D(surface:.procedural(.originalBoundaryCorrected(hosts.1)),parameterCurve:curve)
            let correction=try prepared(OriginalBoundaryCorrectionSnapshotProvider(field:f,tolerance:.standard),input:input,pcurve:p,using:&a)
            input=PolylineLiftProof.shape(points:[.init(u:99,v:99),.init(u:100,v:100)])
            try check(coons,multi:multi,using:&a);try check(correction,multi:multi,corrected:true,using:&a)
        }
        print("PASS actual Coons/correction polyline lifts, irrational joins/all sides/exact XYZ/UV and public point")
        let detached=try detached()
        var independent=try Admission();try check(detached,multi:false,using:&independent)
        print("PASS detached atlas/polyline/source lifetime with independent query admission")
        try resources()
        try PolylineLiftProof.finite();try PolylineLiftProof.periodic()
    }
    nonisolated static func detached() throws -> OriginalFiniteRetainedSurfaceLiftGraphs<OriginalPolylineRetainedAtlasLiftSnapshot<OriginalCoonsAtlasSnapshot>> {
        var a=try Admission();let host=try shape(multi:false,using:&a).0,curve=SurfaceParameterCurve.polyline(PolylineLiftProof.points())
        let p=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylinePcurveSnapshotProvider(maximumValueDepth:32,maximumCoefficientDepth:32)).bind(curve,limits:.init(remainingSourceDepth:8),using:&a)
        return try prepared(OriginalCoonsAtlasSnapshotProvider(field:p.original.originalField,tolerance:.standard),input:.init(surface:.procedural(.originalCoons(host)),parameterCurve:curve),pcurve:p,using:&a)
    }
    static func main() {
        do { try run() }
        catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL prepared polyline retained-atlas lift");exit(1)
        }
    }
}
