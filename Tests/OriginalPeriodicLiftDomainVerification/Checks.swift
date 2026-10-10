import L0
import L1
import DI0
import SourceIssuer
import DI

/// Shared behavioral assertions for independent and actual original-source paths.
enum DomainChecks {
    nonisolated static func limits(charts: Int=64,families: Int=2,source: Int=8,transport: Int=16) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:source),maximumTransportDepth:transport,
            maximumCharts:charts,maximumFamilies:families,maximumIdentityProofs:64)
    }
    nonisolated static func generic<P: OriginalPeriodicNativeSurfaceLiftDomainQuerying>(_ cover: P,
        at tuple: [OriginalExactScalar],using a: inout LiftAdmission) throws -> [OriginalPeriodicNativeSurfaceLiftChartOccurrence<P.Source>] {
        try cover.liftedPositionIncidents(at:tuple,limits:limits(),using:&a)
    }
    nonisolated static func budgetFailure(_ body: () throws -> Void) throws {
        do { try body();throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        catch OriginalDomainIdentityFailure.domain(.scalar(.cancelled)) {}
        catch OriginalDomainIdentityFailure.polynomial(.scalar(.cancelled)) {}
        catch OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
        catch OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
        catch OriginalDomainIdentityFailure.domain(.scalar(.resourceLimit(_))) {}
        catch OriginalDomainIdentityFailure.polynomial(.scalar(.resourceLimit(_))) {}
        catch OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
        catch OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
    }
    nonisolated static func cover<S: OriginalLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        using a: inout LiftAdmission) throws -> OriginalPeriodicNativeSurfaceLiftDomainCover<S> {
        let issuer=DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S>(),l=try limits()
        let space=try issuer.prepare(family:family,limits:l,using:&a)
        return try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
    }
    nonisolated static func run<S: OriginalLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        twoAxes: Bool,multi: Bool=false,nonmonotone: Bool=false,constant: Bool=false) throws {
        var a=try LiftAdmission();let f=family.field,l=try limits(),c=try cover(family,using:&a)
        try LiftChecks.require(c.enclosingSupport.arity==1 && c.surfaceCycleRank==(twoAxes ? 2:1))
        try LiftChecks.require(c.templateCount==family.templateCount)
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let uv=constant ? 3.0:nonmonotone ? -3+18*t*(1-t):-3+9*t
            let tuple=[try f.binary64(exactly:t,using:&a),try f.binary64(exactly:uv,using:&a),try f.binary64(exactly:twoAxes ? uv:0.5,using:&a)]
            let found=try generic(c,at:tuple,using:&a)
            let boundary=uv.rounded(.towardZero)==uv
            try LiftChecks.require(found.count==(boundary ? (twoAxes ? 4:2):1))
            for occurrence in found {
                try occurrence.relation.admitProof(limits:l,using:&a)
                try LiftChecks.require(occurrence.relation.graph.layout.parameters == [0] && occurrence.relation.graph.layout.auxiliaries == [1,2])
                try LiftChecks.require(occurrence.relation.request.contains([tuple[0]],limits:l,using:&a))
                try LiftChecks.require(occurrence.relation.graph.admits(tuple,limits:l.source,using:&a))
                let again=try c.member(template:occurrence.template,cycles:occurrence.cycles,limits:l,using:&a)
                try LiftChecks.require(again.relation.graph.admits(tuple,limits:l.source,using:&a))
            }
            var wrong=tuple;wrong[1]=try f.adding(wrong[1],f.integer(3,using:&a),using:&a)
            try LiftChecks.require(c.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        }
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a),twoThirds=try f.multiplying(third,f.integer(2,using:&a),using:&a)
        let knot=[third,zero,twoAxes ? zero:half]
        if multi { try LiftChecks.require(c.liftedPositionIncidents(at:knot,limits:l,using:&a).count==(twoAxes ? 8:4)) }
        if !constant && !nonmonotone {
            let issuer=DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S>(),space=c.space
            func interval(_ low: OriginalExactScalar,_ high: OriginalExactScalar,closed: Bool=true) throws -> ExactParameterInterval<OriginalExactScalar> {
                try .checked(field:f,lower:.finite(low),upper:.finite(high),includesLower:closed,includesUpper:closed,depth:.init(value:0,coefficient:0),using:&a)
            }
            let strict=try issuer.issue(space:space,request:space.frame.selection(intervals:[[interval(third,twoThirds,closed:false)]],limits:l,using:&a),limits:l,using:&a)
            try LiftChecks.require(strict.liftedPositionIncidents(at:knot,limits:l,using:&a).isEmpty)
            let middle=[half,try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:twoAxes ? 1.5:0.5,using:&a)]
            try LiftChecks.require(strict.liftedPositionIncidents(at:middle,limits:l,using:&a).count==1)
            let singleton=try issuer.issue(space:space,request:space.frame.selection(intervals:[[interval(third,third)]],limits:l,using:&a),limits:l,using:&a)
            try LiftChecks.require(singleton.liftedPositionIncidents(at:knot,limits:l,using:&a).count==(multi ? (twoAxes ? 8:4):(twoAxes ? 4:2)))
            let pieces=try issuer.issue(space:space,request:space.frame.selection(intervals:[[interval(zero,third),interval(twoThirds,one)]],limits:l,using:&a),limits:l,using:&a)
            try LiftChecks.require(pieces.liftedPositionIncidents(at:middle,limits:l,using:&a).isEmpty)
            let outside=try issuer.issue(space:space,request:space.frame.selection(intervals:[[interval(f.integer(2,using:&a),f.integer(3,using:&a))]],limits:l,using:&a),limits:l,using:&a)
            try LiftChecks.require(outside.effectiveEnclosure.isEmpty && outside.liftedPositionIncidents(at:knot,limits:l,using:&a).isEmpty)
        }
        print("PASS periodic lift DI complete incidents, original T/UV roles, exact requests and wrong-UV exclusion")
    }
    nonisolated static func resources<S: OriginalLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        foreign: OriginalPeriodicNativeSurfaceLiftGraphs<S>) throws {
        let issuer=DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S>(),l=try limits()
        var measured=try LiftAdmission();let space=try issuer.prepare(family:family,limits:l,using:&measured)
        var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try issuer.prepare(family:family,limits:l,using:&exact)
        var work=try LiftAdmission(work:measured.ledger.work-1)
        try budgetFailure { _=try issuer.prepare(family:family,limits:l,using:&work) }
        var storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
        try budgetFailure { _=try issuer.prepare(family:family,limits:l,using:&storage) }
        for at in [1,measured.storageCalls] {
            var cancelled=try LiftAdmission(cancelAt:at)
            try budgetFailure { _=try issuer.prepare(family:family,limits:l,using:&cancelled) }
        }
        var a=try LiftAdmission();let full=try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let f=family.field,tuple=[try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:0.5,using:&a)]
        let empty=try issuer.issue(space:space,request:space.frame.selection(intervals:[[]],limits:l,using:&a),limits:l,using:&a)
        for c in [full,empty] {
            var measured=try LiftAdmission();_=try c.liftedPositionIncidents(at:tuple,limits:l,using:&measured)
            var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
            _=try c.liftedPositionIncidents(at:tuple,limits:l,using:&exact)
            var work=try LiftAdmission(work:measured.ledger.work-1)
            try budgetFailure { _=try c.liftedPositionIncidents(at:tuple,limits:l,using:&work) }
            var storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
            try budgetFailure { _=try c.liftedPositionIncidents(at:tuple,limits:l,using:&storage) }
            var entry=try LiftAdmission();entry.ledger.cancel()
            try budgetFailure { _=try c.liftedPositionIncidents(at:tuple,limits:l,using:&entry) }
            for at in [1,measured.storageCalls] {
                var cancelled=try LiftAdmission(cancelAt:at)
                try budgetFailure { _=try c.liftedPositionIncidents(at:tuple,limits:l,using:&cancelled) }
            }
            do { _=try c.liftedPositionIncidents(at:[tuple[0]],limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
            catch OriginalDomainIdentityFailure.invalidDomain {}
        }
        let other=try issuer.prepare(family:foreign,limits:l,using:&a)
        do { _=try issuer.issue(space:space,request:other.frame.fullSelection(limits:l,using:&a),limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        let q=ExactRationalScalarDomain(),z=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        do { _=try full.member(template:full.templateCount,cycles:[z,z],limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _=try full.member(template:0,cycles:[z],limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _=try full.liftedPositionIncidents(at:tuple,limits:limits(families:0),using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.familyLimit {}
        do { _=try issuer.prepare(family:family,limits:limits(charts:family.templateCount-1),using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.source(.chartLimit) {}
        do { _=try full.liftedPositionIncidents(at:tuple,limits:limits(source:0),using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.source(.sourceDepthLimit) {}
        do { _=try issuer.prepare(family:family,limits:limits(transport:0),using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        let alien=try foreignField(using:&a),bad=try alien.generator(using:&a)
        for c in [full,empty] { for index in 0..<3 {
            var invalid=tuple;invalid[index]=bad
            do { _=try c.liftedPositionIncidents(at:invalid,limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
            catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        } }
        print("PASS periodic lift DI exact resources, entry/intermediate/final cancel, invalid/foreign fields/owners and independent limits")
    }
    struct RootPreparation: RationalAlgebraAdmitting {
        mutating func consumeExactWork(_ count: Int) throws { guard count>=0 else { throw ExactScalarFailure.invalidEvidence } }
        mutating func retainExactStorage(_ count: Int) throws { guard count>=0 else { throw ExactScalarFailure.invalidEvidence } }
        mutating func visitExactCell(depth: Int) throws { guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) } }
        mutating func visitCoefficientCell(depth: Int) throws { guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) } }
    }
    nonisolated static func foreignField(using a: inout LiftAdmission) throws -> OriginalExactScalarDomain {
        var u=RootPreparation()
        let p=try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&u)
            .subtracting(.constant(.originalDouble(2,usage:&u),usage:&u),usage:&u)
        let roots=try ExactUnivariateRootIsolator().isolate(p,lower:.one,upper:.originalDouble(2,usage:&u),maximumDepth:32,usage:&u)
        try LiftChecks.require(roots.count==1)
        let root=try ExactAlgebraicRealRoot(polynomial:p,isolation:roots[0],usage:&u)
        return try .init(root:root,axis:.value,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
    }
    nonisolated static func huge<S: OriginalLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,twoAxes: Bool) throws {
        var a=try LiftAdmission();let c=try cover(family,using:&a),f=family.field,q=ExactRationalScalarDomain(),l=try limits()
        let cycle=try q.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let negative=try q.negated(cycle,using:&a),zero=try q.integer(0,using:&a)
        let cycles=[try OriginalParameterCycle(exact:cycle,using:&a),try OriginalParameterCycle(exact:twoAxes ? negative:zero,using:&a)]
        let u=try f.multiplying(f.rational(exactly:cycle,using:&a),f.integer(3,using:&a),using:&a)
        let tuple=[try f.binary64(exactly:0.5,using:&a),u,twoAxes ? try f.negated(u,using:&a):try f.binary64(exactly:0.5,using:&a)]
        let member=try c.member(template:0,cycles:cycles,limits:l,using:&a)
        try LiftChecks.require(member.relation.graph.admits(tuple,limits:l.source,using:&a))
        let found=try c.liftedPositionIncidents(at:tuple,limits:l,using:&a)
        try LiftChecks.require(found.count==(twoAxes ? 4:2))
        try LiftChecks.require(q.compare(member.cycles[0].original,cycle,using:&a) == .equal)
        // The returned occurrence remains valid after its preparation/cover scope ends.
        let retained=try detached(family,tuple:tuple)
        try retained.relation.admitProof(limits:l,using:&a)
        try LiftChecks.require(retained.relation.graph.admits(tuple,limits:l.source,using:&a))
        print("PASS periodic lift DI independent arbitrary-size positive/negative surface cycles and detached occurrence lifetime")
    }
    nonisolated static func detached<S: OriginalLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,tuple: [OriginalExactScalar]) throws -> OriginalPeriodicNativeSurfaceLiftChartOccurrence<S> {
        var a=try LiftAdmission();let c=try cover(family,using:&a)
        guard let result=try c.liftedPositionIncidents(at:tuple,limits:limits(),using:&a).first else { throw LiftChecks.Failure(line:#line) }
        return result
    }
}
