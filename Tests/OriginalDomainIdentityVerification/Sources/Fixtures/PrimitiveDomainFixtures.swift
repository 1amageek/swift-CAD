import L0
import L1
import DI0
import DI
import SourceIssuer

struct WholeLineInput: OriginalLinearSourceReading {
    let origin: [Double]
    let direction: [Double]
    func originCoordinate(in axis: Int) -> Double { origin[axis] }
    func directionCoordinate(in axis: Int) -> Double { direction[axis] }
}
struct WholeLineProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing WholeLineInput,limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<WholeLineInput> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard input.origin.count == 3,input.direction.count == 3 else { throw OriginalSourceIssuanceFailure.invalidSource }
            for i in 0..<3 { try a.consumeWork(1); guard input.origin[i].isFinite,input.direction[i].isFinite else { throw OriginalSourceIssuanceFailure.invalidSource } }
            return .init(original:copy input,sourceDepth:0)
        } catch let e as OriginalSourceIssuanceFailure { throw e }
        catch let e as ExactScalarFailure { throw .scalar(e) }
        catch { throw .sourceRejected(error) }
    }
}
public enum PrimitiveDomainFixtures {
    public static func wholeLineAndPlane() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let source = try DefaultOriginalSourceBindingIssuer(provider:WholeLineProvider()).bind(
            WholeLineInput(origin:[1,2,3],direction:[2,-1,4]),limits:l.source,using:&a)
        let issuer = DefaultOriginalLinearDomainIssuer<WholeLineInput,ExactRationalScalarDomain>()
        let frame = try issuer.frame(source:source,field:f,limits:l,using:&a)
        let cover = try issuer.issue(request:frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let far = try f.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let point = try cover.law.position(at:far,limits:l.source,using:&a)
        try TransportFixtures.require(f.compare(point[0],f.adding(f.integer(1,using:&a),f.multiplying(f.integer(2,using:&a),far,using:&a),using:&a),using:&a) == .equal)
        try TransportFixtures.require(cover.integerFamilyRank == 0 && cover.templateCount == 1)
        try TransportFixtures.require(cover.incident(at:[far],limits:l,using:&a).count == 1)
        let negative = try f.negated(far,using:&a)
        try TransportFixtures.require(cover.incident(at:[negative],limits:l,using:&a).count == 1)
        let zero = try OriginalParameterCycle(exact:f.integer(0,using:&a),using:&a)
        let one = try OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a)
        do { _ = try cover.member(template:0,cycles:[one],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.member(template:0,cycles:[],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        _ = try cover.member(template:0,cycles:[zero],limits:l,using:&a)
        let selected = try frame.selection(intervals:[[TransportFixtures.interval(0,2,false,true,using:&a)]],limits:l,using:&a)
        let restricted = try issuer.issue(request:selected,limits:l,using:&a)
        try TransportFixtures.require(restricted.incident(at:[f.integer(0,using:&a)],limits:l,using:&a).isEmpty)
        try TransportFixtures.require(restricted.incident(at:[f.integer(2,using:&a)],limits:l,using:&a).count == 1)
        let empty = try frame.selection(intervals:[[]],limits:l,using:&a)
        let emptyCover = try issuer.issue(request:empty,limits:l,using:&a)
        try TransportFixtures.require(emptyCover.effective.isEmpty && emptyCover.incident(at:[far],limits:l,using:&a).isEmpty)
        let invalid = try DefaultOriginalSourceBindingIssuer(provider:WholeLineProvider()).bind(
            WholeLineInput(origin:[0,0,0],direction:[0,0,0]),limits:l.source,using:&a)
        let invalidFrame = try issuer.frame(source:invalid,field:f,limits:l,using:&a)
        do { _ = try issuer.issue(request:invalidFrame.fullSelection(limits:l,using:&a),limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.source(.invalidSource) {}

        let planeSource = try DefaultOriginalSourceBindingIssuer(provider:PlaneProvider()).bind(
            PlaneInput(origin:[2,3,4],normal:[3,4,0]),limits:l.source,using:&a)
        let basisIssuer = DefaultOriginalPlaneBasisIssuer<PlaneInput,ExactRationalScalarDomain>()
        let basis = try basisIssuer.issue(source:planeSource,field:f,firstLength:f.integer(4,using:&a),normalLength:f.integer(5,using:&a),limits:l.source,using:&a)
        let planeIssuer = DefaultOriginalPlaneDomainIssuer<PlaneInput,ExactRationalScalarDomain>()
        let planeFrame = try planeIssuer.frame(basis:basis,limits:l,using:&a)
        let planeCover = try planeIssuer.issue(request:planeFrame.fullSelection(limits:l,using:&a),basis:basis,limits:l,using:&a)
        try TransportFixtures.require(planeCover.incident(at:[far,negative],limits:l,using:&a).count == 1)
        let xyz = try planeCover.law.position(u:far,v:negative,limits:l,using:&a)
        let uv = try planeCover.law.parameters(of:xyz,limits:l,using:&a)
        try TransportFixtures.require(f.compare(uv[0],far,using:&a) == .equal && f.compare(uv[1],negative,using:&a) == .equal)
        let foreign = try DefaultOriginalSourceBindingIssuer(provider:PlaneProvider()).bind(
            PlaneInput(origin:[2,3,4],normal:[3,4,0]),limits:l.source,using:&a)
        let foreignBasis = try basisIssuer.issue(source:foreign,field:f,firstLength:f.integer(4,using:&a),normalLength:f.integer(5,using:&a),limits:l.source,using:&a)
        do { _ = try planeIssuer.issue(request:planeFrame.fullSelection(limits:l,using:&a),basis:foreignBasis,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        var denied = try TransportFixtures.admission(work:0)
        do { _ = try cover.incident(at:[far],limits:l,using:&denied); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var cancelled = try TransportFixtures.admission(); cancelled.cancel()
        do { _ = try issuer.issue(request:selected,limits:l,using:&cancelled); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var noStorage = try TransportFixtures.admission(storage:0)
        do { _ = try issuer.issue(request:selected,limits:l,using:&noStorage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
    }
}
