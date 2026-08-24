import CADCore

/// An immutable curve paired with the tolerance at which its complete
/// representation has been validated.
///
/// Repeated numerical consumers should retain this value instead of invoking
/// validation for every sampled parameter.
public struct ValidatedCurve3D: Sendable {
    public let curve: Curve3D
    public let tolerance: ModelingTolerance

    public init(
        _ curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws {
        try curve.validate(tolerance: tolerance)
        self.curve = curve
        self.tolerance = tolerance
    }

    public var parameterDomain: ParameterDomain {
        curve.parameterDomain
    }

    public func point(at parameter: Double) throws -> Point3D {
        guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(parameter)
        }
        return try curve.pointAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
    }

    public func differentialGeometry(
        at parameter: Double
    ) throws -> Curve3D.DifferentialGeometry {
        guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(parameter)
        }
        return try curve.differentialGeometryAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
    }

    public func parameterProjection(
        of point: Point3D,
        options: CurveParameterProjectionOptions = .init()
    ) throws -> CurveParameterProjection {
        try options.validate(tolerance: tolerance)
        try point.validate()
        return try curve.parameterProjectionAssumingValid(
            of: point,
            options: options,
            tolerance: tolerance
        )
    }
}
