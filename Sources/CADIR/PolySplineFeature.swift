import CADCore

public struct PolySplineFeature: Codable, Sendable, Hashable {
    public var sourceMesh: Mesh
    public var options: PolySplineOptions

    public init(
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions()
    ) {
        self.sourceMesh = sourceMesh
        self.options = options
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try sourceMesh.validate(tolerance: tolerance)
        try options.validate()
    }
}

public struct PolySplineOptions: Codable, Sendable, Hashable {
    public var roundedCorners: Bool
    public var mergePatches: Bool
    public var interpolateBoundaryExactly: Bool

    public init(
        roundedCorners: Bool = false,
        mergePatches: Bool = true,
        interpolateBoundaryExactly: Bool = true
    ) {
        self.roundedCorners = roundedCorners
        self.mergePatches = mergePatches
        self.interpolateBoundaryExactly = interpolateBoundaryExactly
    }

    public func validate() throws {
    }
}
