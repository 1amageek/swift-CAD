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

@main struct ActualRetainedHostLiftProof {
    typealias Source = RetainedHostAdapters.OriginalRetainedAtlasSurfaceLiftSnapshot<RetainedHostAdapters.OriginalBoundaryCorrectionSnapshot>
    typealias Family = RetainedHostAdapters.OriginalFiniteRetainedSurfaceLiftGraphs<Source>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var calls=0
        let cancelAt: Int?
        init(work: Int=100_000_000,storage: Int=400_000_000,cancelAt: Int?=nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:storage,valueDepth:32,coefficientDepth:32));self.cancelAt=cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes);calls+=1;if calls==cancelAt { ledger.cancel() } }
        mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        if !value { print("FAIL actual retained host line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func shape(multi: Bool=true,using a: inout Admission) throws -> OriginalBoundaryCorrectedSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func span(_ points: [Point3D],degree: Int=1) throws -> OriginalCurveRootSpan3D {
                let knots=Array(repeating:0.0,count:degree+1)+Array(repeating:1.0,count:degree+1)
                return try .init(source:.bSpline(.init(degree:degree,knots:knots,controlPoints:points)),start:.authored(0),end:.authored(1),
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:1,remainingSourceDepth:0,maximumAlgebraicDepth:0)
            }
            let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],controlPoints:[
                [.origin,.init(x:0.5,y:0,z:0),.init(x:1,y:0,z:0)],
                [.init(x:0,y:0.5,z:0),.init(x:0.5,y:0.5,z:0),.init(x:1,y:0.5,z:0)],
                [.init(x:0,y:1,z:0),.init(x:0.5,y:1,z:0),.init(x:1,y:1,z:0)]])
            let single=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],controlPoints:[[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
            let construction=multi ? native:single,issuer=OriginalSurfaceBoundarySourceIssuer()
            func originalBoundary(_ boundary: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of:.bSpline(construction),at:boundary,maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
            }
            let boundaries=try OriginalCoonsSurface3D(vMinimumBoundary:multi ? originalBoundary(.vLower):span([.origin,.init(x:0.5,y:0,z:0.25),.init(x:1,y:0,z:0)],degree:2),
                vMaximumBoundary:originalBoundary(.vUpper),uMinimumBoundary:originalBoundary(.uLower),uMaximumBoundary:originalBoundary(.uUpper),tolerance:.standard,usage:&usage)
            return try .init(construction:construction,boundaries:boundaries,maximumSpanCount:4,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage)
        }.value
    }
    nonisolated static func family(_ input: SurfaceLiftCurve3D,field: OriginalExactScalarDomain,using a: inout Admission) throws -> Family {
        let l=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let provider=RetainedHostAdapters.OriginalRetainedAtlasSurfaceLiftSnapshotProvider(host:RetainedHostAdapters.OriginalBoundaryCorrectionSnapshotProvider(field:field,tolerance:.standard),field:field,tolerance:.standard)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:l,using:&a)
        try require(source.original.original==input)
        let h=try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceChartPreparer<RetainedHostAdapters.OriginalBoundaryCorrectionSnapshot>()
            .prepare(source:source.original.originalSurface,maximumCharts:4,limits:l,using:&a)
        let c=try RetainedHostAdapters.DefaultOriginalFiniteRetainedCurveChartPreparer<RetainedHostAdapters.OriginalAffinePcurveSnapshot>()
            .prepare(source:source.original.originalPcurve,maximumCharts:1,limits:l,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>()
            .prepare(source:source,surface:h,pcurve:c,maximumCharts:4,limits:l,using:&a)
    }
    nonisolated static func scalarFailure(_ body: () throws -> Void) throws {
        do { try body();throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.resourceLimit(_)) {}
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(_))) {}
    }
    static func main() { do { try run() } catch { print("FAIL actual retained host");exit(1) } }
    nonisolated static func run() throws {
        var a=try Admission();let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        print("CHECK constructing multi-cell host")
        let original=try shape(using:&a)
        print("CHECK multi-cell host constructed")
        let l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:8),maximumTransportDepth:16,maximumCharts:8,maximumFamilies:2,maximumIdentityProofs:8)
        let curves:[SurfaceParameterCurve]=[.constantV(v:0.5,uStart:0,uEnd:1),.constantV(v:0.5,uStart:1,uEnd:0),.constantU(u:0.5,vStart:0,vEnd:1),
            .affine(origin:.init(x:0,y:0),direction:.init(x:1,y:1),startParameter:0,endParameter:1)]
        var detached: Family?
        print("CHECK constructing correction host")
        let corrected=try shape(multi:false,using:&a)
        print("CHECK correction host constructed")
        for (host,multi) in [(original,true),(corrected,false)] {
        for (index,pcurve) in curves.enumerated() {
            let input=SurfaceLiftCurve3D(surface:.procedural(.originalBoundaryCorrected(host)),parameterCurve:pcurve)
            print("CHECK binding host")
            let family=try family(input,field:f,using:&a),issuer=RetainedHostAdapters.DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
            let frame=try issuer.frame(family:family,limits:l,using:&a)
            let cover=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
            for t in [0.0,0.25,0.5,0.75,1.0] {
                let u=index==1 ? 1-t:index==2 ? 0.5:t,v=(index==2 || index==3) ? t:0.5
                let tuple=[try f.binary64(exactly:t,using:&a),try f.binary64(exactly:u,using:&a),try f.binary64(exactly:v,using:&a)]
                let found=try cover.liftedPositionIncidents(at:tuple,limits:l,using:&a)
                try require(found.count==(multi ? ((u==0.5 ? 2:1)*(v==0.5 ? 2:1)):1))
                let expected=try input.point(atNormalizedFraction:t,tolerance:.standard)
                for member in found {
                    let r=member.graph.polynomials,g=member.graph
                    let d=try r.evaluated(g.homogeneous[3],at:tuple,using:&a).value
                    for axis in 0..<3 {
                        let actual=try f.dividing(r.evaluated(g.homogeneous[axis],at:tuple,using:&a).value,d,using:&a)
                        // Exact source equality is checked against the independent original
                        // correction law. The public interval-midpoint evaluator is numerical.
                        let h=10*v*v*v-15*v*v*v*v+6*v*v*v*v*v
                        let sourceZ=multi ? 0:0.5*u*(1-u)*(1-h)
                        let target=axis==0 ? u:axis==1 ? v:sourceZ
                        try require(f.compare(actual,f.binary64(exactly:target,using:&a),using:&a) == .equal)
                        let numeric=axis==0 ? expected.x:axis==1 ? expected.y:expected.z
                        try require(abs(numeric-target)<=ModelingTolerance.standard.distance)
                    }
                }
            }
            detached=family
        }
        }
        let input=SurfaceLiftCurve3D(surface:.procedural(.originalBoundaryCorrected(original)),parameterCurve:curves[0])
        var measured=try Admission();_=try family(input,field:f,using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes);_=try family(input,field:f,using:&exact)
        var work=try Admission(work:measured.ledger.work-1);try scalarFailure { _=try family(input,field:f,using:&work) }
        var storage=try Admission(storage:measured.ledger.storageBytes-1);try scalarFailure { _=try family(input,field:f,using:&storage) }
        for call in [1,measured.calls] { var cancelled=try Admission(cancelAt:call);try scalarFailure { _=try family(input,field:f,using:&cancelled) } }
        let bad=SurfaceLiftCurve3D(surface:input.surface,parameterCurve:.constantV(v:-1e-10,uStart:0,uEnd:1))
        do { _=try family(bad,field:f,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let wrong=SurfaceLiftCurve3D(surface:.plane(.init(origin:.origin,normal:.init(x:0,y:0,z:1))),parameterCurve:curves[0])
        do { _=try family(wrong,field:f,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        try require(detached != nil)
        print("PASS actual retained boundary-correction host source/DI/public point, closed cell sides, reversed/constant/affine UV, preparation budgets, cancel and clamp refusal")
    }
}
