public enum SurfaceSurfaceIntersection: Codable, Hashable, Sendable {
    case curve(SurfaceSurfaceIntersectionCurve)
    case point(SurfaceSurfaceIntersectionPoint)
    case coincident(SurfaceSurfaceCoincidence)

    private enum CodingKeys: String, CodingKey {
        case kind
        case curve
        case point
        case coincident
    }

    private enum Kind: String, Codable {
        case curve
        case point
        case coincident
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .curve:
            try container.validateOnlyExpectedKeys([.kind, .curve], in: decoder)
            self = .curve(try container.decode(
                SurfaceSurfaceIntersectionCurve.self,
                forKey: .curve
            ))
        case .point:
            try container.validateOnlyExpectedKeys([.kind, .point], in: decoder)
            self = .point(try container.decode(
                SurfaceSurfaceIntersectionPoint.self,
                forKey: .point
            ))
        case .coincident:
            try container.validateOnlyExpectedKeys([.kind, .coincident], in: decoder)
            self = .coincident(try container.decode(
                SurfaceSurfaceCoincidence.self,
                forKey: .coincident
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .curve(curve):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(curve, forKey: .curve)
        case let .point(point):
            try container.encode(Kind.point, forKey: .kind)
            try container.encode(point, forKey: .point)
        case let .coincident(coincidence):
            try container.encode(Kind.coincident, forKey: .kind)
            try container.encode(coincidence, forKey: .coincident)
        }
    }
}
