import CADCore

/// A parameter-preserving exact image of a curve under a finite affine map.
public struct AffineImageCurve3D: Codable, Hashable, Sendable {
    public let source: Curve3D
    public let transform: AffineTransform3D

    public init(
        source: Curve3D,
        transform: AffineTransform3D,
        tolerance: ModelingTolerance
    ) throws {
        if case let .affineImage(image) = source {
            self.source = image.source
            self.transform = try transform.composed(after: image.transform)
        } else {
            self.source = source
            self.transform = transform
        }
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try transform.validate()
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
        let speed = firstDerivative.length
        guard speed > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: speed,
                tolerance: tolerance,
                message: "An affine curve image is singular at the requested parameter."
            )
        }
        let tangent = firstDerivative / speed
        let tangentialAcceleration = tangent * secondDerivative.dot(tangent)
        let curvatureVector = (secondDerivative - tangentialAcceleration) / (speed * speed)
        return Curve3D.DifferentialGeometry(
            position: transform.applying(to: sourceGeometry.position),
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            tangent: tangent,
            curvatureVector: curvatureVector,
            curvature: curvatureVector.length
        )
    }
}
