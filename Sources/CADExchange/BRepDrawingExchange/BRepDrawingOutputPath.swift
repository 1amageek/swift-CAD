import CADCore

struct BRepDrawingOutputPath {
    let points: [Point2D]
    let layer: String
    let identity: String
    let startParameter: Double?
    let endParameter: Double?
    let nativeStations: [Double]?
    let originalSilhouettePoint: OriginalSilhouetteDrawingPoint?
    let originalSilhouettePath: OriginalSilhouetteDrawingPath?
    let originalAnnotationDescriptor: String?
    let originalSilhouetteDescriptor: String?
    let originalRootSpanPath: OriginalRootSpanDrawingPath?
    let originalRootSpanDescriptor: String?
    init(points: [Point2D], layer: String, identity: String, startParameter: Double?, endParameter: Double?, nativeStations: [Double]? = nil, originalRootSpanPath: OriginalRootSpanDrawingPath? = nil, originalRootSpanDescriptor: String? = nil, originalSilhouettePath: OriginalSilhouetteDrawingPath? = nil, originalSilhouetteDescriptor: String? = nil, originalSilhouettePoint: OriginalSilhouetteDrawingPoint? = nil, originalAnnotationDescriptor: String? = nil) {
        self.originalAnnotationDescriptor = originalAnnotationDescriptor
        self.points = points; self.layer = layer; self.identity = identity
        self.startParameter = startParameter; self.endParameter = endParameter; self.nativeStations = nativeStations; self.originalRootSpanPath = originalRootSpanPath; self.originalRootSpanDescriptor = originalRootSpanDescriptor; self.originalSilhouettePath = originalSilhouettePath; self.originalSilhouetteDescriptor = originalSilhouetteDescriptor; self.originalSilhouettePoint = originalSilhouettePoint
    }
}
