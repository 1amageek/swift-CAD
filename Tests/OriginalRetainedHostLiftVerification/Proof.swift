import L0
import L1
import SourceIssuer
import DI0
import DI

@main struct RetainedHostLiftProof {
    typealias F = OriginalExactScalarDomain
    typealias P = ExactPolynomial<F>
    struct Cell: Sendable { let bounds: [[F.Value]];let position: [P] }
    struct Host: OriginalRetainedSurfaceSourceReading {
        let originalField: F
        let originalPolynomials: ExactPolynomialDomain<F>
        let cells: [Cell]
        let originalProofDepth: ExactScalarDepth
        var originalCellCount: Int { cells.count }
        func originalCellLowerBound(at index: Int,axis: Int) -> F.Value { cells[index].bounds[axis][0] }
        func originalCellUpperBound(at index: Int,axis: Int) -> F.Value { cells[index].bounds[axis][1] }
        func originalCellHomogeneous(at index: Int) -> [P] { cells[index].position }
    }
    struct Curve: OriginalRetainedCurveSourceReading {
        let originalField: F
        let originalPolynomials: ExactPolynomialDomain<F>
        let lower: F.Value
        let upper: F.Value
        let position: [P]
        let originalProofDepth: ExactScalarDepth
        var originalCellCount: Int { 1 }
        func originalCellLowerBound(at index: Int) -> F.Value { lower }
        func originalCellUpperBound(at index: Int) -> F.Value { upper }
        func originalCellHomogeneous(at index: Int) -> [P] { position }
    }
    struct Source: OriginalRetainedAtlasLiftSourceReading {
        let originalSurface: OriginalSourceBinding<Host>
        let originalPcurve: OriginalSourceBinding<Curve>
    }
    struct Provider<S: Sendable>: OriginalSourceSnapshotting {
        let depth: Int
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing S,
            limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<S> {
            do { try a.checkpoint();try a.consumeWork(1);return .init(original:copy input,sourceDepth:depth) }
            catch { throw .scalar(error) }
        }
    }
    typealias Family = OriginalFiniteRetainedSurfaceLiftGraphs<Source>
    nonisolated static func source(mode: Int=0,missing: Bool=false,discontinuous: Bool=false,using a: inout LiftAdmission)
        throws -> (OriginalSourceBinding<Source>,OriginalFiniteRetainedSurfaceCharts<Host>,OriginalFiniteRetainedCurveCharts<Curve>) {
        let f=try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),r=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        let z=try f.integer(0,using:&a),o=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let third=try f.dividing(o,f.integer(3,using:&a),using:&a),half=try f.dividing(o,two,using:&a)
        let u=try r.variable(0,using:&a),v=try r.variable(1,using:&a),d=try r.adding(r.constant(two,using:&a),u,using:&a)
        let position=[try r.multiplying(u,d,using:&a),try r.multiplying(v,d,using:&a),try r.multiplying(u,v,using:&a),d]
        var cells:[Cell]=[]
        for i in 0..<2 { for j in 0..<2 {
            if missing && i==1 && j==1 { continue }
            var p=position
            if discontinuous && i==1 { p[0]=try r.adding(p[0],d,using:&a) }
            cells.append(.init(bounds:[[i==0 ? z:third,i==0 ? third:o],[j==0 ? z:half,j==0 ? half:o]],position:p))
        } }
        let host=Host(originalField:f,originalPolynomials:r,cells:cells,originalProofDepth:try .init(value:0,coefficient:0))
        let c=try ExactPolynomialDomain(field:f,variableCount:1,using:&a),t=try c.variable(0,using:&a)
        let one=try c.constant(o,using:&a),zero=try c.constant(z,using:&a)
        let denominator=mode==3 ? try c.adding(one,t,using:&a):one
        let x: P
        if mode==1 { x=try c.subtracting(one,t,using:&a) }
        else if mode==2 { x=try c.constant(third,using:&a) }
        else if mode==3 { x=try c.scaled(c.multiplying(t,c.subtracting(one,t,using:&a),using:&a),by:f.integer(4,using:&a),using:&a) }
        else { x=t }
        let curve=Curve(originalField:f,originalPolynomials:c,lower:z,upper:o,
            position:[x,try c.scaled(denominator,by:half,using:&a),zero,denominator],originalProofDepth:try .init(value:0,coefficient:0))
        let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let hb=try DefaultOriginalSourceBindingIssuer(provider:Provider<Host>(depth:1)).bind(host,limits:l,using:&a)
        let cb=try DefaultOriginalSourceBindingIssuer(provider:Provider<Curve>(depth:1)).bind(curve,limits:l,using:&a)
        let s=try DefaultOriginalSourceBindingIssuer(provider:Provider<Source>(depth:2))
            .bind(Source(originalSurface:hb,originalPcurve:cb),limits:l,using:&a)
        let charts=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Host>().prepare(source:hb,maximumCharts:4,limits:l,using:&a)
        let pcurve=try DefaultOriginalFiniteRetainedCurveChartPreparer<Curve>().prepare(source:cb,maximumCharts:1,limits:l,using:&a)
        return (s,charts,pcurve)
    }
    nonisolated static func prepare<Q: OriginalFiniteRetainedAtlasLiftGraphPreparing>(_ p: Q,
        source: OriginalSourceBinding<Q.Source>,surface: OriginalFiniteRetainedSurfaceCharts<Q.Source.Surface>,
        pcurve: OriginalFiniteRetainedCurveCharts<Q.Source.Pcurve>,using a: inout LiftAdmission)
        throws -> OriginalFiniteRetainedSurfaceLiftGraphs<Q.Source> {
        try p.prepare(source:source,surface:surface,pcurve:pcurve,maximumCharts:4,limits:.init(remainingSourceDepth:8),using:&a)
    }
    nonisolated static func family(mode: Int=0,discontinuous: Bool=false) throws -> Family {
        var a=try LiftAdmission();let (s,h,c)=try source(mode:mode,discontinuous:discontinuous,using:&a)
        return try prepare(DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>(),source:s,surface:h,pcurve:c,using:&a)
    }
    nonisolated static func behavior(_ family: Family,mode: Int,discontinuous: Bool=false) throws {
        var a=try LiftAdmission();let f=family.field,l=try DomainChecks.limits(),issuer=DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        try LiftChecks.require(full.templateCount==4)
        let z=try f.integer(0,using:&a),o=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let third=try f.dividing(o,f.integer(3,using:&a),using:&a),half=try f.dividing(o,two,using:&a)
        for t in [z,third,half,o] {
            let u: F.Value
            if mode==1 { u=try f.subtracting(o,t,using:&a) }
            else if mode==2 { u=third }
            else if mode==3 { u=try f.dividing(f.multiplying(f.integer(4,using:&a),f.multiplying(t,f.subtracting(o,t,using:&a),using:&a),using:&a),f.adding(o,t,using:&a),using:&a) }
            else { u=t }
            let tuple=[t,u,half],found=try full.liftedPositionIncidents(at:tuple,limits:l,using:&a)
            try LiftChecks.require(found.count==(try f.compare(u,third,using:&a) == .equal ? 4:2))
            var observed:[F.Value]=[]
            for member in found {
                let graph=member.graph,r=graph.polynomials
                let d=try r.evaluated(graph.homogeneous[3],at:tuple,using:&a).value
                let x=try f.dividing(r.evaluated(graph.homogeneous[0],at:tuple,using:&a).value,d,using:&a)
                let y=try f.dividing(r.evaluated(graph.homogeneous[1],at:tuple,using:&a).value,d,using:&a)
                let zz=try f.dividing(r.evaluated(graph.homogeneous[2],at:tuple,using:&a).value,d,using:&a)
                let upper=try f.compare(graph.evidence.surface.support[0].lower,third,using:&a) == .equal
                try LiftChecks.require(f.compare(x,discontinuous && upper ? f.adding(u,o,using:&a):u,using:&a) == .equal)
                try LiftChecks.require(f.compare(y,half,using:&a) == .equal)
                try LiftChecks.require(f.compare(zz,f.dividing(f.multiplying(u,half,using:&a),f.adding(two,u,using:&a),using:&a),using:&a) == .equal)
                try LiftChecks.require(graph.layout.parameters==[0] && graph.layout.auxiliaries==[1,2])
                observed.append(x)
            }
            if discontinuous && mode==2 { try LiftChecks.require(f.compare(observed[0],observed[2],using:&a) != .equal) }
            try LiftChecks.require(full.liftedPositionIncidents(at:[t,u,z],limits:l,using:&a).isEmpty)
        }
        func interval(_ low: F.Value,_ high: F.Value,closed: Bool=true) throws -> ExactParameterInterval<F.Value> {
            try .checked(field:f,lower:.finite(low),upper:.finite(high),includesLower:closed,includesUpper:closed,depth:.init(value:0,coefficient:0),using:&a)
        }
        let tuple=[third,mode==2 ? third:mode==1 ? try f.subtracting(o,third,using:&a):mode==3 ? try f.dividing(two,f.integer(3,using:&a),using:&a):third,half]
        for kind in 0..<4 {
            let intervals: [ExactParameterInterval<F.Value>]
            if kind==0 { intervals=[try interval(third,third)] }
            else if kind==1 { intervals=[try interval(third,half,closed:false)] }
            else if kind==2 { intervals=[try interval(z,third),try interval(half,o)] }
            else { intervals=[] }
            let selected=try issuer.issue(request:frame.selection(intervals:[intervals],limits:l,using:&a),family:family,limits:l,using:&a)
            let members=try selected.liftedPositionIncidents(at:tuple,limits:l,using:&a)
            try LiftChecks.require(members.isEmpty == (kind==1 || kind==3))
        }
        var measured=try LiftAdmission();_=try full.liftedPositionIncidents(at:tuple,limits:l,using:&measured)
        var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&exact)
        var work=try LiftAdmission(work:measured.ledger.work-1)
        try DomainChecks.budgetFailure { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&work) }
        var storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
        try DomainChecks.budgetFailure { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&storage) }
        for call in [1,measured.storageCalls] {
            var cancelled=try LiftAdmission(cancelAt:call)
            try DomainChecks.budgetFailure { _=try full.liftedPositionIncidents(at:tuple,limits:l,using:&cancelled) }
        }
        do { _=try full.member(template:4,limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:self.family(),limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        print("PASS retained host complete weighted/nonmonotone/constant/reversed lifted relations, all nonbinary sides, exact requests and budget/cancel")
    }
    static func main() throws { try run() }
    nonisolated static func run() throws {
        try PeriodicRetainedLiftProof.run()
        for mode in 0..<4 { try behavior(family(mode:mode),mode:mode) }
        try behavior(family(mode:2,discontinuous:true),mode:2,discontinuous:true)
        var a=try LiftAdmission()
        do { _=try source(missing:true,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        let (s,h,c)=try source(using:&a),preparer=DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>()
        var measured=try LiftAdmission();_=try prepare(preparer,source:s,surface:h,pcurve:c,using:&measured)
        var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try prepare(preparer,source:s,surface:h,pcurve:c,using:&exact)
        var work=try LiftAdmission(work:measured.ledger.work-1)
        try LiftChecks.scalarFailure { _=try prepare(preparer,source:s,surface:h,pcurve:c,using:&work) }
        var storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
        try LiftChecks.scalarFailure { _=try prepare(preparer,source:s,surface:h,pcurve:c,using:&storage) }
        for call in [1,measured.storageCalls] {
            var cancelled=try LiftAdmission(cancelAt:call)
            try LiftChecks.scalarFailure { _=try prepare(preparer,source:s,surface:h,pcurve:c,using:&cancelled) }
        }
        let other=try source(using:&a)
        do { _=try prepare(preparer,source:s,surface:other.1,pcurve:c,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        let held=try family(mode:2).graphs[0],f=held.field
        let t=try f.binary64(exactly:0.5,using:&a),third=try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a)
        try LiftChecks.require(held.admits([t,third,t],limits:.init(remainingSourceDepth:8),using:&a))
        print("PASS retained host source authority, missing-chart refusal, exact preparation budgets, generic protocol and detached lifetime")
    }
}
