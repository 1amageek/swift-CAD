#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension OriginalPhysicalAngleScalarDomain {
    /// Outward bounds at a fixed coefficient refinement; unresolved poles are explicit failure.
    public func enclosing<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Value,
        refinementDepth: Int, using admission: inout A) throws(ExactScalarFailure)
        -> OriginalPhysicalAngleRationalBounds {
        let value = copy input
        return try Self.query(&admission) { a in
            guard refinementDepth > 0 else { throw ExactScalarFailure.invalidEvidence }
            try require(value, &a)
            let q = owner.rationals
            if value.numerator.terms.isEmpty || (value.numerator.terms.count == 1 && value.numerator.terms[0].powers[0] == 0),
                value.denominator.terms.count == 1, value.denominator.terms[0].powers[0] == 0 {
                let zero = try q.integer(0, using: &a)
                let numerator = value.numerator.terms.first?.coefficient ?? zero
                guard let denominator = value.denominator.terms.first?.coefficient else {
                    throw ExactScalarFailure.divisionByZero
                }
                return try Self.publishedBounds(.init(q.dividing(numerator, denominator, using: &a)), &a)
            }
            var refinement = try OriginalPhysicalAngleRefinement(owner, &a)
            var parameter: OriginalPhysicalAngleInterval?
            for _ in 0..<refinementDepth {
                try a.checkpoint()
                parameter = try refinement.next(&a)
            }
            guard let parameter else { throw ExactScalarFailure.invalidEvidence }
            let rounded = try parameter.outwardDyadic(q, &a)
            let n = try enclosed(value.numerator, at: rounded, &a)
            let d = try enclosed(value.denominator, at: rounded, &a)
            return try Self.publishedBounds(n.divided(by: d, q, &a).outwardDyadic(q, &a), &a)
        }
    }

    static func publishedBounds<A: ExactScalarAdmission & ~Copyable>(
        _ interval: OriginalPhysicalAngleInterval, _ a: inout A) throws -> OriginalPhysicalAngleRationalBounds {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalPhysicalAngleRationalBounds.self))
        return .init(interval)
    }
}
