import CADCore

public enum Surface3D: Codable, Sendable, Hashable {
    case plane(Plane3D)
    case cylinder(Cylinder3D)
    case bSpline(BSplineSurface3D)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case let .plane(plane):
            try plane.validate(tolerance: tolerance)
        case let .cylinder(cylinder):
            try cylinder.validate(tolerance: tolerance)
        case let .bSpline(surface):
            try surface.validate(tolerance: tolerance)
        }
    }

    public var uDomain: ParameterDomain {
        switch self {
        case .plane:
            .unbounded
        case .cylinder:
            .periodic(period: Double.pi * 2.0)
        case .bSpline(let surface):
            surface.uDomain
        }
    }

    public var vDomain: ParameterDomain {
        switch self {
        case .plane, .cylinder:
            .unbounded
        case .bSpline(let surface):
            surface.vDomain
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case plane
        case cylinder
        case bSpline
    }

    private enum Kind: String, Codable {
        case plane
        case cylinder
        case bSpline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .plane:
            try container.validateOnlyExpectedKeys([.kind, .plane], in: decoder)
            self = .plane(try container.decode(Plane3D.self, forKey: .plane))
        case .cylinder:
            try container.validateOnlyExpectedKeys([.kind, .cylinder], in: decoder)
            self = .cylinder(try container.decode(Cylinder3D.self, forKey: .cylinder))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineSurface3D.self, forKey: .bSpline))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .plane(plane):
            try container.encode(Kind.plane, forKey: .kind)
            try container.encode(plane, forKey: .plane)
        case let .cylinder(cylinder):
            try container.encode(Kind.cylinder, forKey: .kind)
            try container.encode(cylinder, forKey: .cylinder)
        case let .bSpline(surface):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(surface, forKey: .bSpline)
        }
    }
}
