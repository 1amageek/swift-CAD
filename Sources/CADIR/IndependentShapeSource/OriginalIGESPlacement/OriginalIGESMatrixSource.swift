import CADCore
import CADGeometry

/// Original Type124 lexical matrix, form, coordinate unit and later authored actions.
public struct OriginalIGESMatrixSource: Equatable, Sendable {
    public let coefficients: [String]
    public let form: Int
    public let lengthUnit: LengthUnit
    public let adjustments: [OriginalIGESPlacementAdjustment]
    public init(coefficients: [String], form: Int, lengthUnit: LengthUnit,
        adjustments: [OriginalIGESPlacementAdjustment] = []) {
        self.coefficients = coefficients; self.form = form; self.lengthUnit = lengthUnit; self.adjustments = adjustments
    }
    public func originalOperationWord<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        guard coefficients.count == 12, form == 0 || form == 1 else { throw invalid("Original IGES matrix requires twelve coefficients and its actual orthogonal form.") }
        try RationalAlgebraStorage.retain(12, of: ExactRationalCoefficient.self, usage: &usage)
        var exact: [ExactRationalCoefficient] = []; exact.reserveCapacity(12)
        let gain = try OriginalIGESScalarSource.lengthGain(lengthUnit, usage: &usage)
        for index in coefficients.indices {
            let value = try OriginalIGESScalarSource.coefficient(coefficients[index], usage: &usage)
            exact.append(index % 4 == 3 ? try value.multiplied(by: gain, usage: &usage) : value)
        }
        func dot(_ a: Int, _ b: Int, usage: inout B) throws -> ExactRationalCoefficient {
            var result = ExactRationalCoefficient.zero
            for row in 0..<3 { result = try result.adding(exact[row * 4 + a].multiplied(by: exact[row * 4 + b], usage: &usage), usage: &usage) }
            return result
        }
        for axis in 0..<3 {
            guard try dot(axis, axis, usage: &usage) == .one else { throw invalid("Original IGES matrix has a nonunit exact column.") }
            for other in 0..<axis { guard try dot(axis, other, usage: &usage).isZero else { throw invalid("Original IGES matrix has nonorthogonal exact columns.") } }
        }
        let source = try OriginalRationalAffineSource(coefficients: exact, usage: &usage)
        var word = try OriginalAffineOperationWord(operation: .rationalForward(source), tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        guard word.orientationSign == (form == 0 ? 1 : -1) else { throw invalid("Original IGES matrix determinant contradicts its declared form.") }
        for adjustment in adjustments {
            word = try adjustment.applying(to: word, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        }
        return word
    }
    public func derivedAffineTransform<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> AffineTransform3D {
        try OriginalIGESScalarSource.view(of: originalOperationWord(tolerance: tolerance,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage), usage: &usage)
    }
    public func adjusted<B: RationalAlgebraAdmitting>(by displacement: Vector3D, conjugates: Bool, usage: inout B) throws -> Self {
        try displacement.validate()
        let count = adjustments.count.addingReportingOverflow(1)
        guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES matrix adjustment count overflows.") }
        try usage.consumeExactWork(count.partialValue)
        try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &usage)
        return .init(coefficients: coefficients, form: form, lengthUnit: lengthUnit,
            adjustments: adjustments + [.init(displacement: displacement, conjugates: conjugates)])
    }
    private func invalid(_ message: String) -> IndependentShapeSourceError { .invalidSource(message) }
}

#if !hasFeature(Embedded)
extension OriginalIGESMatrixSource: Codable {
    private enum CodingKeys: String, CodingKey { case coefficients, form, lengthUnit, adjustments }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 4)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.coefficients, .form, .lengthUnit, .adjustments], in: decoder)
        coefficients = try OriginalSTEPPlacementDecoding.retainedArray(String.self, from: c.superDecoder(forKey: .coefficients))
        form = try c.decode(Int.self, forKey: .form); lengthUnit = try c.decode(LengthUnit.self, forKey: .lengthUnit)
        adjustments = try OriginalSTEPPlacementDecoding.retainedArray(OriginalIGESPlacementAdjustment.self, from: c.superDecoder(forKey: .adjustments))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(coefficients, forKey: .coefficients); try c.encode(form, forKey: .form)
        try c.encode(lengthUnit, forKey: .lengthUnit); try c.encode(adjustments, forKey: .adjustments)
    }
}
#endif
