import CADCore
import CADKernel

public enum CADAgentQueryResult: Codable, Sendable, Hashable {
    case snap(SnapQueryResult)
    case measurement(CADAgentMeasurementQueryResult)

    private enum CodingKeys: String, CodingKey {
        case kind
        case snap
        case measurement
    }

    private enum Kind: String, Codable {
        case snap
        case measurement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .snap:
            try container.validateOnlyExpectedKeys([.kind, .snap], in: decoder)
            self = .snap(try container.decode(SnapQueryResult.self, forKey: .snap))
        case .measurement:
            try container.validateOnlyExpectedKeys([.kind, .measurement], in: decoder)
            self = .measurement(try container.decode(CADAgentMeasurementQueryResult.self, forKey: .measurement))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .snap(result):
            try container.encode(Kind.snap, forKey: .kind)
            try container.encode(result, forKey: .snap)
        case let .measurement(result):
            try container.encode(Kind.measurement, forKey: .kind)
            try container.encode(result, forKey: .measurement)
        }
    }
}
