#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Source-owned interval proofs for original label phases and positive radicals.
public enum OriginalPhysicalAngleRationalEnclosures {
    public static func normalizedLabelSineCosine<A: ExactScalarAdmission & ~Copyable>(
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        labelPeriod: ExactRationalCoefficient, refinementDepth: Int, using admission: inout A
    ) throws(ExactScalarFailure) -> (sine: OriginalPhysicalAngleRationalBounds,
        cosine: OriginalPhysicalAngleRationalBounds) {
        try OriginalPhysicalAngleScalarDomain.query(&admission) { a in
            let q = ExactRationalScalarDomain()
            guard refinementDepth > 0, try q.compare(lower, upper, using: &a) != .greater,
                try q.sign(of: labelPeriod, using: &a) == .positive else {
                throw ExactScalarFailure.invalidEvidence
            }
            var pi = try OriginalPiRefinement(&a)
            var piBounds = OriginalPhysicalAngleInterval(try q.integer(0, using: &a))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalPiRefinement.self))
            for depth in 1...refinementDepth {
                try visit(depth, &a)
                piBounds = try pi.next(&a)
            }
            let two = try q.integer(2, using: &a)
            let scale = OriginalPhysicalAngleInterval(try q.dividing(two, labelPeriod, using: &a))
            let phase = try OriginalPhysicalAngleInterval(lower: lower, upper: upper)
                .multiplying(piBounds, q, &a).multiplying(scale, q, &a).outwardDyadic(q, &a)
            let center = try q.dividing(q.adding(phase.lower, phase.upper, using: &a), two, using: &a)
            let radius = try q.dividing(q.subtracting(phase.upper, phase.lower, using: &a), two, using: &a)
            let values = try sineCosine(center, refinementDepth: refinementDepth, q, &a)
            let spread = OriginalPhysicalAngleInterval(lower: try q.negated(radius, using: &a), upper: radius)
            let sine = try values.sine.adding(spread, q, &a).outwardDyadic(q, &a)
            let cosine = try values.cosine.adding(spread, q, &a).outwardDyadic(q, &a)
            return try (OriginalPhysicalAngleScalarDomain.publishedBounds(sine, &a),
                OriginalPhysicalAngleScalarDomain.publishedBounds(cosine, &a))
        }
    }

    /// Positive square-root bounds verified only with rational squared comparisons.
    public static func positiveSquareRoot<A: ExactScalarAdmission & ~Copyable>(
        _ input: OriginalPhysicalAngleRationalBounds, refinementDepth: Int, using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalPhysicalAngleRationalBounds {
        try OriginalPhysicalAngleScalarDomain.query(&admission) { a in
            let q = ExactRationalScalarDomain()
            guard refinementDepth > 0, try q.sign(of: input.lower, using: &a) == .positive else {
                throw ExactScalarFailure.invalidEvidence
            }
            var lower = try q.integer(0, using: &a)
            var upper = try q.integer(1, using: &a)
            let two = try q.integer(2, using: &a)
            while try q.compare(q.multiplying(upper, upper, using: &a), input.upper, using: &a) == .less {
                try a.checkpoint(); try a.consumeWork(1)
                upper = try q.multiplying(upper, two, using: &a)
            }
            var lowerHigh = upper, upperLow = lower
            for depth in 1...refinementDepth {
                try visit(depth, &a)
                for _ in 0..<4 {
                    let lowMid = try q.dividing(q.adding(lower, lowerHigh, using: &a), two, using: &a)
                    let lowSquare = try q.multiplying(lowMid, lowMid, using: &a)
                    if try q.compare(lowSquare, input.lower, using: &a) == .greater { lowerHigh = lowMid }
                    else { lower = lowMid }
                    let highMid = try q.dividing(q.adding(upperLow, upper, using: &a), two, using: &a)
                    let highSquare = try q.multiplying(highMid, highMid, using: &a)
                    if try q.compare(highSquare, input.upper, using: &a) == .less { upperLow = highMid }
                    else { upper = highMid }
                }
            }
            return try OriginalPhysicalAngleScalarDomain.publishedBounds(.init(lower: lower, upper: upper), &a)
        }
    }

    private static func visit<A: ExactScalarAdmission & ~Copyable>(_ depth: Int, _ a: inout A) throws {
        try a.checkpoint()
        try a.visitCell(axis: .coefficient, depth: depth)
        try a.admitDepth(value: 0, coefficient: depth)
        try a.consumeWork(1)
    }

    private static func sineCosine<A: ExactScalarAdmission & ~Copyable>(
        _ input: ExactRationalCoefficient, refinementDepth: Int,
        _ q: ExactRationalScalarDomain, _ a: inout A
    ) throws -> (sine: OriginalPhysicalAngleInterval, cosine: OriginalPhysicalAngleInterval) {
        let negative = try q.sign(of: input, using: &a) == .negative
        var reduced = try negative ? q.negated(input, using: &a) : input
        let one = try q.integer(1, using: &a), two = try q.integer(2, using: &a)
        var doublings = 0
        while try q.compare(reduced, one, using: &a) != .less {
            try a.checkpoint(); try a.consumeWork(1)
            reduced = try q.dividing(reduced, two, using: &a)
            doublings = try OriginalPhysicalAngleScalarDomain.increment(doublings)
        }
        let square = try q.multiplying(reduced, reduced, using: &a)
        var sineTerm = reduced, sineSum = reduced, cosineTerm = one, cosineSum = one
        var sine = OriginalPhysicalAngleInterval(reduced), cosine = OriginalPhysicalAngleInterval(one)
        for index in 0..<refinementDepth {
            let depth = try OriginalPhysicalAngleScalarDomain.increment(index)
            try visit(depth, &a)
            let doubled = index.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw ExactScalarFailure.countOverflow }
            let first = try OriginalPhysicalAngleScalarDomain.increment(doubled.partialValue)
            let second = try OriginalPhysicalAngleScalarDomain.increment(first)
            let third = try OriginalPhysicalAngleScalarDomain.increment(second)
            let sineDivisor = try q.multiplying(q.integer(second, using: &a), q.integer(third, using: &a), using: &a)
            let cosineDivisor = try q.multiplying(q.integer(first, using: &a), q.integer(second, using: &a), using: &a)
            sineTerm = try q.negated(q.dividing(q.multiplying(sineTerm, square, using: &a), sineDivisor, using: &a), using: &a)
            cosineTerm = try q.negated(q.dividing(q.multiplying(cosineTerm, square, using: &a), cosineDivisor, using: &a), using: &a)
            let nextSine = try q.adding(sineSum, sineTerm, using: &a)
            let nextCosine = try q.adding(cosineSum, cosineTerm, using: &a)
            sine = try .ordered(sineSum, nextSine, q, &a)
            cosine = try .ordered(cosineSum, nextCosine, q, &a)
            sineSum = nextSine; cosineSum = nextCosine
        }
        sine = try sine.outwardDyadic(q, &a); cosine = try cosine.outwardDyadic(q, &a)
        for _ in 0..<doublings {
            try a.checkpoint(); try a.consumeWork(1)
            let nextSine = try OriginalPhysicalAngleInterval(two).multiplying(sine, q, &a).multiplying(cosine, q, &a)
            cosine = try cosine.multiplying(cosine, q, &a).subtracting(sine.multiplying(sine, q, &a), q, &a).outwardDyadic(q, &a)
            sine = try nextSine.outwardDyadic(q, &a)
        }
        if negative { sine = try sine.negated(q, &a) }
        return (sine, cosine)
    }
}
