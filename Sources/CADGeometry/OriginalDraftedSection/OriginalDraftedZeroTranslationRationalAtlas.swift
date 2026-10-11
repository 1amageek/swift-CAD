import CADCore

/// Exact original position of the canonical zero-angle translation branch.
struct OriginalDraftedZeroTranslationRationalAtlas: Sendable {
    struct Cell: Sendable {
        let lowerU: ExactRationalCoefficient
        let upperU: ExactRationalCoefficient
        let lowerV: ExactRationalCoefficient
        let upperV: ExactRationalCoefficient
        let homogeneous: [ExactBivariatePolynomial]
    }
    private typealias P = ExactBivariatePolynomial
    private typealias Q = ExactRationalCoefficient
    let cells: [Cell]
    let generatorOffset: ExactRationalCoefficient
    let generatorGain: ExactRationalCoefficient
    private let original: OriginalDraftedRuledSurface3D

    static func supports(_ source: borrowing OriginalDraftedRuledSurface3D) -> Bool {
        translationCapability(source) != nil
    }

    private static func translationCapability(_ source: borrowing OriginalDraftedRuledSurface3D)
        -> (axis: Int, rawAxis: Double, first: Double, last: Double)? {
        let start = source.start, traversal = start.generator
        // FIXME(INCOMPLETE_IMPLEMENTATION): General draft angles, axes and child
        // source families lack their original ordered-field position atlas. Source
        // issuance must reject them before whole-domain success publication.
        guard start.angle == 0, start.pull == start.axis,
            case .bSpline = traversal.source,
            case .authored(let first) = traversal.start,
            case .authored(let last) = traversal.end else { return nil }
        let axis: Int, rawAxis: Double, clearance: Double
        if start.axis.x != 0, start.axis.y == 0, start.axis.z == 0 {
            axis = 0; rawAxis = start.axis.x; clearance = start.normal.x
        } else if start.axis.x == 0, start.axis.y != 0, start.axis.z == 0 {
            axis = 1; rawAxis = start.axis.y; clearance = start.normal.y
        } else if start.axis.x == 0, start.axis.y == 0, start.axis.z != 0 {
            axis = 2; rawAxis = start.axis.z; clearance = start.normal.z
        } else { return nil }
        // Nonzero original component / positive normal length proves clearance;
        // cached interval direction enclosures never supply exact coefficients.
        guard clearance != 0 else { return nil }
        return (axis, rawAxis, first, last)
    }

    static func prepared<B: RationalAlgebraAdmitting>(_ source: OriginalDraftedRuledSurface3D,
        usage: inout B) throws -> Self? {
        try usage.consumeExactWork(1)
        try source.validate(tolerance: source.certificationTolerance)
        guard source.remainingSourceDepth > 1, source.start.remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original drafted wall retained source depth is exhausted.")
        }
        guard let capability = translationCapability(source) else { return nil }
        let start = source.start, traversal = start.generator
        let axis = capability.axis, rawAxis = capability.rawAxis
        let first = capability.first, last = capability.last
        let direction = try Q.originalDouble(rawAxis > 0 ? 1 : -1, usage: &usage)
        let generatorOffset = try Q.originalDouble(first, usage: &usage)
        let generatorGain = try Q.originalDouble(last, usage: &usage).subtracting(generatorOffset, usage: &usage)
        let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(traversal, usage: &usage)
        guard pieces.count <= source.maximumSpanCount else {
            throw GeometryConversionError.resourceLimitExceeded("Original drafted wall exceeds its retained span capability.")
        }
        let height = try Q.originalDouble(start.height, usage: &usage)
        let heightGain = try Q.originalDouble(source.endHeight, usage: &usage).subtracting(height, usage: &usage)
        let translation = try P.coordinate(alongU: false, usage: &usage)
            .scaled(by: heightGain, usage: &usage)
            .adding(.constant(height, usage: &usage), usage: &usage)
            .scaled(by: direction, usage: &usage)
        try RationalAlgebraStorage.retain(pieces.count, of: Cell.self, usage: &usage)
        var cells: [Cell] = []; cells.reserveCapacity(pieces.count)
        for piece in pieces {
            try usage.consumeExactWork(1)
            guard piece.homogeneous.count == 4, !piece.lower.isNegative,
                try !Q.one.subtracting(piece.upper, usage: &usage).isNegative,
                try piece.upper.subtracting(piece.lower, usage: &usage).isPositive else {
                throw GeometryConversionError.invalidInput("Original drafted wall has invalid original traversal support.")
            }
            try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
            var position: [P] = []; position.reserveCapacity(4)
            for coordinate in 0..<3 {
                try usage.consumeExactWork(1)
                position.append(try coordinate == axis
                    ? piece.homogeneous[coordinate].adding(piece.homogeneous[3].multiplied(by: translation, usage: &usage), usage: &usage)
                    : piece.homogeneous[coordinate])
            }
            // Validated Native positive weights and its closed nonnegative
            // partition-of-unity basis prove this unchanged denominator positive.
            position.append(piece.homogeneous[3])
            cells.append(.init(lowerU: piece.lower, upperU: piece.upper,
                lowerV: .zero, upperV: .one, homogeneous: position))
        }
        guard !cells.isEmpty else {
            throw GeometryConversionError.invalidInput("Original drafted wall has no original position cells.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try exactScalarTaskCheckpoint()
        return Self(cells: cells, generatorOffset: generatorOffset,
            generatorGain: generatorGain, original: source)
    }
}
