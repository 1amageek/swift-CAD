import CADCore

/// Queries operate on the evaluated document produced by the exact kernel.
public enum KernelQuery: Codable, Hashable, Sendable {
    case evaluatedDocument
    case lineage(SubshapeID)
    case diagnostics

    private enum CodingKeys: String, CodingKey {
        case kind
        case subshapeID
    }

    private enum Kind: String, Codable {
        case evaluatedDocument
        case lineage
        case diagnostics
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
        }
    }
}

public enum KernelQueryResult: Sendable {
    case evaluatedDocument(EvaluatedDocument)
    case lineage(TopologyLineage?)
    case diagnostics(EvaluationReport)
}

public extension KernelQuery {
    func validate() throws {
        switch self {
        case .evaluatedDocument, .diagnostics:
            return
        case let .lineage(subshapeID):
            guard subshapeID.isValid else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    subshapeID: subshapeID,
                    message: "Kernel lineage query contains an invalid subshape identity."
                )
            }
        }
    }
}
