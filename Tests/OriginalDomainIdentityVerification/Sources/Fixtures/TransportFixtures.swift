import L0
import DI0
import DI
import SourceIssuer

public enum TransportFixtures {
    static func limits(depth: Int = 16, charts: Int = 64, families: Int = 8, identities: Int = 64, sourceDepth: Int = 8) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:sourceDepth),maximumTransportDepth:depth,maximumCharts:charts,maximumFamilies:families,maximumIdentityProofs:identities)
    }
    static func admission(work: Int = 10_000_000, storage: Int = 100_000_000, valueDepth: Int = 32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:storage,valueDepth:valueDepth,coefficientDepth:32))
    }
    static func require(_ value: Bool) throws { if !value { throw ExactScalarFailure.invalidEvidence } }
    static func binding(_ periodic: Bool = false, sourceDepth: Int = 0) throws -> OriginalSourceBinding<NativeSnapshot> {
        var a = try admission()
        let input = NativeInput(degrees:[1],knots:[periodic ? [-1,0,1,2,3] : [0,0,1,1]],counts:[periodic ? 3 : 2],
            controls:periodic ? [[0,0,0],[1,0,0],[0,0,0]] : [[0,0,0],[1,0,0]],weights:periodic ? [1,1,1] : [1,1],periodic:[periodic],sourceDepth:sourceDepth)
        return try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:limits().source,using:&a)
    }
    static func interval(_ lo: Int, _ hi: Int, _ il: Bool = true, _ iu: Bool = true,
        using a: inout ExactScalarLedger) throws -> ExactParameterInterval<ExactRationalCoefficient> {
        let f = ExactRationalScalarDomain()
        return try .checked(field:f,lower:.finite(f.integer(lo,using:&a)),upper:.finite(f.integer(hi,using:&a)),includesLower:il,includesUpper:iu,
            depth:.init(value:0,coefficient:0),using:&a)
    }
    public static func affineAndComposition() throws {
        var a = try admission(); let f = ExactRationalScalarDomain(), l = try limits(), source = try binding()
        let t = DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>()
        let local = try t.frame(source:source,field:f,support:[[interval(0,2,false,true,using:&a)]],semantics:[.authoredScalar],limits:l,using:&a)
        let authored = try t.frame(source:source,field:f,support:[[interval(-3,3,using:&a)]],semantics:[.authoredScalar],limits:l,using:&a)
        let map = try t.affine(from:local.fullSelection(limits:l,using:&a),to:authored,permutation:[0],gains:[f.integer(-2,using:&a)],offsets:[f.integer(1,using:&a)],limits:l,using:&a)
        try require(map.image.axes[0].intervals[0].includesLower && !map.image.axes[0].intervals[0].includesUpper)
        let q = try t.forward([f.integer(1,using:&a)],through:map,limits:l,using:&a)
        try require(f.compare(q[0],f.integer(-1,using:&a),using:&a) == .equal)
        let inverse = try t.inverse(map,limits:l,using:&a)
        try require(f.compare(t.forward(q,through:inverse,limits:l,using:&a)[0],f.integer(1,using:&a),using:&a) == .equal)
        let composition = try t.compose(map,inverse,limits:l,using:&a)
        try require(f.compare(t.forward([f.integer(1,using:&a)],through:composition,limits:l,using:&a)[0],f.integer(1,using:&a),using:&a) == .equal)
        let selected = try local.selection(intervals:[[interval(1,1,using:&a)]],limits:l,using:&a)
        let restricted = try t.restrict(map,to:selected,limits:l,using:&a)
        try require(restricted.local.axes[0].intervalCount == 1)
        do { _ = try t.forward([f.integer(0,using:&a)],through:map,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.outsideSupport {}
        // Surface coordinates are permuted independently; the exact inverse returns both original axes.
        let two = try t.frame(source:source,field:f,support:[[interval(0,2,using:&a)],[interval(4,6,using:&a)]],semantics:[.authoredScalar,.authoredScalar],limits:l,using:&a)
        let output = try t.frame(source:source,field:f,support:[[interval(4,6,using:&a)],[interval(0,2,using:&a)]],semantics:[.authoredScalar,.authoredScalar],limits:l,using:&a)
        let permutation = try t.affine(from:two.fullSelection(limits:l,using:&a),to:output,permutation:[1,0],gains:[f.integer(1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(0,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        let result = try t.forward([f.integer(1,using:&a),f.integer(5,using:&a)],through:permutation,limits:l,using:&a)
        try require(f.compare(result[0],f.integer(5,using:&a),using:&a) == .equal && f.compare(result[1],f.integer(1,using:&a),using:&a) == .equal)
    }
    public static func periodsAndRefusal() throws {
        var a = try admission(); let f = ExactRationalScalarDomain(), l = try limits(), source = try binding(true)
        let prover = DefaultOriginalBSplinePeriodIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let period = try prover.issue(source:source,axis:0,field:f,limits:l.source,using:&a)
        try require(f.compare(period.period,f.integer(2,using:&a),using:&a) == .equal)
        let t = DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>()
        let fundamental = try t.frame(source:source,field:f,support:[[interval(0,2,using:&a)]],semantics:[.authoredScalar],limits:l,using:&a)
        let all = try ExactParameterInterval<ExactRationalCoefficient>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
        let authored = try t.frame(source:source,field:f,support:[[all]],semantics:[.authoredScalar],limits:l,using:&a)
        let big = try f.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let cycle = try OriginalParameterCycle(exact:big,using:&a)
        let lift = try t.periodicLift(from:fundamental.fullSelection(limits:l,using:&a),to:authored,period:period,cycle:cycle,limits:l,using:&a)
        let value = try t.forward([f.integer(1,using:&a)],through:lift.transport,limits:l,using:&a)[0]
        let displacement = try f.multiplying(big,period.period,using:&a)
        try require(f.compare(f.subtracting(value,displacement,using:&a),f.integer(1,using:&a),using:&a) == .equal)
        let inverse = try t.inverse(lift.transport,limits:l,using:&a)
        try require(f.compare(t.forward([value],through:inverse,limits:l,using:&a)[0],f.integer(1,using:&a),using:&a) == .equal)
        let negative = try OriginalParameterCycle(exact:f.integer(Int64.min,using:&a),using:&a)
        let negativeLift = try t.periodicLift(from:fundamental.fullSelection(limits:l,using:&a),to:authored,period:period,cycle:negative,limits:l,using:&a)
        try require(f.sign(of:t.forward([f.integer(0,using:&a)],through:negativeLift.transport,limits:l,using:&a)[0],using:&a) == .negative)
        let other = try binding(true)
        let foreign = try t.frame(source:other,field:f,support:[[all]],semantics:[.authoredScalar],limits:l,using:&a)
        do { _ = try t.periodicLift(from:fundamental.fullSelection(limits:l,using:&a),to:foreign,period:period,cycle:cycle,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        var bad = source.original.input; bad.controls[2][0] = 2
        let badBinding = try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(bad,limits:l.source,using:&a)
        do { _ = try prover.issue(source:badBinding,axis:0,field:f,limits:l.source,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.unresolvedAuthority {}
        let physical = try t.frame(source:source,field:f,support:[[all]],semantics:[.physicalRadian],limits:l,using:&a)
        do { _ = try t.affine(from:fundamental.fullSelection(limits:l,using:&a),to:physical,permutation:[0],gains:[f.integer(1,using:&a)],offsets:[f.integer(0,using:&a)],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.incompatibleCoordinateSemantics {}
        do { _ = try t.affine(from:fundamental.fullSelection(limits:l,using:&a),to:authored,permutation:[0],gains:[f.integer(0,using:&a)],offsets:[f.integer(0,using:&a)],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.singularTransport {}
        let shallow = try limits(depth:0)
        do { _ = try t.forward([f.integer(1,using:&a)],through:lift.transport,limits:shallow,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        var noWork = try admission(work:0)
        do { _ = try t.forward([value],through:inverse,limits:l,using:&noWork); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var noStorage = try admission(storage:0)
        do { _ = try t.forward([value],through:inverse,limits:l,using:&noStorage); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.storage)) {}
        var cancelled = try admission(); cancelled.cancel()
        do { _ = try t.forward([value],through:inverse,limits:l,using:&cancelled); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
    }
}
