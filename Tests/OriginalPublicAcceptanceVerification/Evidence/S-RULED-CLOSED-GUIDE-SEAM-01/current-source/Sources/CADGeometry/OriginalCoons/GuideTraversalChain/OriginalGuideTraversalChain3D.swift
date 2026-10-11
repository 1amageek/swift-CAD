import CADCore

/// Declared aggregate chart retaining every original directed guide traversal.
public struct OriginalGuideTraversalChain3D: Hashable, Sendable {
    public let traversals: [OriginalCurveRootSpan3D]
    public let stations: [ExactRationalCoefficient]
    public let sourceSegmentOrdinals: [Int]
    private let retainedSourceDepth: Int
    private let rationalPieces: [[OriginalSplineTraversalPolynomialPiece]?]
    private let continuousThroughOrder: Int
    private let retainedMaximumSpanCount: Int
    private let retainedMaximumSubdivisionDepth: Int
    private let retainedMaximumAlgebraicDepth: Int

    public init<B: RationalAlgebraAdmitting>(traversals: [OriginalCurveRootSpan3D],
        stations: [ExactRationalCoefficient], sourceSegmentOrdinals: [Int],
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try tolerance.validate()
        let stationCount = traversals.count.addingReportingOverflow(1)
        guard !traversals.isEmpty, !stationCount.overflow, stations.count == stationCount.partialValue,
            sourceSegmentOrdinals.count == traversals.count, stations.first == .zero,
            stations.last == .one, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original guide chain requires a complete exact normalized partition.")
        }
        try RationalAlgebraStorage.retain(traversals.count, of: OriginalCurveRootSpan3D.self, usage: &usage)
        try RationalAlgebraStorage.retain(stations.count, of: ExactRationalCoefficient.self, usage: &usage)
        try RationalAlgebraStorage.retain(sourceSegmentOrdinals.count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(traversals.count, of: [OriginalSplineTraversalPolynomialPiece]?.self, usage: &usage)
        var pieces: [[OriginalSplineTraversalPolynomialPiece]?] = []; pieces.reserveCapacity(traversals.count)
        var continuity = 3
        var spanCap = Int.max, subdivisionCap = Int.max, algebraCap = Int.max
        for index in traversals.indices {
            let span = traversals[index]
            try usage.consumeExactWork(1)
            let hasC0: Bool
            if case .authored(let first) = span.start, case .authored(let last) = span.end {
                hasC0 = try OriginalCurveTraversalContinuityAdmission().proves(source: span.source,
                    first: .originalDouble(first, usage: &usage), last: .originalDouble(last, usage: &usage),
                    remainingSourceDepth: min(remainingSourceDepth-1, span.remainingSourceDepth),
                    maximumSubdivisionDepth: span.maximumSubdivisionDepth,
                    maximumAlgebraicDepth: span.maximumAlgebraicDepth, tolerance: tolerance, usage: &usage)
            } else if case .bSpline = span.source, span.nativeSpanIndex != nil { hasC0 = true }
            else { hasC0 = false }
            guard span.certificationTolerance == tolerance, sourceSegmentOrdinals[index] >= 0,
                try stations[index+1].subtracting(stations[index], usage: &usage).isPositive, hasC0 else {
                throw GeometryConversionError.invalidInput("Original guide traversal lacks its exact positional continuity or station order.")
            }
            spanCap = min(spanCap, span.maximumSpanCount)
            subdivisionCap = min(subdivisionCap, span.maximumSubdivisionDepth)
            algebraCap = min(algebraCap, span.maximumAlgebraicDepth)
            if index > 0 {
                guard sourceSegmentOrdinals[index] >= sourceSegmentOrdinals[index-1],
                    try OriginalCurveTraversalEndpointRelation().proves(first: traversals[index-1], firstAtEnd: true,
                        second: span, secondAtEnd: false, remainingSourceDepth: remainingSourceDepth-1,
                        usage: &usage) else {
                    throw GeometryConversionError.invalidInput("Original guide traversals have unequal source endpoints or source order.")
                }
            }
            if try OriginalSplineTraversalPolynomialPiece.supports(span, usage: &usage) {
                let original = try OriginalSplineTraversalPolynomialPiece.pieces(span, usage: &usage)
                for adjacent in 1..<original.count {
                    if continuity == 0 { break }
                    for order in 1...continuity {
                        try RationalAlgebraStorage.retain(2, of: OriginalSplineTraversalPolynomialPiece.self, usage: &usage)
                        let a = try OriginalSplineTraversalPolynomialPiece.derivative([original[adjacent-1]],
                            at: original[adjacent-1].upper, order: order, usage: &usage)
                        let b = try OriginalSplineTraversalPolynomialPiece.derivative([original[adjacent]],
                            at: original[adjacent].lower, order: order, usage: &usage)
                        if try !a.subtracting(b, usage: &usage).isZero { continuity = order-1; break }
                    }
                }
                pieces.append(original)
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Nonrational/algebraic-endpoint
                // guide traversals retain their original C0 law here. Higher join
                // publication needs the exact original derivative equality issuer;
                // interval derivative hulls cannot authorize smooth continuity.
                pieces.append(nil); continuity = 0
            }
            if index > 0, continuity > 0, let first = pieces[index-1], let second = pieces[index] {
                let firstWidth = try stations[index].subtracting(stations[index-1], usage: &usage)
                let secondWidth = try stations[index+1].subtracting(stations[index], usage: &usage)
                var firstGain = ExactRationalCoefficient.one, secondGain = ExactRationalCoefficient.one
                for order in 1...continuity {
                    firstGain = try firstGain.divided(by: firstWidth, usage: &usage)
                    secondGain = try secondGain.divided(by: secondWidth, usage: &usage)
                    let a = try OriginalSplineTraversalPolynomialPiece.derivative(first, at: .one,
                        order: order, usage: &usage).scaled(by: firstGain, usage: &usage)
                    let b = try OriginalSplineTraversalPolynomialPiece.derivative(second, at: .zero,
                        order: order, usage: &usage).scaled(by: secondGain, usage: &usage)
                    if try !a.subtracting(b, usage: &usage).isZero { continuity = order-1; break }
                }
            }
        }
        self.traversals = traversals; self.stations = stations
        self.sourceSegmentOrdinals = sourceSegmentOrdinals
        retainedSourceDepth = remainingSourceDepth; rationalPieces = pieces; continuousThroughOrder = continuity
        retainedMaximumSpanCount = spanCap; retainedMaximumSubdivisionDepth = subdivisionCap
        retainedMaximumAlgebraicDepth = algebraCap
    }

    public var domain: ParameterDomain { .closed(0, 1) }
    public var certificationTolerance: ModelingTolerance { traversals[0].certificationTolerance }
    package var remainingSourceDepth: Int { retainedSourceDepth }
    package var maximumSpanCount: Int { retainedMaximumSpanCount }
    package var maximumSubdivisionDepth: Int { retainedMaximumSubdivisionDepth }
    package var maximumAlgebraicDepth: Int { retainedMaximumAlgebraicDepth }
    package var provenContinuityOrder: Int { continuousThroughOrder }
    package func originalEndpoint(at parameter: Double) -> (boundary: OriginalCurveRootSpan3D, atEnd: Bool)? {
        if parameter == 0 { return (traversals[0], false) }
        if parameter == 1 { return (traversals[traversals.count-1], true) }
        return nil
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.traversals == b.traversals && a.stations == b.stations
            && a.sourceSegmentOrdinals == b.sourceSegmentOrdinals
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(traversals); hasher.combine(sourceSegmentOrdinals)
        for station in stations {
            hasher.combine(station.canonicalSign); hasher.combine(station.canonicalNumeratorWords)
            hasher.combine(station.canonicalDenominatorWords)
        }
    }
    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard tolerance == certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original guide chain changed its source tolerance.")
        }
    }

    package func selected<B: RationalAlgebraAdmitting>(over range: ScalarInterval,
        usage: inout B) throws -> [(index: Int, local: ScalarInterval, inverseWidth: ExactRationalCoefficient,
            lower: ExactRationalCoefficient, upper: ExactRationalCoefficient)] {
        guard range.lower >= 0, range.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original guide query exceeds its exact normalized source domain.")
        }
        let lower = try ExactRationalCoefficient.originalDouble(range.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(range.upper, usage: &usage)
        try RationalAlgebraStorage.retain(traversals.count,
            of: (Int, ScalarInterval, ExactRationalCoefficient, ExactRationalCoefficient, ExactRationalCoefficient).self, usage: &usage)
        var result: [(index: Int, local: ScalarInterval, inverseWidth: ExactRationalCoefficient,
            lower: ExactRationalCoefficient, upper: ExactRationalCoefficient)] = []
        result.reserveCapacity(traversals.count)
        for index in traversals.indices {
            let a = stations[index], b = stations[index+1]
            if try upper.subtracting(a, usage: &usage).isNegative
                || b.subtracting(lower, usage: &usage).isNegative { continue }
            let clippedLower = try lower.subtracting(a, usage: &usage).isPositive ? lower : a
            let clippedUpper = try upper.subtracting(b, usage: &usage).isNegative ? upper : b
            let width = try b.subtracting(a, usage: &usage)
            let first = try clippedLower.subtracting(a, usage: &usage).divided(by: width, usage: &usage)
            let last = try clippedUpper.subtracting(a, usage: &usage).divided(by: width, usage: &usage)
            let firstBounds = try first.outwardInterval(usage: &usage), lastBounds = try last.outwardInterval(usage: &usage)
            // Exact source clipping above proves these local parameters belong
            // to [0,1]; clamping only limits their outward query localization.
            let local = try ScalarInterval(lower: max(0, firstBounds.lower), upper: min(1, lastBounds.upper))
            result.append((index, local, try .one.divided(by: width, usage: &usage), clippedLower, clippedUpper))
        }
        guard !result.isEmpty else { throw GeometryConversionError.invalidInput("Original guide query has no selected traversal.") }
        return result
    }
}
