import CADCore

public struct CADDocument: Codable, Sendable {
    public var id: DocumentID
    public var schemaVersion: SchemaVersion
    public var units: UnitSystem
    public var parameters: ParameterTable
    public var designGraph: DesignGraph
    public var selectionDimensions: [SelectionDimension]
    public var metadata: DocumentMetadata

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case units
        case parameters
        case designGraph
        case selectionDimensions
        case metadata
    }

    public init(
        id: DocumentID = DocumentID(),
        schemaVersion: SchemaVersion = .current,
        units: UnitSystem,
        parameters: ParameterTable = ParameterTable(),
        designGraph: DesignGraph = DesignGraph(),
        selectionDimensions: [SelectionDimension] = [],
        metadata: DocumentMetadata = DocumentMetadata()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.units = units
        self.parameters = parameters
        self.designGraph = designGraph
        self.selectionDimensions = selectionDimensions
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
            .metadata,
        ], in: decoder)
        id = try container.decode(DocumentID.self, forKey: .id)
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        units = try container.decode(UnitSystem.self, forKey: .units)
        parameters = try container.decode(ParameterTable.self, forKey: .parameters)
        designGraph = try container.decode(DesignGraph.self, forKey: .designGraph)
        selectionDimensions = try container.decodeIfPresent(
            [SelectionDimension].self,
            forKey: .selectionDimensions
        ) ?? []
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
        try container.encode(metadata, forKey: .metadata)
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try schemaVersion.validate()
        try units.validate()
        try metadata.validate()
        try parameters.validate()
        try designGraph.validate(tolerance: tolerance)
        try designGraph.validateExpressions(using: parameters)
        var dimensionIDs: Set<SelectionDimensionID> = []
        for dimension in selectionDimensions {
            guard dimensionIDs.insert(dimension.id).inserted else {
                throw FeatureEvaluationError.invalidGraph("Selection dimension IDs must be unique.")
            }
            try dimension.validate(parameters: parameters, tolerance: tolerance)
        }
    }
}
