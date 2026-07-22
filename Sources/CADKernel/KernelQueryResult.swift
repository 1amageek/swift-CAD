import CADCore

public enum KernelQueryResult: Codable, Sendable {
    case evaluatedDocument(EvaluatedDocument)
    case lineage(TopologyLineage?)
    case diagnostics(EvaluationReport)
    case snap(SnapQueryResult)
    case measurement(MeasurementQueryResult)
    case selectionDimensionEvaluation(SelectionDimensionEvaluation)
    case projection(ProjectionQueryResult)

    private enum CodingKeys: String, CodingKey {
        case kind
        case evaluatedDocument
        case lineage
        case diagnostics
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
        switch try container.decode(Kind.self, forKey: .kind) {
        case .evaluatedDocument:
            try container.validateOnlyExpectedKeys([.kind, .evaluatedDocument], in: decoder)
            self = .evaluatedDocument(try container.decode(
                EvaluatedDocument.self,
                forKey: .evaluatedDocument
            ))
        case .lineage:
            try container.validateOnlyExpectedKeys([.kind, .lineage], in: decoder)
            self = .lineage(try container.decode(
                Optional<TopologyLineage>.self,
                forKey: .lineage
            ))
        case .diagnostics:
            try container.validateOnlyExpectedKeys([.kind, .diagnostics], in: decoder)
            let report = try container.decode(EvaluationReport.self, forKey: .diagnostics)
            try report.validate()
            self = .diagnostics(report)
        case .snap:
            try container.validateOnlyExpectedKeys([.kind, .snap], in: decoder)
            self = .snap(try container.decode(SnapQueryResult.self, forKey: .snap))
        case .measurement:
            try container.validateOnlyExpectedKeys([.kind, .measurement], in: decoder)
            self = .measurement(try container.decode(
                MeasurementQueryResult.self,
                forKey: .measurement
            ))
        case .selectionDimensionEvaluation:
            try container.validateOnlyExpectedKeys(
                [.kind, .selectionDimensionEvaluation],
                in: decoder
            )
            self = .selectionDimensionEvaluation(try container.decode(
                SelectionDimensionEvaluation.self,
                forKey: .selectionDimensionEvaluation
            ))
        case .projection:
            try container.validateOnlyExpectedKeys([.kind, .projection], in: decoder)
            self = .projection(try container.decode(
                ProjectionQueryResult.self,
                forKey: .projection
            ))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .evaluatedDocument(document):
            try container.encode(Kind.evaluatedDocument, forKey: .kind)
            try container.encode(document, forKey: .evaluatedDocument)
        case let .lineage(lineage):
            try container.encode(Kind.lineage, forKey: .kind)
            try container.encode(lineage, forKey: .lineage)
        case let .diagnostics(report):
            try report.validate()
            try container.encode(Kind.diagnostics, forKey: .kind)
            try container.encode(report, forKey: .diagnostics)
        case let .snap(result):
            try container.encode(Kind.snap, forKey: .kind)
            try container.encode(result, forKey: .snap)
        case let .measurement(result):
            try container.encode(Kind.measurement, forKey: .kind)
            try container.encode(result, forKey: .measurement)
        case let .selectionDimensionEvaluation(result):
            try container.encode(Kind.selectionDimensionEvaluation, forKey: .kind)
            try container.encode(result, forKey: .selectionDimensionEvaluation)
        case let .projection(result):
            try container.encode(Kind.projection, forKey: .kind)
            try container.encode(result, forKey: .projection)
        }
    }
}
