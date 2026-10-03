import CADCore

/// Equality is member-wise over every stored value: a document equals the one its own encoding
/// decodes to exactly when the encoding reproduces it, which is how a project proves that its
/// package sources reproduce the edited document.
public struct CADDocument: Codable, Equatable, Sendable {
    public var id: DocumentID
    public var schemaVersion: SchemaVersion
    public var units: UnitSystem
    public var parameters: ParameterTable
    public var designGraph: DesignGraph
    public var selectionDimensions: [SelectionDimension]
    public var documentFoundation: DocumentFoundation
    public var assembly: DocumentAssembly?
    public var productAttributes: ProductAttributes
    public var metadata: DocumentMetadata

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case units
        case parameters
        case designGraph
        case selectionDimensions
        case documentFoundation
        case assembly
        case productAttributes
        case metadata
    }

    public init(
        id: DocumentID = DocumentID(),
        schemaVersion: SchemaVersion = .current,
        units: UnitSystem,
        parameters: ParameterTable = ParameterTable(),
        designGraph: DesignGraph = DesignGraph(),
        selectionDimensions: [SelectionDimension] = [],
        documentFoundation: DocumentFoundation = DocumentFoundation(),
        assembly: DocumentAssembly? = nil,
        productAttributes: ProductAttributes = ProductAttributes(),
        metadata: DocumentMetadata = DocumentMetadata()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.units = units
        self.parameters = parameters
        self.designGraph = designGraph
        self.selectionDimensions = selectionDimensions
        self.documentFoundation = documentFoundation
        self.assembly = assembly
        self.productAttributes = productAttributes
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .id,
            .schemaVersion,
            .units,
            .parameters,
            .designGraph,
            .selectionDimensions,
            .documentFoundation,
            .assembly,
            .productAttributes,
            .metadata,
        ], in: decoder)
        id = try container.decode(DocumentID.self, forKey: .id)
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        units = try container.decode(UnitSystem.self, forKey: .units)
        parameters = try container.decode(ParameterTable.self, forKey: .parameters)
        designGraph = try container.decode(DesignGraph.self, forKey: .designGraph)
        selectionDimensions = try container.decode([SelectionDimension].self, forKey: .selectionDimensions)
        documentFoundation = try container.decode(DocumentFoundation.self, forKey: .documentFoundation)
        guard container.contains(.assembly) else {
            throw AssemblyError.invalidSource("Current documents require an explicit nullable assembly field.")
        }
        assembly = try container.decodeIfPresent(DocumentAssembly.self, forKey: .assembly)
        productAttributes = try container.decode(ProductAttributes.self, forKey: .productAttributes)
        metadata = try container.decode(DocumentMetadata.self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(units, forKey: .units)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(designGraph, forKey: .designGraph)
        try container.encode(selectionDimensions, forKey: .selectionDimensions)
        try container.encode(documentFoundation, forKey: .documentFoundation)
        try container.encode(assembly, forKey: .assembly)
        try container.encode(productAttributes, forKey: .productAttributes)
        try container.encode(metadata, forKey: .metadata)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try schemaVersion.validate()
        try units.validate()
        try metadata.validate()
        try parameters.validate()
        try designGraph.validate(tolerance: tolerance)
        try designGraph.validateExpressions(using: parameters, tolerance: tolerance)
        try documentFoundation.validate(in: self)
        try validateAssembly(tolerance: tolerance)
        try validateProductAttributes()
        var dimensionIDs: Set<SelectionDimensionID> = []
        for dimension in selectionDimensions {
            guard dimensionIDs.insert(dimension.id).inserted else {
                throw FeatureEvaluationError.invalidGraph("Selection dimension IDs must be unique.")
            }
            try dimension.validate(parameters: parameters, tolerance: tolerance)
        }
    }
}

public extension CADDocument {
    func validateProductAttributes(limits: ProductAttributeLimits = .standard) throws {
        var budget = try ProductAttributeBudget(limits: limits)
        try ProductAttributesValidator().validate(productAttributes, in: self, budget: &budget)
    }

    func replacingProductAttributes(_ attributes: ProductAttributes, tolerance: ModelingTolerance) throws -> CADDocument {
        var copy = self
        copy.productAttributes = attributes
        try copy.validate(tolerance: tolerance)
        return copy
    }

    func validateAssembly(tolerance: ModelingTolerance) throws {
        if let assembly {
            _ = try DocumentAssemblyValidator().expandedOccurrences(of: assembly, in: designGraph,
                tolerance: tolerance, limits: .standard)
        }
    }
}
