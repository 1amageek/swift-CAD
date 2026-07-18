import CADCore

/// Queries operate on the evaluated document produced by the exact kernel.
public enum KernelQuery: Codable, Hashable, Sendable {
    case evaluatedDocument
    case lineage(SubshapeID)
    case diagnostics
    case snap(SnapQueryRequest)
    case measurement(MeasurementQuery)
    case selectionDimensionEvaluation(SelectionDimensionEvaluationQuery)
    case projection(ProjectionQuery)

    private enum CodingKeys: String, CodingKey {
        case kind
        case subshapeID
        case snap
        case measurement
        case selectionDimensionEvaluation
        case projection
    }

    private enum Kind: String, Codable {
        case evaluatedDocument
        case lineage
        case diagnostics
        case snap
        case measurement
        case selectionDimensionEvaluation
        case projection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .evaluatedDocument:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .evaluatedDocument
        case .lineage:
            try container.validateOnlyExpectedKeys([.kind, .subshapeID], in: decoder)
            self = .lineage(try container.decode(SubshapeID.self, forKey: .subshapeID))
        case .diagnostics:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .diagnostics
        case .snap:
            try container.validateOnlyExpectedKeys([.kind, .snap], in: decoder)
            self = .snap(try container.decode(SnapQueryRequest.self, forKey: .snap))
        case .measurement:
            try container.validateOnlyExpectedKeys([.kind, .measurement], in: decoder)
            self = .measurement(try container.decode(MeasurementQuery.self, forKey: .measurement))
        case .selectionDimensionEvaluation:
            try container.validateOnlyExpectedKeys([.kind, .selectionDimensionEvaluation], in: decoder)
            self = .selectionDimensionEvaluation(try container.decode(
                SelectionDimensionEvaluationQuery.self,
                forKey: .selectionDimensionEvaluation
            ))
        case .projection:
            try container.validateOnlyExpectedKeys([.kind, .projection], in: decoder)
            self = .projection(try container.decode(ProjectionQuery.self, forKey: .projection))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .evaluatedDocument:
            try container.encode(Kind.evaluatedDocument, forKey: .kind)
        case let .lineage(subshapeID):
            try container.encode(Kind.lineage, forKey: .kind)
            try container.encode(subshapeID, forKey: .subshapeID)
        case .diagnostics:
            try container.encode(Kind.diagnostics, forKey: .kind)
        case let .snap(query):
            try container.encode(Kind.snap, forKey: .kind)
            try container.encode(query, forKey: .snap)
        case let .measurement(query):
            try container.encode(Kind.measurement, forKey: .kind)
            try container.encode(query, forKey: .measurement)
        case let .selectionDimensionEvaluation(query):
            try container.encode(Kind.selectionDimensionEvaluation, forKey: .kind)
            try container.encode(query, forKey: .selectionDimensionEvaluation)
        case let .projection(query):
            try container.encode(Kind.projection, forKey: .kind)
            try container.encode(query, forKey: .projection)
        }
    }
}
