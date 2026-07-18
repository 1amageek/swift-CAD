import CADCore
import CADGeometry

public struct SurfaceContinuitySamplingSide: Codable, Sendable, Hashable {
    public var surface: Surface3D
    public var parameterCurve: SurfaceParameterCurve
    public var parameterDirection: SurfaceParameterCurveDirection
    public var frameOrientation: SurfaceFrameOrientation

    public init(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        parameterDirection: SurfaceParameterCurveDirection = .forward,
        frameOrientation: SurfaceFrameOrientation = .forward
    ) {
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.parameterDirection = parameterDirection
        self.frameOrientation = frameOrientation
    }

    public func target(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceContinuityTarget {
        let directedFraction: Double
        switch parameterDirection {
        case .forward:
            directedFraction = fraction
        case .reversed:
            directedFraction = 1.0 - fraction
        }
        let parameter = try parameterCurve.parameter(
            atNormalizedFraction: directedFraction,
            tolerance: tolerance
        )
        return SurfaceContinuityTarget(
            surface: surface,
            u: parameter.u,
            v: parameter.v,
            orientation: frameOrientation
        )
    }
}

public struct SurfaceContinuitySamplingOptions: Codable, Sendable, Hashable {
    public var sampleCount: Int

    public init(sampleCount: Int = 5) {
        self.sampleCount = sampleCount
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
    }
}

public struct SurfaceContinuitySampler: Sendable {
    private let modelingTolerance: ModelingTolerance

    public init(modelingTolerance: ModelingTolerance) {
        self.modelingTolerance = modelingTolerance
    }

    public func request(
        first: SurfaceContinuitySamplingSide,
        second: SurfaceContinuitySamplingSide,
        requiredLevel: SurfaceContinuityLevel,
        tolerances: SurfaceContinuityTolerances,
        options: SurfaceContinuitySamplingOptions = SurfaceContinuitySamplingOptions()
    ) throws -> SurfaceContinuityRequest {
        try modelingTolerance.validate()
        try tolerances.validate()
        try options.validate()
        try first.parameterCurve.validate(on: first.surface, tolerance: modelingTolerance)
        try second.parameterCurve.validate(on: second.surface, tolerance: modelingTolerance)
        let samplePairs = try (0..<options.sampleCount).map { index in
            let fraction = Double(index) / Double(options.sampleCount - 1)
            return SurfaceContinuitySamplePair(
                first: try first.target(atNormalizedFraction: fraction, tolerance: modelingTolerance),
                second: try second.target(atNormalizedFraction: fraction, tolerance: modelingTolerance)
            )
        }
        return SurfaceContinuityRequest(
            samplePairs: samplePairs,
            requiredLevel: requiredLevel,
            tolerances: tolerances
        )
    }
}
