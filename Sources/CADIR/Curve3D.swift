import CADCore

public enum Curve3D: Codable, Sendable, Hashable {
    case line(Line3D)
    case circle(Circle3D)
    case bSpline(BSplineCurve3D)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case let .line(line):
            try line.validate(tolerance: tolerance)
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
        case let .bSpline(curve):
            try curve.validate(tolerance: tolerance)
        }
    }

    public var parameterDomain: ParameterDomain {
        switch self {
        case .line:
            .unbounded
        case .circle:
            .periodic(period: Double.pi * 2.0)
        case let .bSpline(curve):
            curve.domain
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case line
        case circle
        case bSpline
    }

    private enum Kind: String, Codable {
        case line
        case circle
        case bSpline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .line:
            try container.validateOnlyExpectedKeys([.kind, .line], in: decoder)
            self = .line(try container.decode(Line3D.self, forKey: .line))
        case .circle:
            try container.validateOnlyExpectedKeys([.kind, .circle], in: decoder)
            self = .circle(try container.decode(Circle3D.self, forKey: .circle))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve3D.self, forKey: .bSpline))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .line(line):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(line, forKey: .line)
        case let .circle(circle):
            try container.encode(Kind.circle, forKey: .kind)
            try container.encode(circle, forKey: .circle)
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
        }
    }
}
