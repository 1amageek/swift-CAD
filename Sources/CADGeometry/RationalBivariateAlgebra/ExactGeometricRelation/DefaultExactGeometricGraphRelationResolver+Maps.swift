#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricGraphRelationResolver {
    /// A rational coordinate independent of every other variable and nonconstant
    /// in one parameter has finite fibers. Auxiliary multiplicity is irrelevant.
    func mapEvidence<A: ExactScalarAdmission & ~Copyable>(_ graph: ExactParametricGraph<Base>, _ a: inout A)
        throws -> (constant: Bool, finite: Bool, proofs: [Polynomial]) {
        let laws = graph.predicate.source.polynomials
        let ring = try ExactPolynomialDomain(retaining: laws[0], using: &a)
        var proofs: [Polynomial] = []
        let capacity = try ExactGeometryAccess.multiply(3, graph.variableCount)
        try ExactGeometryAccess.storage(capacity, Polynomial.self, &a)
        proofs.reserveCapacity(capacity)
        var constant = true
        for coordinate in 0..<3 {
            for variable in 0..<graph.variableCount {
                let derivative = try ring.subtracting(
                    ring.multiplying(ring.differentiated(laws[coordinate], in: variable, using: &a), laws[3], using: &a),
                    ring.multiplying(laws[coordinate], ring.differentiated(laws[3], in: variable, using: &a), using: &a), using: &a)
                proofs.append(derivative)
                if try !ring.isZero(derivative, using: &a) { constant = false }
            }
        }
        var finite = true
        for parameter in 0..<graph.parameterCount {
            var found = false
            for coordinate in 0..<3 {
                var candidate = true
                for variable in 0..<graph.variableCount {
                    try a.consumeWork(1)
                    let zero = try ring.isZero(proofs[coordinate * graph.variableCount + variable], using: &a)
                    if variable == parameter ? zero : !zero { candidate = false }
                }
                if candidate { found = true; break }
            }
            if !found { finite = false }
        }
        return (constant, finite, proofs)
    }
}
