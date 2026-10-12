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
        toExactValue value: F.Value, using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRoot<F> {
        let root = copy root
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(copy root, &a)
            try ExactRootAccess.visit(root.isolation.depth, axis: root.source.refinementAxis, &a)
            guard case .finite(let lower) = root.isolation.lower,
                  case .finite(let upper) = root.isolation.upper else { throw ExactRealRootFailure.invalidEvidence }
            let lowOrder = try context.field.compare(value, lower, using: &a)
            let highOrder = try context.field.compare(value, upper, using: &a)
            guard lowOrder != .less, highOrder != .greater,
                  lowOrder != .equal || root.isolation.includesLower,
                  highOrder != .equal || root.isolation.includesUpper else {
                throw ExactRealRootFailure.invalidEvidence
            }
            let singleton = try interval(.finite(value), .finite(value), true, true, &a)
            guard try roots(root.proof, singleton, &a) == 1 else { throw ExactRealRootFailure.invalidEvidence }
            let refined = replaced(copy root, singleton, &a)
            try a.checkpoint()
            return refined
        }
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
    func disjointOrder(_ l: ExactRealRootInterval<F.Value>, _ r: ExactRealRootInterval<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactOrder? {
        guard case .finite(let ll) = l.lower, case .finite(let lh) = l.upper,
            case .finite(let rl) = r.lower, case .finite(let rh) = r.upper else { throw ExactRealRootFailure.invalidEvidence }
        let left = try context.field.compare(lh, rl, using: &a)
        if left == .less || (left == .equal && !(l.includesUpper && r.includesLower)) { return .less }
        let right = try context.field.compare(rh, ll, using: &a)
        if right == .less || (right == .equal && !(r.includesUpper && l.includesLower)) { return .greater }
        return nil
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactRealRoot<F>,
        _ rhs: borrowing ExactRealRoot<F>, using admission: inout A) throws(ExactRealRootFailure) -> ExactOrder {
        let lhs = copy lhs, rhs = copy rhs
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(copy lhs, &a); try admitted(copy rhs, &a)
            if lhs.source.variable == rhs.source.variable,
                try polynomials.equals(lhs.source.original, rhs.source.original, using: &a) {
                return lhs.ordinal == rhs.ordinal ? .equal : lhs.ordinal < rhs.ordinal ? .less : .greater
            }
            if let order = try disjointOrder(lhs.isolation, rhs.isolation, &a) { return order }
            guard case .finite(let lower) = rhs.isolation.lower,
                case .finite(let upper) = rhs.isolation.upper else { throw ExactRealRootFailure.invalidEvidence }
            let derivative = try context.univariate.differentiated(lhs.proof.polynomial, in: 0, using: &a)
            let x = try context.univariate.variable(0, using: &a)
            let lowLaw = try context.univariate.subtracting(x, context.univariate.constant(lower, using: &a), using: &a)
            let lowSign = try tarskiSign(lowLaw, at: lhs, derivative: derivative, &a)
            if lowSign == .negative { return .less }
            if lowSign == .zero {
                return try rhs.isolation.includesLower && zeroAt(rhs.proof, rhs.isolation.lower, &a) ? .equal : .less
            }
            let highLaw = try context.univariate.subtracting(x, context.univariate.constant(upper, using: &a), using: &a)
            let highSign = try tarskiSign(highLaw, at: lhs, derivative: derivative, &a)
            if highSign == .positive { return .greater }
            if highSign == .zero {
                return try rhs.isolation.includesUpper && zeroAt(rhs.proof, rhs.isolation.upper, &a) ? .equal : .greater
            }
            if try tarskiSign(rhs.proof.polynomial, at: lhs, derivative: derivative, &a) == .zero { return .equal }
            var previous = ExactSign.zero, atLeft = 0
            for polynomial in rhs.proof.chain {
                try a.consumeWork(1)
                let sign = try tarskiSign(polynomial, at: lhs, derivative: derivative, &a)
                if sign == .zero { continue }
                if previous != .zero && sign != previous { atLeft = try ExactRootAccess.add(atLeft, 1) }
                previous = sign
            }
            var count = try variations(rhs.proof, rhs.isolation.lower, &a) - atLeft
            if rhs.isolation.includesLower, try zeroAt(rhs.proof, rhs.isolation.lower, &a) { count += 1 }
            guard count == 0 || count == 1 else { throw ExactRealRootFailure.invalidEvidence }
            return count == 0 ? .less : .greater
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
            // The admitted singleton receipt already proves the root coordinate.
            if case .finite(let lo) = root.isolation.lower, case .finite(let hi) = root.isolation.upper,
                try context.field.compare(lo, hi, using: &a) == .equal {
                return try context.field.sign(of: evaluated(polynomial.law, lo, &a), using: &a)
            }
            let derivative = try context.univariate.differentiated(root.proof.polynomial, in: 0, using: &a)
            return try tarskiSign(polynomial.law, at: root, derivative: derivative, &a)
        }
    }
}
