import CADCore
import CADGeometry

public struct BRepVolumeMomentOptions: Sendable, Hashable {
    /// Maximum full enclosure width for each raw moment in its model-unit dimension.
    public let absoluteAccuracy: Double
    /// Width relative to every value permitted by the complete moment enclosure.
    public let relativeAccuracy: Double
    public let maximumWork: Int
    public let maximumSubdivisionDepth: Int
    public init(absoluteAccuracy: Double, relativeAccuracy: Double = 1e-8,
        maximumWork: Int = 262_144, maximumSubdivisionDepth: Int = 32) {
        self.absoluteAccuracy = absoluteAccuracy; self.relativeAccuracy = relativeAccuracy
        self.maximumWork = maximumWork; self.maximumSubdivisionDepth = maximumSubdivisionDepth
    }

    public func validate() throws {
        guard absoluteAccuracy.isFinite, absoluteAccuracy > 0,
            relativeAccuracy.isFinite, relativeAccuracy >= 0,
            (1...262_144).contains(maximumWork), (0...32).contains(maximumSubdivisionDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Volume-moment accuracy and original work/depth ceilings are invalid.")
        }
    }
}

#if !hasFeature(Embedded)
extension BRepVolumeMomentOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case absoluteAccuracy, relativeAccuracy, maximumWork, maximumSubdivisionDepth
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.absoluteAccuracy, .relativeAccuracy, .maximumWork, .maximumSubdivisionDepth], in: decoder)
        self.init(absoluteAccuracy: try c.decode(Double.self, forKey: .absoluteAccuracy),
            relativeAccuracy: try c.decode(Double.self, forKey: .relativeAccuracy),
            maximumWork: try c.decode(Int.self, forKey: .maximumWork),
            maximumSubdivisionDepth: try c.decode(Int.self, forKey: .maximumSubdivisionDepth))
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(absoluteAccuracy, forKey: .absoluteAccuracy)
        try c.encode(relativeAccuracy, forKey: .relativeAccuracy)
        try c.encode(maximumWork, forKey: .maximumWork)
        try c.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
    }
}
#endif
