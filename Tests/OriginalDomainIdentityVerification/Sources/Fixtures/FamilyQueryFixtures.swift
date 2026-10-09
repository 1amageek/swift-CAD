import L0
import L1
import DI0
import DI
import SourceIssuer

/// Witness dispatch and retained correspondence are checked through the public
/// protocol rather than concrete extension-only calls.
public enum FamilyQueryFixtures {
    private static func count<C: OriginalChartFamilyQuerying,A: ExactScalarAdmission & ~Copyable>(
        _ cover: C,at tuple: [C.Field.Value],limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> Int {
        try cover.incident(at:tuple,limits:limits,using:&a).count
    }
    private static func member<C: OriginalChartFamilyQuerying,A: ExactScalarAdmission & ~Copyable>(
        _ cover: C,template: Int,cycles: [OriginalParameterCycle],limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> C.Occurrence {
        try cover.member(template:template,cycles:cycles,limits:limits,using:&a)
    }
    public static func witnessesAndInjection() throws {
        var a = try TransportFixtures.admission()
        let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let source = try TransportFixtures.binding(true)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try issuer.prepare(source:source,field:f,
            periodIssuer:DefaultOriginalBSplinePeriodIssuer<NativeSnapshot,ExactRationalScalarDomain>(),
            transporter:DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>(),
            coverIssuer:DefaultOriginalDomainCoverIssuer<NativeSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
        let cover = try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),
            transporter:DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>(),
            coverIssuer:DefaultOriginalDomainCoverIssuer<NativeSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
        try TransportFixtures.require(cover.templateCount == 2 && cover.integerFamilyRank == 1 && !cover.support.isEmpty)
        try TransportFixtures.require(count(cover,at:[f.integer(0,using:&a)],limits:l,using:&a) == 2)
        let huge = try f.canonical(sign:-1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let cycle = try OriginalParameterCycle(exact:huge,using:&a)
        let occurrence = try member(cover,template:0,cycles:[cycle],limits:l,using:&a)
        try TransportFixtures.require(occurrence.cycles.count == 1 && f.compare(occurrence.cycles[0].original,huge,using:&a) == .equal)
        let foreign = try TransportFixtures.binding(true)
        let foreignPeriod = try DefaultOriginalBSplinePeriodIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(
            source:foreign,axis:0,field:f,limits:l.source,using:&a)
        do {
            _ = try issuer.prepare(source:source,field:f,periodIssuer:RetainedForeignPeriod(proof:foreignPeriod),
                transporter:DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>(),
                coverIssuer:DefaultOriginalDomainCoverIssuer<NativeSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalDomainIdentityFailure.foreignOwner {}
        do {
            _ = try issuer.prepare(source:source,field:f,periodIssuer:RejectedPeriod(),
                transporter:DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>(),
                coverIssuer:DefaultOriginalDomainCoverIssuer<NativeSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalDomainIdentityFailure.source(.invalidSource) {}
        do {
            _ = try DefaultOriginalDomainBoundBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(
                cover:cover,template:0,cycles:[cycle],sourceIssuer:RejectedChart(),
                transporter:DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalDomainIdentityFailure.source(.invalidChart) {}
        let nonperiod = try TransportFixtures.binding()
        let finiteSpace = try issuer.prepare(source:nonperiod,field:f,limits:l,using:&a)
        let finite = try issuer.issue(space:finiteSpace,request:finiteSpace.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let zero = try OriginalParameterCycle(exact:f.integer(0,using:&a),using:&a)
        _ = try member(finite,template:0,cycles:[zero],limits:l,using:&a)
        try TransportFixtures.require(finite.integerFamilyRank == 0 && count(finite,at:[f.integer(1,using:&a)],limits:l,using:&a) == 1)
        do { _ = try member(finite,template:0,cycles:[cycle],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try member(finite,template:1,cycles:[zero],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try member(finite,template:0,cycles:[],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        var emptyBudget = try TransportFixtures.admission(work:0)
        do { _ = try count(cover,at:[f.integer(0,using:&a)],limits:l,using:&emptyBudget); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}

        let sphereSource = try DefaultOriginalSourceBindingIssuer(provider:IntrinsicSphereProvider()).bind(
            IntrinsicSphereInput(center:[2,3,4],radius:5),limits:l.source,using:&a)
        let sphereIssuer = DefaultOriginalIntrinsicSphereDomainIssuer<IntrinsicSphereSnapshot,ExactRationalScalarDomain>()
        let frame = try sphereIssuer.frame(source:sphereSource,field:f,
            transporter:DefaultOriginalParameterTransporter<IntrinsicSphereSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
        let sphere = try sphereIssuer.issue(request:frame.fullSelection(limits:l,using:&a),
            sourceIssuer:DefaultOriginalIntrinsicSphereLawIssuer<IntrinsicSphereSnapshot,ExactRationalScalarDomain>(),
            transporter:DefaultOriginalParameterTransporter<IntrinsicSphereSnapshot,ExactRationalScalarDomain>(),limits:l,using:&a)
        let pole = try f.binary64(exactly:Double.pi * 0.5,using:&a)
        let longitude = try f.multiplying(huge,sphere.period.period,using:&a)
        try TransportFixtures.require(sphere.templateCount == 1 && sphere.integerFamilyRank == 1)
        try TransportFixtures.require(count(sphere,at:[longitude,pole],limits:l,using:&a) == 2)
        let lifted = try member(sphere,template:0,cycles:[cycle,zero],limits:l,using:&a)
        try TransportFixtures.require(lifted.transport.image.contains([longitude,pole],limits:l,using:&a))
        do { _ = try member(sphere,template:0,cycles:[zero,cycle],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let outside = try f.adding(pole,f.integer(1,using:&a),using:&a)
        try TransportFixtures.require(count(sphere,at:[longitude,outside],limits:l,using:&a) == 0)
        var baseline = try TerminalAdmission()
        _ = try count(sphere,at:[longitude,pole],limits:l,using:&baseline)
        var terminal = try TerminalAdmission(); terminal.cancelAt = baseline.checks
        do { _ = try count(sphere,at:[longitude,pole],limits:l,using:&terminal); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
    }
}

private struct RejectedPeriod: OriginalSourcePeriodIssuing {
    typealias Source = NativeSnapshot
    typealias Field = ExactRationalScalarDomain
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,axis: Int,
        field: Field,limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<Source,Field> { throw .invalidSource }
}
private struct RejectedChart: OriginalRationalChartIssuing {
    typealias Source = NativeSnapshot
    typealias Selection = OriginalBSplineChartSelection
    typealias Field = ExactRationalScalarDomain
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source,Selection>,field: borrowing Field,
        limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source,Selection,Field> { throw .invalidChart }
}

private struct RetainedForeignPeriod: OriginalSourcePeriodIssuing {
    typealias Source = NativeSnapshot
    typealias Field = ExactRationalScalarDomain
    let proof: OriginalSourcePeriodReceipt<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,axis: Int,
        field: Field,limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<Source,Field> { proof }
}
