import CADCore

/// A parameter-preserving exact image of a curve under a rigid transform.
public struct RigidImageCurve3D: Codable, Hashable, Sendable {
    public let source: Curve3D
    public let transform: RigidTransform3D

    public init(
        source: Curve3D,
        transform: RigidTransform3D,
        tolerance: ModelingTolerance
    ) throws {
        self.source = source
        self.transform = transform
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try transform.validate(tolerance: tolerance)
        try source.validate(tolerance: tolerance)
    }

    public var parameterDomain: ParameterDomain {
        source.parameterDomain
    }

    public func point(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try validate(tolerance: tolerance)
        return try pointAssumingValid(at: parameter, tolerance: tolerance)
    }

    package func pointAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        transform.applying(to: try source.pointAssumingValid(
            at: parameter,
            tolerance: tolerance
        ))
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Curve3D.DifferentialGeometry {
        try validate(tolerance: tolerance)
        return try differentialGeometryAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
    }

    package func differentialGeometryAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Curve3D.DifferentialGeometry {
        let sourceGeometry = try source.differentialGeometryAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
        let firstDerivative = transform.applying(to: sourceGeometry.firstDerivative)
        let secondDerivative = transform.applying(to: sourceGeometry.secondDerivative)
        return Curve3D.DifferentialGeometry(
            position: transform.applying(to: sourceGeometry.position),
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            tangent: transform.applying(to: sourceGeometry.tangent),
            curvatureVector: transform.applying(to: sourceGeometry.curvatureVector),
            curvature: sourceGeometry.curvature
        )
    }
}
