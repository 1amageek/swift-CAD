import CADCore
import CADGeometry

/// Preserves a complete original support and its authored UV laws under placement.
package struct ExactPatternSurfaceImage: Sendable {
    package let surface: Surface3D
    package let reversesFaceOrientation: Bool
    private let image: OriginalImageSurface3D
    private let budget: OriginalQueryBudget
    private let limits: OriginalQueryExecutionLimits
    private let contributions: [OriginalQueryContributionHandle]

    package init(source: Surface3D, transform: ExactPatternTransform,
        tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(source: source, transform: transform, tolerance: tolerance, using: &execution)
    }

    package func applying(to parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        return try applying(to: parameterCurve, tolerance: tolerance, using: &execution)
    }

    package func applying(to curve: Curve3D, tolerance: ModelingTolerance) throws -> Curve3D {
        var execution = try OriginalQueryExecution(budget: budget, limits: limits, contributions: contributions)
        return try applying(to: curve, tolerance: tolerance, using: &execution)
    }

    package init(source: Surface3D, transform: ExactPatternTransform,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        budget = execution.budget
        limits = execution.effectiveLimits; contributions = try execution.retainActiveContributionHandles()
        let affine = try AffineTransform3D(basisX: transform.basisX,
            basisY: transform.basisY, basisZ: transform.basisZ, translation: transform.translation)
        reversesFaceOrientation = try affine.originalDeterminantSign(using: &execution) == .negative
        image = try OriginalImageSurface3D(source: source, transform: affine, tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
        surface = .parameterImage(image)
    }

    package func applying(to parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve {
        .originalImage(try OriginalImageSurfaceParameterCurve(
            source: SurfaceLiftCurve3D(surface: image.source, parameterCurve: parameterCurve),
            targetImage: image, tolerance: tolerance, using: &execution))
    }

    package func applying(to curve: Curve3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Curve3D {
        .affineImage(try AffineImageCurve3D(source: curve, transform: image.transform, tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution))
    }
}
