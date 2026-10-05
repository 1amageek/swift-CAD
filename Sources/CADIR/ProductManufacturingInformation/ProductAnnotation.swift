import CADCore

public struct ProductAnnotation: Equatable, Sendable {
    public enum Meaning: String, Sendable { case note, dimension, tolerance, datum }
    public let id: ProductMetadataID
    public var name: String
    public var text: String
    public var meaning: Meaning
    public var semanticID: ProductMetadataID?
    public var targets: [ProductAttributeTarget]
    public var polylines: [[Point3D]]
    public var textLiterals: [ProductAnnotationTextLiteral]
    public init(id: ProductMetadataID = ProductMetadataID(), name: String = "", text: String, meaning: Meaning = .note,
                semanticID: ProductMetadataID? = nil, targets: [ProductAttributeTarget] = [], polylines: [[Point3D]] = [], textLiterals: [ProductAnnotationTextLiteral]? = nil) {
        self.id = id; self.name = name; self.text = text; self.meaning = meaning
        self.semanticID = semanticID; self.targets = targets; self.polylines = polylines
        self.textLiterals = textLiterals ?? [ProductAnnotationTextLiteral(text:text)]
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, text, meaning, semanticID, targets, polylines, textLiterals }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .text, .meaning, .semanticID, .targets, .polylines, .textLiterals], in: decoder)
        id = try c.decode(ProductMetadataID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        text = try c.decode(String.self, forKey: .text)
        meaning = try c.decode(Meaning.self, forKey: .meaning)
        guard c.contains(.semanticID) else { throw ProductAttributeError.invalidSource("Missing required nullable metadata field.") }
        semanticID = try c.decodeIfPresent(ProductMetadataID.self, forKey: .semanticID)
        targets = try c.decode([ProductAttributeTarget].self, forKey: .targets)
        polylines = try c.decode([[Point3D]].self, forKey: .polylines)
        textLiterals = try c.decode([ProductAnnotationTextLiteral].self, forKey: .textLiterals)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(text, forKey: .text)
        try c.encode(meaning, forKey: .meaning)
        try c.encode(semanticID, forKey: .semanticID)
        try c.encode(targets, forKey: .targets)
        try c.encode(polylines, forKey: .polylines)
        try c.encode(textLiterals, forKey: .textLiterals)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductAnnotation: Codable {}
extension ProductAnnotation.Meaning: Codable {}
#endif
