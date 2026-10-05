import CADCore

/// Immutable original point position under an exact ordered spatial word.
public struct OriginalAffineWordPoint3D: Hashable, Sendable {
    public let point: Point3D
    public let word: OriginalAffineOperationWord
    private let prepared: PreparedOriginalAffineOperationWord
    private let algebraDepth: Int

    public init<B: RationalAlgebraAdmitting>(point: Point3D, word: OriginalAffineOperationWord,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int, usage: inout B) throws {
        try tolerance.validate()
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            (0...32).contains(maximumAlgebraicDepth), point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            throw GeometryConversionError.invalidInput("Original spatial point requires finite coordinates and independent caller capabilities.")
        }
        try usage.consumeExactWork(3)
        let selected = try OriginalAffineOperationWord(factors: word.factors,
            tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        try selected.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        self.point = point; self.word = selected
        prepared = try selected.prepared(usage: &usage); algebraDepth = maximumAlgebraicDepth
    }

    public static func == (a: Self, b: Self) -> Bool { a.point == b.point && a.word == b.word }
    public func hash(into hasher: inout Hasher) { hasher.combine(point); hasher.combine(word) }

    public func enclosure<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> CoordinateEnclosure3D {
        try tolerance.validate()
        guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
            (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original spatial point query requires caller capabilities.")
        }
        let action: PreparedOriginalAffineOperationWord
        if maximumAlgebraicDepth < algebraDepth {
            let selected = try OriginalAffineOperationWord(factors: word.factors, tolerance: tolerance,
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
            try selected.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            action = try selected.prepared(usage: &usage)
        } else {
            try word.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            action = prepared
        }
        try usage.consumeExactWork(3)
        let original = try CoordinateEnclosure3D(x: .init(lower: point.x, upper: point.x),
            y: .init(lower: point.y, upper: point.y), z: .init(lower: point.z, upper: point.z))
        return try action.enclosure(of: original, isPosition: true, usage: &usage)
    }

    public func localization<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> Point3D {
        let box = try enclosure(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        let candidate = Point3D(x: box.x.lower * 0.5 + box.x.upper * 0.5,
            y: box.y.lower * 0.5 + box.y.upper * 0.5, z: box.z.lower * 0.5 + box.z.upper * 0.5)
        try usage.consumeExactWork(9)
        let error = IntervalVector3DBounds(
            x: OutwardScalarInterval(lower: box.x.lower, upper: box.x.upper) - .exact(candidate.x),
            y: OutwardScalarInterval(lower: box.y.lower, upper: box.y.upper) - .exact(candidate.y),
            z: OutwardScalarInterval(lower: box.z.lower, upper: box.z.upper) - .exact(candidate.z))
        guard error.lengthUpperBound <= tolerance.distance else { throw GeometryConversionError.toleranceRejected }
        return candidate
    }

    public func appending<B: RationalAlgebraAdmitting>(_ operation: OriginalAffineOperation,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> Self {
        let selected = try OriginalAffineOperationWord(factors: word.factors, tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let next = try selected.appending(operation, tolerance: tolerance, usage: &usage)
        return try .init(point: point, word: next, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
    }
}
