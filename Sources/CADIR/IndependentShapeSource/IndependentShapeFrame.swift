import CADCore
import CADGeometry

/// One original coordinate-system owner, shared by actual memberships and maps.
public struct IndependentShapeFrame: Equatable, Sendable {
    public let id: IndependentShapeFrameID
    public let name: String
    public let placement: AffineTransform3D
    public let originalSTEPPlacement: OriginalSTEPPlacementSource?
    public let originalIGES: OriginalIGESMatrixSource?
    public init(id: IndependentShapeFrameID = .init(), name: String = "", placement: AffineTransform3D, originalSTEPPlacement: OriginalSTEPPlacementSource? = nil, originalIGES: OriginalIGESMatrixSource? = nil) {
        self.id = id; self.name = name; self.placement = placement; self.originalSTEPPlacement = originalSTEPPlacement; self.originalIGES = originalIGES
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, placement, originalSTEPPlacement, originalIGES }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 5)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .placement, .originalSTEPPlacement, .originalIGES], in: decoder)
        id = try c.decode(IndependentShapeFrameID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        placement = try IndependentShapeFrameDecoding.decode(from: c.superDecoder(forKey: .placement))
        originalSTEPPlacement = try c.decode(OriginalSTEPPlacementSource?.self, forKey: .originalSTEPPlacement)
        originalIGES = try c.decode(OriginalIGESMatrixSource?.self, forKey: .originalIGES)
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: CodingKeys.self)
        try object.encode(id, forKey: .id)
        try object.encode(name, forKey: .name)
        try object.encode(placement, forKey: .placement)
        try object.encode(originalSTEPPlacement, forKey: .originalSTEPPlacement)
        try object.encode(originalIGES, forKey: .originalIGES)
    }
    #endif
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.name.utf8.elementsEqual(b.name.utf8) && a.placement == b.placement && a.originalSTEPPlacement == b.originalSTEPPlacement && a.originalIGES == b.originalIGES
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeFrame: Codable {}
#endif
