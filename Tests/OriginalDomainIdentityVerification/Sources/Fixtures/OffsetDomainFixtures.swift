import L0
import L1
import DI0
import DI
import SourceIssuer

public enum OffsetDomainFixtures {
    struct Source: OriginalOffsetSourceReading {
        let originalChild: OriginalSourceBinding<NativeSnapshot>
        let originalDistance: Double
    }
    typealias Family = OriginalFiniteNativeOffsetLawFamily<Source>
    static func family(kink: Bool = false,distance: Double = 0.25) throws -> Family {
        var a = try TransportFixtures.admission();let l = try TransportFixtures.limits()
        let input = kink ? NativeInput(degrees:[1,1],knots:[[0,0,0.5,1,1],[0,0,1,1]],counts:[3,2],
            controls:[[0,0,0],[1,0,0],[2,0,1],[0,1,0],[1,1,0],[2,1,1]],weights:[1,1,1,1,1,1],periodic:[false,false])
            : NativeInput(degrees:[1,2],knots:[[0,0,1,1],[-1,-1,-1,1,1,1]],counts:[2,3],
                controls:[[0,1,0],[1,1,0],[0,-1,0],[1,-1,0],[0,1,0],[1,1,0]],weights:[1,1,1,1,1,1],periodic:[false,false])
        let child = try IdentityFixtures.bind(input,&a)
        let f = try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let charts = try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:child,field:f,
            maximumCharts:2,limits:l.source,using:&a)
        let source = try ComposedDomainFixtures.bind(Source(originalChild:child,originalDistance:distance),depth:1,using:&a)
        return try DefaultOriginalFiniteNativeOffsetLawPreparer<Source>().prepare(source:source,child:charts,
            maximumCharts:2,limits:l.source,using:&a)
    }
    static func prepared(_ family: Family,_ a: inout ExactScalarLedger) throws -> OriginalNativeOffsetDomainCover<Source> {
        let issuer = DefaultOriginalNativeOffsetDomainIssuer<Source>(),l = try TransportFixtures.limits()
        let frame = try issuer.frame(family:family,limits:l,using:&a)
        return try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
    }
    static func position<P: OriginalGuardedChartFamilyQuerying>(_ p: P,_ tuple: [P.Field.Value],
        _ l: OriginalDomainIdentityLimits,_ a: inout ExactScalarLedger) throws -> Int {
        try p.positionIncidents(at:tuple,limits:l,using:&a).count
    }
    public static func guardedCoverageAndOwnership() throws {
        let family = try family();var a = try TransportFixtures.admission()
        let cover = try prepared(family,&a),f = family.field,l = try TransportFixtures.limits()
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a),half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let negative = try f.negated(half,using:&a)
        try TransportFixtures.require(cover.enclosingSupport.contains([half,zero],limits:l,using:&a))
        try TransportFixtures.require(position(cover,[half,zero],l,&a) == 0)
        for v in [half,negative] {
            try TransportFixtures.require(position(cover,[half,v],l,&a) == 1)
            try TransportFixtures.require(cover.liftedPositionIncidents(at:[half,v,one],limits:l,using:&a).count == 1)
            try TransportFixtures.require(cover.liftedPositionIncidents(at:[half,v,f.negated(one,using:&a)],limits:l,using:&a).isEmpty)
            try TransportFixtures.require(cover.liftedPositionIncidents(at:[half,v,f.integer(2,using:&a)],limits:l,using:&a).isEmpty)
        }
        let zeroDistance = try Self.family(distance:0)
        let zf = zeroDistance.field
        let zhalf = try zf.dividing(zf.integer(1,using:&a),zf.integer(2,using:&a),using:&a)
        try TransportFixtures.require(prepared(zeroDistance,&a).positionIncidents(at:[zhalf,zf.integer(0,using:&a)],limits:l,using:&a).isEmpty)
        let kink = try prepared(Self.family(kink:true),&a)
        let kf = kink.family.field
        let khalf = try kf.dividing(kf.integer(1,using:&a),kf.integer(2,using:&a),using:&a)
        let atKnot = try kink.positionIncidents(at:[khalf,khalf],limits:l,using:&a)
        try TransportFixtures.require(kink.templateCount == 2 && atKnot.count == 1 && atKnot[0].template == 1)
        let nonowning = try kink.member(template:0,limits:l,using:&a)
        try TransportFixtures.require(nonowning.enclosingSelection.contains([khalf,khalf],limits:l,using:&a) && !nonowning.law.ownsUpperBoundary[0])
        let issuer = DefaultOriginalNativeOffsetDomainIssuer<Source>(),frame = cover.enclosingSupport.frame
        let pointInterval = try ExactParameterInterval<OriginalExactScalar>.checked(field:f,lower:.finite(half),upper:.finite(half),depth:.init(value:0,coefficient:0),using:&a)
        let singleton = try frame.selection(intervals:[[pointInterval],[pointInterval]],limits:l,using:&a)
        let selected = try issuer.issue(request:singleton,family:family,limits:l,using:&a)
        try TransportFixtures.require(selected.positionIncidents(at:[half,half],limits:l,using:&a).count == 1)
        try TransportFixtures.require(selected.positionIncidents(at:[half,negative],limits:l,using:&a).isEmpty)
        let outsideInterval = try ExactParameterInterval<OriginalExactScalar>.checked(field:f,lower:.finite(f.integer(100,using:&a)),upper:.finite(f.integer(101,using:&a)),depth:.init(value:0,coefficient:0),using:&a)
        let empty = try issuer.issue(request:frame.selection(intervals:[[outsideInterval],[outsideInterval]],limits:l,using:&a),family:family,limits:l,using:&a)
        try TransportFixtures.require(empty.effectiveEnclosure.isEmpty && empty.positionIncidents(at:[half,half],limits:l,using:&a).isEmpty)
        print("PASS guarded offset domain: enclosure differs from exact material, signed branches, positive-q relation, zero-distance singular exclusion, canonical knot ownership, singleton/empty request and retained source lifetime")
    }
    static func resource(_ failure: OriginalDomainIdentityFailure,_ budget: ExactResource) throws {
        let actual: ExactResource
        switch failure {
        case .scalar(.resourceLimit(let b)),.domain(.scalar(.resourceLimit(let b))),.polynomial(.scalar(.resourceLimit(let b))),
            .source(.scalar(.resourceLimit(let b))),.source(.polynomial(.scalar(.resourceLimit(let b)))): actual = b
        default: throw failure
        }
        try TransportFixtures.require(actual == budget)
    }
    public static func guardedFailures() throws {
        let family = try family();var a = try TransportFixtures.admission()
        let cover = try prepared(family,&a),f = family.field,l = try TransportFixtures.limits(),issuer = DefaultOriginalNativeOffsetDomainIssuer<Source>()
        let half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),zero = try f.integer(0,using:&a),tuple = [half,half]
        do { _ = try cover.positionIncidents(at:[half],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.member(template:1,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.positionIncidents(at:tuple,limits:TransportFixtures.limits(charts:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _ = try issuer.issue(request:cover.request,family:Self.family(),limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        do { _ = try cover.positionIncidents(at:tuple,limits:TransportFixtures.limits(sourceDepth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.source(.sourceDepthLimit) {}
        var measured = try TransportFixtures.admission();_ = try cover.positionIncidents(at:tuple,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try cover.positionIncidents(at:tuple,limits:l,using:&exact)
        var shortWork = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try cover.positionIncidents(at:tuple,limits:l,using:&shortWork);throw ExactScalarFailure.invalidEvidence }
        catch let failure as OriginalDomainIdentityFailure { try resource(failure,.work) }
        var shortStorage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try cover.positionIncidents(at:tuple,limits:l,using:&shortStorage);throw ExactScalarFailure.invalidEvidence }
        catch let failure as OriginalDomainIdentityFailure { try resource(failure,.storage) }
        for point in [tuple,[half,zero]] {
            var baseline = try TerminalAdmission();_ = try cover.positionIncidents(at:point,limits:l,using:&baseline)
            var terminal = try TerminalAdmission();terminal.cancelAt = baseline.checks
            do { _ = try cover.positionIncidents(at:point,limits:l,using:&terminal);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        }
        var cancelled = try TransportFixtures.admission();cancelled.cancel()
        do { _ = try cover.positionIncidents(at:tuple,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS guarded offset domain failures: foreign source, chart/source limits, malformed tuple/template, exact work/storage admission, success/exclusion terminal cancellation")
    }
}
