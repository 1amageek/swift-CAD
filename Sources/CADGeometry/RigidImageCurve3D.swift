import CADCore

/// A parameter-preserving exact image of a curve under a rigid transform.
public struct RigidImageCurve3D: Hashable, Sendable {
    public let source: Curve3D
    public let transform: RigidTransform3D

    public init(source: Curve3D, transform: RigidTransform3D,
        tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(source: source, transform: transform, tolerance: tolerance,
            using: &execution)
    }

    public init(source: Curve3D, transform: RigidTransform3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        let limits = execution.effectiveLimits
        try self.init(source: source, transform: transform, tolerance: tolerance,
            remainingSourceDepth: limits.remainingSourceDepth,
            maximumSubdivisionDepth: limits.maximumSubdivisionDepth, using: &execution)
    }

    /// Constructs the original image with the composing caller's execution.
    public init(source: Curve3D, transform: RigidTransform3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws {
        self.source = source
        self.transform = transform
        try Curve3D.rigidImage(self).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        try execution.checkpoint()
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        let limits = execution.effectiveLimits
        try Curve3D.rigidImage(self).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: limits.remainingSourceDepth,
            maximumSubdivisionDepth: limits.maximumSubdivisionDepth, using: &execution)
        try execution.checkpoint()
    }

    public var parameterDomain: ParameterDomain { source.parameterDomain }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try validate(tolerance: tolerance, using: &execution)
        return try pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }

    package func pointAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }

    package func pointAssumingValid(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        let sourcePoint = try execution.withSourceDepthOffset(1) { execution in
            try source.pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
        }
        let result = transform.applying(to: sourcePoint)
        try execution.checkpoint()
        return result
    }

    public func differentialGeometry(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Curve3D.DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometry(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Curve3D.DifferentialGeometry {
        try validate(tolerance: tolerance, using: &execution)
        return try differentialGeometryAssumingValid(at: parameter,
            tolerance: tolerance, using: &execution)
    }

    package func differentialGeometryAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance) throws -> Curve3D.DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometryAssumingValid(at: parameter,
            tolerance: tolerance, using: &execution)
    }

    package func differentialGeometryAssumingValid(at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> Curve3D.DifferentialGeometry {
        try execution.consumeWork(1)
        let sourceGeometry = try execution.withSourceDepthOffset(1) { execution in
            try source.differentialGeometryAssumingValid(at: parameter,
                tolerance: tolerance, using: &execution)
        }
        let firstDerivative = transform.applying(to: sourceGeometry.firstDerivative)
        let secondDerivative = transform.applying(to: sourceGeometry.secondDerivative)
        let result = Curve3D.DifferentialGeometry(
            position: transform.applying(to: sourceGeometry.position),
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            tangent: transform.applying(to: sourceGeometry.tangent),
            curvatureVector: transform.applying(to: sourceGeometry.curvatureVector),
            curvature: sourceGeometry.curvature)
        try execution.checkpoint()
        return result
    }
}

#if !hasFeature(Embedded)
extension RigidImageCurve3D: Codable {}
#endif
