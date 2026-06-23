import CADCore

public enum CADAgentQuery: Codable, Sendable, Hashable {
    case snap(CADAgentSnapQuery)
    case measurement(CADAgentMeasurementQuery)
    case selectionDimensionEvaluation(CADAgentSelectionDimensionEvaluationQuery)

    private enum CodingKeys: String, CodingKey {
        case kind
        case snap
        case measurement
        case selectionDimensionEvaluation
    }

    private enum Kind: String, Codable {
        case snap
        case measurement
        case selectionDimensionEvaluation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .snap:
            try container.validateOnlyExpectedKeys([.kind, .snap], in: decoder)
            self = .snap(try container.decode(CADAgentSnapQuery.self, forKey: .snap))
        case .measurement:
            try container.validateOnlyExpectedKeys([.kind, .measurement], in: decoder)
            self = .measurement(try container.decode(CADAgentMeasurementQuery.self, forKey: .measurement))
        case .selectionDimensionEvaluation:
            try container.validateOnlyExpectedKeys([.kind, .selectionDimensionEvaluation], in: decoder)
            self = .selectionDimensionEvaluation(try container.decode(
                CADAgentSelectionDimensionEvaluationQuery.self,
                forKey: .selectionDimensionEvaluation
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .snap(query):
            try container.encode(Kind.snap, forKey: .kind)
            try container.encode(query, forKey: .snap)
        case let .measurement(query):
            try container.encode(Kind.measurement, forKey: .kind)
            try container.encode(query, forKey: .measurement)
        case let .selectionDimensionEvaluation(query):
            try container.encode(Kind.selectionDimensionEvaluation, forKey: .kind)
            try container.encode(query, forKey: .selectionDimensionEvaluation)
        }
    }
}
