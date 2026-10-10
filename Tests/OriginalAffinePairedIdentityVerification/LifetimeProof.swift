import L0
import L1
import DI0
import DI
import SourceIssuer

@main struct PairedLifetimeVerification {
    static func main() throws {
        for swapped in [false,true] {
            // Only the receipt escapes; the caller retains no cover, action or child proof.
            let receipt = try AffinePairedIdentityProof.prepared(swapped:swapped).0
            var a = try TransportFixtures.admission()
            let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
            let zero = try f.integer(0,using:&a),half = try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
            let lhs = try AffinePairedIdentityProof.tuple(swapped ? zero:half,swapped ? half:zero,right:false,&a)
            let rhs = try AffinePairedIdentityProof.tuple(half,zero,right:true,&a)
            let issuer = DefaultOriginalParameterIdentityIssuer<AffinePairedIdentityProof.Parent,ExactRationalScalarDomain>()
            try TransportFixtures.require(issuer.decide(receipt,left:lhs,right:rhs,limits:l,using:&a) == .proven)
            let wrong = try AffinePairedIdentityProof.tuple(zero,zero,right:true,&a)
            try TransportFixtures.require(issuer.decide(receipt,left:lhs,right:wrong,limits:l,using:&a) == .refutedForThisRelation)
            var noStorage = try TransportFixtures.admission(storage:0)
            _ = try issuer.relation(of:receipt,limits:l,using:&noStorage)
            var cancel = try TransportFixtures.admission();cancel.cancel()
            do { _ = try issuer.relation(of:receipt,limits:l,using:&cancel);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        }
        print("PASS paired receipt-only lifetime: independent/swap whole-law queries, zero-storage view and cancellation after all constructing scopes end")
    }
}
