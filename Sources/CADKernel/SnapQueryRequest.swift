import CADCore

public struct SnapQueryRequest: Codable, Sendable, Hashable {
    public var point: Point3D
    public var options: SnapQueryOptions

    private enum CodingKeys: String, CodingKey {
        case point
        case options
    }

    public init(
        point: Point3D,
        options: SnapQueryOptions = SnapQueryOptions()
    ) {
        self.point = point
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.point, .options], in: decoder)
        point = try container.decode(Point3D.self, forKey: .point)
        options = try container.decodeIfPresent(
            SnapQueryOptions.self,
            forKey: .options
        ) ?? SnapQueryOptions()
        try point.validate()
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try point.validate()
        try options.validate(tolerance: tolerance)
    }
}
