import CADCore

/// Explicit canonical mass density, distinct from a scalar or length quantity.
public struct PhysicalDensity: Codable, Hashable, Sendable {
    public let kilogramsPerCubicMeter: Double
    public init(kilogramsPerCubicMeter: Double) { self.kilogramsPerCubicMeter = kilogramsPerCubicMeter }
    public func validate() throws {
        guard kilogramsPerCubicMeter.isFinite, kilogramsPerCubicMeter > 0 else {
            throw ProductAttributeError.invalidSource("Density must be finite and positive in kilograms per cubic meter.")
        }
    }
    private enum CodingKeys: String, CodingKey { case kilogramsPerCubicMeter }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.kilogramsPerCubicMeter], in: decoder)
        kilogramsPerCubicMeter = try c.decode(Double.self, forKey: .kilogramsPerCubicMeter)
        try validate()
    }
}
