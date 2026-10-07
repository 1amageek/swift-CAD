#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    func admitted(_ root: ExactRealRoot<F>, _ a: inout ExactRootBorrowedAdmission) throws {
        try require(root.source, &a); try ExactRootAccess.admit(root.depth, &a)
        try ExactRootAccess.admit(root.isolation.depth, &a); try ExactRootAccess.admit(root.proof.depth, &a)
    }
    func replaced(_ root: ExactRealRoot<F>, _ cell: ExactRealRootInterval<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) -> ExactRealRoot<F> {
        ExactRealRoot(source: root.source, multiplicity: root.multiplicity, ordinal: root.ordinal,
            isolation: cell, proof: root.proof, depth: a.depth)
    }
    public func refine<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<F>,
        maximumWidth: F.Value, using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRoot<F> {
        let root = copy root
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(copy root, &a)
            guard try context.field.sign(of: maximumWidth, using: &a) == .positive else { throw ExactRealRootFailure.invalidDomain }
            var cell = root.isolation
            while true {
                guard case .finite(let lo) = cell.lower, case .finite(let hi) = cell.upper else { throw ExactRealRootFailure.invalidEvidence }
                let width = try context.field.subtracting(hi, lo, using: &a)
                if try context.field.compare(width, maximumWidth, using: &a) != .greater { break }
                cell = try contracted(root.proof, cell, axis: root.source.refinementAxis, &a)
            }
            return replaced(copy root, cell, &a)
        }
    }
    func overlap(_ l: ExactRealRootInterval<F.Value>, _ r: ExactRealRootInterval<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootInterval<F.Value>? {
        guard case .finite(let ll) = l.lower, case .finite(let lh) = l.upper,
            case .finite(let rl) = r.lower, case .finite(let rh) = r.upper else { throw ExactRealRootFailure.invalidEvidence }
        let lowOrder = try context.field.compare(ll, rl, using: &a)
        let hiOrder = try context.field.compare(lh, rh, using: &a)
        let lo = lowOrder == .less ? rl : ll, hi = hiOrder == .greater ? rh : lh
        if try context.field.compare(lo, hi, using: &a) == .greater { return nil }
        let il = lowOrder == .equal ? l.includesLower && r.includesLower : lowOrder == .less ? r.includesLower : l.includesLower
        let iu = hiOrder == .equal ? l.includesUpper && r.includesUpper : hiOrder == .greater ? r.includesUpper : l.includesUpper
        let common = try interval(.finite(lo), .finite(hi), il, iu, &a)
        return common.isEmpty ? nil : common
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactRealRoot<F>,
        _ rhs: borrowing ExactRealRoot<F>, using admission: inout A) throws(ExactRealRootFailure) -> ExactOrder {
        let lhs = copy lhs, rhs = copy rhs
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(copy lhs, &a); try admitted(copy rhs, &a)
            let gcd = try context.univariate.greatestCommonDivisor(lhs.proof.polynomial, rhs.proof.polynomial, using: &a)
            let common = try sturm(gcd, &a)
            var l = lhs.isolation, r = rhs.isolation
            if let shared = try overlap(l, r, &a), try roots(common, shared, &a) == 1 { return .equal }
            while true {
                guard case .finite(let ll) = l.lower, case .finite(let lh) = l.upper,
                    case .finite(let rl) = r.lower, case .finite(let rh) = r.upper else { throw ExactRealRootFailure.invalidEvidence }
                if try context.field.compare(lh, rl, using: &a) != .greater {
                    if try context.field.compare(lh, rl, using: &a) == .less || !(l.includesUpper && r.includesLower) { return .less }
                }
                if try context.field.compare(rh, ll, using: &a) != .greater {
                    if try context.field.compare(rh, ll, using: &a) == .less || !(r.includesUpper && l.includesLower) { return .greater }
                }
                if try context.field.compare(ll, lh, using: &a) == .less {
                    l = try contracted(lhs.proof, l, axis: lhs.source.refinementAxis, &a)
                }
                if try context.field.compare(rl, rh, using: &a) == .less {
                    r = try contracted(rhs.proof, r, axis: rhs.source.refinementAxis, &a)
                }
            }
        }
    }
    public func sign<A: ExactScalarAdmission & ~Copyable>(of polynomial: borrowing ExactRealRootSource<F>,
        at root: borrowing ExactRealRoot<F>, using admission: inout A) throws(ExactRealRootFailure) -> ExactSign {
        let root = copy root, polynomial = copy polynomial
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try require(copy polynomial, &a); try admitted(copy root, &a)
            if try context.univariate.isZero(polynomial.law, using: &a) { return .zero }
            if polynomial.law.termCount == 1, let constant = polynomial.law.terms.first, constant.powers[0] == 0 {
                return try context.field.sign(of: constant.coefficient, using: &a)
            }
            if try degree(polynomial.law, &a) == 1 {
                guard let leading = polynomial.law.terms.first,
                    case .finite(let lo) = root.isolation.lower, case .finite(let hi) = root.isolation.upper else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                let constant = polynomial.law.terms.last!.powers[0] == 0
                    ? polynomial.law.terms.last!.coefficient : try context.field.integer(0, using: &a)
                let threshold = try context.field.dividing(context.field.negated(constant, using: &a), leading.coefficient, using: &a)
                let left = try context.field.compare(threshold, lo, using: &a)
                let right = try context.field.compare(threshold, hi, using: &a)
                let side: ExactSign
                if left == .less || (left == .equal && !root.isolation.includesLower) { side = .positive }
                else if right == .greater || (right == .equal && !root.isolation.includesUpper) { side = .negative }
                else if try context.field.sign(of: evaluated(root.proof.polynomial, threshold, &a), using: &a) == .zero {
                    return .zero
                } else {
                    let below = try interval(.finite(lo), .finite(threshold), root.isolation.includesLower, true, &a)
                    side = try roots(root.proof, below, &a) == 1 ? .negative : .positive
                }
                let coefficientSign = try context.field.sign(of: leading.coefficient, using: &a)
                return side == coefficientSign ? .positive : .negative
            }
            let gcd = try context.univariate.greatestCommonDivisor(root.proof.polynomial, polynomial.law, using: &a)
            if try roots(sturm(gcd, &a), root.isolation, &a) == 1 { return .zero }
            let query = try sturm(polynomial.law, &a)
            var cell = root.isolation
            while true {
                guard case .finite(let lo) = cell.lower, case .finite(let hi) = cell.upper else { throw ExactRealRootFailure.invalidEvidence }
                if try context.field.compare(lo, hi, using: &a) == .equal {
                    return try context.field.sign(of: evaluated(polynomial.law, lo, &a), using: &a)
                }
                // Excluded endpoint zeros still prevent using an endpoint sign as the root's sign.
                let closed = try interval(.finite(lo), .finite(hi), true, true, &a)
                if try roots(query, closed, &a) == 0 {
                    return try context.field.sign(of: evaluated(polynomial.law, lo, &a), using: &a)
                }
                cell = try contracted(root.proof, cell, axis: root.source.refinementAxis, &a)
            }
        }
    }
}
