import L0
import L1
import DI0
import DI
import SourceIssuer
func rejectMissingUV<S:Sendable,C:Sendable,A:ExactScalarAdmission & ~Copyable>(
    image:OriginalImplicitImageReceipt<S,C,OriginalExactScalarDomain>,request:OriginalParameterSelection<S,OriginalExactScalarDomain>,limits:OriginalDomainIdentityLimits,using a:inout A) throws {
    _=try DefaultOriginalParametricGraphDomainBinder<S,OriginalExactScalarDomain,C>().bind(graph:image,request:request,limits:limits,using:&a)
}
