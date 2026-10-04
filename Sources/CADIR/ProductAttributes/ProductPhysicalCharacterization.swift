import CADCore

/// Independent metadata of a global physical item characterization, distinct from the item's name and material.
public struct ProductPhysicalCharacterization: Codable, Hashable, Sendable {
    public let target: ProductAttributeTarget
    public let name: String
    public let description: String?

    public init(target: ProductAttributeTarget, name: String, description: String?) {
        self.target = target; self.name = name; self.description = description
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.name.utf8.elementsEqual(rhs.name.utf8)
            && equalDescription(lhs.description, rhs.description)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        for byte in name.utf8 { hasher.combine(byte) }
        hasher.combine(description != nil)
        if let description { for byte in description.utf8 { hasher.combine(byte) } }
    }

    private static func equalDescription(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return left.utf8.elementsEqual(right.utf8)
        default: return false
        }
    }

    private enum CodingKeys: String, CodingKey { case target, name, description }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.target, .name, .description], in: decoder)
        target = try c.decode(ProductAttributeTarget.self, forKey: .target)
        name = try c.decode(String.self, forKey: .name)
        guard c.contains(.description) else {
            throw ProductAttributeError.invalidSource("Physical characterization requires an explicit nullable description.")
        }
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(target, forKey: .target); try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
    }
}
