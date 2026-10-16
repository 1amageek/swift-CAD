import CADCore
import CADGeometry
import CADKernel

/// Paper-point chord proposals bound to the complete original silhouette invocation.
public struct OriginalSilhouetteDrawingPath: Sendable {
    public struct Sample: Sendable {
        public let normalizedParameter: Double
        public let point: Point2D
    }
    public let span: BRepDrawingExactSilhouetteSpan
    public let pointsPerMeter: Double
    public let translation: Point2D
    public let maximumDeviation: Double
    public let maximumParameterWidth: ExactRationalCoefficient
    public let samples: [Sample]
    let accountingOwner: DrawingExchangeOwner
    let silhouetteOwner: SurfaceSilhouetteContext
    let admission: DrawingSilhouetteAdmission
}
