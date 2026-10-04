import CADCore

public struct ProductAttributes: Codable, Equatable, Sendable {
    public var materials: [PhysicalMaterialDescriptor]
    public var assignments: [ProductAttributeAssignment]
    public var layers: [ProductLayer]
    public var itemCharacterizations: [ProductItemCharacterization]
    public var shapeElementDescriptions: [ProductShapeElementDescription]
    public init(materials: [PhysicalMaterialDescriptor] = [], assignments: [ProductAttributeAssignment] = [], layers: [ProductLayer] = [],
                itemCharacterizations: [ProductItemCharacterization] = [],
                shapeElementDescriptions: [ProductShapeElementDescription] = []) {
        self.materials = materials; self.assignments = assignments; self.layers = layers
        self.itemCharacterizations = itemCharacterizations
        self.shapeElementDescriptions = shapeElementDescriptions
    }
    public var isEmpty: Bool { materials.isEmpty && assignments.isEmpty && layers.isEmpty && itemCharacterizations.isEmpty && shapeElementDescriptions.isEmpty }
    public var canonicalized: Self {
        Self(materials: materials.sorted { $0.id < $1.id }, assignments: assignments.sorted { $0.id < $1.id },
             layers: layers.sorted { $0.id < $1.id }, itemCharacterizations: itemCharacterizations.sorted {
                if $0.target.kind != $1.target.kind { return $0.target.kind.rawValue < $1.target.kind.rawValue }
                guard let left = $0.target.geometry?.subshapeID, let right = $1.target.geometry?.subshapeID else { return false }
                return left < right
             }, shapeElementDescriptions: shapeElementDescriptions.sorted {
                if $0.target.definitionID != $1.target.definitionID {
                    guard let left = $0.target.definitionID, let right = $1.target.definitionID else { return false }
                    return left < right
                }
                if $0.target.kind != $1.target.kind { return $0.target.kind.rawValue < $1.target.kind.rawValue }
                guard let left = $0.target.geometry?.subshapeID, let right = $1.target.geometry?.subshapeID else { return false }
                return left < right
             })
    }
    private enum CodingKeys: String, CodingKey { case materials, assignments, layers, itemCharacterizations, shapeElementDescriptions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.materials, .assignments, .layers, .itemCharacterizations, .shapeElementDescriptions], in: decoder)
        materials = try c.decode([PhysicalMaterialDescriptor].self, forKey: .materials)
        assignments = try c.decode([ProductAttributeAssignment].self, forKey: .assignments)
        layers = try c.decode([ProductLayer].self, forKey: .layers)
        itemCharacterizations = try c.decode([ProductItemCharacterization].self, forKey: .itemCharacterizations)
        shapeElementDescriptions = try c.decode([ProductShapeElementDescription].self, forKey: .shapeElementDescriptions)
    }
}
