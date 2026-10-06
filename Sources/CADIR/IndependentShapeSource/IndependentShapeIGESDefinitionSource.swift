import CADCore
import CADGeometry

/// The original forward subfigure operation and its separately authored directory label.
public struct IndependentShapeIGESDefinitionSource: Equatable, Sendable {
    public let directoryLabel: String
    public let definingFrameID: IndependentShapeFrameID?
    public let adjustments: [OriginalIGESPlacementAdjustment]
    public init(directoryLabel: String, definingFrameID: IndependentShapeFrameID?, adjustments: [OriginalIGESPlacementAdjustment] = []) {
        self.directoryLabel = directoryLabel; self.definingFrameID = definingFrameID; self.adjustments = adjustments
    }
    public func originalOperationWord<B: RationalAlgebraAdmitting>(frame: OriginalIGESMatrixSource?,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        guard (definingFrameID == nil) == (frame == nil) else { throw IndependentShapeSourceError.invalidSource("Original IGES definition forward frame is inconsistent.") }
        var word: OriginalAffineOperationWord
        if let frame { word = try frame.originalOperationWord(tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage) }
        else {
            word = try OriginalAffineOperationWord(operation: .forward(try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)),
                tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        }
        for adjustment in adjustments { word = try adjustment.applying(to: word, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage) }
        return word
    }
    public func adjusted<B: RationalAlgebraAdmitting>(by displacement: Vector3D, usage: inout B) throws -> Self {
        try displacement.validate()
        let count = adjustments.count.addingReportingOverflow(1)
        guard !count.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original IGES definition adjustment count overflows.") }
        try usage.consumeExactWork(count.partialValue)
        try RationalAlgebraStorage.retain(count.partialValue, of: OriginalIGESPlacementAdjustment.self, usage: &usage)
        return .init(directoryLabel: directoryLabel, definingFrameID: definingFrameID,
            adjustments: adjustments + [.init(displacement: displacement, conjugates: true)])
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.directoryLabel.utf8.elementsEqual(b.directoryLabel.utf8) && a.definingFrameID == b.definingFrameID && a.adjustments == b.adjustments
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeIGESDefinitionSource: Codable {
    private enum CodingKeys: String, CodingKey { case directoryLabel, definingFrameID, adjustments }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 3)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.directoryLabel, .definingFrameID, .adjustments], in: decoder)
        directoryLabel = try c.decode(String.self, forKey: .directoryLabel)
        definingFrameID = try c.decode(IndependentShapeFrameID?.self, forKey: .definingFrameID)
        adjustments = try OriginalSTEPPlacementDecoding.retainedArray(OriginalIGESPlacementAdjustment.self, from: c.superDecoder(forKey: .adjustments))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(directoryLabel, forKey: .directoryLabel)
        try c.encode(definingFrameID, forKey: .definingFrameID); try c.encode(adjustments, forKey: .adjustments)
    }
}
#endif
