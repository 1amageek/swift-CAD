import CADCore
import CADGeometry

/// One tool of Imprint Body Body: a solid or sheet crossing the target where `placement` puts it
/// in the target's frame (where it is, when nil).
public struct ImprintBodyTool: Codable, Hashable, Sendable {
    public var body: PatternTargetReference
    public var placement: RigidTransform3D?

    public init(body: PatternTargetReference, placement: RigidTransform3D? = nil) {
        self.body = body
        self.placement = placement
    }

    private enum CodingKeys: String, CodingKey {
        case body, placement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.body, .placement], in: decoder)
        body = try container.decode(PatternTargetReference.self, forKey: .body)
        placement = try container.decodeIfPresent(RigidTransform3D.self, forKey: .placement)
        try body.validate()
    }

    public func encode(to encoder: Encoder) throws {
        try body.validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(placement, forKey: .placement)
    }
}
