import CADCore

public struct ProductClippingPlane: Equatable, Sendable {
    public var origin: Point3D
    public var normal: Vector3D
    public var keepPositive: Bool
    public init(origin: Point3D, normal: Vector3D, keepPositive: Bool = true) {
        self.origin = origin; self.normal = normal; self.keepPositive = keepPositive
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case origin, normal, keepPositive }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.origin, .normal, .keepPositive], in: decoder)
        origin = try c.decode(Point3D.self, forKey: .origin)
        normal = try c.decode(Vector3D.self, forKey: .normal)
        keepPositive = try c.decode(Bool.self, forKey: .keepPositive)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(origin, forKey: .origin)
        try c.encode(normal, forKey: .normal)
        try c.encode(keepPositive, forKey: .keepPositive)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductClippingPlane: Codable {}
#endif
