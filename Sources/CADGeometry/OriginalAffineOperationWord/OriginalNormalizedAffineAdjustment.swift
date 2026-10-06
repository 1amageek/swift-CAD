import CADCore

/// One authored world offset, or its original frame conjugation operation.
public struct OriginalNormalizedAffineAdjustment: Hashable, Sendable {
    public let displacement: Vector3D
    public let conjugates: Bool
    public init(displacement: Vector3D, conjugates: Bool) {
        self.displacement = displacement; self.conjugates = conjugates
    }
}
#if !hasFeature(Embedded)
extension OriginalNormalizedAffineAdjustment: Codable {}
#endif
