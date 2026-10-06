import CADCore

/// Owns one formation/version of a shared standard product.
public struct AssemblyProductFormation: Equatable, Sendable {
    public let id: AssemblyProductFormationID
    public var productID: AssemblyProductID
    public var versionIdentifier: String
    public var description: String?
    public var specifiedSource: AssemblyProductSource?
    public init(id: AssemblyProductFormationID = AssemblyProductFormationID(), productID: AssemblyProductID,
                versionIdentifier: String = "", description: String? = nil, specifiedSource: AssemblyProductSource? = nil) {
        self.id = id; self.productID = productID; self.versionIdentifier = versionIdentifier
        self.description = description; self.specifiedSource = specifiedSource
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.productID == rhs.productID
            && AssemblySourceText(lhs.versionIdentifier) == AssemblySourceText(rhs.versionIdentifier)
            && AssemblySourceText.equal(lhs.description, rhs.description) && lhs.specifiedSource == rhs.specifiedSource
    }
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, productID, versionIdentifier, description, specifiedSource }
#endif
#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .productID, .versionIdentifier, .description, .specifiedSource], in: decoder)
        id = try c.decode(AssemblyProductFormationID.self, forKey: .id)
        productID = try c.decode(AssemblyProductID.self, forKey: .productID)
        versionIdentifier = try c.decode(String.self, forKey: .versionIdentifier)
        description = try c.decode(String?.self, forKey: .description)
        specifiedSource = try c.decode(AssemblyProductSource?.self, forKey: .specifiedSource)
    }
#endif
#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(productID, forKey: .productID)
        try c.encode(versionIdentifier, forKey: .versionIdentifier); try c.encode(description, forKey: .description)
        try c.encode(specifiedSource, forKey: .specifiedSource)
    }
#endif
}

#if !hasFeature(Embedded)
extension AssemblyProductFormation: Codable {}
#endif
