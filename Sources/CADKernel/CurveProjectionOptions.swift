import CADCore

public struct CurveProjectionOptions: Sendable, Hashable {
    public var limits: ProjectionResourceLimits

    public init(limits: ProjectionResourceLimits = ProjectionResourceLimits()) {
        self.limits = limits
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
    }
}
