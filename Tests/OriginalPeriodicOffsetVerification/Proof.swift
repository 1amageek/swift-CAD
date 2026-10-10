import L0
import L1
import DI0
import SourceIssuer
import DI

enum PeriodicOffsetFixtures {
    typealias Source=OffsetDomainFixtures.Source
    typealias Family=OriginalPeriodicNativeOffsetLawFamily<Source>
    typealias Cover=OriginalPeriodicNativeOffsetDomainCover<Source>
    static func input(twoAxes: Bool=false,singular: Bool=false) -> NativeInput {
        let xy: [[Double]]=[[0,0],[1,0],[0,1],[0,0]]
        let yz: [[Double]]=twoAxes ? [[0,0],[1,0],[0,1],[0,0]]:[[0,0],[0,1]]
        var controls: [[Double]]=[]
        for v in yz { for u in xy { controls.append(singular ? [0,0,0]:[u[0],u[1]+v[0],v[1]]) } }
        return NativeInput(degrees:[1,1],knots:[[-1,0,1,2,3,4],twoAxes ? [-1,0,1,2,3,4]:[0,0,1,1]],
            counts:[4,yz.count],controls:controls,weights:Array(repeating:1,count:controls.count),periodic:[true,twoAxes])
    }
    static func family(twoAxes: Bool=false,singular: Bool=false,distance: Double=0.25) throws -> Family {
        var a=try TransportFixtures.admission();let l=try TransportFixtures.limits(charts:32)
        let child=try IdentityFixtures.bind(input(twoAxes:twoAxes,singular:singular),&a)
        let field=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let charts=try DefaultOriginalBSplineFundamentalChartPreparer<NativeSnapshot>().prepare(source:child,field:field,maximumCharts:32,limits:l.source,using:&a)
        let source=try ComposedDomainFixtures.bind(Source(originalChild:child,originalDistance:distance),depth:1,using:&a)
        return try DefaultOriginalPeriodicNativeOffsetLawPreparer<Source>().prepare(source:source,child:charts,maximumCharts:32,limits:l.source,using:&a)
    }
    static func cover(_ family: Family,_ a: inout ExactScalarLedger) throws -> Cover {
        let l=try TransportFixtures.limits(charts:32),issuer=DefaultOriginalPeriodicNativeOffsetDomainIssuer<Source>()
        let space=try issuer.prepare(family:family,limits:l,using:&a)
        return try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
    }
    static func generic<P: OriginalPeriodicGuardedChartFamilyQuerying>(_ cover: P,_ tuple: [P.Field.Value],
        _ l: OriginalDomainIdentityLimits,_ a: inout ExactScalarLedger) throws -> Int {
        try cover.positionIncidents(at:tuple,limits:l,using:&a).count
    }
    static func cyclicCoverage() throws {
        for two in [false,true] {
            let family=try family(twoAxes:two);var a=try TransportFixtures.admission()
            let c=try cover(family,&a),f=family.field,l=try TransportFixtures.limits(charts:32)
            try TransportFixtures.require(c.templateCount==(two ? 9:3) && c.integerFamilyRank==(two ? 2:1))
            let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),three=try f.integer(3,using:&a)
            let half=try f.dividing(one,f.integer(2,using:&a),using:&a)
            let uv=[three,two ? try f.negated(three,using:&a):half]
            let incidents=try c.enclosureIncidents(at:uv,limits:l,using:&a)
            try TransportFixtures.require(incidents.count==(two ? 4:2))
            try TransportFixtures.require(generic(c,uv,l,&a)==1)
            let positions=try c.liftedPositionIncidents(at:uv+[one],limits:l,using:&a)
            try TransportFixtures.require(positions.count==1)
            let chosen=positions[0]
            try TransportFixtures.require(chosen.law.child.chart.selection.spans==[1,two ? 1:1])
            let t=DefaultOriginalParameterTransporter<NativeSnapshot,OriginalExactScalarDomain>()
            let local=try t.forward(uv,through:t.inverse(chosen.child.correspondence,limits:l,using:&a),limits:l,using:&a)
            try TransportFixtures.require(f.compare(local[0],zero,using:&a) == .equal)
            let lifted=[local[0],local[1],one],ring=chosen.law.polynomials
            let d=try ring.evaluated(chosen.law.denominator,at:lifted,using:&a).value
            let x=try f.dividing(ring.evaluated(chosen.law.homogeneous[0],at:lifted,using:&a).value,d,using:&a)
            let y=try f.dividing(ring.evaluated(chosen.law.homogeneous[1],at:lifted,using:&a).value,d,using:&a)
            let z=try f.dividing(ring.evaluated(chosen.law.homogeneous[2],at:lifted,using:&a).value,d,using:&a)
            try TransportFixtures.require(f.compare(x,zero,using:&a) == .equal)
            try TransportFixtures.require(f.compare(y,two ? zero:try f.binary64(exactly:-0.25,using:&a),using:&a) == .equal)
            try TransportFixtures.require(f.compare(z,two ? try f.binary64(exactly:0.25,using:&a):half,using:&a) == .equal)
            for q in [zero,try f.negated(one,using:&a),try f.integer(2,using:&a)] {
                try TransportFixtures.require(c.liftedPositionIncidents(at:uv+[q],limits:l,using:&a).isEmpty)
            }
            let rational=ExactRationalScalarDomain()
            let huge=try rational.canonical(sign:-1,numerator:[1,0,0,1],denominator:[1],using:&a)
            let cycle=try OriginalParameterCycle(exact:huge,using:&a)
            let zeroCycle=try OriginalParameterCycle(exact:rational.integer(0,using:&a),using:&a)
            let cycles=[cycle,two ? cycle:zeroCycle]
            let member=try c.member(template:0,cycles:cycles,limits:l,using:&a)
            let authored=try t.forward([half,half],through:member.child.correspondence,limits:l,using:&a)
            try TransportFixtures.require(generic(c,authored,l,&a)==1)
            try TransportFixtures.require(c.enclosureIncidents(at:authored,limits:l,using:&a).count==1)
            try TransportFixtures.require(rational.compare(member.cycles[0].original,huge,using:&a) == .equal)
        }
        print("PASS independent periodic axes, seam/corner germs, canonical original position, positive-root guards, huge negative cycles and generic witness")
    }
    static func selectionsAndGuards() throws {
        let family=try family();var a=try TransportFixtures.admission();let f=family.field,l=try TransportFixtures.limits(charts:32)
        let issuer=DefaultOriginalPeriodicNativeOffsetDomainIssuer<Source>(),space=try issuer.prepare(family:family,limits:l,using:&a)
        let d=try ExactParameterDomain(field:f,depth:ExactScalarDepth(value:0,coefficient:0),using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),three=try f.integer(3,using:&a)
        let half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,_ lower: Bool=true,_ upper: Bool=true) throws -> ExactParameterInterval<OriginalExactScalar> {
            try d.interval(lower:.finite(lo),upper:.finite(hi),includesLower:lower,includesUpper:upper,using:&a)
        }
        let requests=[try space.frame.selection(intervals:[[interval(zero,one,false,false),interval(three,three)],[interval(zero,one)]],limits:l,using:&a),
            try space.frame.selection(intervals:[[],[interval(zero,one)]],limits:l,using:&a)]
        for request in requests {
            let c=try issuer.issue(space:space,request:request,limits:l,using:&a)
            for (u,included) in [(zero,false),(half,true),(one,false),(three,true)] {
                try TransportFixtures.require(c.positionIncidents(at:[u,half],limits:l,using:&a).count==(included && !request.isEmpty ? 1:0))
            }
        }
        for distance in [-0.25,0,0.25] {
            let singular=try cover(Self.family(singular:true,distance:distance),&a)
            let sf=singular.space.family.field,sz=try sf.integer(0,using:&a),sh=try sf.binary64(exactly:0.5,using:&a)
            try TransportFixtures.require(!singular.enclosureIncidents(at:[sz,sh],limits:l,using:&a).isEmpty)
            try TransportFixtures.require(singular.positionIncidents(at:[sz,sh],limits:l,using:&a).isEmpty)
        }
        print("PASS strict/disconnected/singleton/empty requests and exact singular normal guards at negative/zero/positive distance")
    }
    static func failure(_ e: OriginalDomainIdentityFailure,_ resource: ExactResource) throws {
        switch e {
        case .scalar(.resourceLimit(let r)),.source(.scalar(.resourceLimit(let r))):try TransportFixtures.require(r==resource)
        default:throw e
        }
    }
    static func failuresAndLifetime() throws {
        // Only the final domain result survives the preparation scope.
        func retained() throws -> Cover { var a=try TransportFixtures.admission();return try cover(family(),&a) }
        let c=try retained();var a=try TransportFixtures.admission();let f=c.space.family.field,l=try TransportFixtures.limits(charts:32)
        let half=try f.binary64(exactly:0.5,using:&a),uv=[half,half],one=try f.integer(1,using:&a)
        var measured=try TransportFixtures.admission();_=try c.positionIncidents(at:uv,limits:l,using:&measured)
        var exact=try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        try TransportFixtures.require(c.positionIncidents(at:uv,limits:l,using:&exact).count==1)
        for resource in [ExactResource.work,.storage] {
            var short=try TransportFixtures.admission(work:measured.work-(resource == .work ? 1:0),storage:measured.storageBytes-(resource == .storage ? 1:0))
            do { _=try c.positionIncidents(at:uv,limits:l,using:&short);throw ExactScalarFailure.invalidEvidence }
            catch let e as OriginalDomainIdentityFailure { try failure(e,resource) }
        }
        for point in [uv,[half,try f.integer(2,using:&a)]] {
            var baseline=try TerminalAdmission();_=try c.positionIncidents(at:point,limits:l,using:&baseline)
            for stop in [1,max(1,baseline.checks/2),baseline.checks] {
                var cancelled=try TerminalAdmission();cancelled.cancelAt=stop
                do { _=try c.positionIncidents(at:point,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
                catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
                catch OriginalDomainIdentityFailure.domain(.scalar(.cancelled)) {}
                catch OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
                catch OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
            }
        }
        for tuple in [[],[half],[half,half,one]] {
            do { _=try c.positionIncidents(at:tuple,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.invalidDomain {}
        }
        do { _=try c.positionIncidents(at:uv,limits:TransportFixtures.limits(charts:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _=try c.positionIncidents(at:uv,limits:TransportFixtures.limits(families:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        let foreign=try cover(family(),&a)
        do { _=try DefaultOriginalPeriodicNativeOffsetDomainIssuer<Source>().issue(space:c.space,request:foreign.request,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        var invalid=input();invalid.controls[3][0]=0.0000000000001
        let child=try IdentityFixtures.bind(invalid,&a)
        do { _=try DefaultOriginalBSplineFundamentalChartPreparer<NativeSnapshot>().prepare(source:child,field:f,maximumCharts:32,limits:l.source,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.unresolvedAuthority {}
        let valid=try IdentityFixtures.bind(input(),&a)
        do { _=try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:valid,field:f,maximumCharts:32,limits:l.source,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        var copied=c.space.family.laws;copied.removeAll()
        try TransportFixtures.require(c.liftedPositionIncidents(at:uv+[one],limits:l,using:&a).count==1 && copied.isEmpty)
        print("PASS periodic source refusal, foreign owner, malformed query, exact work/storage, chart/family limits, entry/mid/final cancel and detached lifetime/COW")
    }
}

@main struct PeriodicOffsetProof {
    static func main() throws {
        try PeriodicOffsetFixtures.cyclicCoverage()
        try PeriodicOffsetFixtures.selectionsAndGuards()
        try PeriodicOffsetFixtures.failuresAndLifetime()
        try OffsetDomainFixtures.guardedCoverageAndOwnership()
        try OffsetDomainFixtures.guardedFailures()
    }
}
