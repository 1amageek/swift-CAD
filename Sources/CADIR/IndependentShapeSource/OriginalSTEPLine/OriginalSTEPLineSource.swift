import CADCore
import CADGeometry

/// The original LINE parameter derivative and its named standard records.
public struct OriginalSTEPLineSource: Equatable, Sendable {
    public let location: OriginalSTEPPlacementElement
    public let direction: OriginalSTEPPlacementElement
    public let vectorID: PortableIdentity128
    public let vectorName: String
    public let magnitude: Double
    public let lengthUnit: LengthUnit
    public let originalLengthSource: OriginalSTEPLengthSource?
    public let adjustments: [OriginalSTEPPlacementAdjustment]
    public init(location: OriginalSTEPPlacementElement, direction: OriginalSTEPPlacementElement,
        vectorID: PortableIdentity128, vectorName: String, magnitude: Double, lengthUnit: LengthUnit,
        originalLengthSource: OriginalSTEPLengthSource?, adjustments: [OriginalSTEPPlacementAdjustment] = []) {
        self.location = location; self.direction = direction; self.vectorID = vectorID; self.vectorName = vectorName
        self.magnitude = magnitude; self.lengthUnit = lengthUnit; self.originalLengthSource = originalLengthSource
        self.adjustments = adjustments
    }
    public func originalOperationWord<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        try usage.consumeExactWork(location.name.utf8.count + direction.name.utf8.count + vectorName.utf8.count + 3)
        try location.coordinates.validate(); try direction.coordinates.validate()
        guard magnitude.isFinite, magnitude > 0 else { throw IndependentShapeSourceError.invalidSource("Original LINE magnitude must be positive and finite.") }
        let raw = direction.coordinates
        // Crossing a cardinal axis only permutes/signs original coefficients: no rounded derived frame authority.
        let helper = raw.x == 0 && raw.y == 0 ? Vector3D.unitY : .unitZ
        let perpendicular = raw.cross(helper)
        let gain = try originalLengthSource?.exactGain(maximumDepth: maximumSourceDepth, usage: &usage)
            ?? ExactRationalCoefficient.originalDouble(lengthUnit.toInternal(1), usage: &usage)
        try usage.consumeExactWork(adjustments.count)
        let bytes = adjustments.count.multipliedReportingOverflow(by: MemoryLayout<OriginalNormalizedAffineAdjustment>.stride)
        guard !bytes.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original LINE adjustment storage overflows.") }
        try usage.retainExactStorage(bytes.partialValue / MemoryLayout<UInt32>.stride + (bytes.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1))
        var operations: [OriginalNormalizedAffineAdjustment] = []; operations.reserveCapacity(adjustments.count)
        for operation in adjustments { operations.append(.init(displacement: operation.displacement, conjugates: operation.conjugates)) }
        let law = OriginalNormalizedAffineSource(family: .cartesian, location: location.coordinates,
            axis1: raw, axis2: helper, axis3: perpendicular, scale: magnitude, lengthGain: gain, linearGain: gain, adjustments: operations)
        return try OriginalAffineOperationWord(operation: .normalizedForward(law), tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
    }
    public func translated(by displacement: Vector3D) throws -> Self {
        try displacement.validate()
        return .init(location: location, direction: direction, vectorID: vectorID, vectorName: vectorName,
            magnitude: magnitude, lengthUnit: lengthUnit, originalLengthSource: originalLengthSource,
            adjustments: adjustments + [.init(displacement: displacement, conjugates: false)])
    }
    public static func == (first: Self, second: Self) -> Bool {
        first.location == second.location && first.direction == second.direction && first.vectorID == second.vectorID
            && first.vectorName.utf8.elementsEqual(second.vectorName.utf8) && first.magnitude == second.magnitude
            && first.lengthUnit == second.lengthUnit && first.originalLengthSource == second.originalLengthSource && first.adjustments == second.adjustments
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPLineSource: Codable {
    private enum Keys: String, CodingKey { case location, direction, vectorID, vectorName, magnitude, lengthUnit, originalLengthSource, adjustments }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 8)
        let c = try decoder.container(keyedBy: Keys.self)
        try c.validateOnlyExpectedKeys([.location, .direction, .vectorID, .vectorName, .magnitude, .lengthUnit, .originalLengthSource, .adjustments], in: decoder)
        location = try c.decode(OriginalSTEPPlacementElement.self, forKey: .location)
        direction = try c.decode(OriginalSTEPPlacementElement.self, forKey: .direction)
        vectorID = try c.decode(PortableIdentity128.self, forKey: .vectorID); vectorName = try c.decode(String.self, forKey: .vectorName)
        magnitude = try c.decode(Double.self, forKey: .magnitude); lengthUnit = try c.decode(LengthUnit.self, forKey: .lengthUnit)
        originalLengthSource = try c.decode(OriginalSTEPLengthSource?.self, forKey: .originalLengthSource)
        adjustments = try OriginalSTEPPlacementDecoding.adjustments(from: c.superDecoder(forKey: .adjustments))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(location, forKey: .location); try c.encode(direction, forKey: .direction)
        try c.encode(vectorID, forKey: .vectorID); try c.encode(vectorName, forKey: .vectorName)
        try c.encode(magnitude, forKey: .magnitude); try c.encode(lengthUnit, forKey: .lengthUnit)
        try c.encode(originalLengthSource, forKey: .originalLengthSource); try c.encode(adjustments, forKey: .adjustments)
    }
}
#endif
