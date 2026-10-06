import CADCore

public struct ProductValidationProperty: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case area(Double)
        case volume(Double)
        case centroid(Point3D)
        case length(Double)

        #if !hasFeature(Embedded)
        private enum CodingKeys: String, CodingKey { case kind, scalar, point }
        #endif

        #if !hasFeature(Embedded)
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            if kind == "centroid" {
                try c.validateOnlyExpectedKeys([.kind, .point], in: decoder)
                let point = try c.decode(Point3D.self, forKey: .point)
                guard point.isFinite else { throw ProductAttributeError.invalidSource("Invalid validation centroid.") }
                self = .centroid(point)
            } else {
                try c.validateOnlyExpectedKeys([.kind, .scalar], in: decoder)
                let scalar = try c.decode(Double.self, forKey: .scalar)
                guard scalar.isFinite, scalar >= 0 else { throw ProductAttributeError.invalidSource("Invalid validation measure.") }
                switch kind {
                case "area": self = .area(scalar)
                case "volume": self = .volume(scalar)
                case "length": self = .length(scalar)
                default: throw ProductAttributeError.invalidSource("Unknown validation measure kind.")
                }
            }
        }
        #endif

        #if !hasFeature(Embedded)
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .centroid(point): try c.encode("centroid", forKey: .kind); try c.encode(point, forKey: .point)
            case let .area(value): try c.encode("area", forKey: .kind); try c.encode(value, forKey: .scalar)
            case let .volume(value): try c.encode("volume", forKey: .kind); try c.encode(value, forKey: .scalar)
            case let .length(value): try c.encode("length", forKey: .kind); try c.encode(value, forKey: .scalar)
            }
        }
        #endif
    }
    public let id: ProductMetadataID
    public var name: String
    public var description: String
    public var target: ProductAttributeTarget
    public var value: Value
    public init(id: ProductMetadataID = ProductMetadataID(), name: String = "", description: String = "",
                target: ProductAttributeTarget, value: Value) {
        self.id = id; self.name = name; self.description = description; self.target = target; self.value = value
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description, target, value }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .target, .value], in: decoder)
        id = try c.decode(ProductMetadataID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        target = try c.decode(ProductAttributeTarget.self, forKey: .target)
        value = try c.decode(Value.self, forKey: .value)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(target, forKey: .target)
        try c.encode(value, forKey: .value)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductValidationProperty: Codable {}
extension ProductValidationProperty.Value: Codable {}
#endif
