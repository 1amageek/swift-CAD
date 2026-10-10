import CADCore
@testable import CADGeometry
import RetainedHostAdapters
import CallerAdapters

@main struct RetainedLiftCallerProof {
    typealias Admission = ActualRetainedHostLiftProof.Admission
    static func main() throws { try run() }
    nonisolated static func run() throws {
        var a=try Admission();let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let surface=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],controlPoints:[
            [.origin,.init(x:0.5,y:0,z:0),.init(x:1,y:0,z:0)],
            [.init(x:0,y:0.5,z:0),.init(x:0.5,y:0.5,z:0),.init(x:1,y:0.5,z:0)],
            [.init(x:0,y:1,z:0),.init(x:0.5,y:1,z:0),.init(x:1,y:1,z:0)]])
        let input=Curve3D.surfaceLift(.init(surface:.bSpline(surface),parameterCurve:.constantV(v:0.5,uStart:0,uEnd:1)))
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:
            CallerAdapters.OriginalRollingBallCurveSnapshotProvider(field:f,tolerance:.standard))
            .bind(input,limits:.init(remainingSourceDepth:3),using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer()
        let family=try p.prepare(source:source,field:f,maximumCharts:4,limits:.init(remainingSourceDepth:3),using:&a)
        try ActualRetainedHostLiftProof.require(family.graphs.count==4)
        guard case .retainedLift(let lift)=family.coverage else { throw ExactScalarFailure.invalidEvidence }
        try ActualRetainedHostLiftProof.require(lift.pcurve.laws.count==1)
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        for graph in family.graphs {
            try ActualRetainedHostLiftProof.require(graph.admits([half,half,half],limits:.init(remainingSourceDepth:3),using:&a))
        }
        var measured=try Admission();_=try p.prepare(source:source,field:f,maximumCharts:4,limits:.init(remainingSourceDepth:3),using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try p.prepare(source:source,field:f,maximumCharts:4,limits:.init(remainingSourceDepth:3),using:&exact)
        var short=try Admission(work:measured.ledger.work-1)
        try ActualRetainedHostLiftProof.scalarFailure { _=try p.prepare(source:source,field:f,maximumCharts:4,limits:.init(remainingSourceDepth:3),using:&short) }
        var bytes=try Admission(storage:measured.ledger.storageBytes-1)
        try ActualRetainedHostLiftProof.scalarFailure { _=try p.prepare(source:source,field:f,maximumCharts:4,limits:.init(remainingSourceDepth:3),using:&bytes) }
        for call in [1,measured.calls] {
            var cancelled=try Admission(cancelAt:call)
            try ActualRetainedHostLiftProof.scalarFailure { _=try p.prepare(source:source,field:f,maximumCharts:4,limits:.init(remainingSourceDepth:3),using:&cancelled) }
        }
        print("PASS existing rolling-ball curve caller consumes retained lift source/family with complete knot sides, typed pcurve view and exact resources/cancel")
    }
}
