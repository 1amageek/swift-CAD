import CADCore

public enum CADAgentQuery: Codable, Sendable, Hashable {
    case snap(CADAgentSnapQuery)

    private enum CodingKeys: String, CodingKey {
        case kind
        case snap
    }

    private enum Kind: String, Codable {
        case snap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .snap:
            try container.validateOnlyExpectedKeys([.kind, .snap], in: decoder)
            self = .snap(try container.decode(CADAgentSnapQuery.self, forKey: .snap))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .snap(query):
            try container.encode(Kind.snap, forKey: .kind)
            try container.encode(query, forKey: .snap)
        }
    }
}
