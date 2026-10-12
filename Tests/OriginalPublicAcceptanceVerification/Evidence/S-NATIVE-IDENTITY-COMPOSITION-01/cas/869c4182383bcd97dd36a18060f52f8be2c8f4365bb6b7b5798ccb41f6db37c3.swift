#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    func degree(_ p: ExactPolynomial<F>, _ a: inout ExactRootBorrowedAdmission) throws -> Int? {
        try context.univariate.degree(of: p, in: 0, using: &a)
    }
    func evaluated(_ p: ExactPolynomial<F>, _ x: F.Value, _ a: inout ExactRootBorrowedAdmission) throws -> F.Value {
        try ExactRootAccess.storage(1, F.Value.self, &a)
        let result = try context.univariate.evaluated(p, at: [x], using: &a)
        try ExactRootAccess.admit(result.depth, &a); return result.value
    }
    func positiveUnitNormalized(_ law: ExactPolynomial<F>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactPolynomial<F> {
        guard let leading = law.terms.first else { return law }
        let monic = try context.univariate.normalized(law, using: &a)
        return try context.field.sign(of: leading.coefficient, using: &a) == .negative
            ? context.univariate.negated(monic, using: &a) : monic
    }
    func sturm(_ law: ExactPolynomial<F>, _ a: inout ExactRootBorrowedAdmission) throws -> ExactRootSturm<F> {
        guard try degree(law, &a) != nil else { throw ExactRealRootFailure.invalidSource }
        let derivative = try context.univariate.differentiated(law, in: 0, using: &a)
        let repeated = try context.univariate.greatestCommonDivisor(law, derivative, using: &a)
        let p = try positiveUnitNormalized(context.univariate.dividedExactly(law, by: repeated, using: &a), &a)
        let d = try positiveUnitNormalized(context.univariate.differentiated(p, in: 0, using: &a), &a)
        try ExactRootAccess.storage(1, ExactPolynomial<F>.self, &a)
        var chain = [p]
        if try degree(d, &a) != nil {
            try ExactRootAccess.storage(1, ExactPolynomial<F>.self, &a); chain.append(d)
            var first = p, second = d
            while true {
                try a.consumeWork(1)
                let remainder = try context.univariate.divided(first, by: second, using: &a).remainder
                guard let nextDegree = try degree(remainder, &a) else { break }
                guard let oldDegree = try degree(second, &a), nextDegree < oldDegree else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                let next = try positiveUnitNormalized(context.univariate.negated(remainder, using: &a), &a)
                try ExactRootAccess.storage(1, ExactPolynomial<F>.self, &a); chain.append(next)
                first = second; second = next
            }
        }
        try ExactRootAccess.owner((ExactPolynomial<F>, [ExactPolynomial<F>], ExactScalarDepth).self, &a)
        return ExactRootSturm(polynomial: p, chain: chain, depth: a.depth)
    }
    func variations(_ proof: ExactRootSturm<F>, _ at: ExactRealRootBound<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) throws -> Int {
        try ExactRootAccess.admit(proof.depth, &a)
        var previous = ExactSign.zero, result = 0
        for p in proof.chain {
            try a.consumeWork(1)
            let sign: ExactSign
            switch at {
            case .finite(let x): sign = try context.field.sign(of: evaluated(p, x, &a), using: &a)
            case .negativeInfinity, .positiveInfinity:
                guard let lead = p.terms.first else { throw ExactRealRootFailure.invalidEvidence }
                let raw = try context.field.sign(of: lead.coefficient, using: &a)
                if case .negativeInfinity = at, lead.powers[0] % 2 == 1 {
                    sign = raw == .positive ? .negative : raw == .negative ? .positive : .zero
                } else { sign = raw }
            }
            if sign == .zero { continue }
            if previous != .zero && previous != sign { result = try ExactRootAccess.add(result, 1) }
            previous = sign
        }
        return result
    }
    func zeroAt(_ proof: ExactRootSturm<F>, _ bound: ExactRealRootBound<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) throws -> Bool {
        if case .finite(let x) = bound { return try context.field.sign(of: evaluated(proof.polynomial, x, &a), using: &a) == .zero }
        return false
    }
    func roots(_ proof: ExactRootSturm<F>, _ domain: ExactRealRootInterval<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) throws -> Int {
        try ExactRootAccess.admit(domain.depth, &a)
        if domain.isEmpty { return 0 }
        let left = try variations(proof, domain.lower, &a)
        let right = try variations(proof, domain.upper, &a)
        var result = left - right
        if domain.includesLower { if try zeroAt(proof, domain.lower, &a) { result += 1 } }
        if !domain.includesUpper { if try zeroAt(proof, domain.upper, &a) { result -= 1 } }
        guard result >= 0 else { throw ExactRealRootFailure.invalidEvidence }; return result
    }
    func bound(_ p: ExactPolynomial<F>, _ a: inout ExactRootBorrowedAdmission) throws -> F.Value {
        guard let lead = p.terms.first else { throw ExactRealRootFailure.invalidSource }
        let one = try context.field.integer(1, using: &a)
        var largest = try context.field.integer(0, using: &a)
        for t in p.terms.dropFirst() {
            try a.consumeWork(1)
            var value = try context.field.dividing(t.coefficient, lead.coefficient, using: &a)
            if try context.field.sign(of: value, using: &a) == .negative { value = try context.field.negated(value, using: &a) }
            if try context.field.compare(value, largest, using: &a) == .greater { largest = value }
        }
        return try context.field.adding(one, largest, using: &a)
    }
    func finite(_ selected: ExactRealRootInterval<F.Value>, proof: ExactRootSturm<F>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootInterval<F.Value> {
        let b = try bound(proof.polynomial, &a)
        let negative = try context.field.negated(b, using: &a)
        var lo = negative, hi = b, il = true, iu = true
        if case .finite(let l) = selected.lower {
            if try context.field.compare(l, lo, using: &a) != .less { lo = l; il = selected.includesLower }
        }
        if case .finite(let h) = selected.upper {
            if try context.field.compare(h, hi, using: &a) != .greater { hi = h; iu = selected.includesUpper }
        }
        if try context.field.compare(lo, hi, using: &a) == .greater {
            return try interval(.finite(lo), .finite(lo), false, false, &a)
        }
        return try interval(.finite(lo), .finite(hi), il, iu, &a)
    }
    func split(_ domain: ExactRealRootInterval<F.Value>, axis: ExactScalarRootAxis,
        _ a: inout ExactRootBorrowedAdmission) throws -> (ExactRealRootInterval<F.Value>, ExactRealRootInterval<F.Value>) {
        guard case .finite(let lo) = domain.lower, case .finite(let hi) = domain.upper,
            try context.field.compare(lo, hi, using: &a) == .less else { throw ExactRealRootFailure.invalidEvidence }
        _ = try ExactRootAccess.step(domain.depth, axis: axis, &a)
        let sum = try context.field.adding(lo, hi, using: &a)
        let two = try context.field.integer(2, using: &a)
        let midpoint = try context.field.dividing(sum, two, using: &a)
        let left = try interval(.finite(lo), .finite(midpoint), domain.includesLower, true, &a)
        let right = try interval(.finite(midpoint), .finite(hi), false, domain.includesUpper, &a)
        return (left, right)
    }
}
