import CADCore

public struct ProductAttributeTarget: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case body, face, part, occurrence, directUsage }
    public let kind: Kind
    public let geometry: StableSubshapeReference?
    public let definitionID: AssemblyDefinitionID?
    public let path: AssemblyOccurrencePath?
    public let usageID: AssemblyOccurrenceID?
    public init(kind: Kind, geometry: StableSubshapeReference? = nil, definitionID: AssemblyDefinitionID? = nil,
                path: AssemblyOccurrencePath? = nil, usageID: AssemblyOccurrenceID? = nil) {
        self.kind = kind; self.geometry = geometry; self.definitionID = definitionID; self.path = path; self.usageID = usageID
    }
    public func validate() throws {
        switch kind {
        case .body, .face:
            guard let geometry, usageID == nil, definitionID == nil || path == nil else {
                throw ProductAttributeError.invalidSource("Geometry target has invalid payload.")
            }
            try geometry.validate()
            switch (kind, geometry.geometrySignature) {
            case (.body, .body), (.face, .face): break
            default: throw ProductAttributeError.invalidSource("Geometry target has an incompatible signature kind.")
            }
        case .part:
            guard definitionID != nil, geometry == nil, path == nil, usageID == nil else { throw ProductAttributeError.invalidSource("Part target has invalid payload.") }
        case .occurrence:
            guard path != nil, geometry == nil, definitionID == nil, usageID == nil else { throw ProductAttributeError.invalidSource("Occurrence target has invalid payload.") }
        case .directUsage:
            guard usageID != nil, geometry == nil, definitionID == nil, path == nil else { throw ProductAttributeError.invalidSource("Direct usage target has invalid payload.") }
        }
        if let path, path.components.isEmpty { throw ProductAttributeError.invalidSource("Occurrence scope cannot be empty.") }
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case kind, geometry, definitionID, path, usageID }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.kind, .geometry, .definitionID, .path, .usageID], in: decoder)
        kind = try c.decode(Kind.self, forKey: .kind)
        guard c.contains(.geometry), c.contains(.definitionID), c.contains(.path), c.contains(.usageID) else {
            throw ProductAttributeError.invalidSource("Attribute target requires explicit payload fields.")
        }
        geometry = try c.decodeIfPresent(StableSubshapeReference.self, forKey: .geometry)
        definitionID = try c.decodeIfPresent(AssemblyDefinitionID.self, forKey: .definitionID)
        path = try c.decodeIfPresent(AssemblyOccurrencePath.self, forKey: .path)
        usageID = try c.decodeIfPresent(AssemblyOccurrenceID.self, forKey: .usageID)
        try validate()
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(geometry, forKey: .geometry)
        try c.encode(definitionID, forKey: .definitionID); try c.encode(path, forKey: .path); try c.encode(usageID, forKey: .usageID)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductAttributeTarget: Codable {}
extension ProductAttributeTarget.Kind: Codable {}
#endif
