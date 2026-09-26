import CADCore

/// A physically based appearance: the metallic–roughness base with index of refraction, clearcoat,
/// sheen, specular, iridescence and transmission layers, and the density that turns an object's
/// volume into mass.
///
/// Every layer defaults to having no effect (the values of a plain metallic–roughness material), so
/// a material written before the layers existed decodes to the appearance it always had.
public struct Material: Codable, Sendable, Hashable {
    public var id: MaterialID
    public var name: String
    public var baseColor: ColorRGBA
    public var metallic: Double
    public var roughness: Double
    public var opacity: Double
    /// Index of refraction, 1 (air) to 3.
    public var ior: Double
    public var clearcoat: Double
    public var clearcoatRoughness: Double
    public var sheen: Double
    public var sheenColor: ColorRGBA
    public var sheenRoughness: Double
    public var specularColor: ColorRGBA
    public var specularIntensity: Double
    public var iridescence: Double
    /// Index of refraction of the iridescent thin film, 1 to 3.
    public var iridescenceIOR: Double
    /// Thickness of the transmitting volume, in meters.
    public var thickness: Double
    public var transmission: Double
    /// Mass per volume in kilograms per cubic meter, or `nil` when the material has no mass.
    public var density: Double?

    public static let defaultIOR = 1.5
    public static let defaultIridescenceIOR = 1.3

    public init(
        id: MaterialID = MaterialID(),
        name: String,
        baseColor: ColorRGBA,
        metallic: Double,
        roughness: Double,
        opacity: Double,
        ior: Double = Material.defaultIOR,
        clearcoat: Double = 0,
        clearcoatRoughness: Double = 0,
        sheen: Double = 0,
        sheenColor: ColorRGBA = ColorRGBA(r: 0, g: 0, b: 0, a: 1),
        sheenRoughness: Double = 1,
        specularColor: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1, a: 1),
        specularIntensity: Double = 1,
        iridescence: Double = 0,
        iridescenceIOR: Double = Material.defaultIridescenceIOR,
        thickness: Double = 0,
        transmission: Double = 0,
        density: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.opacity = opacity
        self.ior = ior
        self.clearcoat = clearcoat
        self.clearcoatRoughness = clearcoatRoughness
        self.sheen = sheen
        self.sheenColor = sheenColor
        self.sheenRoughness = sheenRoughness
        self.specularColor = specularColor
        self.specularIntensity = specularIntensity
        self.iridescence = iridescence
        self.iridescenceIOR = iridescenceIOR
        self.thickness = thickness
        self.transmission = transmission
        self.density = density
    }

    public func validate() throws {
        try baseColor.validate()
        try validateUnitInterval(metallic, field: "metallic")
        try validateUnitInterval(roughness, field: "roughness")
        try validateUnitInterval(opacity, field: "opacity")
        try validateRange(ior, 1...3, field: "ior")
        try validateUnitInterval(clearcoat, field: "clearcoat")
        try validateUnitInterval(clearcoatRoughness, field: "clearcoatRoughness")
        try validateUnitInterval(sheen, field: "sheen")
        try sheenColor.validate()
        try validateUnitInterval(sheenRoughness, field: "sheenRoughness")
        try specularColor.validate()
        try validateUnitInterval(specularIntensity, field: "specularIntensity")
        try validateUnitInterval(iridescence, field: "iridescence")
        try validateRange(iridescenceIOR, 1...3, field: "iridescenceIOR")
        guard thickness.isFinite, thickness >= 0 else {
            throw MaterialError.valueOutOfRange(field: "thickness", value: thickness)
        }
        try validateUnitInterval(transmission, field: "transmission")
        if let density {
            guard density.isFinite, density > 0 else {
                throw MaterialError.valueOutOfRange(field: "density", value: density)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseColor, metallic, roughness, opacity
        case ior, clearcoat, clearcoatRoughness, sheen, sheenColor, sheenRoughness
        case specularColor, specularIntensity, iridescence, iridescenceIOR, thickness, transmission, density
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let plain = Material(
            id: try container.decode(MaterialID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            baseColor: try container.decode(ColorRGBA.self, forKey: .baseColor),
            metallic: try container.decode(Double.self, forKey: .metallic),
            roughness: try container.decode(Double.self, forKey: .roughness),
            opacity: try container.decode(Double.self, forKey: .opacity)
        )
        // Materials written before the physical layers existed carry none of them.
        self = plain
        ior = try container.decodeIfPresent(Double.self, forKey: .ior) ?? plain.ior
        clearcoat = try container.decodeIfPresent(Double.self, forKey: .clearcoat) ?? plain.clearcoat
        clearcoatRoughness = try container.decodeIfPresent(Double.self, forKey: .clearcoatRoughness) ?? plain.clearcoatRoughness
        sheen = try container.decodeIfPresent(Double.self, forKey: .sheen) ?? plain.sheen
        sheenColor = try container.decodeIfPresent(ColorRGBA.self, forKey: .sheenColor) ?? plain.sheenColor
        sheenRoughness = try container.decodeIfPresent(Double.self, forKey: .sheenRoughness) ?? plain.sheenRoughness
        specularColor = try container.decodeIfPresent(ColorRGBA.self, forKey: .specularColor) ?? plain.specularColor
        specularIntensity = try container.decodeIfPresent(Double.self, forKey: .specularIntensity) ?? plain.specularIntensity
        iridescence = try container.decodeIfPresent(Double.self, forKey: .iridescence) ?? plain.iridescence
        iridescenceIOR = try container.decodeIfPresent(Double.self, forKey: .iridescenceIOR) ?? plain.iridescenceIOR
        thickness = try container.decodeIfPresent(Double.self, forKey: .thickness) ?? plain.thickness
        transmission = try container.decodeIfPresent(Double.self, forKey: .transmission) ?? plain.transmission
        density = try container.decodeIfPresent(Double.self, forKey: .density)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseColor, forKey: .baseColor)
        try container.encode(metallic, forKey: .metallic)
        try container.encode(roughness, forKey: .roughness)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(ior, forKey: .ior)
        try container.encode(clearcoat, forKey: .clearcoat)
        try container.encode(clearcoatRoughness, forKey: .clearcoatRoughness)
        try container.encode(sheen, forKey: .sheen)
        try container.encode(sheenColor, forKey: .sheenColor)
        try container.encode(sheenRoughness, forKey: .sheenRoughness)
        try container.encode(specularColor, forKey: .specularColor)
        try container.encode(specularIntensity, forKey: .specularIntensity)
        try container.encode(iridescence, forKey: .iridescence)
        try container.encode(iridescenceIOR, forKey: .iridescenceIOR)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(transmission, forKey: .transmission)
        try container.encodeIfPresent(density, forKey: .density)
    }
}

public struct ColorRGBA: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public func validate() throws {
        try validateUnitInterval(r, field: "baseColor.r")
        try validateUnitInterval(g, field: "baseColor.g")
        try validateUnitInterval(b, field: "baseColor.b")
        try validateUnitInterval(a, field: "baseColor.a")
    }
}

private func validateRange(_ value: Double, _ range: ClosedRange<Double>, field: String) throws {
    guard value.isFinite, range.contains(value) else {
        throw MaterialError.valueOutOfRange(field: field, value: value)
    }
}

private func validateUnitInterval(_ value: Double, field: String) throws {
    guard value.isFinite, (0.0...1.0).contains(value) else {
        throw MaterialError.valueOutOfRange(field: field, value: value)
    }
}
