import CADCore

/// Page curves, leaders or points after one original model-to-page placement.
public struct DrawingPagePath: Sendable {
    public let points: [Point2D]
    public let identity: String
    public let role: DrawingPageStrokeRole
    public let originalRadialDimension: DrawingRadialDimensionSource?
    public let originalParameters: [Double]?
    public let originalSilhouettePoint: OriginalSilhouetteDrawingPoint?
    public let originalSilhouettePath: OriginalSilhouetteDrawingPath?
    public let originalRootSpanPath: OriginalRootSpanDrawingPath?
    public init(points: [Point2D], identity: String, role: DrawingPageStrokeRole,
                originalParameters: [Double]? = nil, originalRootSpanPath: OriginalRootSpanDrawingPath? = nil,
                originalSilhouettePath: OriginalSilhouetteDrawingPath? = nil,
                originalSilhouettePoint: OriginalSilhouetteDrawingPoint? = nil,
                originalRadialDimension: DrawingRadialDimensionSource? = nil) {
        self.originalRadialDimension = originalRadialDimension
        self.points = points; self.identity = identity; self.role = role
        self.originalParameters = originalParameters; self.originalRootSpanPath = originalRootSpanPath; self.originalSilhouettePath = originalSilhouettePath; self.originalSilhouettePoint = originalSilhouettePoint
    }
}
