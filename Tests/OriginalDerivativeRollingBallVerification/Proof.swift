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

@main struct DerivativeRollingBallProof {
    typealias Legacy=RetainedRollingBallProof
    typealias Admission=Legacy.Admission
    typealias Family=Legacy.Family
    nonisolated static func host(x: Double,y: Double,projected: Bool,using a: inout Admission) throws -> Surface3D {
        let base=try Legacy.host(x:x,y:y,coons:false,using:&a)
        guard case .procedural(.originalBoundaryCorrected(let construction)) = base else { throw ExactScalarFailure.invalidEvidence }
        return try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let original=construction.boundaries
            let constraints: [OriginalPlaneDerivativeConstraint]=projected ? [
                .init(surface:.plane(.init(origin:.origin,normal:.init(x:0,y:1,z:1))),order:.curvature)]:[]
            func connector(_ source: OriginalCurveRootSpan3D) throws -> OriginalCurveRootSpan3D {
                if !projected { return source }
                let curve=try OriginalPlaneDerivativeCurve3D(source:source,startConstraints:constraints,endConstraints:constraints,
                    tolerance:.standard,usage:&usage,remainingSourceDepth:1)
                return try .init(source:.originalPlaneDerivative(curve),start:.authored(0),end:.authored(1),
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:4,remainingSourceDepth:1,maximumAlgebraicDepth:0)
            }
            let final=try OriginalCoonsSurface3D(vMinimumBoundary:original.vMinimumBoundary,vMaximumBoundary:original.vMaximumBoundary,
                uMinimumBoundary:connector(original.uMinimumBoundary),uMaximumBoundary:connector(original.uMaximumBoundary),tolerance:.standard,usage:&usage)
            return .procedural(.originalPlaneDerivative(try .init(construction:construction,boundaries:final,
                startConstraints:constraints,endConstraints:constraints,remainingSourceDepth:2,tolerance:.standard,usage:&usage)))
        }.value
    }
    nonisolated static func childChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let original=try DerivativeHostShape.shape(weighted:true,projected:true,using:&a)
        for native in [true,false] {
            let pcurve: SurfaceParameterCurve=native ? Legacy.nativePcurve():.affine(origin:.init(x:0,y:0),direction:.init(x:1,y:1),startParameter:0,endParameter:1)
            let input=Curve3D.surfaceLift(.init(surface:.procedural(.originalPlaneDerivative(original)),parameterCurve:pcurve))
            let family=try Legacy.child(input,field:f,using:&a)
            switch family.coverage {
            case .derivativeNativeLift:try Legacy.require(native)
            case .derivativeLift:try Legacy.require(!native)
            default:throw ExactScalarFailure.invalidEvidence
            }
            try Legacy.require(family.graphs.count==(native ? 8:4))
            for t in [0.25,0.5,0.75] {
                let u=try f.binary64(exactly:t,using:&a),v=try f.binary64(exactly:native ? 0:t,using:&a)
                let tuple=[u,u,v],found=try family.graphs.filter { try $0.admits(tuple,limits:.init(remainingSourceDepth:6),using:&a) }
                try Legacy.require(found.count==(t==0.5 ? 4:1))
                let y: OriginalExactScalar
                if !native && t>0.5 {
                    y=try f.dividing(f.subtracting(f.multiplying(f.integer(3,using:&a),v,using:&a),f.integer(1,using:&a),using:&a),f.multiplying(f.integer(2,using:&a),v,using:&a),using:&a)
                } else { y=v }
                let z=try f.binary64(exactly:native ? 0:t*(1-t)*DerivativeHostShape.expected(t,weighted:true,projected:true),using:&a)
                for graph in found {
                    let r=graph.polynomials,d=try r.evaluated(graph.homogeneous[3],at:tuple,using:&a).value
                    for (axis,target) in [u,y,z].enumerated() {
                        let value=try f.dividing(r.evaluated(graph.homogeneous[axis],at:tuple,using:&a).value,d,using:&a)
                        try Legacy.require(f.compare(value,target,using:&a) == .equal)
                    }
                }
            }
        }
        print("PASS derivative rolling-ball children: sealed Native/retained cases, weighted projected source, all incidents and exact original XYZ/UV")
    }
    nonisolated static func family(reverse: Bool,projected: Bool,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Family {
        func rail(_ x: Double,_ y: Double,_ native: Bool) throws -> Curve3D {
            let pcurve: SurfaceParameterCurve=native ? Legacy.nativePcurve(reverse:reverse):.constantV(v:0,uStart:reverse ? 1:0,uEnd:reverse ? 0:1)
            return .surfaceLift(.init(surface:try host(x:x,y:y,projected:projected,using:&a),parameterCurve:pcurve))
        }
        let original=CallerAdapters.RollingBallBlendSurface3D(centerSpine:try rail(0,0,true),
            firstContact:try rail(3,4,false),secondContact:try rail(3,-4,false),radius:5,tolerance:.standard)
        let l=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:7)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:CallerAdapters.OriginalGraphRollingBallSnapshotProvider(field:f))
            .bind(original,limits:l,using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer(),cl=try RetainedHostAdapters.OriginalSourceIssuanceLimits(remainingSourceDepth:6)
        let center=try p.prepare(source:source.original.originalCenter,field:f,maximumCharts:8,limits:cl,using:&a)
        let first=try p.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:8,limits:cl,using:&a)
        let second=try p.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:8,limits:cl,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
            .prepare(source:source,center:center,first:first,second:second,maximumCharts:128,limits:l,using:&a)
    }
    static func main() { do { try run() } catch { print("FAIL derivative rolling-ball uncaught failure");exit(1) } }
    nonisolated static func run() throws {
        try Legacy.run()
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try childChecks(field:f,using:&a)
        var held: Family?
        for reverse in [false,true] {
            var preparation=try Admission(work:300_000_000,storage:1_073_741_824)
            let prepared=try family(reverse:reverse,projected:reverse,field:f,using:&preparation)
            // Prepared results admit later independent queries under their caller's ledger.
            var query=try Admission(work:300_000_000,storage:1_073_741_824)
            try Legacy.check(prepared,reverse:reverse,using:&query);held=prepared
            try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth),using:&query)
            do { try prepared.admitProof(limits:.init(remainingSourceDepth:prepared.source.sourceDepth-1),using:&query);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        }
        var cost=try Admission(work:300_000_000,storage:1_073_741_824);_=try family(reverse:false,projected:false,field:f,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try family(reverse:false,projected:false,field:f,using:&exact)
        var short=try Admission(work:cost.ledger.work-1);try Legacy.scalarFailure { _=try family(reverse:false,projected:false,field:f,using:&short) }
        var bytes=try Admission(storage:cost.ledger.storageBytes-1);try Legacy.scalarFailure { _=try family(reverse:false,projected:false,field:f,using:&bytes) }
        for call in [1,cost.calls] {
            var cancelled=try Admission(cancelAt:call);try Legacy.scalarFailure { _=try family(reverse:false,projected:false,field:f,using:&cancelled) }
        }
        var cancelled=try Admission();cancelled.ledger.cancel();try Legacy.scalarFailure { _=try family(reverse:false,projected:false,field:f,using:&cancelled) }
        guard let held else { throw ExactScalarFailure.invalidEvidence }
        let wrong=try family(reverse:false,projected:false,field:f,using:&a)
        do {
            _=try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
                .prepare(source:held.source,center:wrong.center,first:held.first,second:held.second,maximumCharts:128,
                    limits:.init(remainingSourceDepth:7),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
        let q=try Legacy.tuple(t:f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),reverse:true,field:f,using:&a)
        var incidents=0
        for graph in held.graphs { if try graph.admits(q,limits:.init(remainingSourceDepth:7),using:&a) { incidents+=1 } }
        try Legacy.require(incidents==16)
        print("PASS derivative rolling-ball complete product/resources/lifetime: projected/reversed original rails, 128 products/sixteen incidents, all requests, exact ceilings/depth/cancel/foreign binding and retained owners")
    }
}
