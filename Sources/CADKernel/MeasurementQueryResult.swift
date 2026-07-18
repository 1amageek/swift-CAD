import CADCore

public enum MeasurementQueryResult: Codable, Sendable, Hashable {
    case point(SelectionMeasurementPoint)
    case distance(SelectionDistanceMeasurement)
    case angle(SelectionAngleMeasurement)

    private enum CodingKeys: String, CodingKey {
        case kind
        case point
        case distance
        case angle
    }

    private enum Kind: String, Codable {
        case point
        case distance
        case angle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .point:
            try container.validateOnlyExpectedKeys([.kind, .point], in: decoder)
            self = .point(try container.decode(SelectionMeasurementPoint.self, forKey: .point))
        case .distance:
            try container.validateOnlyExpectedKeys([.kind, .distance], in: decoder)
            self = .distance(try container.decode(SelectionDistanceMeasurement.self, forKey: .distance))
        case .angle:
            try container.validateOnlyExpectedKeys([.kind, .angle], in: decoder)
            self = .angle(try container.decode(SelectionAngleMeasurement.self, forKey: .angle))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .point(result):
            try container.encode(Kind.point, forKey: .kind)
            try container.encode(result, forKey: .point)
        case let .distance(result):
            try container.encode(Kind.distance, forKey: .kind)
            try container.encode(result, forKey: .distance)
        case let .angle(result):
            try container.encode(Kind.angle, forKey: .kind)
            try container.encode(result, forKey: .angle)
        }
    }
}
