import CADCore
import CADTopology
import CADGeometry

public struct PolySplineFeature: Sendable, Hashable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try sourceMesh.validate(tolerance: tolerance, using: &execution)
        try options.validate(using: &execution)
        var addresses = Set<PolySplineSurfaceControlPointAddress>()
        for override in controlPointOverrides {
            try execution.consumeWork(1)
            try override.validate(using: &execution)
            let address = override.address
            guard try OriginalParameterQueryStorage.insert(address, in: &addresses, using: &execution) else {
                throw FeatureEvaluationError.invalidGraph(
                    "PolySpline surface control point overrides must not contain duplicate addresses."
                )
            }
        }
        try execution.checkpoint()
    }
}

/// PolySplines' options, defaulting as Plasticity's dialog opens: Rounded corners off, Merge
/// patches on, Interpolate boundary exactly off.
public struct PolySplineOptions: Sendable, Hashable {
    public var roundedCorners: Bool
    public var mergePatches: Bool
    public var interpolateBoundaryExactly: Bool

    public init(
        roundedCorners: Bool = false,
        mergePatches: Bool = true,
        interpolateBoundaryExactly: Bool = false
    ) {
        self.roundedCorners = roundedCorners
        self.mergePatches = mergePatches
        self.interpolateBoundaryExactly = interpolateBoundaryExactly
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.checkpoint()
    }
}

#if !hasFeature(Embedded)
extension PolySplineFeature: Codable {}
extension PolySplineOptions: Codable {}
#endif
