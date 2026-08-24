import CADCore

public struct CurveDirectionalProjectionOptions: Sendable, Hashable {
    public var limits: ProjectionResourceLimits
    public var range: CurveDirectionalProjectionRange

    public init(
        limits: ProjectionResourceLimits = ProjectionResourceLimits(),
        range: CurveDirectionalProjectionRange = .line
    ) {
        self.limits = limits
        self.range = range
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
    }
}
