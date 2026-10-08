#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension OriginalPhysicalAngleScalarDomain {
    public func negated<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let x = copy input
        return try Self.query(&admission) { a in
            try require(x, &a)
            return try value(owner.ring.negated(x.numerator, using: &a), x.denominator, &a)
        }
    }
    public func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let x = copy lhs, y = copy rhs
        return try Self.query(&admission) { a in
            try require(x, &a); try require(y, &a)
            let n = try owner.ring.adding(owner.ring.multiplying(x.numerator, y.denominator, using: &a),
                owner.ring.multiplying(y.numerator, x.denominator, using: &a), using: &a)
            return try value(n, owner.ring.multiplying(x.denominator, y.denominator, using: &a), &a)
        }
    }
    public func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let x = copy lhs, y = copy rhs
        return try Self.query(&admission) { a in
            try require(x, &a); try require(y, &a)
            let n = try owner.ring.subtracting(owner.ring.multiplying(x.numerator, y.denominator, using: &a),
                owner.ring.multiplying(y.numerator, x.denominator, using: &a), using: &a)
            return try value(n, owner.ring.multiplying(x.denominator, y.denominator, using: &a), &a)
        }
    }
    public func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let x = copy lhs, y = copy rhs
        return try Self.query(&admission) { a in
            try require(x, &a); try require(y, &a)
            return try value(owner.ring.multiplying(x.numerator, y.numerator, using: &a),
                owner.ring.multiplying(x.denominator, y.denominator, using: &a), &a)
        }
    }
    public func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let x = copy lhs, y = copy rhs
        return try Self.query(&admission) { a in
            try require(x, &a); try require(y, &a)
            guard try !owner.ring.isZero(y.numerator, using: &a) else { throw ExactScalarFailure.divisionByZero }
            return try value(owner.ring.multiplying(x.numerator, y.denominator, using: &a),
                owner.ring.multiplying(x.denominator, y.numerator, using: &a), &a)
        }
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactOrder {
        switch try sign(of: subtracting(lhs, rhs, using: &admission), using: &admission) {
        case .negative: return .less
        case .zero: return .equal
        case .positive: return .greater
        }
    }
}
