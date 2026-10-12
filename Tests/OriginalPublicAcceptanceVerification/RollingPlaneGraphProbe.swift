import CADCore
@testable import CADGeometry
import Darwin

@main struct RollingPlaneGraphProbe {
    static func lift(_ x: Double, _ y: Double, _ pcurve: SurfaceParameterCurve) -> Curve3D {
        let stations = [0.0,0.5,1.0], knots = [0.0,0,0.5,1,1]
        return .surfaceLift(.init(surface:.bSpline(.init(uDegree:1,vDegree:1,uKnots:knots,vKnots:knots,
            controlPoints:stations.map { _ in stations.map { Point3D(x:x,y:y,z:$0) } })),parameterCurve:pcurve))
    }
    static func shape() -> Surface3D {
        .procedural(.rollingBall(.init(centerSpine:lift(0,0,.constantV(v:0,uStart:0,uEnd:1)),
            firstContact:lift(3,4,.affine(origin:.init(x:0,y:0),direction:.init(x:1,y:0),startParameter:0,endParameter:1)),
            secondContact:lift(3,-4,.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0),.init(x:1,y:0)]))),radius:5,tolerance:.standard)))
    }
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

    static func main() throws {
        var a = try Admission(work:8_388_608)
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:12),maximumTransportDepth:32,maximumCharts:262144,maximumFamilies:2,maximumIdentityProofs:0)
        let f = try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        guard case .procedural(.rollingBall(let original)) = shape() else { return }
        let source = try DefaultOriginalSourceBindingIssuer(provider:OriginalGraphRollingBallSnapshotProvider(field:f)).bind(original,limits:limits.source,using:&a)
        let child = DefaultOriginalRollingBallCurveGraphPreparer(), sl = try OriginalSourceIssuanceLimits(remainingSourceDepth:11)
        let center = try child.prepare(source:source.original.originalCenter,field:f,maximumCharts:262144,limits:sl,using:&a)
        let first = try child.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:262144,limits:sl,using:&a)
        let second = try child.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:262144,limits:sl,using:&a)
        let family = try DefaultOriginalFiniteRollingBallGraphPreparer<OriginalGraphRollingBallSnapshot,OriginalRollingBallCurveGraphEvidence,OriginalRollingBallCurveGraphCoverage>().prepare(source:source,center:center,first:first,second:second,maximumCharts:262144,limits:limits.source,using:&a)
        print("SOURCE",family.graphs.count,a.ledger.work,a.ledger.storageBytes)
        let domain = DefaultOriginalRollingBallGraphDomainIssuer<OriginalGraphRollingBallSnapshot,OriginalRollingBallCurveGraphEvidence,OriginalRollingBallCurveGraphCoverage>()
        let frame = try domain.frame(family:family,limits:limits,using:&a), request = try frame.fullSelection(limits:limits,using:&a)
        let cover = try domain.issue(request:request,family:family,limits:limits,using:&a)
        let field = try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        for i in 0..<cover.templateCount {
            do {
                let member = try cover.member(template:i,limits:limits,using:&a)
                let reduced = try DefaultOriginalRollingBallGraphReducer<OriginalGraphRollingBallSnapshot,OriginalRollingBallCurveGraphEvidence>().reduce(member.graph,limits:limits.source,using:&a)
                var excluded = false
                for condition in reduced.conditions {
                    if condition.polynomial.terms.allSatisfy({ $0.powers.allSatisfy { $0 == 0 } }) {
                        let value = try condition.polynomial.terms.first?.coefficient ?? f.integer(0,using:&a)
                        if try !condition.accepts(f.sign(of:value,using:&a)) { excluded = true }
                    }
                }
                print("REDUCED",i,a.ledger.work,"EXCLUDED",excluded)
                if excluded { continue }
                let fixed = try f.binary64(exactly:0.5,using:&a)
                let interval = try ExactParameterInterval.checked(field:f,lower:.finite(fixed),upper:.finite(fixed),includesLower:true,includesUpper:true,depth:fixed.depth,using:&a)
                let sliced = try frame.selection(intervals:[[interval],Array(cover.effectiveEnclosure.axes[1].intervals)],limits:limits,using:&a)
                let binding = try DefaultOriginalParametricGraphDomainBinder().bind(graph:reduced,request:sliced,limits:limits,using:&a)
                let prepared = try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:field,limits:limits,using:&a)
                let plane = try DefaultOriginalSourceBindingIssuer(provider:OriginalPlaneSnapshotProvider(tolerance:.standard)).bind(Surface3D.plane(.init(origin:.init(x:0,y:0,z:0.5),normal:.unitZ)),limits:limits.source,using:&a)
                let one = try f.integer(1,using:&a)
                let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>().issue(source:plane,field:f,firstLength:one,normalLength:one,limits:limits.source,using:&a)
                let pd = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,OriginalExactScalarDomain>()
                let pf = try pd.frame(basis:basis,limits:limits,using:&a), pr = try pf.fullSelection(limits:limits,using:&a)
                let pc = try pd.issue(request:pr,basis:basis,limits:limits,using:&a)
                let pg = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>().compile(cover:pc,field:field,limits:limits,using:&a)
                typealias Cells = ExactRealCellDomain<OriginalExactScalarDomain>
                let solver = ExactParametricRelationDomain<OriginalExactScalarDomain,Cells,ExactRealTopology<OriginalExactScalarDomain>>(cells:Cells.self,topology:.init(cells:Cells.self))
                let input = try solver.compile(kind:.surfaceSurface,first:prepared.graph,second:pg.graph,using:&a)
                print("L5_COMPILE",i,a.ledger.work);fflush(stdout)
                let geometry = try NativeExactPublicLimits.unboundedStructure()
                let solved = try solver.resolve(input,cellLimits:geometry.cells,topologyLimits:geometry.topology,using:&a)
                print("L5_RESOLVED",i,a.ledger.work,solved.selection.cells.count);return
                print("COMPILED",i,a.ledger.work)
            } catch { print("STOP",i,a.ledger.work,error); return }
        }
    }
}
