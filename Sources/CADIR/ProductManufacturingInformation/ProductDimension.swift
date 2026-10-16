import CADCore
import CADGeometry

public struct ProductDimension: Equatable, Sendable {
    public enum Kind: String, Sendable { case size, location, diameter, radius, angle, arcLength }
    public let id: ProductMetadataID
    public var name: String
    public var description: String
    public var kind: Kind
    public var target: ProductAttributeTarget
    public var referenceTarget: ProductAttributeTarget?
    public var nominal: Double
    public var lowerDeviation: Double?
    public var upperDeviation: Double?
    public init(id: ProductMetadataID = ProductMetadataID(), name: String, description: String = "", kind: Kind,
                target: ProductAttributeTarget, referenceTarget: ProductAttributeTarget? = nil,
                nominal: Double, lowerDeviation: Double? = nil, upperDeviation: Double? = nil) {
        self.id = id; self.name = name; self.description = description; self.kind = kind
        self.target = target; self.referenceTarget = referenceTarget; self.nominal = nominal
        self.lowerDeviation = lowerDeviation; self.upperDeviation = upperDeviation
    }
    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate(using: &execution); try referenceTarget?.validate(using: &execution)
        guard nominal.isFinite, nominal >= 0,
              (lowerDeviation == nil) == (upperDeviation == nil),
              lowerDeviation?.isFinite != false, upperDeviation?.isFinite != false,
              lowerDeviation == nil || lowerDeviation! <= upperDeviation!,
              kind != .location || referenceTarget != nil else {
            throw ProductAttributeError.invalidSource("Invalid dimensional value, interval or location reference.")
        }
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description, kind, target, referenceTarget, nominal, lowerDeviation, upperDeviation }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .kind, .target, .referenceTarget, .nominal, .lowerDeviation, .upperDeviation], in: decoder)
        id = try c.decode(ProductMetadataID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        kind = try c.decode(Kind.self, forKey: .kind)
        target = try c.decode(ProductAttributeTarget.self, forKey: .target)
        guard c.contains(.referenceTarget) else { throw ProductAttributeError.invalidSource("Missing required nullable metadata field.") }
        referenceTarget = try c.decodeIfPresent(ProductAttributeTarget.self, forKey: .referenceTarget)
        nominal = try c.decode(Double.self, forKey: .nominal)
        guard c.contains(.lowerDeviation) else { throw ProductAttributeError.invalidSource("Missing required nullable metadata field.") }
        lowerDeviation = try c.decodeIfPresent(Double.self, forKey: .lowerDeviation)
        guard c.contains(.upperDeviation) else { throw ProductAttributeError.invalidSource("Missing required nullable metadata field.") }
        upperDeviation = try c.decodeIfPresent(Double.self, forKey: .upperDeviation)
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
        try c.encode(target, forKey: .target)
        try c.encode(referenceTarget, forKey: .referenceTarget)
        try c.encode(nominal, forKey: .nominal)
        try c.encode(lowerDeviation, forKey: .lowerDeviation)
        try c.encode(upperDeviation, forKey: .upperDeviation)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductDimension: Codable {}
extension ProductDimension.Kind: Codable {}
#endif
