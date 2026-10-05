import CADCore
import CADGeometry

public struct IndependentShapeInstance: Equatable, Sendable {
    public let id: IndependentShapeInstanceID
    public let name: String
    public let placementName: String
    public let target: IndependentShapeDefinitionID
    public let placement: AffineTransform3D
    public let originalSTEPPlacement: OriginalSTEPPlacementSource?
    public let originalIGES: OriginalIGESInstanceSource?
    public init(id: IndependentShapeInstanceID = .init(), name: String = "", placementName: String = "", target: IndependentShapeDefinitionID, placement: AffineTransform3D, originalSTEPPlacement: OriginalSTEPPlacementSource? = nil, originalIGES: OriginalIGESInstanceSource? = nil) {
        self.id = id; self.name = name; self.placementName = placementName; self.target = target; self.placement = placement; self.originalSTEPPlacement = originalSTEPPlacement; self.originalIGES = originalIGES
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, placementName, target, placement, originalSTEPPlacement, originalIGES }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 7)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .placementName, .target, .placement, .originalSTEPPlacement, .originalIGES], in: decoder)
        id = try c.decode(IndependentShapeInstanceID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        placementName = try c.decode(String.self, forKey: .placementName)
        target = try c.decode(IndependentShapeDefinitionID.self, forKey: .target)
        placement = try IndependentShapeFrameDecoding.decode(from: c.superDecoder(forKey: .placement))
        originalSTEPPlacement = try c.decode(OriginalSTEPPlacementSource?.self, forKey: .originalSTEPPlacement)
        originalIGES = try c.decode(OriginalIGESInstanceSource?.self, forKey: .originalIGES)
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: CodingKeys.self)
        try object.encode(id, forKey: .id)
        try object.encode(name, forKey: .name)
        try object.encode(placementName, forKey: .placementName)
        try object.encode(target, forKey: .target)
        try object.encode(placement, forKey: .placement)
        try object.encode(originalSTEPPlacement, forKey: .originalSTEPPlacement)
        try object.encode(originalIGES, forKey: .originalIGES)
    }
    #endif
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.placementName.utf8.elementsEqual(rhs.placementName.utf8) && lhs.target == rhs.target && lhs.placement == rhs.placement && lhs.originalSTEPPlacement == rhs.originalSTEPPlacement && lhs.originalIGES == rhs.originalIGES
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeInstance: Codable {}
#endif
