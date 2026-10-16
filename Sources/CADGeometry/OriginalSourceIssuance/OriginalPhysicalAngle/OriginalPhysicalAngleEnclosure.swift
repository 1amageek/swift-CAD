#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// One query's continuing T enclosure for the retained physical-angle expressions.
struct OriginalPhysicalAngleEnclosure: ~Copyable {
    private let domain: OriginalPhysicalAngleScalarDomain
    private let sine: OriginalPhysicalAngleValue
    private let cosine: OriginalPhysicalAngleValue
    private var refinement: OriginalPhysicalAngleRefinement
    private var parameter: OriginalPhysicalAngleInterval?
    private(set) var refinementDepth = 0

    init<A: ExactScalarAdmission & ~Copyable>(domain: OriginalPhysicalAngleScalarDomain,
        using admission: inout A) throws(ExactScalarFailure) {
        let prepared = try OriginalPhysicalAngleScalarDomain.query(&admission) { a in
            let sine = try domain.sine(using: &a), cosine = try domain.cosine(using: &a)
            let refinement = try OriginalPhysicalAngleRefinement(domain.owner, &a)
            try a.retainStorage(bytes: MemoryLayout<Self>.stride)
            return (sine, cosine, refinement)
        }
        self.domain = domain
        sine = prepared.0; cosine = prepared.1; refinement = prepared.2
    }

    /// Re-admits an already published immutable bound without evaluating it again.
    func admitProof<A: ExactScalarAdmission & ~Copyable>(using admission: inout A)
        throws(ExactScalarFailure) {
        try OriginalPhysicalAngleScalarDomain.query(&admission) { a in
            guard refinementDepth > 0, parameter != nil else { throw ExactScalarFailure.invalidEvidence }
            try domain.require(sine, &a); try domain.require(cosine, &a)
            try a.admitDepth(value: 0, coefficient: refinementDepth)
        }
    }

    mutating func enclosing<A: ExactScalarAdmission & ~Copyable>(refinementDepth requested: Int,
        using admission: inout A) throws(ExactScalarFailure)
        -> (sine: OriginalPhysicalAngleRationalBounds, cosine: OriginalPhysicalAngleRationalBounds) {
        try OriginalPhysicalAngleScalarDomain.query(&admission) { a in
            guard requested > 0, requested >= refinementDepth else { throw ExactScalarFailure.invalidEvidence }
            try domain.require(sine, &a); try domain.require(cosine, &a)
            try a.admitDepth(value: 0, coefficient: refinementDepth)
            while refinementDepth < requested {
                try a.checkpoint()
                parameter = try refinement.next(&a)
                refinementDepth = refinement.order
            }
            guard let parameter else { throw ExactScalarFailure.invalidEvidence }
            let q = domain.owner.rationals
            let rounded = try parameter.outwardDyadic(q, &a)
            func enclose(_ value: borrowing OriginalPhysicalAngleValue,
                using a: inout A) throws -> OriginalPhysicalAngleRationalBounds {
                let n = try domain.enclosed(value.numerator, at: rounded, &a)
                let d = try domain.enclosed(value.denominator, at: rounded, &a)
                return try OriginalPhysicalAngleScalarDomain.publishedBounds(
                    n.divided(by: d, q, &a).outwardDyadic(q, &a), &a)
            }
            return try (enclose(sine, using: &a), enclose(cosine, using: &a))
        }
    }
}
