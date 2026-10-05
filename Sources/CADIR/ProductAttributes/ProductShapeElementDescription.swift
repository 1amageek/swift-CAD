import CADCore

/// Independent description of an existing definition-qualified shape element.
public struct ProductShapeElementDescription: Hashable, Sendable {
    public let target: ProductAttributeTarget
    public let description: String

    public init(target: ProductAttributeTarget, description: String) {
        self.target = target; self.description = description
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.description.utf8.elementsEqual(rhs.description.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        for byte in description.utf8 { hasher.combine(byte) }
    }

    #if !hasFeature(Embedded)

    private enum CodingKeys: String, CodingKey { case target, description }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.target, .description], in: decoder)
        target = try c.decode(ProductAttributeTarget.self, forKey: .target)
        description = try c.decode(String.self, forKey: .description)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductShapeElementDescription: Codable {}
#endif
