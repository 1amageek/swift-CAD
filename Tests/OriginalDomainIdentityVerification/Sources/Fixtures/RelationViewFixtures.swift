import L0
import L1
import DI0
import DI
import SourceIssuer

public enum RelationViewFixtures {
    typealias F = ExactRationalScalarDomain
    typealias S = NativeSnapshot
    static func coordinates<T: OriginalParameterAffineCoordinateQuerying,A: ExactScalarAdmission & ~Copyable>(
        _ query: T, _ map: OriginalParameterTransport<T.Source,T.Field>, using a: inout A
    ) throws -> OriginalParameterAffineCoordinates<T.Source,T.Field> {
        try query.affineCoordinates(of:map,limits:TransportFixtures.limits(),using:&a)
    }
    static func relation<T: OriginalParameterIdentityRelationQuerying,A: ExactScalarAdmission & ~Copyable>(
        _ query: T, _ receipt: OriginalParameterIdentity<T.Source,T.Field>, using a: inout A
    ) throws -> OriginalParameterIdentityRelation<T.Source,T.Field> {
        try query.relation(of:receipt,limits:TransportFixtures.limits(),using:&a)
    }
    static func retained() throws -> (OriginalParameterAffineCoordinates<S,F>,OriginalParameterIdentityRelation<S,F>) {
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),source = try TransportFixtures.binding(sourceDepth:3)
        let t = DefaultOriginalParameterTransporter<S,F>(),ids = DefaultOriginalParameterIdentityIssuer<S,F>()
        let local = try t.frame(source:source,field:f,
            support:[[TransportFixtures.interval(0,2,false,true,using:&a)],[TransportFixtures.interval(4,6,using:&a)]],
            semantics:[.authoredScalar,.authoredScalar],limits:l,using:&a)
        let output = try t.frame(source:source,field:f,
            support:[[TransportFixtures.interval(-11,-7,using:&a)],[TransportFixtures.interval(0,2,false,true,using:&a)]],
            semantics:[.authoredScalar,.authoredScalar],limits:l,using:&a)
        let map = try t.affine(from:local.fullSelection(limits:l,using:&a),to:output,
            permutation:[1,0],gains:[f.integer(-2,using:&a),f.integer(1,using:&a)],
            offsets:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        let same = try t.affine(from:output.fullSelection(limits:l,using:&a),to:output,
            permutation:[0,1],gains:[f.integer(1,using:&a),f.integer(1,using:&a)],
            offsets:[f.integer(0,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        let identity = try ids.authored(left:map,right:same,limits:l,using:&a)
        return try (coordinates(t,map,using:&a),relation(ids,identity,using:&a))
    }
    public static func affineWordsAndLifetime() throws {
        // All creating bindings, frames and receipts have left scope; views own their evidence.
        let (view,proof) = try retained()
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),ids = DefaultOriginalParameterIdentityIssuer<S,F>()
        let lhs = try [f.integer(1,using:&a),f.integer(5,using:&a)]
        let rhs = try [f.integer(-9,using:&a),f.integer(1,using:&a)]
        try TransportFixtures.require(view.permutation == [1,0] && proof.kind == .authoredCoordinate)
        try TransportFixtures.require(proof.left.contains(lhs,limits:l,using:&a) && proof.right.contains(rhs,limits:l,using:&a))
        guard case .affine(let p,let gains,let offsets) = proof.constraints else { throw ExactScalarFailure.invalidEvidence }
        // Consumer compiles the owner-issued entire relation, without sampling an inverse.
        let ring = try ExactPolynomialDomain(field:f,variableCount:4,using:&a)
        for i in p.indices {
            let mapped = try ring.adding(ring.scaled(ring.variable(p[i],using:&a),by:gains[i],using:&a),ring.constant(offsets[i],using:&a),using:&a)
            let equation = try ring.subtracting(ring.variable(2+i,using:&a),mapped,using:&a)
            try TransportFixtures.require(f.sign(of:ring.evaluated(equation,at:lhs+rhs,using:&a).value,using:&a) == .zero)
            let outside = try [f.integer(1,using:&a),f.integer(5,using:&a),f.integer(-8,using:&a),f.integer(1,using:&a)]
            if i == 0 { try TransportFixtures.require(f.sign(of:ring.evaluated(equation,at:outside,using:&a).value,using:&a) != .zero) }
        }
        try TransportFixtures.require(ids.decide(proof.receipt,left:lhs,right:rhs,limits:l,using:&a) == .proven)
        let excluded = try [f.integer(0,using:&a),f.integer(5,using:&a)]
        try TransportFixtures.require(!proof.left.contains(excluded,limits:l,using:&a))
        var changed = view.gains
        changed[0] = try f.integer(99,using:&a)
        try TransportFixtures.require(f.compare(view.gains[0],f.integer(-2,using:&a),using:&a) == .equal)
        try TransportFixtures.require(view.local.frame.source.sourceDepth == 3 && proof.evidenceSourceDepth == 3)
        print("PASS checked DI affine/relation view: original scope, polynomial constraints, reversed/permuted axes, COW and retained lifetime")
    }
    public static func completeProductsAndFailures() throws {
        var a = try TransportFixtures.admission()
        let f = F(),l = try TransportFixtures.limits(),ids = DefaultOriginalParameterIdentityIssuer<S,F>()
        let input = NativeInput(degrees:[1],knots:[[0,0,1,1]],counts:[2],controls:[[2,3,4],[2,3,4]],weights:[1,1],periodic:[false])
        let s = try IdentityFixtures.bind(input,&a)
        let space = try DefaultOriginalBSplineDomainIssuer<S,F>().prepare(source:s,field:f,limits:l,using:&a)
        let law = try DefaultOriginalBSplineChartIssuer<S,F>().issue(source:s,chart:space.sourceCharts[0],field:f,limits:l.source,using:&a)
        let scope = try space.frame.fullSelection(limits:l,using:&a)
        let collapse = try ids.collapsed(law:law,on:scope,limits:l,using:&a)
        let product = try relation(ids,collapse,using:&a)
        guard case .completeProduct = product.constraints else { throw ExactScalarFailure.invalidEvidence }
        for left in 0...1 { for right in 0...1 {
            try TransportFixtures.require(ids.decide(product.receipt,left:[f.integer(left,using:&a)],right:[f.integer(right,using:&a)],limits:l,using:&a) == .proven)
        } }
        try TransportFixtures.require(!product.left.contains([f.integer(2,using:&a)],limits:l,using:&a))
        let (view,proof) = try retained()
        let t = DefaultOriginalParameterTransporter<S,F>()
        // Reuse charges admission work, but never re-charges the retained coefficient payload.
        var direct = try TransportFixtures.admission(),queried = try TransportFixtures.admission()
        try t.admitted(view.transport,limits:l,using:&direct)
        _ = try coordinates(t,view.transport,using:&queried)
        try TransportFixtures.require(direct.work == queried.work && direct.storageBytes == queried.storageBytes)
        var exact = try TransportFixtures.admission(work:queried.work,storage:queried.storageBytes)
        _ = try coordinates(t,view.transport,using:&exact)
        var short = try TransportFixtures.admission(work:queried.work-1,storage:queried.storageBytes)
        do { _ = try coordinates(t,view.transport,using:&short); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.resourceLimit(.work)) {}
        var noStorage = try TransportFixtures.admission(storage:0)
        _ = try relation(ids,proof.receipt,using:&noStorage)
        try TransportFixtures.require(noStorage.storageBytes == 0)
        do { _ = try t.affineCoordinates(of:view.transport,limits:TransportFixtures.limits(depth:0),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        do { _ = try ids.relation(of:proof.receipt,limits:TransportFixtures.limits(sourceDepth:2),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.sourceDepthLimit {}
        do { _ = try ids.relation(of:proof.receipt,limits:TransportFixtures.limits(identities:0),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.identityLimit {}
        var cancelled = try TransportFixtures.admission(); cancelled.cancel()
        do { _ = try coordinates(t,view.transport,using:&cancelled); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var baseline = try TerminalAdmission()
        _ = try relation(ids,proof.receipt,using:&baseline)
        var terminal = try TerminalAdmission(); terminal.cancelAt = baseline.checks
        do { _ = try relation(ids,proof.receipt,using:&terminal); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS checked DI complete-product relation and exact admission/work/storage/source/proof/transport/cancellation failures")
    }
}
