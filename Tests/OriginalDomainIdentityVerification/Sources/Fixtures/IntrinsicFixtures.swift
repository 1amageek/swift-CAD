import L0
import DI0
import DI
import SourceIssuer

struct IntrinsicSphereInput: Sendable { var center: [Double]; var radius: Double }
struct IntrinsicSphereSnapshot: OriginalIntrinsicSphereSourceReading {
    let input: IntrinsicSphereInput
    var radius: Double { input.radius }
    func centerCoordinate(in axis: Int) -> Double { input.center[axis] }
}
struct IntrinsicSphereProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing IntrinsicSphereInput,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<IntrinsicSphereSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard input.center.count == 3,input.radius.isFinite,input.radius > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
            for x in input.center { try a.consumeWork(1); guard x.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource } }
            return .init(original:.init(input:copy input),sourceDepth:0)
        } catch let e as OriginalSourceIssuanceFailure { throw e }
        catch let e as ExactScalarFailure { throw .scalar(e) }
        catch { throw .sourceRejected(error) }
    }
}
public enum IntrinsicFixtures {
    public static func polesAndMeaning() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        var input = IntrinsicSphereInput(center:[2,3,4],radius:5)
        let source = try DefaultOriginalSourceBindingIssuer(provider:IntrinsicSphereProvider()).bind(input,limits:l.source,using:&a)
        input.center[2] = 99
        let issuer = DefaultOriginalIntrinsicSphereDomainIssuer<IntrinsicSphereSnapshot,ExactRationalScalarDomain>()
        let frame = try issuer.frame(source:source,field:f,limits:l,using:&a)
        let full = try frame.fullSelection(limits:l,using:&a)
        let cover = try issuer.issue(request:full,limits:l,using:&a)
        let quarter = try f.binary64(exactly:Double.pi * 0.5,using:&a)
        let latitude = try ExactParameterInterval.checked(field:f,lower:.finite(quarter),upper:.finite(quarter),depth:.init(value:0,coefficient:0),using:&a)
        let u = try ExactParameterInterval<ExactRationalCoefficient>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
        let pole = try frame.selection(intervals:[[u],[latitude]],limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<IntrinsicSphereSnapshot,ExactRationalScalarDomain>()
        let proof = try ids.intrinsicPole(cover:cover,on:pole,latitude:quarter,limits:l,using:&a)
        try TransportFixtures.require(proof.left.arity == 2 && ids.decide(proof,left:[f.integer(-100000,using:&a),quarter],right:[f.integer(100000,using:&a),quarter],limits:l,using:&a) == .proven)
        let cycle = try OriginalParameterCycle(exact:f.integer(3,using:&a),using:&a)
        let orbit = try ids.periodic(cover:cover,from:pole,cycle:cycle,limits:l,using:&a)
        let shiftedLongitude = try f.multiplying(f.integer(3,using:&a),cover.period.period,using:&a)
        try TransportFixtures.require(ids.decide(orbit,left:[f.integer(0,using:&a),quarter],right:[shiftedLongitude,quarter],limits:l,using:&a) == .proven)
        let narrow = try frame.selection(intervals:[[TransportFixtures.interval(0,0,using:&a)],[latitude]],limits:l,using:&a)
        let narrowCover = try issuer.issue(request:narrow,limits:l,using:&a)
        let narrowedOwners = try narrowCover.incident(at:[f.integer(0,using:&a),quarter],limits:l,using:&a)
        try TransportFixtures.require(narrowedOwners.count == 2)
        for owner in narrowedOwners {
            try TransportFixtures.require(!owner.transport.image.contains([f.integer(1,using:&a),quarter],limits:l,using:&a))
        }
        let sourceLaw = try DefaultOriginalIntrinsicSphereLawIssuer<IntrinsicSphereSnapshot,ExactRationalScalarDomain>().pole(source:source,latitude:quarter,field:f,limits:l.source,using:&a)
        try TransportFixtures.require(f.compare(sourceLaw.position[2],f.integer(9,using:&a),using:&a) == .equal)
        let near = try f.binary64(exactly:(Double.pi * 0.5).nextDown,using:&a)
        do { _ = try DefaultOriginalIntrinsicSphereLawIssuer<IntrinsicSphereSnapshot,ExactRationalScalarDomain>().pole(source:source,latitude:near,field:f,limits:l.source,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        try TransportFixtures.require(ids.decide(proof,left:[f.integer(0,using:&a),near],right:[f.integer(1,using:&a),near],limits:l,using:&a) == .notEstablished)
        let seam = try cover.incident(at:[f.integer(0,using:&a),quarter],limits:l,using:&a)
        try TransportFixtures.require(seam.count == 2)
        let t = DefaultOriginalParameterTransporter<IntrinsicSphereSnapshot,ExactRationalScalarDomain>()
        let physical = try t.frame(source:source,field:f,support:[[u],[latitude]],semantics:[.physicalRadian,.intrinsicAngularLabel],limits:l,using:&a)
        do { _ = try t.periodicLift(from:pole,to:physical,period:cover.period,cycle:OriginalParameterCycle(exact:f.integer(1,using:&a),using:&a),limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.incompatibleCoordinateSemantics {}
        var baseline = try TerminalAdmission()
        _ = try ids.decide(proof,left:[f.integer(0,using:&a),quarter],right:[f.integer(1,using:&a),quarter],limits:l,using:&baseline)
        var terminal = try TerminalAdmission(); terminal.cancelAt = baseline.checks
        do { _ = try ids.decide(proof,left:[f.integer(0,using:&a),quarter],right:[f.integer(1,using:&a),quarter],limits:l,using:&terminal); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
    }
    public static func sourceDomainHandoff() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits(),source = try TransportFixtures.binding(true)
        let domain = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try domain.prepare(source:source,field:f,limits:l,using:&a)
        let cover = try domain.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let producer = DefaultOriginalDomainBoundBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let huge = try f.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let cycle = try OriginalParameterCycle(exact:huge,using:&a)
        let chart = try producer.issue(cover:cover,template:0,cycles:[cycle],limits:l,using:&a)
        let authored = try f.adding(f.multiplying(huge,f.integer(2,using:&a),using:&a),f.integer(1,using:&a),using:&a)
        let point = try chart.position(at:[authored],limits:l,using:&a)
        try TransportFixtures.require(f.compare(point[0],f.integer(1,using:&a),using:&a) == .equal && f.sign(of:point[1],using:&a) == .zero)
        let singleton = try space.frame.selection(intervals:[[.checked(field:f,lower:.finite(authored),upper:.finite(authored),depth:.init(value:0,coefficient:0),using:&a)]],limits:l,using:&a)
        let restricted = try domain.issue(space:space,request:singleton,limits:l,using:&a)
        let selected = try producer.issue(cover:restricted,template:0,cycles:[cycle],limits:l,using:&a)
        do { _ = try selected.position(at:[f.subtracting(authored,f.integer(1,using:&a),using:&a)],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.outsideSupport {}
    }
}
