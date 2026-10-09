import L0
import L1
import L2
import DI0
import DI
import SourceIssuer
import IssuedGraphs
func rejectCoefficient<S:Sendable,F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E:Sendable,A:ExactScalarAdmission & ~Copyable>(
    binding:OriginalDomainBoundParametricGraph<S,F,E>,field:ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,limits:OriginalDomainIdentityLimits,using a:inout A) throws {
    _=try DefaultOriginalIssuedGraphCompiler<S,E>().compile(binding:binding,field:field,limits:limits,using:&a)
}
