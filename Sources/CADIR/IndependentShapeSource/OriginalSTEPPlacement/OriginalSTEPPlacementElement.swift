import CADCore
import CADGeometry

/// An original named point or direction record selected by a standard placement.
public struct OriginalSTEPPlacementElement: Equatable, Sendable {
    public let id: PortableIdentity128
    public let name: String
    public let coordinates: Vector3D
    public init(id: PortableIdentity128, name: String, coordinates: Vector3D) {
        self.id = id; self.name = name; self.coordinates = coordinates
    }
    public static func == (first: Self, second: Self) -> Bool {
        first.id == second.id && first.name.utf8.elementsEqual(second.name.utf8)
            && first.coordinates == second.coordinates
    }
}
#if !hasFeature(Embedded)
extension OriginalSTEPPlacementElement: Codable {
    private enum Keys: String, CodingKey { case id, name, coordinates }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 3)
        let object = try decoder.container(keyedBy: Keys.self)
        try object.validateOnlyExpectedKeys([.id, .name, .coordinates], in: decoder)
        id = try OriginalSTEPIdentityCoding.decode(from: object.superDecoder(forKey: .id))
        name = try object.decode(String.self, forKey: .name)
        let vectorDecoder = try object.superDecoder(forKey: .coordinates)
        coordinates = try IndependentShapeFrameDecoding.decodeVector(from: vectorDecoder)
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        try object.encode(id.canonicalString, forKey: .id); try object.encode(name, forKey: .name)
        try object.encode(coordinates, forKey: .coordinates)
    }
}
#endif
