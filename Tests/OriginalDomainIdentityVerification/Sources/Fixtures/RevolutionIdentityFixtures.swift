import L0
import L1
import DI0
import DI
import SourceIssuer

public enum RevolutionIdentityFixtures {
    typealias S = RevolutionDomainFixtures.Source
    typealias F = ExactRationalScalarDomain
    typealias Cover = OriginalRevolutionDomainCover<S,OriginalBSplineChartSelection,F>
    static func prepared(_ a: inout ExactScalarLedger) throws -> Cover {
        let family = try RevolutionDomainFixtures.family(),l = try TransportFixtures.limits()
        let issuer = DefaultOriginalRevolutionDomainIssuer<S,OriginalBSplineChartSelection,F>()
        let frame = try issuer.frame(family:family,limits:l,using:&a)
        return try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
    }
    static func throughProtocol<I: OriginalRevolutionParameterIdentityIssuing>(_ issuer: I,
        cover: OriginalRevolutionDomainCover<I.Source,OriginalBSplineChartSelection,I.Field>,cycle: OriginalParameterCycle,
        _ l: OriginalDomainIdentityLimits,_ a: inout ExactScalarLedger) throws -> OriginalParameterIdentity<I.Source,I.Field> {
        try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&a)
    }
    public static func scopedPeriodAndClipping() throws {
        var a = try TransportFixtures.admission();let cover = try prepared(&a),f = F(),l = try TransportFixtures.limits()
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>(),one = try OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a)
        let period = cover.family.period.period,zero = try f.integer(0,using:&a),half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        let receipt = try throughProtocol(issuer,cover:cover,cycle:one,l,&a)
        try TransportFixtures.require(issuer.decide(receipt,left:[zero,half],right:[period,half],limits:l,using:&a) == .proven)
        try TransportFixtures.require(receipt.left.contains([f.negated(period,using:&a),half],limits:l,using:&a))
        try TransportFixtures.require(!receipt.left.contains([period,half],limits:l,using:&a))
        try TransportFixtures.require(issuer.decide(receipt,left:[zero,half],right:[period,zero],limits:l,using:&a) == .refutedForThisRelation)
        let near = try f.subtracting(period,f.binary64(exactly:1e-15,using:&a),using:&a)
        try TransportFixtures.require(issuer.decide(receipt,left:[zero,half],right:[near,half],limits:l,using:&a) == .refutedForThisRelation)
        let negative = try issuer.periodic(cover:cover,from:cover.effective,
            cycle:OriginalParameterCycle(exact:f.integer(-1,using:&a),using:&a),limits:l,using:&a)
        try TransportFixtures.require(issuer.decide(negative,left:[period,half],right:[zero,half],limits:l,using:&a) == .proven)
        let empty = try issuer.periodic(cover:cover,from:cover.effective,
            cycle:OriginalParameterCycle(exact:f.integer(3,using:&a),using:&a),limits:l,using:&a)
        try TransportFixtures.require(empty.left.isEmpty && empty.right.isEmpty)
        // Structural angular identity does not collapse the retained original V fiber.
        try TransportFixtures.require(receipt.left.arity == 2 && receipt.right.arity == 2)
        print("PASS revolution source period identities: protocol query, finite clipping/empty overlap, negative cycles, exact original UV, distinct V and near-period refusal, retained source theorem")
    }
    public static func identityFailures() throws {
        var a = try TransportFixtures.admission();let cover = try prepared(&a),f = F(),l = try TransportFixtures.limits()
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>(),cycle = try OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a)
        let foreign = try prepared(&a)
        do { _ = try issuer.periodic(cover:cover,from:foreign.effective,cycle:cycle,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:TransportFixtures.limits(families:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:TransportFixtures.limits(identities:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.identityLimit {}
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:TransportFixtures.limits(depth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        var measured = try TransportFixtures.admission();_ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&measured)
        var exact = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&exact)
        var shortWork = try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&shortWork);throw ExactScalarFailure.invalidEvidence }
        catch let failure as OriginalDomainIdentityFailure { try OffsetDomainFixtures.resource(failure,.work) }
        var shortStorage = try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&shortStorage);throw ExactScalarFailure.invalidEvidence }
        catch let failure as OriginalDomainIdentityFailure { try OffsetDomainFixtures.resource(failure,.storage) }
        var cancelled = try TransportFixtures.admission();cancelled.cancel()
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var baseline = try TerminalAdmission();_ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&baseline)
        var terminal = try TerminalAdmission();terminal.cancelAt = baseline.checks
        do { _ = try issuer.periodic(cover:cover,from:cover.effective,cycle:cycle,limits:l,using:&terminal);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS revolution identity work/storage/source-owner/family/identity/depth/entry/terminal failures")
    }
}
