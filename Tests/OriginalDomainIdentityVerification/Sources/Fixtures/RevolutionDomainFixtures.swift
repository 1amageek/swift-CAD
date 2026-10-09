import L0
import L1
import DI0
import DI
import SourceIssuer

public enum RevolutionDomainFixtures {
    typealias F = ExactRationalScalarDomain
    struct Source: OriginalRevolutionSourceReading {
        let originalGenerator: OriginalSourceBinding<NativeSnapshot>
        let originalLowerU: Double = -2 * Double.pi
        let originalUpperU: Double = 2 * Double.pi
        func axisOriginCoordinate(in axis: Int) -> Double { 0 }
        func axisDirectionCoordinate(in axis: Int) -> Double { axis == 2 ? 2 : 0 }
    }
    typealias Family = OriginalFiniteRevolutionLawFamily<Source,OriginalBSplineChartSelection,F>
    static func family() throws -> Family {
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits()
        let input = NativeInput(degrees:[1],knots:[[0,0,0.5,1,1]],counts:[3],controls:[[0,0,0],[1,0,0],[2,0,0]],weights:[1,2,1],periodic:[false])
        let child = try IdentityFixtures.bind(input,&a)
        let space = try DefaultOriginalBSplineDomainIssuer<NativeSnapshot,F>().prepare(source:child,field:f,limits:l,using:&a)
        let source = try ComposedDomainFixtures.bind(Source(originalGenerator:child),depth:1,using:&a)
        var laws: [OriginalRationalChartReceipt<NativeSnapshot,OriginalBSplineChartSelection,F>] = []
        for chart in space.sourceCharts {
            laws.append(try DefaultOriginalBSplineChartIssuer<NativeSnapshot,F>().issue(source:child,chart:chart,field:f,limits:l.source,using:&a))
        }
        return try DefaultOriginalFiniteRevolutionLawPreparer<Source,OriginalBSplineChartSelection,F>().prepare(
            source:source,generators:laws,field:f,axisLength:f.integer(2,using:&a),maximumCharts:2,limits:l.source,using:&a)
    }
    public static func completeFamiliesAndGuards() throws {
        let family = try family()
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),issuer = DefaultOriginalRevolutionDomainIssuer<Source,OriginalBSplineChartSelection,F>()
        let frame = try issuer.frame(family:family,limits:l,using:&a)
        let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a),half = try f.dividing(one,f.integer(2,using:&a),using:&a)
        let incidents = try cover.incident(at:[zero,half],limits:l,using:&a)
        try TransportFixtures.require(incidents.count == 4 && cover.templateCount == 2 && cover.integerFamilyRank == 1)
        for item in incidents {
            try TransportFixtures.require(item.transport.image.contains([zero,half],limits:l,using:&a))
            try TransportFixtures.require(item.law.generator.chart.selection.spans == [item.template+1])
        }
        let pole = try cover.incident(at:[zero,zero],limits:l,using:&a)
        try TransportFixtures.require(pole.count == 2)
        for item in pole {
            try TransportFixtures.require(f.sign(of:item.law.polynomials.evaluated(item.law.radialSquaredNumerator,at:[one,zero,zero],using:&a).value,using:&a) == .zero)
            try TransportFixtures.require(f.sign(of:item.law.polynomials.evaluated(item.law.denominator,at:[one,zero,zero],using:&a).value,using:&a) == .positive)
        }
        let singleton = try frame.selection(intervals:[[TransportFixtures.interval(0,0,using:&a)],[.checked(field:f,lower:.finite(half),upper:.finite(half),depth:.init(value:0,coefficient:0),using:&a)]],limits:l,using:&a)
        let selected = try issuer.issue(request:singleton,family:family,limits:l,using:&a)
        try TransportFixtures.require(selected.incident(at:[zero,half],limits:l,using:&a).count == 4 && selected.effective.arity == 2)
        try TransportFixtures.require(selected.incident(at:[one,half],limits:l,using:&a).isEmpty)
        let outside = try frame.selection(intervals:[[TransportFixtures.interval(100,101,using:&a)],[TransportFixtures.interval(0,1,using:&a)]],limits:l,using:&a)
        let empty = try issuer.issue(request:outside,family:family,limits:l,using:&a)
        try TransportFixtures.require(empty.effective.isEmpty && empty.incident(at:[f.integer(100,using:&a),half],limits:l,using:&a).isEmpty)
        print("PASS complete revolution domain: retained weighted chart sides, closed U seam/V knot, singleton/empty clipping and collapsed-fiber denominator guards")
    }
    public static func admissionAndRefusal() throws {
        let family = try family()
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),issuer = DefaultOriginalRevolutionDomainIssuer<Source,OriginalBSplineChartSelection,F>()
        let frame = try issuer.frame(family:family,limits:l,using:&a)
        let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let zero = try OriginalParameterCycle(exact:f.integer(0,using:&a),using:&a)
        let nonzero = try OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a)
        do { _ = try cover.member(template:0,cycles:[zero,nonzero],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.member(template:0,cycles:[zero,zero],limits:TransportFixtures.limits(depth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        let tuple = try [f.integer(0,using:&a),f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)]
        do { _ = try cover.incident(at:tuple,limits:TransportFixtures.limits(charts:3),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _ = try cover.incident(at:tuple,limits:TransportFixtures.limits(families:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        let other = try Self.family()
        do { _ = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:other,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        var measured = try TransportFixtures.admission()
        _ = try cover.incident(at:tuple,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try cover.incident(at:tuple,limits:l,using:&exact)
        var shortWork = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try cover.incident(at:tuple,limits:l,using:&shortWork);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalDomainIdentityFailure.domain(.scalar(.resourceLimit(.work))) {}
        var shortStorage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try cover.incident(at:tuple,limits:l,using:&shortStorage);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalDomainIdentityFailure.domain(.scalar(.resourceLimit(.storage))) {}
        var cancelled = try TransportFixtures.admission();cancelled.cancel()
        do { _ = try cover.incident(at:tuple,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var baseline = try TerminalAdmission()
        _ = try cover.incident(at:tuple,limits:l,using:&baseline)
        var terminal = try TerminalAdmission();terminal.cancelAt = baseline.checks
        do { _ = try cover.incident(at:tuple,limits:l,using:&terminal);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS revolution domain source/cycle/chart/family/depth/work/storage/entry/terminal refusal")
    }
}
