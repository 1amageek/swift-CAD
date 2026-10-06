import CADCore

public struct IndependentShapeTrimmingSource: Equatable, Sendable {
    public enum Preference: String, Sendable { case parameter, cartesian, unspecified }
    public enum Selector: Equatable, Sendable { case parameter(Double), point(Point3D) }
    public let first: [Selector]
    public let second: [Selector]
    public let agreesWithBasis: Bool
    public let preference: Preference
    public init(first: [Selector], second: [Selector], agreesWithBasis: Bool, preference: Preference) {
        self.first = first; self.second = second; self.agreesWithBasis = agreesWithBasis; self.preference = preference
    }
    public func translated(by displacement: Vector3D) -> IndependentShapeTrimmingSource {
        func shift(_ selectors: [Selector]) -> [Selector] {
            selectors.map { selector in
                switch selector { case .parameter: selector; case .point(let point): .point(point + displacement) }
            }
        }
        return .init(first: shift(first), second: shift(second), agreesWithBasis: agreesWithBasis, preference: preference)
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeTrimmingSource: Codable {
    private enum CodingKeys: String, CodingKey { case first, second, agreesWithBasis, preference }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.first, .second, .agreesWithBasis, .preference], in: decoder)
        first = try c.decode([Selector].self, forKey: .first); second = try c.decode([Selector].self, forKey: .second)
        agreesWithBasis = try c.decode(Bool.self, forKey: .agreesWithBasis); preference = try c.decode(Preference.self, forKey: .preference)
    }
}
extension IndependentShapeTrimmingSource.Preference: Codable {}
extension IndependentShapeTrimmingSource.Selector: Codable {
    private enum CodingKeys: String, CodingKey { case kind, parameter, point }
    private enum Kind: String, Codable { case parameter, point }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .parameter:
            try c.validateOnlyExpectedKeys([.kind, .parameter], in: decoder)
            self = .parameter(try c.decode(Double.self, forKey: .parameter))
        case .point:
            try c.validateOnlyExpectedKeys([.kind, .point], in: decoder)
            self = .point(try c.decode(Point3D.self, forKey: .point))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .parameter(let value): try c.encode(Kind.parameter, forKey: .kind); try c.encode(value, forKey: .parameter)
        case .point(let point): try c.encode(Kind.point, forKey: .kind); try c.encode(point, forKey: .point)
        }
    }
}
#endif
