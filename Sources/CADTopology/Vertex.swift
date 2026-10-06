import CADCore
import CADGeometry

/// A topological vertex with binary position or retained original spatial authority.
public struct Vertex: Equatable, Sendable {
    public var id: VertexID
    public var point: Point3D
    // FIXME(INCOMPLETE_IMPLEMENTATION): Foreign unit/frame ingress retains this
    // original spatial law. Existing validation, measurement, mesh and transform
    // consumers must use its bounded D0 producer before that source path can
    // publish whole-body success; the point localization alone is not authority.
    public var originalPoint: OriginalAffineWordPoint3D?

    public init(id: VertexID = VertexID(), point: Point3D,
        originalPoint: OriginalAffineWordPoint3D? = nil) {
        self.id = id
        self.point = point
        self.originalPoint = originalPoint
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case id
        case point
        case originalPoint
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .point, .originalPoint], in: decoder)
        id = try container.decode(VertexID.self, forKey: .id)
        point = try container.decode(Point3D.self, forKey: .point)
        originalPoint = try container.decodeIfPresent(OriginalAffineWordPoint3D.self, forKey: .originalPoint)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(point, forKey: .point)
        try container.encodeIfPresent(originalPoint, forKey: .originalPoint)
    }
    #endif
}

#if !hasFeature(Embedded)
extension Vertex: Codable {}
#endif
