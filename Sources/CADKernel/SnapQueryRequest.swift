import CADCore

public struct SnapQueryRequest: Sendable, Hashable {
    public var point: Point3D
    public var options: SnapQueryOptions

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case point
        case options
    }
    #endif

    public init(
        point: Point3D,
        options: SnapQueryOptions = SnapQueryOptions()
    ) {
        self.point = point
        self.options = options
    }

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.point, .options], in: decoder)
        point = try container.decode(Point3D.self, forKey: .point)
        options = try container.decode(SnapQueryOptions.self, forKey: .options)
        try point.validate()
    }
    #endif

    public func validate(tolerance: ModelingTolerance) throws {
        try point.validate()
        try options.validate(tolerance: tolerance)
    }
}

#if !hasFeature(Embedded)
extension SnapQueryRequest: Codable {}
#endif
