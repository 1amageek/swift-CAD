import L0
import DI0
import DI
import SourceIssuer

/// Exact rational arithmetic with an observable retained source-depth requirement.
struct IdentityDepthField: ExactScalarArithmetic, ExactScalarOrdering {
    struct Value: Sendable {
        let rational: ExactRationalCoefficient
        let depth: Int
    }
    let q = ExactRationalScalarDomain()
    let usesCoefficientDepth: Bool
    init(usesCoefficientDepth: Bool = false) { self.usesCoefficientDepth = usesCoefficientDepth }
    func require<A: ExactScalarAdmission & ~Copyable>(_ value: Value,_ a: inout A) throws(ExactScalarFailure) {
        try a.admitDepth(value:usesCoefficientDepth ? 0:value.depth,coefficient:usesCoefficientDepth ? value.depth:0)
    }
    func value<A: ExactScalarAdmission & ~Copyable>(_ number: ExactRationalCoefficient,_ a: inout A) throws(ExactScalarFailure) -> Value {
        // Only the retained offset needs depth7; cancellation to another value loses that requirement.
        let five = try q.integer(5,using:&a)
        let absolute = try q.sign(of:number,using:&a) == .negative ? q.negated(number,using:&a):number
        let depth = try q.compare(absolute,five,using:&a) == .equal ? 7:0
        let result = Value(rational:number,depth:depth)
        try require(result,&a);return result
    }
    func integer<I: BinaryInteger,A: ExactScalarAdmission & ~Copyable>(_ source: I,using a: inout A) throws(ExactScalarFailure) -> Value {
        let depth = source == 5 ? 7:0
        let result = Value(rational:try q.integer(source,using:&a),depth:depth)
        try require(result,&a);return result
    }
    func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double,using a: inout A) throws(ExactScalarFailure) -> Value {
        try value(q.binary64(exactly:source,using:&a),&a)
    }
    func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> Value {
        try require(value,&a)
        return .init(rational:try q.negated(value.rational,using:&a),depth:value.depth)
    }
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value,_ rhs: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> Value {
        try require(lhs,&a);try require(rhs,&a);return try value(q.adding(lhs.rational,rhs.rational,using:&a),&a)
    }
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value,_ rhs: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> Value {
        try require(lhs,&a);try require(rhs,&a);return try value(q.subtracting(lhs.rational,rhs.rational,using:&a),&a)
    }
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value,_ rhs: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> Value {
        try require(lhs,&a);try require(rhs,&a);return try value(q.multiplying(lhs.rational,rhs.rational,using:&a),&a)
    }
    func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value,_ rhs: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> Value {
        try require(lhs,&a);try require(rhs,&a);return try value(q.dividing(lhs.rational,rhs.rational,using:&a),&a)
    }
    func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> ExactSign {
        try require(value,&a);return try q.sign(of:value.rational,using:&a)
    }
    func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value,_ rhs: borrowing Value,using a: inout A) throws(ExactScalarFailure) -> ExactOrder {
        try require(lhs,&a);try require(rhs,&a);return try q.compare(lhs.rational,rhs.rational,using:&a)
    }
}

enum AffineIdentityDepthFixtures {
    static func cancellationReadmission() throws {
        for coefficient in [false,true] {
        var a = try TransportFixtures.admission()
        let f = IdentityDepthField(usesCoefficientDepth:coefficient),l = try TransportFixtures.limits(),source = try TransportFixtures.binding(true)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,IdentityDepthField>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let child = try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let cycle = try OriginalParameterCycle(exact:ExactRationalScalarDomain().integer(1,using:&a),using:&a)
        let original = try DefaultOriginalParameterIdentityIssuer<NativeSnapshot,IdentityDepthField>().periodic(cover:child,from:child.effective,axis:0,cycle:cycle,limits:l,using:&a)
        typealias Parent = ComposedDomainFixtures.Image<NativeSnapshot>
        let parentSource = try ComposedDomainFixtures.bind(Parent(originalChild:source,gains:[1],offsets:[5],axes:[0]),depth:1,using:&a)
        let cover = try DefaultOriginalParameterImageDomainIssuer<Parent,OriginalBSplineDomainCover<NativeSnapshot,IdentityDepthField>>().issue(source:parentSource,child:child,limits:l,using:&a)
        let proof = try DefaultOriginalAffineChildParameterIdentityIssuer<Parent,OriginalBSplineDomainCover<NativeSnapshot,IdentityDepthField>>().lifted(original,through:cover,limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<Parent,IdentityDepthField>()
        let symmetric = try ids.symmetric(proof,limits:l,using:&a)
        let composed = try ids.compose(proof,symmetric,limits:l,using:&a)
        for receipt in [proof,symmetric,composed] {
            try TransportFixtures.require(receipt.evidenceDepth.value < 7)
            var exact = ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:100_000_000,valueDepth:coefficient ? 32:7,coefficientDepth:coefficient ? 7:32))
            _ = try ids.relation(of:receipt,limits:l,using:&exact)
            var shallow = ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:100_000_000,valueDepth:coefficient ? 32:6,coefficientDepth:coefficient ? 6:32))
            do { _ = try ids.relation(of:receipt,limits:l,using:&shallow); throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.valueDepth)) {}
            catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        }
        }
        print("PASS affine identity retained depth: coefficient cancellation cannot bypass independent original value/coefficient depth7, including symmetry/transitive composition")
    }
}
