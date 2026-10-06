import CADCore

/// Explicit canonical mass density, distinct from a scalar or length quantity.
public struct PhysicalDensity: Hashable, Sendable {
    public let kilogramsPerCubicMeter: Double
    public init(kilogramsPerCubicMeter: Double) { self.kilogramsPerCubicMeter = kilogramsPerCubicMeter }
    public func validate() throws {
        guard kilogramsPerCubicMeter.isFinite, kilogramsPerCubicMeter > 0 else {
            throw ProductAttributeError.invalidSource("Density must be finite and positive in kilograms per cubic meter.")
        }
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case kilogramsPerCubicMeter }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.kilogramsPerCubicMeter], in: decoder)
        kilogramsPerCubicMeter = try c.decode(Double.self, forKey: .kilogramsPerCubicMeter)
        try validate()
    }
    #endif
}

#if !hasFeature(Embedded)
extension PhysicalDensity: Codable {}
#endif
