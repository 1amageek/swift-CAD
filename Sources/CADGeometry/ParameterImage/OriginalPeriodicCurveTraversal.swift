import CADCore

/// Builds a persistent normalized traversal from original endpoints and exact turns.
public enum OriginalPeriodicCurveTraversal {
    public static func normalized<B: RationalAlgebraAdmitting>(source: Curve3D,
        originalStart: Double, originalEnd: Double,
        translation: OriginalParameterPeriodicTranslation,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws -> ParameterImageCurve3D {
        guard originalStart.isFinite, originalEnd.isFinite, remainingSourceDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original cyclic traversal requires finite selectors and source admission.")
        }
        try source.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try usage.consumeExactWork(1) })
        func authority(_ curve: Curve3D, depth: Int) throws -> (period: Double, gain: ExactRationalCoefficient) {
            try usage.consumeExactWork(1)
            guard depth >= 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original cyclic source authority exhausted caller depth.")
            }
            switch curve {
            case .parameterImage(let image):
                guard depth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original cyclic image exhausted source depth.") }
                let original = try authority(image.source, depth: depth - 1)
                return try (original.period, original.gain.multiplied(by: image.parameterGain.exactCoefficient(usage: &usage), usage: &usage))
            case .rigidImage(let image): return try authority(image.source, depth: depth - 1)
            case .affineImage(let image): return try authority(image.source, depth: depth - 1)
            case .originalAffineWord(let image): return try authority(image.source, depth: depth - 1)
            default:
                guard case .periodic(let period) = curve.parameterDomain else {
                    throw GeometryConversionError.invalidInput("Original cyclic traversal is not bound to a periodic source law.")
                }
                return (period, .one)
            }
        }
        let original = try authority(source, depth: remainingSourceDepth)
        guard original.period == translation.originalSourcePeriod,
              original.gain == (try translation.parameterGain.exactCoefficient(usage: &usage)) else {
            throw GeometryConversionError.invalidInput("Original cyclic translation belongs to another source period or parameter gain.")
        }
        let gain = try OriginalParameterGain.originalDifference(originalLower: originalStart,
            originalUpper: originalEnd, periodicTranslation: translation, usage: &usage)
        // The nested image retains all source endpoints and exact translation in
        // the gain source value. A rounded foreign period is never constructed.
        return ParameterImageCurve3D(validatedSource: source, parameterGain: gain, offset: originalStart)
    }
}
