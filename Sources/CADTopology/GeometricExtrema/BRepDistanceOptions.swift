import CADCore

public struct BRepDistanceOptions: Hashable, Sendable {
    public var absoluteAccuracy: Double
    public var relativeAccuracy: Double
    public var maximumWork: Int
    public var maximumSubdivisionDepth: Int
    public var maximumCumulativeStorageBytes: Int?
    public var maximumSourceDepth: Int
    public var maximumAlgebraicDepth: Int

    public init(absoluteAccuracy: Double, relativeAccuracy: Double = 0,
        maximumWork: Int = 262_144, maximumSubdivisionDepth: Int = 32,
        maximumCumulativeStorageBytes: Int? = nil, maximumSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int = 32) {
        self.absoluteAccuracy = absoluteAccuracy
        self.relativeAccuracy = relativeAccuracy
        self.maximumWork = maximumWork
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCumulativeStorageBytes = maximumCumulativeStorageBytes
        self.maximumSourceDepth = maximumSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    public func validate() throws {
        guard absoluteAccuracy.isFinite, absoluteAccuracy > 0,
            relativeAccuracy.isFinite, relativeAccuracy >= 0,
            maximumCumulativeStorageBytes.map({ $0 >= 0 }) ?? true,
            (0...16).contains(maximumSourceDepth), (0...32).contains(maximumAlgebraicDepth),
            (1...262_144).contains(maximumWork), (0...32).contains(maximumSubdivisionDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Distance accuracy and original work/depth ceilings are invalid.")
        }
    }
}

#if !hasFeature(Embedded)
extension BRepDistanceOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case absoluteAccuracy, relativeAccuracy, maximumWork, maximumSubdivisionDepth, maximumCumulativeStorageBytes, maximumSourceDepth, maximumAlgebraicDepth
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.absoluteAccuracy, .relativeAccuracy, .maximumWork, .maximumSubdivisionDepth, .maximumCumulativeStorageBytes, .maximumSourceDepth, .maximumAlgebraicDepth], in: decoder)
        self.init(absoluteAccuracy: try c.decode(Double.self, forKey: .absoluteAccuracy),
            relativeAccuracy: try c.decode(Double.self, forKey: .relativeAccuracy),
            maximumWork: try c.decode(Int.self, forKey: .maximumWork),
            maximumSubdivisionDepth: try c.decode(Int.self, forKey: .maximumSubdivisionDepth),
            maximumCumulativeStorageBytes: try c.decodeIfPresent(Int.self, forKey: .maximumCumulativeStorageBytes),
            maximumSourceDepth: try c.decodeIfPresent(Int.self, forKey: .maximumSourceDepth) ?? 16,
            maximumAlgebraicDepth: try c.decodeIfPresent(Int.self, forKey: .maximumAlgebraicDepth) ?? 32)
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(absoluteAccuracy, forKey: .absoluteAccuracy)
        try c.encode(relativeAccuracy, forKey: .relativeAccuracy)
        try c.encode(maximumWork, forKey: .maximumWork)
        try c.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try c.encodeIfPresent(maximumCumulativeStorageBytes, forKey: .maximumCumulativeStorageBytes)
        try c.encode(maximumSourceDepth, forKey: .maximumSourceDepth)
        try c.encode(maximumAlgebraicDepth, forKey: .maximumAlgebraicDepth)
    }
}
#endif
