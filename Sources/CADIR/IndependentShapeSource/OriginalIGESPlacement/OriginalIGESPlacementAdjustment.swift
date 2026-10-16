import CADCore
import CADGeometry

/// A subsequently authored world displacement and its original scope.
public struct OriginalIGESPlacementAdjustment: Equatable, Sendable {
    public let displacement: Vector3D
    public let conjugates: Bool
    public init(displacement: Vector3D, conjugates: Bool) { self.displacement = displacement; self.conjugates = conjugates }
    package func applying(to word: OriginalAffineOperationWord,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalAffineOperationWord {
        try displacement.validate()
        let action = try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: displacement)
        if !conjugates { return try word.appending(.forward(action), tolerance: tolerance, usage: &execution) }
        let count = word.factors.count.addingReportingOverflow(2)
        guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES adjustment factor count overflows.") }
        try RationalAlgebraStorage.retain(count.partialValue, of: OriginalAffineOperation.self, usage: &execution)
        var factors: [OriginalAffineOperation] = []; factors.reserveCapacity(count.partialValue)
        factors.append(.inverse(action)); factors.append(contentsOf: word.factors); factors.append(.forward(action))
        return try OriginalAffineOperationWord(factors: factors, tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &execution)
    }
}

#if !hasFeature(Embedded)
extension OriginalIGESPlacementAdjustment: Codable {
    private enum CodingKeys: String, CodingKey { case displacement, conjugates }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 2)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.displacement, .conjugates], in: decoder)
        displacement = try IndependentShapeFrameDecoding.decodeVector(from: c.superDecoder(forKey: .displacement))
        conjugates = try c.decode(Bool.self, forKey: .conjugates)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displacement, forKey: .displacement); try c.encode(conjugates, forKey: .conjugates)
    }
}
#endif
