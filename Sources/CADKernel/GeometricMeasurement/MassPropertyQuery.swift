import CADCore
import CADGeometry
import CADTopology

public struct MassPropertyQuery: Sendable, Hashable {
    public let components: [MassPropertyComponent]
    public let options: BRepVolumeMomentOptions
    /// Inertia reference in canonical metres.
    public let reference: Point3D

    public init(components: [MassPropertyComponent], options: BRepVolumeMomentOptions,
        reference: Point3D = .origin) {
        self.components = components; self.options = options; self.reference = reference
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate(); try validateTransport()
        for component in components { try component.validate(tolerance: tolerance) }
    }

    private func validateTransport() throws {
        try options.validate(); try reference.validate()
        guard !components.isEmpty, components.count <= options.maximumWork else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Mass property query requires bounded original body occurrences.")
        }
    }
}

#if !hasFeature(Embedded)
extension MassPropertyQuery: Codable {
    private enum CodingKeys: String, CodingKey { case components, options, reference }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.components, .options, .reference], in: decoder)
        self.init(components: try c.decode([MassPropertyComponent].self, forKey: .components),
            options: try c.decode(BRepVolumeMomentOptions.self, forKey: .options),
            reference: try c.decode(Point3D.self, forKey: .reference))
        try validateTransport()
    }
    public func encode(to encoder: Encoder) throws {
        try validateTransport()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(components, forKey: .components)
        try c.encode(options, forKey: .options)
        try c.encode(reference, forKey: .reference)
    }
}
#endif
