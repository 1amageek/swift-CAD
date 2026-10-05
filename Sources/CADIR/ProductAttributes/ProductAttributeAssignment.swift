import CADCore

public struct ProductAttributeAssignment: Hashable, Sendable {
    public let id: ProductAttributeID
    public let target: ProductAttributeTarget
    public let value: ProductAttributeValue
    public let overrides: ProductAttributeID?
    public init(id: ProductAttributeID = ProductAttributeID(), target: ProductAttributeTarget,
                value: ProductAttributeValue, overrides: ProductAttributeID? = nil) {
        self.id = id; self.target = target; self.value = value; self.overrides = overrides
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, target, value, overrides }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .target, .value, .overrides], in: decoder)
        id = try c.decode(ProductAttributeID.self, forKey: .id); target = try c.decode(ProductAttributeTarget.self, forKey: .target)
        value = try c.decode(ProductAttributeValue.self, forKey: .value)
        guard c.contains(.overrides) else { throw ProductAttributeError.invalidSource("Assignment requires an explicit nullable predecessor.") }
        overrides = try c.decodeIfPresent(ProductAttributeID.self, forKey: .overrides)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(target, forKey: .target)
        try c.encode(value, forKey: .value); try c.encode(overrides, forKey: .overrides)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductAttributeAssignment: Codable {}
#endif
