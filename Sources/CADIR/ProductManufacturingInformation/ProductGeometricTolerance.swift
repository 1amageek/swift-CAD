import CADCore

public struct ProductGeometricTolerance: Equatable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case angularity, circularRunout, coaxiality, concentricity, cylindricity, flatness,
             lineProfile, parallelism, perpendicularity, position, roundness, straightness,
             surfaceProfile, symmetry, totalRunout
    }
    public enum Modifier: String, Hashable, Sendable {
        case maximumMaterialCondition, leastMaterialCondition, regardlessOfFeatureSize,
             commonZone, freeState, projectedToleranceZone, tangentPlane
    }
    public let id: ProductMetadataID
    public var name: String
    public var description: String
    public var kind: Kind
    public var magnitude: Double
    public var target: ProductAttributeTarget
    public var datumIDs: [ProductMetadataID]
    public var modifiers: [Modifier]
    public init(id: ProductMetadataID = ProductMetadataID(), name: String, description: String = "", kind: Kind, magnitude: Double,
                target: ProductAttributeTarget, datumIDs: [ProductMetadataID] = [], modifiers: [Modifier] = []) {
        self.id = id; self.name = name; self.description = description; self.kind = kind
        self.magnitude = magnitude; self.target = target; self.datumIDs = datumIDs; self.modifiers = modifiers
    }
    public func validate() throws {
        try target.validate()
        guard magnitude.isFinite, magnitude >= 0, Set(datumIDs).count == datumIDs.count,
              Set(modifiers.map(\.rawValue)).count == modifiers.count else {
            throw ProductAttributeError.invalidSource("Invalid geometric tolerance magnitude, datum order or modifiers.")
        }
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description, kind, magnitude, target, datumIDs, modifiers }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .kind, .magnitude, .target, .datumIDs, .modifiers], in: decoder)
        id = try c.decode(ProductMetadataID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        kind = try c.decode(Kind.self, forKey: .kind)
        magnitude = try c.decode(Double.self, forKey: .magnitude)
        target = try c.decode(ProductAttributeTarget.self, forKey: .target)
        datumIDs = try c.decode([ProductMetadataID].self, forKey: .datumIDs)
        modifiers = try c.decode([Modifier].self, forKey: .modifiers)
        try validate()
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(kind, forKey: .kind)
        try c.encode(magnitude, forKey: .magnitude)
        try c.encode(target, forKey: .target)
        try c.encode(datumIDs, forKey: .datumIDs)
        try c.encode(modifiers, forKey: .modifiers)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductGeometricTolerance: Codable {}
extension ProductGeometricTolerance.Kind: Codable {}
extension ProductGeometricTolerance.Modifier: Codable {}
#endif
