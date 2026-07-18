import CADCore

public enum PrimitiveDefinition: Codable, Hashable, Sendable {
    case box(BoxPrimitive)
    case cylinder(CylinderPrimitive)
    case cone(ConePrimitive)
    case sphere(SpherePrimitive)
    case torus(TorusPrimitive)

    public func validate(tolerance: ModelingTolerance) throws {
        switch self {
        case let .box(primitive): try primitive.validate(tolerance: tolerance)
        case let .cylinder(primitive): try primitive.validate(tolerance: tolerance)
        case let .cone(primitive): try primitive.validate(tolerance: tolerance)
        case let .sphere(primitive): try primitive.validate(tolerance: tolerance)
        case let .torus(primitive): try primitive.validate(tolerance: tolerance)
        }
    }

    public var referencedParameterIDs: Set<ParameterID> {
        switch self {
        case let .box(primitive):
            return primitive.width.referencedParameterIDs
                .union(primitive.depth.referencedParameterIDs)
                .union(primitive.height.referencedParameterIDs)
        case let .cylinder(primitive):
            return primitive.radius.referencedParameterIDs
                .union(primitive.height.referencedParameterIDs)
        case let .cone(primitive):
            return primitive.baseRadius.referencedParameterIDs
                .union(primitive.height.referencedParameterIDs)
        case let .sphere(primitive):
            return primitive.radius.referencedParameterIDs
        case let .torus(primitive):
            return primitive.majorRadius.referencedParameterIDs
                .union(primitive.minorRadius.referencedParameterIDs)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case box
        case cylinder
        case cone
        case sphere
        case torus
    }

    private enum Kind: String, Codable {
        case box
        case cylinder
        case cone
        case sphere
        case torus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .box:
            try container.validateOnlyExpectedKeys([.kind, .box], in: decoder)
            self = .box(try container.decode(BoxPrimitive.self, forKey: .box))
        case .cylinder:
            try container.validateOnlyExpectedKeys([.kind, .cylinder], in: decoder)
            self = .cylinder(try container.decode(CylinderPrimitive.self, forKey: .cylinder))
        case .cone:
            try container.validateOnlyExpectedKeys([.kind, .cone], in: decoder)
            self = .cone(try container.decode(ConePrimitive.self, forKey: .cone))
        case .sphere:
            try container.validateOnlyExpectedKeys([.kind, .sphere], in: decoder)
            self = .sphere(try container.decode(SpherePrimitive.self, forKey: .sphere))
        case .torus:
            try container.validateOnlyExpectedKeys([.kind, .torus], in: decoder)
            self = .torus(try container.decode(TorusPrimitive.self, forKey: .torus))
        }
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .box(primitive):
            try container.encode(Kind.box, forKey: .kind)
            try container.encode(primitive, forKey: .box)
        case let .cylinder(primitive):
            try container.encode(Kind.cylinder, forKey: .kind)
            try container.encode(primitive, forKey: .cylinder)
        case let .cone(primitive):
            try container.encode(Kind.cone, forKey: .kind)
            try container.encode(primitive, forKey: .cone)
        case let .sphere(primitive):
            try container.encode(Kind.sphere, forKey: .kind)
            try container.encode(primitive, forKey: .sphere)
        case let .torus(primitive):
            try container.encode(Kind.torus, forKey: .kind)
            try container.encode(primitive, forKey: .torus)
        }
    }
}
