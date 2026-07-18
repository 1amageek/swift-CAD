import CADCore

public struct PolySplineFeature: Codable, Sendable, Hashable {
    public var sourceMesh: Mesh
    public var options: PolySplineOptions
    public var controlPointOverrides: [PolySplineSurfaceControlPointOverride]

    public init(
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        controlPointOverrides: [PolySplineSurfaceControlPointOverride] = []
    ) {
        self.sourceMesh = sourceMesh
        self.options = options
        self.controlPointOverrides = controlPointOverrides
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try sourceMesh.validate(tolerance: tolerance)
        try options.validate()
        var addresses = Set<PolySplineSurfaceControlPointAddress>()
        for override in controlPointOverrides {
            try override.validate()
            let address = override.address
            guard addresses.insert(address).inserted else {
                throw FeatureEvaluationError.invalidGraph(
                    "PolySpline surface control point overrides must not contain duplicate addresses."
                )
            }
        }
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
