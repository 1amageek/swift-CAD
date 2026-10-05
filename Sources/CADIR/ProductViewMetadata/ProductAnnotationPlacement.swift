import CADCore

public struct ProductAnnotationPlacement: Equatable, Sendable {
    public var annotationID: ProductMetadataID
    public var origin: Point3D
    public var direction: Vector3D
    public var up: Vector3D
    public var basisX: Vector3D
    public var mappingOrigin: Point3D
    public var mappingDirection: Vector3D
    public var mappingUp: Vector3D
    public var scale: Double
    public init(annotationID: ProductMetadataID, origin: Point3D, direction: Vector3D, up: Vector3D, scale: Double = 1, basisX: Vector3D? = nil,
                mappingOrigin: Point3D = .origin, mappingDirection: Vector3D = .unitZ, mappingUp: Vector3D = .unitY) {
        self.annotationID = annotationID; self.origin = origin; self.direction = direction; self.up = up; self.scale = scale
        self.basisX = basisX ?? up.cross(direction)
        self.mappingOrigin = mappingOrigin; self.mappingDirection = mappingDirection; self.mappingUp = mappingUp
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case annotationID, origin, direction, up, scale, basisX, mappingOrigin, mappingDirection, mappingUp }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.annotationID, .origin, .direction, .up, .scale, .basisX, .mappingOrigin, .mappingDirection, .mappingUp], in: decoder)
        annotationID = try c.decode(ProductMetadataID.self, forKey: .annotationID)
        origin = try c.decode(Point3D.self, forKey: .origin)
        direction = try c.decode(Vector3D.self, forKey: .direction)
        up = try c.decode(Vector3D.self, forKey: .up)
        basisX = try c.decode(Vector3D.self, forKey: .basisX)
        mappingOrigin = try c.decode(Point3D.self, forKey: .mappingOrigin)
        mappingDirection = try c.decode(Vector3D.self, forKey: .mappingDirection)
        mappingUp = try c.decode(Vector3D.self, forKey: .mappingUp)
        scale = try c.decode(Double.self, forKey: .scale)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(annotationID, forKey: .annotationID)
        try c.encode(origin, forKey: .origin)
        try c.encode(direction, forKey: .direction)
        try c.encode(up, forKey: .up)
        try c.encode(basisX, forKey: .basisX)
        try c.encode(mappingOrigin, forKey: .mappingOrigin)
        try c.encode(mappingDirection, forKey: .mappingDirection)
        try c.encode(mappingUp, forKey: .mappingUp)
        try c.encode(scale, forKey: .scale)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductAnnotationPlacement: Codable {}
#endif
