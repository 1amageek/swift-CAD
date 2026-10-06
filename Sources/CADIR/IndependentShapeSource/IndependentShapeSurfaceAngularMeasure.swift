import CADCore

/// A retained original scalar angular field of its actual standard surface entity.
public enum IndependentShapeSurfaceAngularMeasure: Equatable, Sendable {
    case coneSemiAngle(Double)
}

#if !hasFeature(Embedded)
extension IndependentShapeSurfaceAngularMeasure: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case coneSemiAngle }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.kind, .value], in: decoder)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .coneSemiAngle: self = .coneSemiAngle(try c.decode(Double.self, forKey: .value))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .coneSemiAngle(let value):
            try c.encode(Kind.coneSemiAngle, forKey: .kind); try c.encode(value, forKey: .value)
        }
    }
}
#endif
