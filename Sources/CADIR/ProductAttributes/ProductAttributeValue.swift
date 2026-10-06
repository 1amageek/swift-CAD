import CADCore

public enum ProductAttributeValue: Hashable, Sendable {
    public enum Property: String, Hashable, Sendable { case name, color, opacity, material, density }
    case name(String)
    case color(ColorRGBA)
    case opacity(Double)
    case material(PhysicalMaterialID)
    case density(PhysicalDensity)
    case descriptorDensity(PhysicalMaterialID)
    public var property: Property {
        switch self {
        case .name: .name
        case .color: .color
        case .opacity: .opacity
        case .material: .material
        case .density, .descriptorDensity: .density
        }
    }
    public func validate() throws {
        switch self {
        case let .color(color):
            try color.validate()
            guard color.a == 1 else { throw ProductAttributeError.invalidSource("Product color uses separate explicit opacity.") }
        case let .opacity(value):
            guard value.isFinite, (0...1).contains(value) else { throw ProductAttributeError.invalidSource("Opacity must be finite in zero through one.") }
        case let .density(value): try value.validate()
        case .name, .material, .descriptorDensity: break
        }
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case kind, name, color, opacity, material, density, descriptorDensity }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let key: CodingKeys
        switch kind {
        case "name": key = .name; self = .name(try c.decode(String.self, forKey: .name))
        case "color": key = .color; self = .color(try c.decode(ColorRGBA.self, forKey: .color))
        case "opacity": key = .opacity; self = .opacity(try c.decode(Double.self, forKey: .opacity))
        case "material": key = .material; self = .material(try c.decode(PhysicalMaterialID.self, forKey: .material))
        case "density": key = .density; self = .density(try c.decode(PhysicalDensity.self, forKey: .density))
        case "descriptorDensity": key = .descriptorDensity; self = .descriptorDensity(try c.decode(PhysicalMaterialID.self, forKey: .descriptorDensity))
        default: throw ProductAttributeError.invalidSource("Unknown product property kind.")
        }
        try c.validateOnlyExpectedKeys([.kind, key], in: decoder)
        try validate()
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .name(value): try c.encode("name", forKey: .kind); try c.encode(value, forKey: .name)
        case let .color(value): try c.encode("color", forKey: .kind); try c.encode(value, forKey: .color)
        case let .opacity(value): try c.encode("opacity", forKey: .kind); try c.encode(value, forKey: .opacity)
        case let .material(value): try c.encode("material", forKey: .kind); try c.encode(value, forKey: .material)
        case let .density(value): try c.encode("density", forKey: .kind); try c.encode(value, forKey: .density)
        case let .descriptorDensity(value): try c.encode("descriptorDensity", forKey: .kind); try c.encode(value, forKey: .descriptorDensity)
        }
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductAttributeValue: Codable {}
extension ProductAttributeValue.Property: Codable {}
#endif
