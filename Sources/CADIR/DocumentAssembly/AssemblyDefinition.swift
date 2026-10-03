import CADCore

public struct AssemblyDefinition: Codable, Equatable, Sendable {
    public let id: AssemblyDefinitionID
    public var formationID: AssemblyProductFormationID
    public var identifier: String
    public var definitionDescription: String?
    public var features: [FeatureID]
    public var children: [AssemblyOccurrence]
    public init(id: AssemblyDefinitionID = AssemblyDefinitionID(), formationID: AssemblyProductFormationID,
                identifier: String = "", definitionDescription: String? = nil,
                features: [FeatureID] = [], children: [AssemblyOccurrence] = []) {
        self.id = id; self.formationID = formationID; self.identifier = identifier
        self.definitionDescription = definitionDescription; self.features = features; self.children = children
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.formationID == rhs.formationID
            && AssemblySourceText(lhs.identifier) == AssemblySourceText(rhs.identifier)
            && AssemblySourceText.equal(lhs.definitionDescription, rhs.definitionDescription)
            && lhs.features == rhs.features && lhs.children == rhs.children
    }
    private enum CodingKeys: String, CodingKey { case id, formationID, identifier, definitionDescription, features, children }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .formationID, .identifier, .definitionDescription, .features, .children], in: decoder)
        id = try c.decode(AssemblyDefinitionID.self, forKey: .id)
        formationID = try c.decode(AssemblyProductFormationID.self, forKey: .formationID)
        identifier = try c.decode(String.self, forKey: .identifier)
        definitionDescription = try c.decode(String?.self, forKey: .definitionDescription)
        features = try c.decode([FeatureID].self, forKey: .features)
        children = try c.decode([AssemblyOccurrence].self, forKey: .children)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(formationID, forKey: .formationID)
        try c.encode(identifier, forKey: .identifier); try c.encode(definitionDescription, forKey: .definitionDescription)
        try c.encode(features, forKey: .features); try c.encode(children, forKey: .children)
    }
}
