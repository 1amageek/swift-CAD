#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

extension ExactParametricRelationDomain {
    func squareReduction<A: ExactScalarAdmission & ~Copyable>(equation: Polynomial,
        index: Int, laws: inout [Polynomial], polynomials p: ExactPolynomialDomain<Field>,
        field: Field, using a: inout A) throws -> ExactParametricSquareReduction<Base>? {
        let n = p.variableCount
        let zero = try field.integer(0, using: &a)
        try storage(n, Field.Value.self, &a); try storage(n, Field.Value.self, &a)
        var quadratic = Array(repeating: zero, count: n)
        var linear = Array(repeating: zero, count: n)
        var constant = zero
        for term in equation.terms {
            var active: Int? = nil, power = 0
            for axis in term.powers.indices {
                try a.consumeWork(1)
                if term.powers[axis] != 0 {
                    guard active == nil, term.powers[axis] <= 2 else { return nil }
                    active = axis; power = term.powers[axis]
                }
            }
            if let active {
                if power == 2 { quadratic[active] = term.coefficient }
                else { linear[active] = term.coefficient }
            } else { constant = term.coefficient }
        }
        var negated: Bool? = nil
        for axis in 0..<n {
            try a.consumeWork(1)
            let sign = try field.sign(of: quadratic[axis], using: &a)
            if sign == .zero {
                guard try field.sign(of: linear[axis], using: &a) == .zero else { return nil }
            } else if let orientation = negated {
                guard (sign == .negative) == orientation else { return nil }
            } else { negated = sign == .negative }
        }
        guard let negated else { return nil }
        let orientation = try field.integer(negated ? -1 : 1, using: &a)
        let two = try field.integer(2, using: &a)
        var remainder = try field.multiplying(constant, orientation, using: &a)
        var identity = try p.zero(using: &a)
        try storage(n, Field.Value.self, &a); try storage(n, Polynomial.self, &a)
        var weights: [Field.Value] = [], factors: [Polynomial] = []
        weights.reserveCapacity(n); factors.reserveCapacity(n)
        for axis in 0..<n {
            try a.consumeWork(1)
            if try field.sign(of: quadratic[axis], using: &a) == .zero { continue }
            let weight = try field.multiplying(quadratic[axis], orientation, using: &a)
            let coefficient = try field.multiplying(linear[axis], orientation, using: &a)
            let shift = try field.dividing(coefficient, field.multiplying(two, weight, using: &a), using: &a)
            let factor = try p.adding(p.variable(axis, using: &a), p.constant(shift, using: &a), using: &a)
            let square = try p.multiplying(factor, factor, using: &a)
            identity = try p.adding(identity, p.multiplying(p.constant(weight, using: &a), square, using: &a), using: &a)
            remainder = try field.subtracting(remainder,
                field.multiplying(weight, field.multiplying(shift, shift, using: &a), using: &a), using: &a)
            weights.append(weight); factors.append(factor)
        }
        guard try field.sign(of: remainder, using: &a) == .zero else { return nil }
        let signed = try p.multiplying(equation, p.constant(orientation, using: &a), using: &a)
        guard try p.equals(signed, identity, using: &a) else { throw ExactParametricRelationFailure.invalidEvidence }
        // The real-zero-set equivalence is now proved. Every remainder below is
        // equivalent only under all retained factor equalities; no guard is lost.
        let size = laws.count.multipliedReportingOverflow(by: factors.count)
        guard !size.overflow else { throw ExactParametricRelationFailure.countOverflow }
        let count = size.partialValue
        try storage(count, ExactParametricConstraintDivision<Base>.self, &a)
        try storage(laws.count, Polynomial.self, &a)
        var divisions: [ExactParametricConstraintDivision<Base>] = []; divisions.reserveCapacity(count)
        for lawIndex in laws.indices {
            for factorIndex in factors.indices {
                try a.consumeWork(1)
                let dividend = laws[lawIndex]
                let division = try p.divided(dividend, by: factors[factorIndex], using: &a)
                divisions.append(.init(lawIndex: lawIndex, factorIndex: factorIndex,
                    dividend: dividend, division: division))
                laws[lawIndex] = division.remainder
            }
        }
        try storage(factors.count, Polynomial.self, &a)
        laws.append(contentsOf: factors)
        try storage(1, ExactParametricSquareReduction<Base>.self, &a)
        return .init(equationIndex: index, equation: equation, negated: negated,
            positiveWeights: weights, factors: factors, reconstructedIdentity: identity, divisions: divisions)
    }
}
