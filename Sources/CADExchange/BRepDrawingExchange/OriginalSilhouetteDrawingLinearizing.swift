import CADCore
import CADGeometry
import CADKernel

/// Original silhouette projection and complete-interval paper chord certification.
public protocol OriginalSilhouetteDrawingLinearizing: Sendable {
    func linearize(_ span: BRepDrawingExactSilhouetteSpan, pointsPerMeter: Double, translation: Point2D,
        maximumDeviation: Double, maximumParameterWidth: ExactRationalCoefficient,
        admission: DrawingSilhouetteAdmission, usage: inout DrawingExchangeUsage,
        silhouetteUsage: inout SurfaceSilhouetteUsage) throws -> OriginalSilhouetteDrawingPath
}
