import CADCore
import CADGeometry
import CADIR

/// Original normative model-coordinate gain without a rounded binary SI matrix.
enum IndependentSTEPLengthLaw {
    static func coordinateWord(source: OriginalSTEPLengthSource?, units: UnitSystem,
        tolerance: ModelingTolerance, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalAffineOperationWord {
        let gain = try source?.exactGain(maximumDepth: usage.limits.maximumNesting, using: &execution)
            ?? ExactRationalCoefficient.originalDouble(units.length.toInternal(1), usage: &execution)
        let law = OriginalNormalizedAffineSource(family: .axis2, location: .zero,
            axis1: nil, axis2: nil, axis3: nil, scale: nil,
            lengthGain: gain, linearGain: gain, adjustments: [])
        return try OriginalAffineOperationWord(operation: .normalizedForward(law),
            tolerance: tolerance, maximumDepth: usage.limits.maximumAlgebraicDepth, usage: &execution)
    }
}
