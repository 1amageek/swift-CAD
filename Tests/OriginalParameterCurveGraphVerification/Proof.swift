#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import CallerAdapters

@main struct ParameterCurveGraphProof {
    typealias Legacy=RetainedRollingBallProof
    typealias Admission=Legacy.Admission
    typealias Child=Legacy.Child
    typealias Limits=Legacy.Limits
    nonisolated static func image(_ input: Curve3D,gain: Double,offset: Double) throws -> Curve3D {
        .parameterImage(try .init(source:input,gain:gain,offset:offset,tolerance:.standard))
    }
    nonisolated static func child(_ input: Curve3D,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Child {
        let l=try Limits(remainingSourceDepth:16)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:
            CallerAdapters.OriginalRollingBallCurveSnapshotProvider(field:f,tolerance:.standard)).bind(input,limits:l,using:&a)
        return try CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer().prepare(source:source,field:f,maximumCharts:16,limits:l,using:&a)
    }
    nonisolated static func native(_ x: Double=0,_ y: Double=0) -> Curve3D {
        .bSpline(.init(degree:1,knots:[2,2,3.5,5,5],controlPoints:[0.0,0.5,1].map { .init(x:x,y:y,z:$0) }))
    }
    nonisolated static func traversal(_ input: Curve3D,start: Double,end: Double,using a: inout Admission) throws -> Curve3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let span=try OriginalCurveRootSpan3D(source:input,start:.authored(start),end:.authored(end),
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,usage:&usage,maximumSpanCount:16,remainingSourceDepth:12,maximumAlgebraicDepth:0)
            return .originalConstructionChart(try .init(traversal:span,maximumSpanCount:16,usage:&usage))
        }.value
    }
    nonisolated static func value(_ graph: Child.Graph,at q: [OriginalExactScalar],axis: Int,using a: inout Admission) throws -> OriginalExactScalar {
        let r=graph.polynomials,f=graph.field
        return try f.dividing(r.evaluated(graph.homogeneous[axis],at:q,using:&a).value,
            r.evaluated(graph.homogeneous[3],at:q,using:&a).value,using:&a)
    }
    nonisolated static func childChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        for mode in 0..<5 {
            let input: Curve3D
            if mode<2 { input=try image(native(),gain:mode==0 ? 3:-3,offset:mode==0 ? 2:5) }
            else if mode==2 { input=try image(image(native(),gain:3,offset:2),gain:-1,offset:1) }
            else if mode==3 { input=try traversal(native(),start:4.25,end:2.75,using:&a) }
            else { input=try traversal(image(native(),gain:3,offset:2),start:0.75,end:0.25,using:&a) }
            let family=try child(input,field:f,using:&a)
            try Legacy.require(family.graphs.count==2)
            for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
                let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
                let normalized: OriginalExactScalar
                if mode==0 { normalized=t }
                else if mode<3 { normalized=try f.subtracting(one,t,using:&a) }
                else { normalized=try f.subtracting(f.binary64(exactly:0.75,using:&a),f.multiplying(half,t,using:&a),using:&a) }
                let raw=try f.adding(f.integer(2,using:&a),f.multiplying(f.integer(3,using:&a),normalized,using:&a),using:&a)
                let q=mode==2 || mode==4 ? [t,normalized,raw]:[t,raw]
                var incidents=0
                for graph in family.graphs {
                    try Legacy.require(graph.layout.parameters==[0] && graph.layout.auxiliaries.count==q.count-1)
                    if try graph.admits(q,limits:.init(remainingSourceDepth:16),using:&a) {
                        incidents+=1;try Legacy.require(f.compare(value(graph,at:q,axis:2,using:&a),normalized,using:&a) == .equal)
                    }
                    var wrong=q;wrong[wrong.count-1]=z
                    try Legacy.require(!graph.admits(wrong,limits:.init(remainingSourceDepth:16),using:&a))
                }
                try Legacy.require(incidents==(n==1 && d==2 ? 2:1))
                let actual=try input.point(at:Double(n)/Double(d),tolerance:.standard)
                let expected=mode==0 ? Double(n)/Double(d):mode<3 ? 1-Double(n)/Double(d):0.75-0.5*Double(n)/Double(d)
                try Legacy.require(abs(actual.z-expected)<1e-12)
            }
        }
        let normalized=SpatialCurveGraphProof.native()
        let ratio=Curve3D.parameterImage(try .init(source:normalized,parameterGain:OriginalParameterGain.ratio(numerator:1,denominator:3),offset:0,tolerance:.standard))
        let nested=try image(ratio,gain:3,offset:0),ratioFamily=try child(nested,field:f,using:&a)
        let threeHalf=try f.multiplying(f.integer(3,using:&a),half,using:&a)
        for graph in ratioFamily.graphs {
            try Legacy.require(graph.admits([half,threeHalf,half],limits:.init(remainingSourceDepth:16),using:&a))
            try Legacy.require(f.compare(value(graph,at:[half,threeHalf,half],axis:2,using:&a),half,using:&a) == .equal)
        }
        for mode in [1,2] {
            let lift=Curve3D.surfaceLift(.init(surface:try Legacy.host(x:0,y:0,coons:true,using:&a),parameterCurve:Legacy.nativePcurve(mode:mode)))
            let input=try image(lift,gain:-1,offset:1),family=try child(input,field:f,using:&a)
            for t in [try f.binary64(exactly:0.25,using:&a),half,try f.binary64(exactly:0.75,using:&a)] {
                let old=try f.subtracting(one,t,using:&a)
                let u=mode==1 ? try f.multiplying(f.integer(2,using:&a),f.multiplying(old,t,using:&a),using:&a):half
                let q=[t,old,u,z]
                var incidents=0
                for graph in family.graphs {
                    if try graph.admits(q,limits:.init(remainingSourceDepth:16),using:&a) {
                        incidents+=1;try Legacy.require(f.compare(value(graph,at:q,axis:2,using:&a),u,using:&a) == .equal)
                    }
                    var wrong=q;wrong[2]=z
                    try Legacy.require(!graph.admits(wrong,limits:.init(remainingSourceDepth:16),using:&a))
                }
                try Legacy.require(incidents==(mode==2 || f.compare(t,half,using:&a) == .equal ? 2:1))
                let actual=try input.point(at:mode==1 ? 0.5:0.25,tolerance:.standard)
                try Legacy.require(abs(actual.z-0.5)<1e-12)
            }
        }
        print("PASS parameter graph child transport")
    }
    nonisolated static func issued<P: CallerAdapters.OriginalParameterImageGraphIssuing>(_ issuer: P,
        source: RetainedHostAdapters.OriginalSourceBinding<P.Source>,child: RetainedHostAdapters.OriginalParametricGraphReceipt<P.Source.Child,P.Field,P.ChildEvidence>,
        parameters: RetainedHostAdapters.OriginalSourceParameterInterval<P.Field.Value>,using a: inout Admission) throws
        -> RetainedHostAdapters.OriginalParametricGraphReceipt<P.Source,P.Field,CallerAdapters.OriginalCurveParameterGraphEvidence<P.Source.Child,P.Field,P.ChildEvidence>> {
        try issuer.issue(source:source,child:child,parameters:parameters,limits:.init(remainingSourceDepth:16),using:&a)
    }
    nonisolated static func nonlinearChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        // Internal theorem fixtures use an actual constant source: every retained
        // local coordinate and parameter image has independently equal original XYZ.
        let constant=Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.origin]))
        let family=try child(image(constant,gain:1,offset:0),field:f,using:&a)
        guard case .parameterImage(let owner)=family.coverage else { throw ExactScalarFailure.invalidEvidence }
        let old=owner.children.graphs[0],r=old.polynomials,z=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let half=try f.binary64(exactly:0.5,using:&a),quarter=try f.binary64(exactly:0.25,using:&a),threeQuarter=try f.binary64(exactly:0.75,using:&a)
        let q=try r.variable(0,using:&a),delta=try r.subtracting(q,r.constant(half,using:&a),using:&a)
        let square=try r.scaled(r.multiplying(delta,delta,using:&a),by:f.integer(4,using:&a),using:&a)
        let issuer=CallerAdapters.DefaultOriginalParameterImageGraphIssuer<CallerAdapters.OriginalRollingBallParameterImageCoverage.Map,OriginalExactScalarDomain,CallerAdapters.OriginalRollingBallCurveGraphEvidence>()
        for mode in 0..<4 {
            let numerator=mode==0 || mode==3 ? square:mode==1 ? try r.zero(using:&a):try r.multiplying(q,q,using:&a)
            let denominator=mode==2 ? q:try r.constant(one,using:&a)
            var conditions=old.conditions
            if mode==3 { conditions.append(.init(delta,.notEqual)) }
            let theorem=RetainedHostAdapters.OriginalParametricGraphReceipt(source:old.source,evidence:old.evidence,field:f,polynomials:r,
                homogeneous:old.homogeneous,support:old.support,includesUpperBoundary:[mode != 3],layout:old.layout,
                conditions:conditions,parameterTransport:.init(numerators:[numerator],denominators:[denominator]),proofDepth:old.proofDepth)
            let graph=try issued(issuer,source:owner.source,child:theorem,parameters:family.support,using:&a)
            if mode==0 {
                for local in [quarter,threeQuarter] {
                    try Legacy.require(graph.admits([quarter,local],limits:.init(remainingSourceDepth:16),using:&a))
                    let d=try graph.polynomials.evaluated(graph.homogeneous[3],at:[quarter,local],using:&a).value
                    try Legacy.require(f.compare(graph.polynomials.evaluated(graph.homogeneous[2],at:[quarter,local],using:&a).value,z,using:&a) == .equal && f.sign(of:d,using:&a) != .zero)
                }
                try Legacy.require(!graph.admits([quarter,half],limits:.init(remainingSourceDepth:16),using:&a))
            } else if mode==1 {
                for local in [z,quarter,half,one] { try Legacy.require(graph.admits([z,local],limits:.init(remainingSourceDepth:16),using:&a)) }
                try Legacy.require(!graph.admits([quarter,half],limits:.init(remainingSourceDepth:16),using:&a))
            } else if mode==2 {
                try Legacy.require(!graph.admits([z,z],limits:.init(remainingSourceDepth:16),using:&a))
                try Legacy.require(graph.admits([quarter,quarter],limits:.init(remainingSourceDepth:16),using:&a))
            } else {
                try Legacy.require(!graph.admits([z,half],limits:.init(remainingSourceDepth:16),using:&a))
                try Legacy.require(!graph.admits([one,one],limits:.init(remainingSourceDepth:16),using:&a))
                try Legacy.require(graph.admits([quarter,quarter],limits:.init(remainingSourceDepth:16),using:&a))
            }
        }
        // The original constant position theorem also permits correspondence
        // through an auxiliary coordinate and a non-prefix parameter layout.
        let mixed=try ExactPolynomialDomain(field:f,variableCount:2,using:&a),aux=try mixed.variable(0,using:&a)
        let mixedLayout=try RetainedHostAdapters.OriginalParametricVariableLayout.checked(variableCount:2,parameters:[1],auxiliaries:[0],using:&a)
        let mixedPosition=[try mixed.zero(using:&a),try mixed.zero(using:&a),try mixed.zero(using:&a),try mixed.constant(one,using:&a)]
        let auxiliary=RetainedHostAdapters.OriginalParametricGraphReceipt(source:old.source,evidence:old.evidence,field:f,polynomials:mixed,
            homogeneous:mixedPosition,support:old.support,includesUpperBoundary:[true],layout:mixedLayout,
            conditions:[.init(aux,.nonnegative),.init(try mixed.subtracting(mixed.constant(one,using:&a),aux,using:&a),.nonnegative)],
            parameterTransport:.init(numerators:[aux],denominators:[try mixed.constant(one,using:&a)]),proofDepth:old.proofDepth)
        let graph=try issued(issuer,source:owner.source,child:auxiliary,parameters:family.support,using:&a)
        try Legacy.require(graph.admits([quarter,quarter,threeQuarter],limits:.init(remainingSourceDepth:16),using:&a))
        try Legacy.require(!graph.admits([quarter,half,threeQuarter],limits:.init(remainingSourceDepth:16),using:&a))
        try Legacy.require(!graph.admits([quarter,quarter,try f.integer(2,using:&a)],limits:.init(remainingSourceDepth:16),using:&a))
        let normalized=try SpatialCurveGraphProof.normalized(constant,using:&a)
        guard case .originalAffineWord(let word)=normalized else { throw ExactScalarFailure.invalidEvidence }
        let coefficients=try CallerAdapters.OriginalAffineWordCoefficientImport.values(word.preparedWord,tolerance:.standard,maximumDepth:32,using:&a)
        let alien=try OriginalExactScalarDomain(retaining:coefficients[0],maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let alienRing=try ExactPolynomialDomain(field:alien,variableCount:1,using:&a)
        let guardOnly=try alienRing.constant(coefficients[0],using:&a)
        let foreign=RetainedHostAdapters.OriginalParametricGraphReceipt(source:old.source,evidence:old.evidence,field:f,polynomials:r,
            homogeneous:old.homogeneous,support:old.support,includesUpperBoundary:old.includesUpperBoundary,layout:old.layout,
            conditions:[.init(guardOnly,.positive)],parameterTransport:old.parameterTransport,proofDepth:old.proofDepth)
        do { _=try issuer.issue(source:owner.source,child:foreign,parameters:family.support,limits:.init(remainingSourceDepth:16),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.polynomial(.scalar(.incompatibleDomain)) {}
        let algebraic=try child(image(normalized,gain:-1,offset:1),field:alien,using:&a)
        try Legacy.require(algebraic.proofDepth.coefficient>0)
        var low=try Admission();low.ledger = .init(limits:try .init(work:100_000_000,storageBytes:400_000_000,valueDepth:32,coefficientDepth:algebraic.proofDepth.coefficient-1))
        try Legacy.scalarFailure { try algebraic.admitProof(limits:.init(remainingSourceDepth:16),using:&low) }
        print("PASS nonlinear and collapsed child preimages, open guards and foreign field")
    }
    nonisolated static func family(lifted: Bool,traversed: Bool,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Legacy.Family {
        func rail(_ x: Double,_ y: Double,_ lift: Bool) throws -> Curve3D {
            let original: Curve3D
            if lift { original = .surfaceLift(.init(surface:try Legacy.host(x:x,y:y,coons:true,using:&a),parameterCurve:.constantV(v:0,uStart:0,uEnd:1))) }
            else { original=native(x,y) }
            let mapped=try image(original,gain:lift ? -1:-3,offset:lift ? 1:5)
            return traversed ? try traversal(mapped,start:0.75,end:0.25,using:&a):mapped
        }
        let original=try CallerAdapters.RollingBallBlendSurface3D(centerSpine:rail(0,0,lifted),firstContact:rail(3,4,false),
            secondContact:rail(3,-4,false),radius:5,tolerance:.standard)
        let l=try Limits(remainingSourceDepth:17),cl=try Limits(remainingSourceDepth:16)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:CallerAdapters.OriginalGraphRollingBallSnapshotProvider(field:f))
            .bind(original,limits:l,using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer()
        let c=try p.prepare(source:source.original.originalCenter,field:f,maximumCharts:16,limits:cl,using:&a)
        let x=try p.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:16,limits:cl,using:&a)
        let y=try p.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:16,limits:cl,using:&a)
        return try CallerAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
            .prepare(source:source,center:c,first:x,second:y,maximumCharts:32,limits:l,using:&a)
    }
    nonisolated static func check(_ family: Legacy.Family,lifted: Bool,traversed: Bool,using a: inout Admission) throws {
        let f=family.field,l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:17),maximumTransportDepth:32,maximumCharts:32,maximumFamilies:8,maximumIdentityProofs:8)
        try Legacy.require(family.graphs.count==(lifted ? 16:8))
        let issuer=RetainedHostAdapters.DefaultOriginalRollingBallGraphDomainIssuer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        func tuple(_ t: OriginalExactScalar) throws -> [OriginalExactScalar] {
            let old=traversed ? try f.subtracting(f.binary64(exactly:0.75,using:&a),f.multiplying(half,t,using:&a),using:&a):t
            let u=try f.subtracting(one,old,using:&a),raw=try f.adding(f.integer(2,using:&a),f.multiplying(f.integer(3,using:&a),u,using:&a),using:&a)
            var q=[t,half]
            if traversed { q.append(old) }
            if lifted { q += [u,u,z] } else { q.append(raw) }
            if traversed { q.append(old) };q.append(raw)
            if traversed { q.append(old) };q.append(raw)
            q += [try f.integer(5,using:&a),try f.integer(5,using:&a),try f.dividing(f.integer(3,using:&a),f.integer(5,using:&a),using:&a)]
            return q
        }
        for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
            let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),q=try tuple(t)
            let found=try full.liftedPositionIncidents(at:q,limits:l,using:&a)
            try Legacy.require(found.count==(n==1 && d==2 ? 8:1))
            let old=traversed ? try f.subtracting(f.binary64(exactly:0.75,using:&a),f.multiplying(half,t,using:&a),using:&a):t
            let expected=try f.subtracting(one,old,using:&a)
            for member in found {
                let g=member.graph,r=g.polynomials,den=try r.evaluated(g.homogeneous[3],at:q,using:&a).value
                for (axis,target) in [try f.integer(5,using:&a),z,expected].enumerated() {
                    try Legacy.require(f.compare(f.dividing(r.evaluated(g.homogeneous[axis],at:q,using:&a).value,den,using:&a),target,using:&a) == .equal)
                }
            }
            if !(lifted && traversed) {
                let numeric=try family.source.original.original.point(u:Double(n)/Double(d),v:0.5)
                try Legacy.require(abs(numeric.x-5)<1e-12 && abs(numeric.y)<1e-12 && abs(numeric.z-(traversed ? 0.25+0.5*Double(n)/Double(d):1-Double(n)/Double(d)))<1e-12)
            } else if n==1 && d==2 {
                // This source/DI slice must preserve the diagnosed legacy evaluator failure.
                // Its required caller repair remains a separate unfinished PG.J item.
                do { _=try family.source.original.original.point(u:0.5,v:0.5);throw ExactScalarFailure.invalidEvidence }
                catch let error as KernelError {
                    try Legacy.require(error.code == .invalidInput)
                    print("PASS diagnosed legacy traversed-lift point refusal retained")
                }
            }
        }
        let q=try tuple(half)
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,closed: Bool=true) throws -> RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:.init(value:32,coefficient:32),using:&a)
        }
        func selected(_ intervals: [[RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar>]]) throws -> RetainedHostAdapters.OriginalRollingBallGraphDomainCover<Legacy.Source,Legacy.Evidence,Legacy.Coverage> {
            try issuer.issue(request:frame.selection(intervals:intervals,limits:l,using:&a),family:family,limits:l,using:&a)
        }
        let strict=try selected([[interval(z,half,closed:false)],[interval(z,one)]])
        try Legacy.require(strict.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        let singleton=try selected([[interval(half,half)],[interval(half,half)]])
        try Legacy.require(singleton.liftedPositionIncidents(at:q,limits:l,using:&a).count==8)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let disconnected=try selected([[interval(z,third),interval(f.subtracting(one,third,using:&a),one)],[interval(z,one)]])
        try Legacy.require(disconnected.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        let empty=try selected([[],[]]);try Legacy.require(empty.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        var wrong=q;wrong[wrong.count-3]=try f.integer(-5,using:&a)
        try Legacy.require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        wrong=q;wrong[2]=z;try Legacy.require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        var cost=try Admission();_=try full.liftedPositionIncidents(at:q,limits:l,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try full.liftedPositionIncidents(at:q,limits:l,using:&exact)
        for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls/2),(100_000_000,400_000_000,cost.calls)] {
            var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
            do { _=try full.liftedPositionIncidents(at:q,limits:l,using:&failed);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
        }
        var cancel=try Admission();cancel.ledger.cancel()
        do { _=try empty.liftedPositionIncidents(at:q,limits:l,using:&cancel);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS parameter graph product and DI")
    }
    nonisolated static func failureChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let input=try traversal(image(native(),gain:3,offset:2),start:0.75,end:0.25,using:&a)
        var cost=try Admission();let held=try child(input,field:f,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try child(input,field:f,using:&exact)
        for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls/2),(100_000_000,400_000_000,cost.calls)] {
            var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
            try Legacy.scalarFailure { _=try child(input,field:f,using:&failed) }
        }
        do { _=try child(native(),field:f,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.invalidChart {}
        do { _=try child(image(native(),gain:1,offset:0),field:f,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.invalidChart {}
        let binding=held.source,p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer()
        _=try p.prepare(source:binding,field:f,maximumCharts:2,limits:.init(remainingSourceDepth:binding.sourceDepth),using:&a)
        do { _=try p.prepare(source:binding,field:f,maximumCharts:1,limits:.init(remainingSourceDepth:16),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.chartLimit {}
        try held.admitProof(limits:.init(remainingSourceDepth:held.source.sourceDepth),using:&a)
        do { try held.admitProof(limits:.init(remainingSourceDepth:held.source.sourceDepth-1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let original=try child(image(native(),gain:3,offset:2),field:f,using:&a)
        let foreign=try child(image(native(),gain:3,offset:2),field:f,using:&a)
        guard case .parameterImage(let owner)=original.coverage,case .parameterImage(let other)=foreign.coverage else { throw ExactScalarFailure.invalidEvidence }
        let issuer=CallerAdapters.DefaultOriginalParameterImageGraphIssuer<CallerAdapters.OriginalRollingBallParameterImageCoverage.Map,OriginalExactScalarDomain,CallerAdapters.OriginalRollingBallCurveGraphEvidence>()
        do { _=try issuer.issue(source:owner.source,child:other.children.graphs[0],parameters:original.support,limits:.init(remainingSourceDepth:16),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
        let half=try f.binary64(exactly:0.5,using:&a),raw=try f.binary64(exactly:3.5,using:&a)
        var query=try Admission();try Legacy.require(held.graphs[0].admits([half,half,raw],limits:.init(remainingSourceDepth:16),using:&query))
        guard case .originalConstructionChart(let chart)=input,case .traversal(let span)=chart.chart,
            case .parameterImage(let map)=span.source,case .bSpline(let originalNative)=map.source else { throw ExactScalarFailure.invalidEvidence }
        var points=originalNative.controlPoints;points[0] = .init(x:99,y:99,z:99)
        try Legacy.require(points != originalNative.controlPoints && held.source.original.original==input)
        print("PASS parameter graph failures and lifetime")
    }
    nonisolated static func run() throws {
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try childChecks(field:f,using:&a)
        try nonlinearChecks(field:f,using:&a)
        for lifted in [false,true] { for traversed in [false,true] {
            let prepared=try family(lifted:lifted,traversed:traversed,field:f,using:&a)
            try check(prepared,lifted:lifted,traversed:traversed,using:&a)
        } }
        try failureChecks(field:f,using:&a)
        try SpatialCurveGraphProof.run()
    }
    nonisolated static func finding() throws {
        var a=try Admission()
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try nonlinearChecks(field:f,using:&a)
        print("PASS auxiliary transport and variable-layout finding confirmation")
    }
    static func main() {
        do {
            #if ORIGINAL_PARAMETER_GRAPH_FINDING
            try finding()
            #else
            try run()
            #endif
        }
        catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL parameter curve graphs");exit(1)
        }
    }
}
