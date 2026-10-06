public indirect enum ProductClippingExpression: Equatable, Sendable {
    case plane(ProductClippingPlane)
    case union([ProductClippingExpression])
    case intersection([ProductClippingExpression])
}

#if !hasFeature(Embedded)
extension ProductClippingExpression: Codable {
    private enum CodingKeys: String, CodingKey { case kind, plane, operands }
    private enum Kind: String, Codable { case plane, union, intersection }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .plane:
            try c.validateOnlyExpectedKeys([.kind, .plane], in: decoder)
            self = .plane(try c.decode(ProductClippingPlane.self, forKey: .plane))
        case .union:
            try c.validateOnlyExpectedKeys([.kind, .operands], in: decoder)
            self = .union(try c.decode([ProductClippingExpression].self, forKey: .operands))
        case .intersection:
            try c.validateOnlyExpectedKeys([.kind, .operands], in: decoder)
            self = .intersection(try c.decode([ProductClippingExpression].self, forKey: .operands))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plane(let plane): try c.encode(Kind.plane, forKey: .kind); try c.encode(plane, forKey: .plane)
        case .union(let operands): try c.encode(Kind.union, forKey: .kind); try c.encode(operands, forKey: .operands)
        case .intersection(let operands): try c.encode(Kind.intersection, forKey: .kind); try c.encode(operands, forKey: .operands)
        }
    }
}
#endif
