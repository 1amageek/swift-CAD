import CADCore

/// Identity and units of an original three-dimensional representation context.
public struct IndependentShapeContext: Equatable, Sendable {
    public let id: IndependentShapeContextID
    public let identifier: String
    public let type: String
    public let units: UnitSystem
    public let originalLengthSource: OriginalSTEPLengthSource?
    public let originalAngularSource: IndependentShapeAngularSource?
    public init(id: IndependentShapeContextID = .init(), identifier: String = "", type: String = "", units: UnitSystem, originalAngularSource: IndependentShapeAngularSource? = nil, originalLengthSource: OriginalSTEPLengthSource? = nil) {
        self.originalLengthSource = originalLengthSource; self.id = id; self.identifier = identifier; self.type = type; self.units = units; self.originalAngularSource = originalAngularSource
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, identifier, type, units, originalAngularSource, originalLengthSource }
    #endif
    #if !hasFeature(Embedded)
    private enum UnitKeys: String, CodingKey { case length, angle }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .identifier, .type, .units, .originalAngularSource, .originalLengthSource], in: decoder)
        id = try c.decode(IndependentShapeContextID.self, forKey: .id)
        identifier = try c.decode(String.self, forKey: .identifier)
        type = try c.decode(String.self, forKey: .type)
        let d = try c.superDecoder(forKey: .units)
        let u = try d.container(keyedBy: UnitKeys.self)
        try u.validateOnlyExpectedKeys([.length, .angle], in: d)
        units = try UnitSystem(from: d)
        originalLengthSource = try c.decode(OriginalSTEPLengthSource?.self, forKey: .originalLengthSource)
        originalAngularSource = try c.decode(IndependentShapeAngularSource?.self, forKey: .originalAngularSource)
    }
    #endif
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.identifier.utf8.elementsEqual(b.identifier.utf8)
            && a.type.utf8.elementsEqual(b.type.utf8) && a.units == b.units && a.originalAngularSource == b.originalAngularSource && a.originalLengthSource == b.originalLengthSource
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeContext: Codable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(identifier, forKey: .identifier)
        try c.encode(type, forKey: .type); try c.encode(units, forKey: .units)
        try c.encode(originalAngularSource, forKey: .originalAngularSource)
        try c.encode(originalLengthSource, forKey: .originalLengthSource)
    }
}
#endif
