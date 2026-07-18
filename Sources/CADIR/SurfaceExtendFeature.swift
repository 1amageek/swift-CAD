public struct SurfaceExtendFeature: Codable, Hashable, Sendable {
    public let target: SurfaceOperationTargetReference
    public let distances: SurfaceExtensionDistances

    public init(
        target: SurfaceOperationTargetReference,
        distances: SurfaceExtensionDistances
    ) {
        self.target = target
        self.distances = distances
    }

    public func validate() throws {
        try target.validate()
        try distances.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case distances
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .distances], in: decoder)
        target = try container.decode(SurfaceOperationTargetReference.self, forKey: .target)
        distances = try container.decode(SurfaceExtensionDistances.self, forKey: .distances)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(distances, forKey: .distances)
    }
}
