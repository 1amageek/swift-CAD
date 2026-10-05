import CADCore

public struct ProductAttributes: Equatable, Sendable {
    public var manufacturingInformation: ProductManufacturingInformation
    public var viewMetadata: ProductViewMetadata
    public var materials: [PhysicalMaterialDescriptor]
    public var assignments: [ProductAttributeAssignment]
    public var layers: [ProductLayer]
    public var itemCharacterizations: [ProductItemCharacterization]
    public var shapeElementDescriptions: [ProductShapeElementDescription]
    public init(materials: [PhysicalMaterialDescriptor] = [], assignments: [ProductAttributeAssignment] = [], layers: [ProductLayer] = [],
                itemCharacterizations: [ProductItemCharacterization] = [],
                shapeElementDescriptions: [ProductShapeElementDescription] = [],
                manufacturingInformation: ProductManufacturingInformation = .init(), viewMetadata: ProductViewMetadata = .init()) {
        self.manufacturingInformation = manufacturingInformation; self.viewMetadata = viewMetadata
        self.materials = materials; self.assignments = assignments; self.layers = layers
        self.itemCharacterizations = itemCharacterizations
        self.shapeElementDescriptions = shapeElementDescriptions
    }
    public var isEmpty: Bool { materials.isEmpty && assignments.isEmpty && layers.isEmpty && itemCharacterizations.isEmpty && shapeElementDescriptions.isEmpty && manufacturingInformation.isEmpty && viewMetadata.isEmpty }
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
             }, manufacturingInformation: manufacturingInformation.canonicalized, viewMetadata: viewMetadata.canonicalized)
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case materials, assignments, layers, itemCharacterizations, shapeElementDescriptions, manufacturingInformation, viewMetadata }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.materials, .assignments, .layers, .itemCharacterizations, .shapeElementDescriptions, .manufacturingInformation, .viewMetadata], in: decoder)
        manufacturingInformation = try c.decode(ProductManufacturingInformation.self, forKey: .manufacturingInformation)
        viewMetadata = try c.decode(ProductViewMetadata.self, forKey: .viewMetadata)
        materials = try c.decode([PhysicalMaterialDescriptor].self, forKey: .materials)
        assignments = try c.decode([ProductAttributeAssignment].self, forKey: .assignments)
        layers = try c.decode([ProductLayer].self, forKey: .layers)
        itemCharacterizations = try c.decode([ProductItemCharacterization].self, forKey: .itemCharacterizations)
        shapeElementDescriptions = try c.decode([ProductShapeElementDescription].self, forKey: .shapeElementDescriptions)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductAttributes: Codable {}
#endif
