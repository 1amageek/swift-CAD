import CADCore

public enum ParameterDomain: Codable, Equatable, Sendable, Hashable {
    case unbounded
    case closed(Double, Double)
    case periodic(period: Double)

    private enum CodingKeys: String, CodingKey {
        case kind
        case lowerBound
        case upperBound
        case period
    }

    private enum Kind: String, Codable {
        case unbounded
        case closed
        case periodic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .unbounded:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .unbounded
        case .closed:
            try container.validateOnlyExpectedKeys([.kind, .lowerBound, .upperBound], in: decoder)
            self = .closed(
                try container.decode(Double.self, forKey: .lowerBound),
                try container.decode(Double.self, forKey: .upperBound)
            )
        case .periodic:
            try container.validateOnlyExpectedKeys([.kind, .period], in: decoder)
            self = .periodic(period: try container.decode(Double.self, forKey: .period))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unbounded:
            try container.encode(Kind.unbounded, forKey: .kind)
        case let .closed(lowerBound, upperBound):
            try container.encode(Kind.closed, forKey: .kind)
            try container.encode(lowerBound, forKey: .lowerBound)
            try container.encode(upperBound, forKey: .upperBound)
        case let .periodic(period):
            try container.encode(Kind.periodic, forKey: .kind)
            try container.encode(period, forKey: .period)
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        switch self {
        case .unbounded:
            return
        case let .closed(lowerBound, upperBound):
            let resolution = Self.parameterResolution(
                lowerBound: lowerBound,
                upperBound: upperBound,
                tolerance: tolerance
            )
            guard lowerBound.isFinite,
                  upperBound.isFinite,
                  upperBound - lowerBound > resolution else {
                throw GeometryError.invalidDistance(upperBound - lowerBound)
            }
        case let .periodic(period):
            let resolution = Self.parameterResolution(
                lowerBound: 0.0,
                upperBound: period,
                tolerance: tolerance
            )
            guard period.isFinite,
                  period > resolution else {
                throw GeometryError.invalidDistance(period)
            }
        }
    }

    public func contains(_ parameter: Double, tolerance: ModelingTolerance) throws -> Bool {
        try validate(tolerance: tolerance)
        guard parameter.isFinite else {
            return false
        }
        switch self {
        case .unbounded, .periodic:
            return true
        case let .closed(lowerBound, upperBound):
            let resolution = Self.parameterResolution(
                lowerBound: lowerBound,
                upperBound: upperBound,
                tolerance: tolerance
            )
            return parameter >= lowerBound - resolution
                && parameter <= upperBound + resolution
        }
    }

    public func containsSpan(
        from start: Double,
        to end: Double,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let containsStart = try contains(start, tolerance: tolerance)
        let containsEnd = try contains(end, tolerance: tolerance)
        return containsStart && containsEnd
    }

    func parameterResolution(tolerance: ModelingTolerance) -> Double {
        switch self {
        case .unbounded:
            return tolerance.relative
        case let .closed(lowerBound, upperBound):
            return Self.parameterResolution(
                lowerBound: lowerBound,
                upperBound: upperBound,
                tolerance: tolerance
            )
        case let .periodic(period):
            return Self.parameterResolution(
                lowerBound: 0.0,
                upperBound: period,
                tolerance: tolerance
            )
        }
    }

    private static func parameterResolution(
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        let span = upperBound - lowerBound
        let scale = max(abs(lowerBound), abs(upperBound), abs(span), 1.0)
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }
}
