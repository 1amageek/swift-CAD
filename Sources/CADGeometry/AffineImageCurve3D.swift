import CADCore

/// A parameter-preserving exact image of a curve under a finite affine map.
public struct AffineImageCurve3D: Hashable, Sendable {
    public let source: Curve3D
    public let transform: AffineTransform3D

    public init(
        source: Curve3D,
        transform: AffineTransform3D,
        tolerance: ModelingTolerance
    ) throws {
        self.source = source
        self.transform = transform
        try validate(tolerance: tolerance)
    }

    /// Retains the original affine law while admitting source visits to one caller.
    public init(source: Curve3D, transform: AffineTransform3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
        self.source = source; self.transform = transform
        try Curve3D.affineImage(self).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { _ in try consumeWork() }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
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

#if !hasFeature(Embedded)
extension AffineImageCurve3D: Codable {}
#endif
