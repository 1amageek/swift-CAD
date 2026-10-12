#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

public struct ExactParametricRelationDomain<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,
    Cells: ExactRealCellPreparing & ExactRealCellProducing & ExactRealCellSelecting & ExactRealCellQuerying & ExactRealCellDescribing,
    Topology: ExactRealIncidenceProducing & ExactRealComponentsProducing>: Sendable
    where Base.Source == Base.Value, Cells.Base == Base, Topology.Base == Base {
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public typealias Polynomial = ExactPolynomial<Field>
    let topology: Topology
    public init(cells: Cells.Type, topology: Topology) { self.topology = topology }

    func storage<T, A: ExactScalarAdmission & ~Copyable>(_ count: Int, _ type: T.Type,
        _ admission: inout A) throws {
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: type))
    }

    func remap<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, offset: Int,
        to polynomials: ExactPolynomialDomain<Field>, field: Field, using admission: inout A) throws -> Polynomial {
        try admission.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        try storage(law.terms.count, ExactPolynomialTerm<Field.Value>.self, &admission)
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.terms.count)
        for term in law.terms {
            try admission.consumeWork(1)
            try storage(polynomials.variableCount, Int.self, &admission)
            try admission.consumeWork(polynomials.variableCount)
            var powers = [Int](repeating: 0, count: polynomials.variableCount)
            for index in term.powers.indices {
                try admission.consumeWork(1)
                powers[offset + index] = term.powers[index]
            }
            terms.append(.init(powers: powers, coefficient: try field.importing(term.coefficient, using: &admission)))
        }
        // Canonical construction validates coefficient family and inherited depth.
        return try polynomials.polynomial(terms: terms, using: &admission)
    }
}
