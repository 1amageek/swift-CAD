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

@main struct PolylineFieldFamilyProof {
    typealias Admission=PolylineLiftProof.Admission
    typealias F=OriginalExactScalarDomain
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        if !value { print("FAIL polyline field family line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func originals() -> [SurfaceParameterCurve] {
        [.polyline(PolylineLiftProof.points()),.polyline([.init(u:0,v:0),.init(u:0.5,v:1),.init(u:1,v:1)]),.polyline(PolylineLiftProof.points())]
    }
    nonisolated static func prepare<P: OriginalPolylinePcurveFamilyPreparing>(_ provider: P,
        _ input: [SurfaceParameterCurve],maximum: Int=3,using a: inout Admission) throws -> OriginalPreparedPolylinePcurves {
        try provider.prepare(input,maximumCurves:maximum,limits:.init(remainingSourceDepth:0),using:&a)
    }
    nonisolated static func detached() throws -> OriginalPreparedPolylinePcurves {
        var a=try Admission(),input=originals()
        let family=try prepare(DefaultOriginalPolylinePcurveFamilyPreparer(maximumValueDepth:32,maximumCoefficientDepth:32),input,using:&a)
        input[0] = .polyline([.init(u:99,v:99),.init(u:100,v:100)])
        return family
    }
    nonisolated static func check(_ family: OriginalPreparedPolylinePcurves,using a: inout Admission) throws {
        let f=family.field,zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        try require(family.sources.count==3 && family.sources[0].owner !== family.sources[2].owner)
        for (index,source) in family.sources.enumerated() {
            let p=source.original;try require(source.sourceDepth==0 && p.original==originals()[index])
            let station=try f.importing(p.originalCellUpperBound(at:0),using:&a)
            let squared=try f.multiplying(station,station,using:&a)
            let equation=index==1 ? try f.adding(f.subtracting(f.multiplying(f.integer(4,using:&a),squared,using:&a),f.multiplying(f.integer(10,using:&a),station,using:&a),using:&a),f.integer(5,using:&a),using:&a):try f.subtracting(f.adding(squared,f.multiplying(f.integer(2,using:&a),station,using:&a),using:&a),one,using:&a)
            try require(f.sign(of:equation,using:&a) == .zero)
            let half=try f.binary64(exactly:0.5,using:&a)
            try require(f.compare(station,index==1 ? half:zero,using:&a) == .greater)
            try require(f.compare(station,index==1 ? one:half,using:&a) == .less)
            let ring=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
            for cell in 0..<p.originalCellCount {
                let at=try f.importing(p.originalCellLowerBound(at:cell),using:&a)
                let law=p.originalCellHomogeneous(at:cell),originalIndex=p.originalPointIndex(at:cell)
                guard case .polyline(let points)=p.original else { throw ExactScalarFailure.invalidEvidence }
                for axis in 0..<2 {
                    let mapped=try ring.importing(law[axis],using:&a)
                    let value=try ring.evaluated(mapped,at:[at],using:&a).value
                    let expected=try f.binary64(exactly:axis==0 ? points[originalIndex].u:points[originalIndex].v,using:&a)
                    try require(f.compare(value,expected,using:&a) == .equal)
                }
            }
            let l=try PolylineLiftProof.limits(),c=try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalPolylinePcurveSnapshot>().prepare(source:source,maximumCharts:3,limits:l.source,using:&a)
            try require(c.laws.count==(index==1 ? 2:3))
            let nativeInput=PolylineLiftProof.shape(points:index==1 ? [.init(u:0,v:0),.init(u:0.5,v:1),.init(u:1,v:1)]:PolylineLiftProof.points())
            let native=try DefaultOriginalSourceBindingIssuer(provider:OriginalPolylineSurfaceLiftSnapshotProvider(pcurve:source,tolerance:.standard)).bind(nativeInput,limits:l.source,using:&a)
            let h=try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:native.original.originalSurface,field:f,maximumCharts:4,limits:l.source,using:&a)
            let graphs=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<OriginalPolylineSurfaceLiftSnapshot>().prepare(source:native,surface:h,pcurve:c,maximumCharts:12,limits:l.source,using:&a)
            try lift(graphs,station:station,v:index==1 ? one:half,z:f.adding(half,index==1 ? one:half,using:&a),expectedSides:index==1 ? 4:8,using:&a)
            let hosts=try PolylineAtlasLiftProof.shape(multi:true,using:&a)
            let coons=try PolylineAtlasLiftProof.prepared(OriginalCoonsAtlasSnapshotProvider(field:f,tolerance:.standard),input:.init(surface:.procedural(.originalCoons(hosts.0)),parameterCurve:p.original),pcurve:source,using:&a)
            try lift(coons,station:station,v:index==1 ? one:half,z:zero,expectedSides:index==1 ? 4:8,using:&a)
            let corrected=try PolylineAtlasLiftProof.prepared(OriginalBoundaryCorrectionSnapshotProvider(field:f,tolerance:.standard),input:.init(surface:.procedural(.originalBoundaryCorrected(hosts.1)),parameterCurve:p.original),pcurve:source,using:&a)
            try lift(corrected,station:station,v:index==1 ? one:half,z:zero,expectedSides:index==1 ? 4:8,using:&a)
        }
        // The earlier field cannot silently import a later independent root.
        do { _=try family.sources[0].original.originalField.importing(family.sources[1].original.originalCellUpperBound(at:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        let linear=SurfaceParameterCurve.polyline([.init(u:0,v:0),.init(u:1,v:0)])
        let provider=OriginalPolylinePcurveSnapshotProvider(field:f)
        let seeded=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(linear,limits:.init(remainingSourceDepth:0),using:&a)
        let inheritedStation=family.sources[0].original.originalCellUpperBound(at:0)
        try require(f.compare(seeded.original.originalField.importing(inheritedStation,using:&a),f.importing(inheritedStation,using:&a),using:&a) == .equal)
        try require(f.originalDepth.coefficient>0)
        var shallow=try Admission(coefficient:f.originalDepth.coefficient-1)
        do { _=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(linear,limits:.init(remainingSourceDepth:0),using:&shallow);throw ExactScalarFailure.invalidEvidence }
        catch let e as OriginalSourceIssuanceFailure { guard case .resourceLimit(.coefficientDepth)=try PolylineLiftProof.scalarCause(e) else { throw e } }
        let unrelated=try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        do { _=try unrelated.importing(family.sources[0].original.originalCellUpperBound(at:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        print("PASS distinct sqrt2/sqrt5 original stations, ordered owners, ancestor imports and backward/foreign refusal")
        print("PASS all shared-field Native/Coons/correction lift chart products, original T/UV, exact domains and detached lifetime")
    }
    nonisolated static func lift<S: OriginalLiftGraphSourceReading>(_ family: OriginalFiniteRetainedSurfaceLiftGraphs<S>,station: F.Value,v: F.Value,z: F.Value,expectedSides: Int,using a: inout Admission) throws {
        let f=family.field,l=try PolylineLiftProof.limits(),issuer=DefaultOriginalRetainedSurfaceLiftDomainIssuer<S>()
        let frame=try issuer.frame(family:family,limits:l,using:&a),full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let half=try f.binary64(exactly:0.5,using:&a),zero=try f.integer(0,using:&a)
        let tuple=[station,half,v],found=try full.liftedPositionIncidents(at:tuple,limits:l,using:&a)
        try require(family.graphs.count==4*family.pcurveLaws.count)
        try require(found.count==expectedSides)
        try require(full.liftedPositionIncidents(at:[station,zero,v],limits:l,using:&a).isEmpty)
        let interval=try ExactParameterInterval.checked(field:f,lower:.finite(station),upper:.finite(station),depth:family.proofDepth,using:&a)
        let selected=try issuer.issue(request:frame.selection(intervals:[[interval]],limits:l,using:&a),family:family,limits:l,using:&a)
        try require(selected.liftedPositionIncidents(at:tuple,limits:l,using:&a).count==expectedSides)
        for member in found {
            let g=member.graph,r=g.polynomials,d=try r.evaluated(g.homogeneous[3],at:tuple,using:&a).value
            for (axis,target) in [half,v,z].enumerated() {
                let x=try f.dividing(r.evaluated(g.homogeneous[axis],at:tuple,using:&a).value,d,using:&a)
                try require(f.compare(x,target,using:&a) == .equal)
            }
        }
    }
    nonisolated static func resources() throws {
        let p=DefaultOriginalPolylinePcurveFamilyPreparer(maximumValueDepth:32,maximumCoefficientDepth:32),input=originals()
        var measured=try Admission();_=try prepare(p,input,using:&measured)
        var exact=try Admission(work:measured.ledger.work,bytes:measured.ledger.storageBytes);_=try prepare(p,input,using:&exact)
        for kind in 0..<2 {
            var low=try Admission(work:kind==0 ? measured.ledger.work-1:300_000_000,bytes:kind==1 ? measured.ledger.storageBytes-1:1_073_741_824)
            do { _=try prepare(p,input,using:&low);throw ExactScalarFailure.invalidEvidence }
            catch let e as OriginalSourceIssuanceFailure { guard case .resourceLimit(let r)=try PolylineLiftProof.scalarCause(e) else { throw e };try require(r == (kind==0 ? .work:.storage)) }
        }
        for tick in [1,measured.checkpoints/2,measured.checkpoints] {
            var cancel=try Admission(cancelAt:tick)
            do { _=try prepare(p,input,using:&cancel);throw ExactScalarFailure.invalidEvidence }
            catch let e as OriginalSourceIssuanceFailure { guard case .cancelled=try PolylineLiftProof.scalarCause(e) else { throw e } }
        }
        var a=try Admission()
        do { _=try prepare(p,input,maximum:2,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        do { _=try prepare(DefaultOriginalPolylinePcurveFamilyPreparer(maximumValueDepth:32,maximumCoefficientDepth:0),input,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch let e as OriginalSourceIssuanceFailure { guard case .resourceLimit(.coefficientDepth)=try PolylineLiftProof.scalarCause(e) else { throw e } }
        do { _=try prepare(p,[input[0],.polyline([.init(u:0,v:0)])],using:&a);throw ExactScalarFailure.invalidEvidence }
        catch let e as OriginalSourceIssuanceFailure {
            guard case .admissionRejected(let cause)=try PolylineLiftProof.scalarCause(e),
                let rejected=cause as? KernelError else { throw e }
            try require(rejected.phase == .geometry && rejected.code == .intersectionFailure)
        }
        var empty=try Admission();try require(prepare(p,[],maximum:0,using:&empty).sources.isEmpty)
        var final=try Admission(cancelAt:empty.checkpoints)
        do { _=try prepare(p,[],maximum:0,using:&final);throw ExactScalarFailure.invalidEvidence }
        catch let e as OriginalSourceIssuanceFailure { guard case .cancelled=try PolylineLiftProof.scalarCause(e) else { throw e } }
        print("PASS shared preparation exact count/work/bytes/depth, entry/mid/final/empty cancel and atomic invalid-child refusal")
    }
    static func main() {
        do {
            let family=try detached();var a=try Admission();try check(family,using:&a);try resources()
            try PolylineAtlasLiftProof.run()
        } catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL shared polyline coefficient family");exit(1)
        }
    }
}
