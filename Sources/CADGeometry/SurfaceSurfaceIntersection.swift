public enum SurfaceSurfaceIntersection: Hashable, Sendable {
    case curve(SurfaceSurfaceIntersectionCurve)
    case point(SurfaceSurfaceIntersectionPoint)
    case coincident(SurfaceSurfaceCoincidence)

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case curve
        case point
        case coincident
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case curve
        case point
        case coincident
    }
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif
}

#if !hasFeature(Embedded)
extension SurfaceSurfaceIntersection: Codable {}
#endif
