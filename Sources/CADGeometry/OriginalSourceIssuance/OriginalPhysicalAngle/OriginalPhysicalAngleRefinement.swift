#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Query-local alternating-series state; no retained mutable coefficient cache.
struct OriginalPhysicalAngleRefinement {
    let owner: OriginalPhysicalAngleOwner
    let square: ExactRationalCoefficient
    var sineTerm: ExactRationalCoefficient
    var cosineTerm: ExactRationalCoefficient
    var sineSum: ExactRationalCoefficient
    var cosineSum: ExactRationalCoefficient
    var order = 0
    init<A: ExactScalarAdmission & ~Copyable>(_ owner: OriginalPhysicalAngleOwner, _ a: inout A) throws {
        self.owner = owner
        square = try owner.rationals.multiplying(owner.reducedArgument, owner.reducedArgument, using: &a)
        sineTerm = owner.reducedArgument; sineSum = sineTerm
        cosineTerm = try owner.rationals.integer(1, using: &a); cosineSum = cosineTerm
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
    }
    mutating func next<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws -> OriginalPhysicalAngleInterval? {
        let q = owner.rationals
        let nextOrder = try OriginalPhysicalAngleScalarDomain.increment(order)
        try a.visitCell(axis: .coefficient, depth: nextOrder)
        try a.admitDepth(value: 0, coefficient: nextOrder)
        let twice = order.multipliedReportingOverflow(by: 2)
        guard !twice.overflow else { throw ExactScalarFailure.countOverflow }
        let a1 = try OriginalPhysicalAngleScalarDomain.increment(twice.partialValue)
        let a2 = try OriginalPhysicalAngleScalarDomain.increment(a1)
        let a3 = try OriginalPhysicalAngleScalarDomain.increment(a2)
        // Integer factors are multiplied in Q, never overflowing an Int factorial.
        let sineDivisor = try q.multiplying(q.integer(a2, using: &a), q.integer(a3, using: &a), using: &a)
        let cosineDivisor = try q.multiplying(q.integer(a1, using: &a), q.integer(a2, using: &a), using: &a)
        let nextSine = try q.negated(q.dividing(q.multiplying(sineTerm, square, using: &a), sineDivisor, using: &a), using: &a)
        let nextCosine = try q.negated(q.dividing(q.multiplying(cosineTerm, square, using: &a), cosineDivisor, using: &a), using: &a)
        let nextSineSum = try q.adding(sineSum, nextSine, using: &a)
        let nextCosineSum = try q.adding(cosineSum, nextCosine, using: &a)
        var s = try OriginalPhysicalAngleInterval.ordered(sineSum, nextSineSum, q, &a)
        var c = try OriginalPhysicalAngleInterval.ordered(cosineSum, nextCosineSum, q, &a)
        sineTerm = nextSine; cosineTerm = nextCosine; sineSum = nextSineSum; cosineSum = nextCosineSum; order = nextOrder
        let two = OriginalPhysicalAngleInterval(try q.integer(2, using: &a))
        for _ in 0..<owner.doublings {
            try a.consumeWork(1)
            let next = try two.multiplying(s, q, &a).multiplying(c, q, &a)
            c = try c.multiplying(c, q, &a).subtracting(s.multiplying(s, q, &a), q, &a)
            s = next
        }
        if owner.negative { s = try s.negated(q, &a) }
        s = try s.outwardDyadic(q, &a)
        c = try c.outwardDyadic(q, &a)
        guard try c.sign(q, &a) != nil else { return nil }
        return try s.divided(by: c, q, &a)
    }
}
