#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalParametricGraphDomainBinder<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E: Sendable>: OriginalParametricGraphDomainBinding {
    public typealias Source=S
    public typealias Field=F
    public typealias Evidence=E
    public init() {}
    public func bind<A: ExactScalarAdmission & ~Copyable>(graph: borrowing OriginalParametricGraphReceipt<S,F,E>,
        request: borrowing OriginalParameterSelection<S,F>, limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalDomainBoundParametricGraph<S,F,E> {
        let graph=copy graph,request=copy request
        return try OriginalDomainAccess.run(&admission) { a in
            guard graph.source.owns(request.frame.owner.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard graph.layout.parameters.count == request.arity,
                graph.parameterTransport.numerators.count == request.arity,
                graph.parameterTransport.denominators.count == request.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard graph.source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            try request.frame.require(limits,&a)
            var v=graph.proofDepth.value,c=graph.proofDepth.coefficient
            for axis in request.axes { try a.consumeWork(1);v=max(v,axis.depth.value);c=max(c,axis.depth.coefficient) }
            let depth=try ExactScalarDepth(value:v,coefficient:c)
            try a.admitDepth(value:v,coefficient:c)
            try OriginalDomainAccess.storage(1,OriginalDomainBoundParametricGraph<S,F,E>.self,&a)
            return .init(graph:graph,request:request,depth:depth)
        }
    }
}
