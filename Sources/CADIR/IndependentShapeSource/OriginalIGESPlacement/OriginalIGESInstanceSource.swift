import CADCore
import CADGeometry

/// Type408's original parameter scale, shared matrix identity and parameter translation.
public struct OriginalIGESInstanceSource: Equatable, Sendable {
    public let matrixFrameID: IndependentShapeFrameID?
    public let scale: String
    public let translation: [String]
    public let lengthUnit: LengthUnit
    public let adjustments: [OriginalIGESPlacementAdjustment]
    public init(matrixFrameID: IndependentShapeFrameID?, scale: String, translation: [String], lengthUnit: LengthUnit,
        adjustments: [OriginalIGESPlacementAdjustment] = []) {
        self.matrixFrameID = matrixFrameID; self.scale = scale; self.translation = translation
        self.lengthUnit = lengthUnit; self.adjustments = adjustments
    }
    public func originalOperationWord<B: RationalAlgebraAdmitting>(matrix: OriginalIGESMatrixSource?,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        guard translation.count == 3, (matrixFrameID == nil) == (matrix == nil),
            matrix == nil || matrix?.lengthUnit == lengthUnit else {
            throw IndependentShapeSourceError.invalidSource("Original IGES instance matrix/unit/translation source is inconsistent.")
        }
        let originalScale = try OriginalIGESScalarSource.coefficient(scale, usage: &usage)
        guard originalScale.isPositive else { throw IndependentShapeSourceError.invalidSource("Original IGES instance scale must be positive.") }
        try RationalAlgebraStorage.retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        let scaleSource = try OriginalRationalAffineSource(coefficients: [originalScale, .zero, .zero, .zero,
            .zero, originalScale, .zero, .zero, .zero, .zero, originalScale, .zero], usage: &usage)
        var word = try OriginalAffineOperationWord(operation: .rationalForward(scaleSource), tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        if let matrix {
            let matrixWord = try matrix.originalOperationWord(tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
            for factor in matrixWord.factors { word = try word.appending(factor, tolerance: tolerance, usage: &usage) }
        }
        let gain = try OriginalIGESScalarSource.lengthGain(lengthUnit, usage: &usage)
        let x = try OriginalIGESScalarSource.coefficient(translation[0], usage: &usage).multiplied(by: gain, usage: &usage)
        let y = try OriginalIGESScalarSource.coefficient(translation[1], usage: &usage).multiplied(by: gain, usage: &usage)
        let z = try OriginalIGESScalarSource.coefficient(translation[2], usage: &usage).multiplied(by: gain, usage: &usage)
        try RationalAlgebraStorage.retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        let translated = try OriginalRationalAffineSource(coefficients: [.one, .zero, .zero, x,
            .zero, .one, .zero, y, .zero, .zero, .one, z], usage: &usage)
        word = try word.appending(.rationalForward(translated), tolerance: tolerance, usage: &usage)
        for adjustment in adjustments { word = try adjustment.applying(to: word, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage) }
        return word
    }
    public func derivedAffineTransform<B: RationalAlgebraAdmitting>(matrix: OriginalIGESMatrixSource?, tolerance: ModelingTolerance,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> AffineTransform3D {
        try OriginalIGESScalarSource.view(of: originalOperationWord(matrix: matrix, tolerance: tolerance,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage), usage: &usage)
    }
    public func adjusted<B: RationalAlgebraAdmitting>(by displacement: Vector3D, conjugates: Bool, usage: inout B) throws -> Self {
        try displacement.validate()
        let count = adjustments.count.addingReportingOverflow(1)
        guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES instance adjustment count overflows.") }
        try usage.consumeExactWork(count.partialValue)
        try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &usage)
        return .init(matrixFrameID: matrixFrameID, scale: scale, translation: translation, lengthUnit: lengthUnit,
            adjustments: adjustments + [.init(displacement: displacement, conjugates: conjugates)])
    }
}

#if !hasFeature(Embedded)
extension OriginalIGESInstanceSource: Codable {
    private enum CodingKeys: String, CodingKey { case matrixFrameID, scale, translation, lengthUnit, adjustments }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 5)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.matrixFrameID, .scale, .translation, .lengthUnit, .adjustments], in: decoder)
        matrixFrameID = try c.decode(IndependentShapeFrameID?.self, forKey: .matrixFrameID)
        scale = try c.decode(String.self, forKey: .scale); translation = try OriginalSTEPPlacementDecoding.retainedArray(String.self, from: c.superDecoder(forKey: .translation))
        lengthUnit = try c.decode(LengthUnit.self, forKey: .lengthUnit)
        adjustments = try OriginalSTEPPlacementDecoding.retainedArray(OriginalIGESPlacementAdjustment.self, from: c.superDecoder(forKey: .adjustments))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(matrixFrameID, forKey: .matrixFrameID); try c.encode(scale, forKey: .scale)
        try c.encode(translation, forKey: .translation); try c.encode(lengthUnit, forKey: .lengthUnit)
        try c.encode(adjustments, forKey: .adjustments)
    }
}
#endif
