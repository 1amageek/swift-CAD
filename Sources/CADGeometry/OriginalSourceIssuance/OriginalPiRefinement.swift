#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Query-local exact alternating-series state for Machin's identity.
struct OriginalPiRefinement {
    let q = ExactRationalScalarDomain()
    let square5: ExactRationalCoefficient
    let square239: ExactRationalCoefficient
    var power5: ExactRationalCoefficient
    var power239: ExactRationalCoefficient
    var sum5: ExactRationalCoefficient
    var sum239: ExactRationalCoefficient
    var index = 0
    /// Sealed exact Machin bounds from an attained source refinement step.
    struct Evidence {
        let interval: OriginalPhysicalAngleInterval
        let coefficientDepth: Int
        fileprivate init(interval: OriginalPhysicalAngleInterval, coefficientDepth: Int) {
            self.interval = interval; self.coefficientDepth = coefficientDepth
        }
        func admitProof<A: ExactScalarAdmission & ~Copyable>(using a: inout A)
            throws(ExactScalarFailure) {
            try a.checkpoint()
            try a.admitDepth(value: 0, coefficient: coefficientDepth)
            try a.checkpoint()
        }
    }

    mutating func nextEvidence<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws -> Evidence {
        let depth = index.addingReportingOverflow(1)
        guard !depth.overflow else { throw ExactScalarFailure.countOverflow }
        try a.checkpoint()
        try a.visitCell(axis: .coefficient, depth: depth.partialValue)
        try a.admitDepth(value: 0, coefficient: depth.partialValue)
        let bounds = try next(&a)
        guard index == depth.partialValue else { throw ExactScalarFailure.invalidEvidence }
        try a.checkpoint()
        return Evidence(interval: bounds, coefficientDepth: index)
    }

    init<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws {
        let one = try q.integer(1,using:&a)
        power5 = try q.dividing(one,q.integer(5,using:&a),using:&a)
        power239 = try q.dividing(one,q.integer(239,using:&a),using:&a)
        square5 = try q.multiplying(power5,power5,using:&a)
        square239 = try q.multiplying(power239,power239,using:&a)
        sum5 = try q.integer(0,using:&a); sum239 = sum5
    }
    mutating func next<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws -> OriginalPhysicalAngleInterval {
        try a.consumeWork(1)
        let doubled = index.multipliedReportingOverflow(by:2)
        let current = doubled.partialValue.addingReportingOverflow(1)
        let next = current.partialValue.addingReportingOverflow(2)
        let successor = index.addingReportingOverflow(1)
        guard !doubled.overflow,!current.overflow,!next.overflow,!successor.overflow else { throw ExactScalarFailure.countOverflow }
        let divisor = try q.integer(current.partialValue,using:&a),nextDivisor = try q.integer(next.partialValue,using:&a)
        let term5 = try q.dividing(power5,divisor,using:&a),term239 = try q.dividing(power239,divisor,using:&a)
        let positive = index % 2 == 0
        sum5 = try positive ? q.adding(sum5,term5,using:&a) : q.subtracting(sum5,term5,using:&a)
        sum239 = try positive ? q.adding(sum239,term239,using:&a) : q.subtracting(sum239,term239,using:&a)
        power5 = try q.multiplying(power5,square5,using:&a)
        power239 = try q.multiplying(power239,square239,using:&a)
        let tail5 = try q.dividing(power5,nextDivisor,using:&a),tail239 = try q.dividing(power239,nextDivisor,using:&a)
        let bound5 = try OriginalPhysicalAngleInterval(lower:positive ? q.subtracting(sum5,tail5,using:&a) : sum5,
            upper:positive ? sum5 : q.adding(sum5,tail5,using:&a))
        let bound239 = try OriginalPhysicalAngleInterval(lower:positive ? q.subtracting(sum239,tail239,using:&a) : sum239,
            upper:positive ? sum239 : q.adding(sum239,tail239,using:&a))
        index = successor.partialValue
        return try bound5.multiplying(.init(q.integer(16,using:&a)),q,&a)
            .subtracting(bound239.multiplying(.init(q.integer(4,using:&a)),q,&a),q,&a)
    }
}
