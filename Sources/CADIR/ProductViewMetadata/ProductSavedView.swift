import CADCore

public struct ProductSavedView: Equatable, Sendable {
    public enum Projection: String, Sendable { case parallel, perspective }
    public enum WindowPlacement: String, Sendable { case twoDimensional, threeDimensional }
    public let id: ProductMetadataID
    public var name: String
    public var origin: Point3D
    public var direction: Vector3D
    public var up: Vector3D
    public var projection: Projection
    public var horizontalSize: Double
    public var verticalSize: Double
    public var focalDistance: Double
    public var nearDistance: Double
    public var farDistance: Double
    public var projectionPoint: Point3D
    public var windowOrigin: Point3D
    public var windowPlacement: WindowPlacement
    public var windowDirection: Vector3D
    public var windowUp: Vector3D
    public var frontClipping: Bool
    public var backClipping: Bool
    public var sideClipping: Bool
    public var clippingExpression: ProductClippingExpression?
    public var clippingPlanes: [ProductClippingPlane]
    public var annotationPlacements: [ProductAnnotationPlacement]
    public init(id: ProductMetadataID = ProductMetadataID(), name: String, origin: Point3D, direction: Vector3D, up: Vector3D,
                projection: Projection = .parallel, horizontalSize: Double, verticalSize: Double,
                focalDistance: Double, nearDistance: Double, farDistance: Double,
                clippingPlanes: [ProductClippingPlane] = [], annotationPlacements: [ProductAnnotationPlacement] = [],
                projectionPoint: Point3D = .origin, windowOrigin: Point3D? = nil, windowUp: Vector3D = .unitY, windowDirection: Vector3D = .unitZ, windowPlacement: WindowPlacement = .threeDimensional,
                frontClipping: Bool = true, backClipping: Bool = true, sideClipping: Bool = true,
                clippingExpression: ProductClippingExpression? = nil) {
        self.id = id; self.name = name; self.origin = origin; self.direction = direction; self.up = up
        self.projection = projection; self.horizontalSize = horizontalSize; self.verticalSize = verticalSize
        self.focalDistance = focalDistance; self.nearDistance = nearDistance; self.farDistance = farDistance
        self.projectionPoint = projectionPoint
        self.windowOrigin = windowOrigin ?? Point3D(x: -horizontalSize / 2, y: -verticalSize / 2, z: windowPlacement == .twoDimensional ? 0 : focalDistance)
        self.windowPlacement = windowPlacement
        self.windowDirection = windowDirection
        self.windowUp = windowUp; self.frontClipping = frontClipping; self.backClipping = backClipping; self.sideClipping = sideClipping
        self.clippingExpression = clippingExpression
        self.clippingPlanes = clippingPlanes; self.annotationPlacements = annotationPlacements
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, origin, direction, up, projection, horizontalSize, verticalSize, focalDistance, nearDistance, farDistance, clippingPlanes, annotationPlacements, projectionPoint, windowOrigin, windowUp, windowDirection, windowPlacement, frontClipping, backClipping, sideClipping, clippingExpression }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .origin, .direction, .up, .projection, .horizontalSize, .verticalSize, .focalDistance, .nearDistance, .farDistance, .clippingPlanes, .annotationPlacements, .projectionPoint, .windowOrigin, .windowUp, .windowDirection, .windowPlacement, .frontClipping, .backClipping, .sideClipping, .clippingExpression], in: decoder)
        id = try c.decode(ProductMetadataID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        origin = try c.decode(Point3D.self, forKey: .origin)
        direction = try c.decode(Vector3D.self, forKey: .direction)
        up = try c.decode(Vector3D.self, forKey: .up)
        projection = try c.decode(Projection.self, forKey: .projection)
        horizontalSize = try c.decode(Double.self, forKey: .horizontalSize)
        verticalSize = try c.decode(Double.self, forKey: .verticalSize)
        focalDistance = try c.decode(Double.self, forKey: .focalDistance)
        nearDistance = try c.decode(Double.self, forKey: .nearDistance)
        farDistance = try c.decode(Double.self, forKey: .farDistance)
        projectionPoint = try c.decode(Point3D.self, forKey: .projectionPoint)
        windowOrigin = try c.decode(Point3D.self, forKey: .windowOrigin)
        windowPlacement = try c.decode(WindowPlacement.self, forKey: .windowPlacement)
        windowDirection = try c.decode(Vector3D.self, forKey: .windowDirection)
        windowUp = try c.decode(Vector3D.self, forKey: .windowUp)
        frontClipping = try c.decode(Bool.self, forKey: .frontClipping)
        backClipping = try c.decode(Bool.self, forKey: .backClipping)
        sideClipping = try c.decode(Bool.self, forKey: .sideClipping)
        guard c.contains(.clippingExpression) else { throw DecodingError.keyNotFound(CodingKeys.clippingExpression, .init(codingPath: decoder.codingPath, debugDescription: "Missing clipping expression.")) }
        clippingExpression = try c.decodeIfPresent(ProductClippingExpression.self, forKey: .clippingExpression)
        clippingPlanes = try c.decode([ProductClippingPlane].self, forKey: .clippingPlanes)
        annotationPlacements = try c.decode([ProductAnnotationPlacement].self, forKey: .annotationPlacements)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(origin, forKey: .origin)
        try c.encode(direction, forKey: .direction)
        try c.encode(up, forKey: .up)
        try c.encode(projection, forKey: .projection)
        try c.encode(horizontalSize, forKey: .horizontalSize)
        try c.encode(verticalSize, forKey: .verticalSize)
        try c.encode(focalDistance, forKey: .focalDistance)
        try c.encode(nearDistance, forKey: .nearDistance)
        try c.encode(farDistance, forKey: .farDistance)
        try c.encode(projectionPoint, forKey: .projectionPoint)
        try c.encode(windowOrigin, forKey: .windowOrigin)
        try c.encode(windowPlacement, forKey: .windowPlacement)
        try c.encode(windowDirection, forKey: .windowDirection)
        try c.encode(windowUp, forKey: .windowUp)
        try c.encode(frontClipping, forKey: .frontClipping)
        try c.encode(backClipping, forKey: .backClipping)
        try c.encode(sideClipping, forKey: .sideClipping)
        if let clippingExpression { try c.encode(clippingExpression, forKey: .clippingExpression) } else { try c.encodeNil(forKey: .clippingExpression) }
        try c.encode(clippingPlanes, forKey: .clippingPlanes)
        try c.encode(annotationPlacements, forKey: .annotationPlacements)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductSavedView: Codable {}
extension ProductSavedView.Projection: Codable {}
#endif

#if !hasFeature(Embedded)
extension ProductSavedView.WindowPlacement: Codable {}
#endif
