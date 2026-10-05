import CADCore
import CADGeometry

/// Preserves a complete original support and its authored UV laws under placement.
package struct ExactPatternSurfaceImage: Sendable {
    package let surface: Surface3D
    package let reversesFaceOrientation: Bool
    private let image: OriginalImageSurface3D

    package init(source: Surface3D, transform: ExactPatternTransform,
        tolerance: ModelingTolerance) throws {
        let affine = try AffineTransform3D(basisX: transform.basisX,
            basisY: transform.basisY, basisZ: transform.basisZ, translation: transform.translation)
        reversesFaceOrientation = try affine.originalDeterminantSign(consumeWork: {
            try Task.checkCancellation()
        }) == .negative
        image = try OriginalImageSurface3D(source: source, transform: affine, tolerance: tolerance)
        surface = .parameterImage(image)
    }

    package func applying(to parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        .originalImage(try OriginalImageSurfaceParameterCurve(
            source: SurfaceLiftCurve3D(surface: image.source, parameterCurve: parameterCurve),
            targetImage: image, tolerance: tolerance))
    }

    package func applying(to curve: Curve3D, tolerance: ModelingTolerance) throws -> Curve3D {
        .affineImage(try AffineImageCurve3D(source: curve, transform: image.transform, tolerance: tolerance))
    }
}
