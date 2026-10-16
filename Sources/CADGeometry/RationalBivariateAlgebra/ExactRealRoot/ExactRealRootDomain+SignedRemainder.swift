#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    func signedRemainders<A: ExactScalarAdmission & ~Copyable>(_ first: ExactPolynomial<F>, _ second: ExactPolynomial<F>,
        _ a: inout A) throws -> [ExactPolynomial<F>] {
        try ExactRootAccess.storage(2, ExactPolynomial<F>.self, &a)
        var chain = [first], left = first, right = try positiveUnitNormalized(second, &a)
        if try context.univariate.isZero(right, using: &a) { return chain }
        chain.append(right)
        while true {
            try a.consumeWork(1)
            let division = try context.univariate.divided(left, by: right, using: &a)
            guard let nextDegree = try degree(division.remainder, &a) else { break }
            guard let oldDegree = try degree(right, &a), nextDegree < oldDegree else {
                throw ExactRealRootFailure.invalidEvidence
            }
            let next = try positiveUnitNormalized(context.univariate.negated(division.remainder, using: &a), &a)
            try ExactRootAccess.storage(1, ExactPolynomial<F>.self, &a)
            chain.append(next); left = right; right = next
        }
        return chain
    }

    func sideSign<A: ExactScalarAdmission & ~Copyable>(_ polynomial: ExactPolynomial<F>, at bound: ExactRealRootBound<F.Value>,
        direction: Int, _ a: inout A) throws -> ExactSign {
        switch bound {
        case .negativeInfinity, .positiveInfinity:
            guard let leading = polynomial.terms.first else { throw ExactRealRootFailure.invalidEvidence }
            let sign = try context.field.sign(of: leading.coefficient, using: &a)
            if case .negativeInfinity = bound, leading.powers[0] % 2 == 1 {
                return sign == .positive ? .negative : sign == .negative ? .positive : .zero
            }
            return sign
        case .finite(let value):
            var derivative = polynomial, order = 0
            while true {
                try a.consumeWork(1)
                let sign = try context.field.sign(of: evaluated(derivative, value, &a), using: &a)
                if sign != .zero {
                    return direction < 0 && order % 2 == 1 ? (sign == .positive ? .negative : .positive) : sign
                }
                guard let degree = try degree(derivative, &a), degree > 0 else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                derivative = try context.univariate.differentiated(derivative, in: 0, using: &a)
                order = try ExactRootAccess.add(order, 1)
            }
        }
    }

    func sideVariations<A: ExactScalarAdmission & ~Copyable>(_ chain: [ExactPolynomial<F>], at bound: ExactRealRootBound<F.Value>,
        direction: Int, _ a: inout A) throws -> Int {
        var previous = ExactSign.zero, result = 0
        for polynomial in chain {
            try a.consumeWork(1)
            let sign = try sideSign(polynomial, at: bound, direction: direction, &a)
            guard sign != .zero else { throw ExactRealRootFailure.invalidEvidence }
            if previous != .zero && sign != previous { result = try ExactRootAccess.add(result, 1) }
            previous = sign
        }
        return result
    }

    func tarskiSign<A: ExactScalarAdmission & ~Copyable>(_ query: ExactPolynomial<F>, at root: ExactRealRoot<F>,
        derivative: ExactPolynomial<F>, _ a: inout A) throws -> ExactSign {
        let p = root.proof.polynomial
        let remainder = try context.univariate.divided(query, by: p, using: &a).remainder
        if try context.univariate.isZero(remainder, using: &a) { return .zero }
        if case .finite(let lower) = root.isolation.lower, case .finite(let upper) = root.isolation.upper,
            try context.field.compare(lower, upper, using: &a) == .equal {
            return try context.field.sign(of: evaluated(remainder, lower, &a), using: &a)
        }
        let numerator = try context.univariate.divided(
            context.univariate.multiplying(derivative, remainder, using: &a), by: p, using: &a).remainder
        let chain = try signedRemainders(p, numerator, &a)
        let lower = try sideVariations(chain, at: root.isolation.lower, direction: 1, &a)
        let upper = try sideVariations(chain, at: root.isolation.upper, direction: -1, &a)
        var sum = lower - upper
        try ExactRootAccess.storage(2, (ExactRealRootBound<F.Value>, Bool).self, &a)
        for (bound, included) in [(root.isolation.lower, root.isolation.includesLower),
                                  (root.isolation.upper, root.isolation.includesUpper)] {
            try a.consumeWork(1)
            if included, case .finite(let value) = bound,
                try context.field.sign(of: evaluated(p, value, &a), using: &a) == .zero {
                let sign = try context.field.sign(of: evaluated(remainder, value, &a), using: &a)
                sum += sign == .negative ? -1 : sign == .positive ? 1 : 0
            }
        }
        switch sum {
        case -1: return .negative
        case 0: return .zero
        case 1: return .positive
        default: throw ExactRealRootFailure.invalidEvidence
        }
    }

    public func signs<A: ExactScalarAdmission & ~Copyable>(of polynomials: [ExactRealRootSource<F>],
        at root: borrowing ExactRealRoot<F>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSigns<F> {
        let root = copy root
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(root, &a)
            let derivative = try context.univariate.differentiated(root.proof.polynomial, in: 0, using: &a)
            try ExactRootAccess.storage(polynomials.count, ExactSign.self, &a)
            var values: [ExactSign] = []; values.reserveCapacity(polynomials.count)
            for query in polynomials {
                try require(query, &a)
                values.append(try tarskiSign(query.law, at: root, derivative: derivative, &a))
            }
            return .init(root: root, queries: polynomials, values: values, depth: (try a.depth))
        }
    }
}
