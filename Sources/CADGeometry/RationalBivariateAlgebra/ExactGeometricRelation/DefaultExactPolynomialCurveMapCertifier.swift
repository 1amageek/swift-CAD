#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Publishes the existing map proof without decomposing a new intersection problem.
public struct DefaultExactPolynomialCurveMapCertifier<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: ExactPolynomialCurveMapCertifying where Base.Source == Base.Value {
    public init() {}
    public func certify<A: ExactScalarAdmission & ~Copyable>(_ graph: borrowing ExactParametricGraph<Base>,
        using admission: inout A) throws(ExactGeometricRelationFailure) -> ExactPolynomialCurveMapEvidence<Base> {
        do {
            try admission.checkpoint()
            guard graph.parameterCount == 1, graph.variableCount == 1 else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            let laws = graph.predicate.source.polynomials
            let ring = try ExactPolynomialDomain(retaining: laws[0], using: &admission)
            for term in laws[3].terms {
                try admission.consumeWork(1)
                guard term.powers.allSatisfy({ $0 == 0 }) else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            }
            guard try !ring.isZero(laws[3], using: &admission) else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            let proof = try DefaultExactGeometricGraphRelationResolver<Base>().mapEvidence(copy graph, &admission)
            guard proof.constant || proof.finite else { throw ExactGeometricRelationFailure.invalidCoverage }
            var depth = graph.predicate.depth
            for minor in proof.proofs {
                try admission.consumeWork(1)
                depth = try .init(value: max(depth.value, minor.depth.value), coefficient: max(depth.coefficient, minor.depth.coefficient))
            }
            try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactPolynomialCurveMapEvidence<Base>.self))
            let result = ExactPolynomialCurveMapEvidence(graph: copy graph, isConstant: proof.constant,
                hasFiniteFibers: proof.finite, derivativeMinors: proof.proofs, depth: depth)
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
