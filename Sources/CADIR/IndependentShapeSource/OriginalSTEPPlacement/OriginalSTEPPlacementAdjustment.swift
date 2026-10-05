import CADCore
import CADGeometry

/// An authored world displacement applied after the retained original operator.
public struct OriginalSTEPPlacementAdjustment: Equatable, Sendable {
    public let displacement: Vector3D
    public let conjugates: Bool
    public init(displacement: Vector3D, conjugates: Bool) {
        self.displacement = displacement; self.conjugates = conjugates
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPPlacementAdjustment: Codable {
    private enum Keys: String, CodingKey { case displacement, conjugates }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 2)
        let object = try decoder.container(keyedBy: Keys.self)
        try object.validateOnlyExpectedKeys([.displacement, .conjugates], in: decoder)
        displacement = try IndependentShapeFrameDecoding.decodeVector(from: object.superDecoder(forKey: .displacement))
        conjugates = try object.decode(Bool.self, forKey: .conjugates)
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(displacement, forKey: .displacement); try object.encode(conjugates, forKey: .conjugates)
    }
}
#endif
