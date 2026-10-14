#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Checked closed rational bounds; they make no equality or geometric coverage claim.
public struct OriginalPhysicalAngleRationalBounds: Sendable {
    public let lower: ExactRationalCoefficient
    public let upper: ExactRationalCoefficient

    public init<A: ExactScalarAdmission & ~Copyable>(lower: ExactRationalCoefficient,
        upper: ExactRationalCoefficient, using admission: inout A) throws(ExactScalarFailure) {
        self = try OriginalPhysicalAngleScalarDomain.query(&admission) { a in
            guard try ExactRationalScalarDomain().compare(lower, upper, using: &a) != .greater else {
                throw ExactScalarFailure.invalidEvidence
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            return Self(.init(lower: lower, upper: upper))
        }
    }

    init(_ interval: OriginalPhysicalAngleInterval) {
        lower = interval.lower; upper = interval.upper
    }

    var interval: OriginalPhysicalAngleInterval { .init(lower: lower, upper: upper) }
}
